FROM busybox:latest

# Copy entrypoint script
COPY --chmod=700 entrypoint.sh /usr/local/bin/entrypoint.sh

# Entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
LABEL org.opencontainers.image.source https://github.com/wolffshots/connectorr
