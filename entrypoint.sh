#!/bin/sh

# Remove default route
ip route del default

# Add local subnets via BYPASS_IP
for subnet in ${LOCAL_SUBNETS//,/ }
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

echo "IP through the default route:"
echo $(curl -s ifconfig.me/ip || "Failed to fetch IP")

# Infinite loop to keep container running
while true; do
    # Health check pings
    if ! ping -c 1 $INTERNET_IP >/dev/null 2>&1; then
        echo "Health check failed: Cannot ping INTERNET_IP ($INTERNET_IP)"
    fi

    if ! ping -c 1 $LOCAL_IP >/dev/null 2>&1; then
        echo "Health check failed: Cannot ping LOCAL_IP ($LOCAL_IP)"
    fi

    sleep 30
done
