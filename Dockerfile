FROM alpine:latest

# Install iproute2 and ping utility
RUN apk --no-cache add iproute2 iputils curl

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

