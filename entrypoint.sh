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
LONG_SLEEP=360

# Infinite loop to keep container running
while true; do
    sleep "$LONG_SLEEP" &
    wait $!
done
