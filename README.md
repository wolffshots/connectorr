# connectorr

Simple sidecar to connect a container to an external network with another container as the gateway. 
The goal is to be able to connect to a Gluetun container from multiple stacks without using `network_mode: container:<gluetun>`.

