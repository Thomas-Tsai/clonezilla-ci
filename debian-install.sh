#!/bin/bash
# ----------------------------------------------------------------------
# QEMU Debian Installation Script
#
# Function: Starts a QEMU VM to install Debian from a network
#           installation ISO onto a new or existing QCOW2 disk image.
# ----------------------------------------------------------------------

# --- Default values ---
ISO_PATH="isos/debian-13.2.0-amd64-netinst.iso"
DISK_IMAGE="qemu/debian.qcow2"
MEMORY="4096"
SMP="2"

# --- Helper Functions ---

# Function to display usage information
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This script starts a QEMU VM to install Debian from a netinst ISO."
    echo ""
    echo "Optional Arguments:"
    echo "  --iso <path>    Path to the Debian netinst ISO file."
    echo "                  (Default: $ISO_PATH)"
    echo "  --disk <path>   Path to the QCOW2 disk image to install to."
    echo "                  (Default: $DISK_IMAGE)"
    echo "  -m, --mem <MB>  Memory to allocate to the VM in MB. (Default: $MEMORY)"
    echo "  --smp <cores>   Number of CPU cores for the VM. (Default: $SMP)"
    echo "  -h, --help      Display this help message and exit."
    echo ""
    echo "Example:"
    echo "  $0 --iso ./isos/debian-testing-amd64-netinst.iso --disk ./qemu/testing.qcow2"
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
        -m|--mem)
            MEMORY="$2"
            shift 2
            ;; 
        --smp)
            SMP="$2"
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

# Check if the disk image directory exists, but not necessarily the file itself,
# as QEMU can create it.
DISK_DIR=$(dirname "$DISK_IMAGE")
if [ ! -d "$DISK_DIR" ]; then
    echo "ERROR: The directory for the disk image does not exist: $DISK_DIR" >&2
    exit 1
fi

# --- QEMU Execution ---
echo "--- Starting Debian Installation ---"
echo "ISO File: $ISO_PATH"
echo "Disk Image: $DISK_IMAGE"
echo "Memory: ${MEMORY}MB"
echo "CPU Cores: $SMP"
echo "------------------------------------"

qemu-system-x86_64 \
  -enable-kvm \
  -m "$MEMORY" \
  -smp "$SMP" \
  -cpu host \
  -drive file="$DISK_IMAGE",if=virtio,format=qcow2 \
  -cdrom "$ISO_PATH" \
  -boot d \
  -nic user,hostfwd=tcp::2222-:22 \
  -display gtk