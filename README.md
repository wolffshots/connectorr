# connectorr

Simple sidecar to connect a container to an external network with another container as the gateway. 
The goal is to be able to connect to a Gluetun container from multiple stacks without using `network_mode: container:<gluetun>` since the `container` network mode introduces some problems like it not being a direct dependency which can cause stacks to fail to start and if the Gluetun container updates and restarts then the attached container won't regain network access until it is taken down and started again.

I tried to keep the container itself as lightweight (I got it to like `4.1MB` with the BusyBox variant! But that one couldn't manage other Docker containers in the Compose stack. The default Alpine variant now comes in at `13.9MB`.) and simple as possible with enough functionality and configurability that it solves lots of problems.

## Network

You'll need an external network with a known subnet which you can create like this:
```sh
docker network create -subnet=172.21.0.0/24 --ip-range=172.21.0.128/25 --gateway=172.21.0.1 vpn_net
```

You'll use IPs in this subnet and this network name for the containers you want to hook up. If you don't specify an IP it will assing one from 172.21.0.128-172.21.0.255 but if you do specify then you can use 172.21.0.0-172.21.0.255 but it's better to keep manual and auto assigned IPs separate so if you want a manual IP it would be better to select from 172.21.0.3-172.21.0.127.

## Gateway container

Here's a simple setup for a [gluetun](https://github.com/qdm12/gluetun) stack which you could have at `/opt/stacks/glutun/docker-compose.yml`. You'll just need to set up your credentials for your provider as you can see in the [gluetun-wiki](https://github.com/qdm12/gluetun-wiki) repo
```yml
services:
  gluetun:
    image: qmcgaw/gluetun
    container_name: gluetun
    cap_add:
      - NET_ADMIN
    environment:
      - VPN_SERVICE_PROVIDER=${VPN_PROVIDER}
      - VPN_TYPE=wireguard
      - WIREGUARD_PRIVATE_KEY=${WIREGUARD_PRIVATE_KEY}
      - WIREGUARD_ADDRESSES=${WIREGUARD_ADDRESSES}
      - SERVER_CITIES=${SERVER_CITIES}
    volumes:
      - /opt/stacks/gluetun/iptables:/iptables
      - /etc/localtime:/etc/localtime:ro
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv4.ip_forward=1
    networks:
      vpn_net:
        ipv4_address: 172.21.0.2
    restart: always
    logging:
      driver: json-file
      options:
        max-size: 100m
        max-file: "5"
networks:
  vpn_net:
    external: true
```

And then create a file at `/opt/stacks/gluetun/iptables/post-rules.txt` with the following content (edit the subnets if your network uses a different one):
```sh
iptables -A FORWARD -s 172.21.0.0/24 -o tun0 -j ACCEPT
iptables -A FORWARD -d 172.21.0.0/24 -i tun0 -j ACCEPT
iptables -t nat -A POSTROUTING -s 172.21.0.0/24 -o tun0 -j MASQUERADE
```

Make sure the [gluetun](https://github.com/qdm12/gluetun) stack is up and running correctly before moving on. If you have trouble please check the [gluetun-wiki](https://github.com/qdm12/gluetun-wiki) repo for help

## Environment

Once you have the gateway container set up and configured correctly you have these options for the environment of this connector:

| Variable              | Description                                                                                           | Status                                                         | Default                                  | Example                                  |
| --------------------- | ----------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- | ---------------------------------------- | ---------------------------------------- |
| `GATEWAY_IP`          | IP of the gateway container (on the Docker network) that traffic will be routed through               | Required                                                       | N/A                                      | 172.21.0.2                               |
| `BYPASS_IP`           | IP of the Docker host in the Docker network, normally 172.x.0.1                                       | Optional unless `BYPASS_SUBNETS` is defined then required      | N/A                                      | 172.21.0.1                               |
| `BYPASS_SUBNETS`      | Comma separated list of subnets that should be routed through the bypass IP                           | Optional                                                       | Empty                                    | 192.168.88.0/24,100.64.0.0/10            |
| `HEALTH_REMOTE_IP`    | External IP to ping for health check                                                                  | Optional unless `HEALTH_REMOTE_CHECK` is on                    | N/A                                      | 1.1.1.1                                  |
| `HEALTH_REMOTE_CHECK` | Whether to ping the HEALTH_REMOTE_IP from inside the container to log health                          | Optional with default off                                      | off                                      | on                                       |
| `HEALTH_LOCAL_IP`     | Local IP to ping for health check                                                                     | Optional unless `HEALTH_LOCAL_CHECK` is on then required       | N/A                                      | 192.168.88.1                             |
| `HEALTH_LOCAL_CHECK`  | Whether to ping the `HEALTH_LOCAL_IP` from inside the container to log health                         | Optional with default off                                      | off                                      | on                                       |
| `IP_API_URL`          | Endpoint to wget from to print IP                                                                     | Optional with default [ifconfig.me/ip](https://ifconfig.me/ip) | [ifconfig.me/ip](https://ifconfig.me/ip) | [ifconfig.me/ip](https://ifconfig.me/ip) |
| `IP_API_CHECK`        | Whether to check the public IP on boot using IP_API_URL                                               | Optional with default on                                       | on                                       | on                                       |
| `TRACE_ON_START`      | Run traceroutes when starting using `HEALTH_REMOTE_IP` and `HEALTH_LOCAL_IP` to confirm routing table | Optional with default off                                      | off                                      | off                                      |
| `DEBUG`               | Used for controlling whether certain intermediary data is printed to terminal.            | Optional with default off (`true` to turn on)                                | off | true |
| `LONG_SLEEP`               | The amount of time (in seconds) to sleep for between primary loops (checking containers and healths)            | Optional with default of 360  | 360 | 360 |

# Compose stack
Create a new stack for the things you want to include in what this connector routes and then add it as you see in the [example docker-compose.yml](./docker-compose.yml).

If you include a volume for the Docker socket then the `connectorr` container will try update the networking of attached containers and simply restart other containers in the same Compose stack as it. By default this is run every 360 seconds (6 minutes) unless changed via the `LONG_SLEEP` environment variable.
If you omit this section below then it will skip that functionality:
```
volumes:
      - /var/run/docker.sock:/var/run/docker.sock # this optional and is for ensuring attached containers are healthy and started on reboots
```

Here is a simplified version:
```yml
services:
  # this apline container represents your apps
  app_one:
    image: alpine:latest
    network_mode: service:connectorr # connect it to the connectorr container
    command: sh -c "apk add curl && curl ifconfig.me/ip"
  app_two:
    image: alpine:latest
    network_mode: service:connectorr # connect it to the connectorr container
    command: sh -c "apk add curl && curl ifconfig.me/ip"
  connectorr:
    image: ghcr.io/wolffshots/connectorr:latest
    container_name: app_connectorr
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock # this optional and is for ensuring attached containers are healthy and started on reboots
    ## specific port for the app/s you have connected (in this case the ports you access alpine on)
    ## note that they must be unique ports on the actual app side
    ports:
      - 8085:8085 # an example port for app one. to access app one in the docker network it would be 172.21.0.50:8085 or app_connectorr:8085
      - 8086:8086 # an example port for app two. vice versa for app two
    cap_add:
      - NET_ADMIN
    environment:
      - GATEWAY_IP=172.21.0.2 # gluetun
      - BYPASS_IP=172.21.0.1 # docker host
      - BYPASS_SUBNETS=192.168.88.0/24 # local network
    restart: always
    networks:
      - vpn_net # the network you created which will assign an ip in 172.21.0.128-172.21.0.255 based on the ip pool of the network
networks:
  vpn_net: # the network you created
    external: true
```

Once this stack is up your apps should be using `connectorr` as their network and it should be routing all traffic through `gluetun` except for traffic between the bypassed subnets

You can demo the functionality of the Docker management by using the included `docker-compose.yml` (you will just need to make sure the network config is right for you) to run:
```sh
docker compose down --remove-orphans && docker compose create && docker compose up --build -d connectorr && docker compose logs -f connectorr
```
You will see the output for `connectorr` and see it check the `alpine-*` containers and start them all after `LONG_SLEEP` (by default 6 min). After the first restart subsequent ones will only restart the containers that have exited.

While the stack is running (after 6 minutes if you used the command above or immediately if you use something like `docker compose up -d`) you can also demo the functionality of other containers routing through `connectorr` by running these commands:
```sh
docker compose exec alpine-disconnected sh -c "apk add curl --no-cache && curl ifconfig.me"
```
The above should show your actual IP

```sh
docker compose exec alpine-connected sh -c "apk add curl --no-cache && curl ifconfig.me"
```
The above should show your IP through `connectorr` (so the VPN IP if `connectorr` is routing through a VPN like `gluetun`)
