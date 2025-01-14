#!/bin/sh

. ./envcheck.sh

# Remove default route
ip route del default

# Set IFS to comma to split
IFS=','

# Add local subnets via BYPASS_IP
for subnet in $BYPASS_SUBNETS; do
    echo "Adding route for subnet $subnet via $BYPASS_IP"
    ip route add "$subnet" via "$BYPASS_IP"
done

# Add default route via GATEWAY_IP
echo "Adding default route via $GATEWAY_IP"
ip route add default via "$GATEWAY_IP"

# Log routes
echo "Current routing table:"
ip route

# Function to handle cleanup on termination signals
cleanup() {
    echo "Shutting down gracefully..."
    exit 0
}

# Trap termination signals (15 for SIGTERM, 2 for SIGINT)
trap cleanup 15 2

# Function to check and restart containers
check_and_restart_containers() {
    # Check if the Docker socket exists
    if [ ! -S /var/run/docker.sock ]; then
        echo "Docker socket /var/run/docker.sock does not exist so not managing other services"
    else
        # Get the project name
        project_json=$(curl -sS --unix-socket /var/run/docker.sock http://localhost/containers/"$(hostname)"/json)
        if [ "$DEBUG" = "true" ]; then
            echo "Project JSON: $project_json"
        fi
        project=$(echo "$project_json" | jq -r '.Config.Labels["com.docker.compose.project"]')
        if [ "$DEBUG" = "true" ]; then
            echo "Project: $project"
        fi

        # Get the current connectorr container ID
        connectorr_id=$(curl -sS --unix-socket /var/run/docker.sock "http://localhost/containers/json?filters=$(echo "{\"label\":[\"com.docker.compose.service=connectorr\",\"com.docker.compose.project=${project}\"]}" | jq -s -R -r @uri)" | jq -r '.[0].Id')
        if [ "$DEBUG" = "true" ]; then
            echo "Connectorr ID: $connectorr_id"
        fi

        # Get the services
        services_json=$(curl -sS --unix-socket /var/run/docker.sock "http://localhost/containers/json?all=true&filters=$(echo "{\"label\":[\"com.docker.compose.project=${project}\"]}" | jq -s -R -r @uri)")
        if [ "$DEBUG" = "true" ]; then
            echo "Services JSON: $services_json"
        fi
        services=$(echo "$services_json" | jq -r '.[] | select(.Labels["com.docker.compose.service"] != "connectorr" and (.Image | test("connector") | not)) | .Labels["com.docker.compose.service"]')
        if [ "$DEBUG" = "true" ]; then
            echo "Services: $services"
        fi

        # Iterate over services and check their state
        echo "$services" | while IFS= read -r service; do
            if [ "$DEBUG" = "true" ]; then
                echo "Checking service: $service"
            fi
            filter=$(echo "{\"label\":[\"com.docker.compose.service=${service}\",\"com.docker.compose.project=${project}\"]}" | jq -s -R -r @uri)
            if [ "$DEBUG" = "true" ]; then
                echo "Filter: $filter"
            fi
            service_json=$(curl -sS --unix-socket /var/run/docker.sock "http://localhost/containers/json?all=true&filters=$filter")
            if [ "$DEBUG" = "true" ]; then
                echo "Service JSON: $service_json"
            fi
            state=$(echo "$service_json" | jq -r '.[0].State')
            network_mode=$(echo "$service_json" | jq -r '.[0].HostConfig.NetworkMode')
            if [ "$state" != "running" ]; then
                if echo "$network_mode" | grep -q '^container:'; then
                    echo "Service $service is not running. Recreating with updated networking..."
                    container_id=$(echo "$service_json" | jq -r '.[0].Id')
                    container_name=$(echo "$service_json" | jq -r '.[0].Names[0]' | sed 's/^\///')
                    # Get full container details to extract Config
                    full_service_json=$(curl -sS --unix-socket /var/run/docker.sock http://localhost/containers/"$container_id"/json)
                    if [ "$DEBUG" = "true" ]; then
                        echo "Full Service JSON: $full_service_json"
                    fi
                    # Extract Config, HostConfig, and NetworkingConfig
                    config=$(echo "$full_service_json" | jq '.Config')
                    host_config=$(echo "$full_service_json" | jq '.HostConfig')
                    networking_config=$(echo "$full_service_json" | jq '.NetworkSettings.Networks')
                    # Update HostConfig to use the new connectorr container ID for networking
                    host_config=$(echo "$host_config" | jq --arg connectorr_id "$connectorr_id" '.NetworkMode = "container:" + $connectorr_id')
                    # Recreate and start the container without Hostname
                    create_payload=$(jq -n --argjson config "$config" --argjson host_config "$host_config" --argjson networking_config "$networking_config" '{Domainname: $config.Domainname, User: $config.User, AttachStdin: $config.AttachStdin, AttachStdout: $config.AttachStdout, AttachStderr: $config.AttachStderr, Tty: $config.Tty, OpenStdin: $config.OpenStdin, StdinOnce: $config.StdinOnce, Env: $config.Env, Cmd: $config.Cmd, Entrypoint: $config.Entrypoint, Image: $config.Image, Labels: $config.Labels, Volumes: $config.Volumes, WorkingDir: $config.WorkingDir, NetworkDisabled: $config.NetworkDisabled, MacAddress: $config.MacAddress, ExposedPorts: $config.ExposedPorts, StopSignal: $config.StopSignal, StopTimeout: $config.StopTimeout, HostConfig: $host_config, NetworkingConfig: {EndpointsConfig: $networking_config}}')
                    if [ "$DEBUG" = "true" ]; then
                        echo "Create JSON: $(echo "$create_payload" | jq .)"
                    fi
                    # Stop and remove the container
                    curl -sS --unix-socket /var/run/docker.sock -X POST http://localhost/containers/"$container_id"/stop
                    curl -sS --unix-socket /var/run/docker.sock -X DELETE http://localhost/containers/"$container_id"
                    # Create and start the new container with the same name
                    create_response=$(curl -sS --unix-socket /var/run/docker.sock -X POST http://localhost/containers/create?name="$container_name" -H "Content-Type: application/json" -d "$create_payload")
                    if [ "$DEBUG" = "true" ]; then
                        echo "Create Response: $create_response"
                    fi
                    new_container_id=$(echo "$create_response" | jq -r '.Id')
                    curl -sS --unix-socket /var/run/docker.sock -X POST http://localhost/containers/"$new_container_id"/start
                    echo "Service $service recreated and started with updated networking."
                else
                    echo "Service $service is not running. Restarting..."
                    container_id=$(echo "$service_json" | jq -r '.[0].Id')
                    # Restart the container
                    curl -sS --unix-socket /var/run/docker.sock -X POST http://localhost/containers/"$container_id"/restart
                    echo "Service $service restarted."
                fi
            else
                echo "Service $service is running."
            fi
        done
    fi
}

if [ "${TRACE_ON_START}" = "on" ] || [ "${TRACE_ON_START}" = "true" ] || [ "${TRACE_ON_START}" = "ON" ] || [ "${TRACE_ON_START}" = "TRUE" ]; then
    echo "Running traceroute..."
    # Run traceroute if HEALTH_REMOTE_IP is defined
    if [ -n "$HEALTH_REMOTE_IP" ]; then
        traceroute "$HEALTH_REMOTE_IP"
    fi

    # Run traceroute if HEALTH_LOCAL_IP is defined
    if [ -n "$HEALTH_LOCAL_IP" ]; then
        traceroute "$HEALTH_LOCAL_IP"
    fi
fi

# Set IP_API_URL to ifconfig.me if it is not defined
if [ -z "$IP_API_URL" ]; then
    IP_API_URL="http://ifconfig.me"
fi

# Fetch IP through the default route if IP_API_CHECK is undefined, on, ON, true, or TRUE
if [ -z "$IP_API_CHECK" ] || [ "$IP_API_CHECK" = "on" ] || [ "$IP_API_CHECK" = "ON" ] || [ "$IP_API_CHECK" = "true" ] || [ "$IP_API_CHECK" = "TRUE" ]; then
    public_ip=$(wget -qO- "$IP_API_URL")
    if [ -z "$public_ip" ]; then
        echo "Failed to fetch IP"
    else
        echo "IP through the default route: $public_ip"
    fi
fi

# Long sleep if not doing health checks
LONG_SLEEP=${LONG_SLEEP:-360}

# Infinite loop to keep container running
while true; do
    sleep "$LONG_SLEEP" &
    wait $!
    check_and_restart_containers
done
