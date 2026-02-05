#!/bin/bash
# This script is for Clonezilla lite server BitTorrent test.
# It sets up the server-side network.

# Dynamically find an unconfigured network interface (excluding loopback)
# This is to avoid hardcoding interface names and ensure we configure a fresh interface.
IFACE=""
for i in $(ip -o link show | awk -F': ' '!/lo/ {print $2}'); do
  if ! ip -o a show dev "$i" | grep -q "inet "; then
    IFACE="$i"
    break
  fi
done

if [ -z "$IFACE" ]; then
  echo "Error: Could not find an unconfigured network interface to use for the server." >&2
  exit 1
fi
echo "Info: Found unconfigured network interface for server: $IFACE"

# In lite server mode, the server has to set a static IP address and run DHCP service,
# so the client can lease an IP address and find the server.
# The default route from ocs_prerun="dhclient" might exist, so we remove it first.
ip route del default >/dev/null 2>&1 || true
# Configure the IP address for the lite server.
ip link set "${IFACE}" up
ip a add 192.168.0.1/24 dev "${IFACE}"
ip r add default via 192.168.0.1

echo "Info: Running Clonezilla lite server multicast device"
ocs-live-feed-img -cbm both -dm start-new-dhcpd -lscm massive-deployment -mdst from-device -cdt disk-2-mdisks -bsdf sfsck -g auto -e1 auto -e2 -r -x -j2 -k0 -p true -md multicast --clients-to-wait 1 start "${OCS_IMG_NAME:-vda}" vda

echo "Info: Powering off the server"
poweroff