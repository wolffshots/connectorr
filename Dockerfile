# First stage: Build environment (Alpine)
FROM alpine:latest AS builder

# Install iproute2 and ip
RUN apk --no-cache add iproute2 iputils
RUN rm -rf /var/cache/apk/*

# Second stage: Minimal runtime image (BusyBox)
FROM busybox:latest

COPY --from=builder /sbin/ip /sbin/ip

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

