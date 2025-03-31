FROM alpine:latest

RUN apk add --no-cache curl jq

# Copy entrypoint script
COPY --chmod=700 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=700 envcheck.sh /usr/local/bin/envcheck.sh
COPY --chmod=700 healthcheck.sh /usr/local/bin/healthcheck.sh

WORKDIR /usr/local/bin/

# Entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Healthcheck
HEALTHCHECK --interval=5m --timeout=10s --retries=3 --start-period=5s CMD ["/usr/local/bin/healthcheck.sh"]

# Labels for Github container registry
LABEL org.opencontainers.image.source="https://github.com/wolffshots/connectorr" \
    org.opencontainers.image.documentation="https://github.com/wolffshots/connectorr/blob/$commit/README.md" \
    org.opencontainers.image.description="Simple sidecar to connect a container to an external network with another container as the gateway. See [connectorr](https://github.com/wolffshots/connectorr) for usage details." \
    org.opencontainers.image.title="connectorr"
