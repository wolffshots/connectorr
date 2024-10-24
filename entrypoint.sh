#!/bin/sh

# Remove default route
ip route del default

# Add local subnets via BYPASS_IP
for subnet in ${BYPASS_SUBNETS//,/ }
do
    echo "Adding route for subnet $subnet via $BYPASS_IP"
    ip route add $subnet via $BYPASS_IP
done

# Add default route via GATEWAY_IP
echo "Adding default route via $GATEWAY_IP"
ip route add default via $GATEWAY_IP

# Log routes
echo "Current routing table:"
ip route

sleep 2

if [ "${TRACE}" = "on" ] || [ "${TRACE}" = "true" ] || [ "${TRACE}" = "ON" ] || [ "${TRACE}" = "TRUE" ]; then
    echo "Running traceroute..."
    traceroute "$HEALTH_REMOTE_IP"
    traceroute "$HEALTH_LOCAL_IP"
fi

echo "IP through the default route:"
echo $(busybox wget -qO- $IP_API_URL || "Failed to fetch IP")

check_health() {
    local ip="$1"
    if ! ping -c 1 "$ip" >/dev/null 2>&1; then
        echo "Health check failed: Cannot ping $ip"
    fi
}

# Total duration between health checks in seconds
TOTAL_SLEEP=30
# Shorter sleep duration in seconds
SHORT_SLEEP=1

# Function to handle cleanup on SIGTERM
cleanup() {
    echo "Shutting down gracefully..."
    exit 0
}

# Trap SIGTERM and SIGINT signals
trap cleanup SIGTERM SIGINT

# Infinite loop to keep container running
while true; do
    # Health check pings
    check_health "$HEALTH_REMOTE_IP"
    check_health "$HEALTH_LOCAL_IP"

    # Initialize elapsed time
    elapsed=0

    # Sleep in shorter intervals until total sleep is reached
    while [ "$elapsed" -lt "$TOTAL_SLEEP" ]; do
        sleep "$SHORT_SLEEP"
        elapsed=$((elapsed + SHORT_SLEEP))
    done
done
