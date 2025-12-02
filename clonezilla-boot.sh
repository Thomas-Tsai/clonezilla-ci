#!/bin/bash
# ----------------------------------------------------------------------
# QEMU Clonezilla Boot Script
#
# Function: Use QEMU to boot a Clonezilla Live ISO for manual backup 
#           or restoration tasks.
# ----------------------------------------------------------------------

# --- Default values ---
ISO_PATH="isos/clonezilla-live-3.3.0-33-amd64.iso"
DISK_IMAGE="qemu/debian.qcow2"
PARTIMAG_PATH="partimag"

# --- Helper Functions ---

# Function to display usage information
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This script boots a QEMU VM from a Clonezilla ISO with a specified disk image"
    echo "and a shared directory for Clonezilla images."
    echo ""
    echo "Optional Arguments:"
    echo "  --iso <path>      Path to the Clonezilla Live ISO file."
    echo "                    (Default: $ISO_PATH)"
    echo "  --disk <path>     Path to the QCOW2 disk image to attach."
    echo "                    (Default: $DISK_IMAGE)"
    echo "  --partimag <path> Path to the shared directory for Clonezilla images."
    echo "                    (Default: $PARTIMAG_PATH)"
    echo "  -h, --help        Display this help message and exit."
    echo ""
    echo "Example:"
    echo "  $0 --iso ./isos/my-clonezilla.iso --disk ./qemu/my-disk.qcow2"
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --iso)
            ISO_PATH="$2"
            shift 2
            ;; 
        --disk)
            DISK_IMAGE="$2"
            shift 2
            ;; 
        --partimag)
            PARTIMAG_PATH="$2"
            shift 2
            ;; 
        -h|--help)
            print_usage
            exit 0
            ;; 
        *)
            echo "ERROR: Unknown argument: $1" >&2
            print_usage
            exit 1
            ;; 
    esac
done

# --- Argument Validation ---
if [ ! -f "$ISO_PATH" ]; then
    echo "ERROR: ISO file not found: $ISO_PATH" >&2
    echo "Please specify a valid path using the --iso option." >&2
    exit 1
fi

if [ ! -f "$DISK_IMAGE" ]; then
    echo "ERROR: Disk image not found: $DISK_IMAGE" >&2
    echo "Please specify a valid path using the --disk option." >&2
    exit 1
fi

if [ ! -d "$PARTIMAG_PATH" ]; then
    echo "ERROR: The partimag directory does not exist: $PARTIMAG_PATH" >&2
    echo "Please create it or specify a valid path using the --partimag option." >&2
    exit 1
fi

# --- QEMU Execution ---
echo "--- Starting QEMU with Clonezilla ---"
echo "ISO File: $ISO_PATH"
echo "Disk Image: $DISK_IMAGE"
echo "Image Share: $PARTIMAG_PATH"
echo "-------------------------------------"

qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -cpu host \
  -drive file="$DISK_IMAGE",if=virtio,format=qcow2 \
  -cdrom "$ISO_PATH" \
  -boot d \
  -fsdev local,id=hostshare,path="$PARTIMAG_PATH",security_model=mapped-xattr \
  -device virtio-9p-pci,fsdev=hostshare,mount_tag=hostshare \
  -nic user,hostfwd=tcp::2222-:22 \
  -display gtk \
  -serial mon:stdio