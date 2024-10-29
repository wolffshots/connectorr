#!/bin/sh

# Check that GATEWAY_IP is defined
if [ -z "$GATEWAY_IP" ]; then
    echo "Error: GATEWAY_IP must be defined."
    exit 1
fi

# Check that BYPASS_IP is defined if BYPASS_SUBNETS is defined
if [ -n "$BYPASS_SUBNETS" ] && [ -z "$BYPASS_IP" ]; then
    echo "Error: BYPASS_IP must be defined if BYPASS_SUBNETS is defined."
    exit 1
fi

# Check that HEALTH_REMOTE_IP is defined if HEALTH_REMOTE_CHECK is on, ON, true, or TRUE or undefined (default on)
if { [ "${HEALTH_REMOTE_CHECK}" = "on" ] || [ "${HEALTH_REMOTE_CHECK}" = "true" ] || [ "${HEALTH_REMOTE_CHECK}" = "ON" ] || [ "${HEALTH_REMOTE_CHECK}" = "TRUE" ]; } && [ -z "$HEALTH_REMOTE_IP" ]; then
    echo "Error: HEALTH_REMOTE_IP must be defined if HEALTH_REMOTE_CHECK is enabled."
    exit 1
fi

# Check that HEALTH_LOCAL_IP is defined if HEALTH_LOCAL_CHECK is on, ON, true, or TRUE or undefined (default on)
if { [ "${HEALTH_LOCAL_CHECK}" = "on" ] || [ "${HEALTH_LOCAL_CHECK}" = "true" ] || [ "${HEALTH_LOCAL_CHECK}" = "ON" ] || [ "${HEALTH_LOCAL_CHECK}" = "TRUE" ]; } && [ -z "$HEALTH_LOCAL_IP" ]; then
    echo "Error: HEALTH_LOCAL_IP must be defined if HEALTH_LOCAL_CHECK is enabled."
    exit 1
fi
