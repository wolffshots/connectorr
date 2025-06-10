#!/bin/sh

# Function to add timestamps to logs
ts() {
    while IFS= read -r line; do
        echo  "$(date '+%Y-%m-%d %H:%M:%S') | $line"
    done
}

. ./envcheck.sh

# Remove default route
ip route del default

# Set IFS to comma to split
IFS=','

# Add specified subnets via BYPASS_IP
for subnet in $BYPASS_SUBNETS; do
    echo "Adding route for subnet $subnet via $BYPASS_IP" | ts
    ip route add "$subnet" via "$BYPASS_IP"
done

# Add routes for sites specified in BYPASS_SITES
for site in $BYPASS_SITES; do
    echo "Adding IPs for $site" | ts
    # Lookup IPs using nslookup and filter for A records
    site_ips=$(nslookup "$site" 2>/dev/null | grep -A 10 "Name:" | grep "Address:" | awk '{print $2}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')

    if [ -z "$site_ips" ]; then
        echo "Failed to lookup IPs for $site" | ts
        if [ "${SUPPRESS_ERRORS}" = "on" ] || [ "${SUPPRESS_ERRORS}" = "true" ] || [ "${SUPPRESS_ERRORS}" = "ON" ] || [ "${SUPPRESS_ERRORS}" = "TRUE" ]; then
            echo "SUPPRESS_ERRORS is enabled, continuing despite lookup failure" | ts
        else
            exit 1
        fi
    fi

    # Add route for each IP
    for ip in $site_ips; do
        echo "Adding route for IP $ip (from $site) via $BYPASS_IP" | ts
        ip route add "$ip/32" via "$BYPASS_IP" 2>/dev/null || echo "Failed to add route for $ip" | ts
    done
done

# Add default route via GATEWAY_IP
echo "Adding default route via $GATEWAY_IP" | ts
ip route add default via "$GATEWAY_IP"

# Log routes
echo "Current routing table:" | ts
ip route | ts
sleep 2

# Function to handle cleanup on termination signals
cleanup() {
    echo "Shutting down gracefully..." | ts
    exit 0
}

# Trap termination signals (15 for SIGTERM, 2 for SIGINT)
trap cleanup 15 2

restart_service() {
    local_service=$1
    local_service_json=$2
    local_state=$3

    echo "Service $local_service is not running (state: $local_state). Restarting..." | ts
    local_container_id=$(echo "$local_service_json" | jq -r '.[0].Id')
    # Restart the container
    curl -sS --unix-socket /var/run/docker.sock -X POST http://localhost/containers/"$local_container_id"/restart
    echo "Service $local_service restarted." | ts
}

