#!/bin/sh

UPTIME=$(cat /proc/uptime | cut -d' ' -f1 | cut -d'.' -f1)

. ./envcheck.sh

check_health() {
    ip="$1"
    if ! ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
        echo "Health check failed: Cannot ping $ip"
        exit 1
    fi
}

if [ "${HEALTH_LOCAL_CHECK}" = "on" ] || [ "${HEALTH_LOCAL_CHECK}" = "true" ] || [ "${HEALTH_LOCAL_CHECK}" = "ON" ] || [ "${HEALTH_LOCAL_CHECK}" = "TRUE" ]; then
    check_health "$HEALTH_LOCAL_IP"
fi
if [ "${HEALTH_REMOTE_CHECK}" = "on" ] || [ "${HEALTH_REMOTE_CHECK}" = "true" ] || [ "${HEALTH_REMOTE_CHECK}" = "ON" ] || [ "${HEALTH_REMOTE_CHECK}" = "TRUE" ]; then
    check_health "$HEALTH_REMOTE_IP"
else
    if [ "$UPTIME" -lt 15 ]; then
        if [ "${HEALTH_REMOTE_CHECK}" = "on" ] || [ "${HEALTH_REMOTE_CHECK}" = "true" ] || [ "${HEALTH_REMOTE_CHECK}" = "ON" ] || [ "${HEALTH_REMOTE_CHECK}" = "TRUE" ]; then
            exit 1  # Return unhealthy during first 15 seconds
        fi
    fi
fi

sleep 5 &
wait $!
