#!/bin/bash
ip route del default
ip link set ens5 up
ip a add 192.168.0.1/24 dev ens5
ip r add default via 192.168.0.1
ocs-live-feed-img -cbm both -dm start-new-dhcpd -lscm massive-deployment -mdst from-device -cdt disk-2-mdisks -bsdf sfsck -g auto -e1 auto -e2 -r -x -j2 -k0 -p poweroff -md bittorrent start "vda" vda
