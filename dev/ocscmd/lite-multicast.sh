#!/bin/bash
ip route del default
ip link set ens5 up
ip a add 192.168.0.1/24 dev ens5
ip r add default via 192.168.0.1
ocs-live-feed-img -cbm both -dm start-new-dhcpd -lscm massive-deployment -mdst from-image -g auto -e1 auto -e2 -r -x -j2 -k0 -sc0 -p true -md multicast --clients-to-wait 1 start "debian-13-amd64" vda"
