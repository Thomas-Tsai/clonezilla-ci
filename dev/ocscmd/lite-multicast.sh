#!/bin/bash
ip route del default
ip link set ens5 up
ip a add 192.168.0.1/24 dev ens5
ip r add default via 192.168.0.1
/usr/sbin/ocs-sr -b -q2 -c -j2 -edio -z9p -i 0 -sfsck -scs -senc -p command savedisk "MT-vda" vda
mount -t 9p -o trans=virtio,version=9p2000.L hostshare /home/partimag
ocs-live-feed-img -cbm both -dm start-new-dhcpd -lscm massive-deployment -mdst from-image -g auto -e1 auto -e2 -r -x -j2 -k0 -sc0 -p poweroff -md multicast --clients-to-wait 1 start "MT-vda" vda
