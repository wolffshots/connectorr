# First stage: Build environment (Alpine)
FROM alpine:latest AS builder

# Install iproute2 and ip
RUN apk --no-cache add iproute2 iputils traceroute
RUN rm -rf /var/cache/apk/*

# Second stage: Minimal runtime image (BusyBox)
FROM busybox:latest

COPY --from=builder /sbin/ip /sbin/ip
COPY --from=builder /usr/bin/traceroute /usr/bin/traceroute

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

