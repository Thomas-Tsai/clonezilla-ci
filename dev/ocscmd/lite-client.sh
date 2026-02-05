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
  echo "DEBUG: No unconfigured interface found" > /dev/ttyS0
  exit 1
fi
echo "Info: Found unconfigured network interface for server: $IFACE"
echo "DEBUG: Found interface $IFACE" > /dev/ttyS0

# In lite server mode, the server has to set a static IP address and run DHCP service,
# so the client can lease an IP address and find the server.
# The default route from ocs_prerun="dhclient" might exist, so we remove it first.
ip route del default >/dev/null 2>&1 || true
# Configure the IP address for the lite server.
ip link set "${IFACE}" up
ip a add 192.168.0.2/24 dev "${IFACE}"
ip r add default via 192.168.0.2
# Now run the Clonezilla lite server command with retries.
# This loop will try to execute 'ocs-live-get-img 192.168.0.1' up to 10 times.
echo "DEBUG: Starting ocs-live-get-img loop" > /dev/ttyS0
for i in $(seq 1 10); do
  echo "Attempt $i/10: Running ocs-live-get-img..."
  echo "DEBUG: Attempt $i running ocs-live-get-img" > /dev/ttyS0
  # Execute the command with non-interactive flags.
  # -g auto: use the default values for everything
  # -batch: run in batch mode
  ocs-live-get-img --batch 192.168.0.1 "${OCS_IMG_NAME:-}" && break

  # If 'ocs-live-get-img' fails (returns a non-zero exit code), the code below will execute.
  if [ $i -lt 10 ]; then
    echo "Command failed. Retrying in 1 minute..."
    sleep 60 # Wait for 1 minute before the next attempt.
  else
    # If this was the 10th and final attempt and it still failed, print an error and exit.
    echo "Error: Command failed after 10 attempts." >&2
    exit 1
  fi
done

