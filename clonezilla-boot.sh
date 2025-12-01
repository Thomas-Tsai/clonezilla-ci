#!/bin/bash
# Script purpose: Use QEMU to boot Clonezilla for backing up or restoring disk images
# Prerequisites: Ensure Clonezilla image is downloaded and placed in the isos/ directory

# Default paths (can be overridden by positional arguments)

# Usage: $0 [iso_path] [qcow2_image]
#   iso_path      Path to Clonezilla ISO (default: isos/clonezilla-live-3.3.0-33-amd64.iso)
#   qcow2_image   Path to QCOW2 image (default: qemu/debian.qcow2)
#   Use -h or --help to display this message.

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  echo -e "Usage: $0 [iso_path] [qcow2_image]\n\n"
  echo "   iso_path      Path to Clonezilla ISO (default: isos/clonezilla-live-3.3.0-33-amd64.iso)"
  echo "   qcow2_image   Path to QCOW2 image (default: qemu/debian.qcow2)"
  exit 0
fi
iso_path="isos/clonezilla-live-3.3.0-33-amd64.iso"
# Default QCOW2 image
debian_image="qemu/debian.qcow2"
# Directory for Clonezilla images
partimag_path="partimag"

# Override defaults if arguments are provided
if [[ -n "$1" ]]; then
  iso_path="$1"
fi
if [[ -n "$2" ]]; then
  debian_image="$2"
fi


# Start QEMU with 9p share
qemu-system-x86_64 \
  -enable-kvm -m 4096 -cpu host \
  -drive file=${debian_image},if=virtio,format=qcow2 \
  -cdrom ${iso_path} \
  -boot d \
  -fsdev local,id=hostshare,path=${partimag_path},security_model=mapped-xattr \
  -device virtio-9p-pci,fsdev=hostshare,mount_tag=hostshare \
  -nic user,hostfwd=tcp::2222-:22 \
  -display gtk \
  -serial mon:stdio <<'QEMU_EOF'
# This text will be sent to the QEMU monitor/serial interface
# Once the guest has booted into a shell (console after Clonezilla boot completes),
# the following commands will be executed in the guest.

# 1) Create mount point
mkdir -p /home/partimag

# 2) Mount 9p (mount_tag must match the -device parameter above)
mount -t 9p -o trans=virtio,version=9p2000.L hostshare /home/partimag

# 3) Display a prompt for the user to operate Clonezilla in the GUI
echo "=== 9p mounted at /home/partimag ==="
QEMU_EOF
