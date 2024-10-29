FROM busybox:latest

# Copy entrypoint script
COPY --chmod=700 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=700 envcheck.sh /usr/local/bin/envcheck.sh
COPY --chmod=700 healthcheck.sh /usr/local/bin/healthcheck.sh

WORKDIR /usr/local/bin/

# Entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Healthcheck
HEALTHCHECK --interval=5m --timeout=10s --retries=3 --start-period=5s CMD ["/usr/local/bin/healthcheck.sh"]

# Label for Github container registry
LABEL org.opencontainers.image.source https://github.com/wolffshots/connectorr