recreate_service() {
    service=$1
    service_json=$2
    state=$3
    connectorr_id=$4

    echo "Service $service is not running (state: $state). Recreating with updated networking..." | ts
    container_id=$(echo "$service_json" | jq -r '.[0].Id')
    container_name=$(echo "$service_json" | jq -r '.[0].Names[0]' | sed 's/^\///')
    # Get full container details to extract Config
    full_service_json=$(curl -sS --unix-socket /var/run/docker.sock http://localhost/containers/"$container_id"/json)
    if [ "$DEBUG" = "true" ]; then
        echo "Full Service JSON: $full_service_json" | ts
    fi
    # Extract Config, HostConfig, and NetworkingConfig
    config=$(echo "$full_service_json" | jq '.Config')
    host_config=$(echo "$full_service_json" | jq '.HostConfig')
    networking_config=$(echo "$full_service_json" | jq '.NetworkSettings.Networks')
    # Update HostConfig to use the new connectorr container ID for networking
    host_config=$(echo "$host_config" | jq --arg connectorr_id "$connectorr_id" '.NetworkMode = "container:" + $connectorr_id')
    # Recreate and start the container without Hostname
    create_payload=$(jq -n --argjson config "$config" --argjson host_config "$host_config" --argjson networking_config "$networking_config" '{Domainname: $config.Domainname, User: $config.User, AttachStdin: $config.AttachStdin, AttachStdout: $config.AttachStdout, AttachStderr: $config.AttachStderr, Tty: $config.Tty, OpenStdin: $config.OpenStdin, StdinOnce: $config.StdinOnce, Env: $config.Env, Cmd: $config.Cmd, Entrypoint: $config.Entrypoint, Image: $config.Image, Labels: $config.Labels, Volumes: $config.Volumes, WorkingDir: $config.WorkingDir, NetworkDisabled: $config.NetworkDisabled, MacAddress: $config.MacAddress, StopSignal: $config.StopSignal, StopTimeout: $config.StopTimeout, HostConfig: $host_config, NetworkingConfig: {EndpointsConfig: $networking_config}}')
    if [ "$DEBUG" = "true" ]; then
        echo "Create JSON: $(echo "$create_payload" | jq .)" | ts
    fi
    # Stop and remove the container
    curl -sS --unix-socket /var/run/docker.sock -X POST http://localhost/containers/"$container_id"/stop
    curl -sS --unix-socket /var/run/docker.sock -X DELETE http://localhost/containers/"$container_id"
    # Create and start the new container with the same name
    create_response=$(curl -sS --unix-socket /var/run/docker.sock -X POST http://localhost/containers/create?name="$container_name" -H "Content-Type: application/json" -d "$create_payload")
    if [ "$DEBUG" = "true" ]; then
        echo "Create Response: $create_response" | ts
    fi
    new_container_id=$(echo "$create_response" | jq -r '.Id')
    curl -sS --unix-socket /var/run/docker.sock -X POST http://localhost/containers/"$new_container_id"/start
    echo "Service $service recreated and started with updated networking." | ts
}

# Function to check and restart containers
check_and_restart_containers() {
    # Check if the Docker socket exists
    if [ ! -S /var/run/docker.sock ]; then
        echo "Docker socket /var/run/docker.sock does not exist so not managing other services" | ts
    else
        # Get the project name
        project_json=$(curl -sS --unix-socket /var/run/docker.sock http://localhost/containers/"$(hostname)"/json)
        if [ "$DEBUG" = "true" ]; then
            echo "Project JSON: $project_json" | ts
        fi
        project=$(echo "$project_json" | jq -r '.Config.Labels["com.docker.compose.project"]')
        if [ "$DEBUG" = "true" ]; then
            echo "Project: $project" | ts
        fi

        # Get the current connectorr container ID
        connectorr_id=$(curl -sS --unix-socket /var/run/docker.sock "http://localhost/containers/json?filters=$(echo "{\"label\":[\"com.docker.compose.service=connectorr\",\"com.docker.compose.project=${project}\"]}" | jq -s -R -r @uri)" | jq -r '.[0].Id')
        if [ "$DEBUG" = "true" ]; then
            echo "Connectorr ID: $connectorr_id" | ts
        fi

        # Get the services
        services_json=$(curl -sS --unix-socket /var/run/docker.sock "http://localhost/containers/json?all=true&filters=$(echo "{\"label\":[\"com.docker.compose.project=${project}\"]}" | jq -s -R -r @uri)")
        if [ "$DEBUG" = "true" ]; then
            echo "Services JSON: $services_json" | ts
        fi
        services=$(echo "$services_json" | jq -r '.[] | select(.Labels["com.docker.compose.service"] != "connectorr" and (.Image | test("connector") | not)) | .Labels["com.docker.compose.service"]')
        if [ "$DEBUG" = "true" ]; then
            echo "Services: $services" | ts
        fi

        if [ -z "$services" ]; then
            echo "No services found." | ts
            return 1
        fi

        # Iterate over services and check their state
        echo "$services" | while IFS= read -r service; do
            if [ "$DEBUG" = "true" ]; then
                echo "Checking service: $service" | ts
            fi
            filter=$(echo "{\"label\":[\"com.docker.compose.service=${service}\",\"com.docker.compose.project=${project}\"]}" | jq -s -R -r @uri)
            if [ "$DEBUG" = "true" ]; then
                echo "Filter: $filter" | ts
            fi
            max_retries=3
            retry_count=0

            while [ $retry_count -lt $max_retries ]; do
                service_json=$(curl -sS --unix-socket /var/run/docker.sock "http://localhost/containers/json?all=true&filters=$filter")
                if [ "$DEBUG" = "true" ]; then
                    echo "Service JSON: $service_json" | ts
                fi
                state=$(echo "$service_json" | jq -r '.[0].State')
                network_mode=$(echo "$service_json" | jq -r '.[0].HostConfig.NetworkMode')
                if [ "$state" != "running" ]; then
                    if echo "$network_mode" | grep -q '^container:'; then
                        recreate_service "$service" "$service_json" "$state" "$connectorr_id"
                    else
                        restart_service "$service" "$service_json" "$state"
                    fi
                    retry_count=$((retry_count + 1))
                    sleep 3
                else
                    echo "Service $service is running. (attempt $((retry_count + 0)))" | ts
                    break
                fi
            done
            if [ $retry_count -eq $max_retries ]; then
                echo "Service $service failed to start after $max_retries attempts." | ts
            fi
        done
    fi
}

echo "Checking gateway MTU via Gluetun API" | ts
GATEWAY_SETTINGS=$(curl -s -H "X-API-Key: $GATEWAY_API_KEY" $GATEWAY_IP:${GATEWAY_API_PORT:-8000}/v1/vpn/settings)
GATEWAY_TYPE=$(echo $GATEWAY_SETTINGS | jq -r ".type")
GATEWAY_WIREGUARD_MTU=$(echo $GATEWAY_SETTINGS | jq -r ".wireguard.mtu")
GATEWAY_IFACE=$(ip route | grep default | awk '{print $5}')
# Set the MTU of default interface to match the gateway MTU
if [ -n "$GATEWAY_IFACE" ]; then
    echo "Gateway interface determined as $GATEWAY_IFACE" | ts
else
    echo "Gateway interface could not be determined, defaulting to eth0" | ts
    GATEWAY_IFACE=eth0
fi

if [ "$GATEWAY_TYPE" = "wireguard" ]; then
    if [ -n "$GATEWAY_WIREGUARD_MTU" ]; then
        echo "MTU for $GATEWAY_IP is: $GATEWAY_WIREGUARD_MTU " | ts
        if [ "$GATEWAY_WIREGUARD_MTU" = 0 ]; then
            echo "Skipping setting MTU since it is 0, this implies that the VPN is not connected or is not Wireguard"
        else
            echo "Setting MTU to $GATEWAY_WIREGUARD_MTU on $GATEWAY_IFACE" | ts
            ip link set dev $GATEWAY_IFACE mtu $GATEWAY_WIREGUARD_MTU
        fi
    else
        echo "Failed to determine gateway MTU." | ts
        if [ "${SUPPRESS_ERRORS}" = "on" ] || [ "${SUPPRESS_ERRORS}" = "true" ] || [ "${SUPPRESS_ERRORS}" = "ON" ] || [ "${SUPPRESS_ERRORS}" = "TRUE" ]; then
            echo "SUPPRESS_ERRORS is enabled, continuing despite lookup failure" | ts
        else
            exit 1
        fi
    fi
elif [ "$GATEWAY_TYPE" = "openvpn" ]; then
    echo "Gateway type is $GATEWAY_TYPE, skipping MTU configuration (only applies to wireguard)" | ts
else
    echo "Gateway type is invalid: $GATEWAY_TYPE" | ts
    if [ "${SUPPRESS_ERRORS}" = "on" ] || [ "${SUPPRESS_ERRORS}" = "true" ] || [ "${SUPPRESS_ERRORS}" = "ON" ] || [ "${SUPPRESS_ERRORS}" = "TRUE" ]; then
        echo "SUPPRESS_ERRORS is enabled, continuing despite lookup failure" | ts
    else
        exit 1
    fi
fi

if [ "${TRACE_ON_START}" = "on" ] || [ "${TRACE_ON_START}" = "true" ] || [ "${TRACE_ON_START}" = "ON" ] || [ "${TRACE_ON_START}" = "TRUE" ]; then
    echo "Running traceroute..." | ts
    # Run traceroute if HEALTH_REMOTE_IP is defined
    if [ -n "$HEALTH_REMOTE_IP" ]; then
        traceroute "$HEALTH_REMOTE_IP" | ts
    fi

    # Run traceroute if HEALTH_LOCAL_IP is defined
    if [ -n "$HEALTH_LOCAL_IP" ]; then
        traceroute "$HEALTH_LOCAL_IP" | ts
    fi
fi

# Set IP_API_URL to ifconfig.me if it is not defined
if [ -z "$IP_API_URL" ]; then
    IP_API_URL="http://ifconfig.me/ip"
fi

# Fetch IP through the default route if IP_API_CHECK is undefined, on, ON, true, or TRUE
if [ -z "$IP_API_CHECK" ] || [ "$IP_API_CHECK" = "on" ] || [ "$IP_API_CHECK" = "ON" ] || [ "$IP_API_CHECK" = "true" ] || [ "$IP_API_CHECK" = "TRUE" ]; then
    public_ip=$(wget -qO- "$IP_API_URL")
    if [ -z "$public_ip" ]; then
        echo "Failed to fetch IP" | ts
        if [ "${SUPPRESS_ERRORS}" = "on" ] || [ "${SUPPRESS_ERRORS}" = "true" ] || [ "${SUPPRESS_ERRORS}" = "ON" ] || [ "${SUPPRESS_ERRORS}" = "TRUE" ]; then
            echo "SUPPRESS_ERRORS is enabled, continuing despite failure to fetch IP" | ts
        else
            exit 1
        fi
    else
        echo "IP through the default route: $public_ip" | ts
    fi
fi

# Initial check and restart of containers
check_and_restart_containers

# Long sleep if not doing health checks
LONG_SLEEP=${LONG_SLEEP:-360}

# Infinite loop to keep container running
while true; do
    sleep "$LONG_SLEEP" &
    wait $!
    check_and_restart_containers
done
