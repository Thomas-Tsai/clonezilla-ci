#!/bin/bash
# This script is for Clonezilla lite server BitTorrent test.
# It sets up the server-side network.

# Select network interface. If PRIVNET_MAC is provided, use it strictly.
# Otherwise, dynamically find an unconfigured network interface (excluding loopback).
IFACE=""
if [ -n "${PRIVNET_MAC:-}" ]; then
  IFACE=$(ip -o link show | grep -i "\b${PRIVNET_MAC}\b" | awk -F': ' '{print $2}')
  if [ -z "$IFACE" ]; then
    echo "Error: Could not find network interface with MAC ${PRIVNET_MAC}" >&2
    exit 1
  fi
  echo "Info: Found network interface by MAC ($PRIVNET_MAC): $IFACE"
else
  for i in $(ip -o link show | awk -F': ' '!/lo/ {print $2}'); do
    if ! ip -o a show dev "$i" | grep -q "inet "; then
      IFACE="$i"
      break
    fi
  done

  if [ -z "$IFACE" ]; then
    echo "Error: Could not find an unconfigured network interface to use." >&2
    exit 1
  fi
  echo "Info: Found unconfigured network interface for server: $IFACE"
fi

# In lite server mode, the server has to set a static IP address and run DHCP service,
# so the client can lease an IP address and find the server.
# The default route from ocs_prerun="dhclient" might exist, so we remove it first.
ip route del default >/dev/null 2>&1 || true
# Configure the IP address for the lite server.
ip link set "${IFACE}" up
ip a add 192.168.0.1/24 dev "${IFACE}"
ip r add default via 192.168.0.1

# Signal that image creation is complete so the host can stop waiting.
touch /home/partimag/image_creation_complete

# Now run the Clonezilla lite server command.
ocs-live-feed-img -cbm both -dm start-new-dhcpd -lscm massive-deployment -mdst from-device -cdt disk-2-mdisks -bsdf sfsck -g auto -e1 auto -e2 -r -x -j2 -k0 -p poweroff -md bittorrent start "${OCS_IMG_NAME:-vda}" vda
