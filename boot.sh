#!/bin/bash
# ----------------------------------------------------------------------
# QEMU Boot Script
#
# Function: A simple script to quickly boot a QEMU virtual machine
#           from a specified QCOW2 disk image.
# ----------------------------------------------------------------------

# --- Default values ---
DISK_IMAGE="qemu/debian.qcow2"
MEMORY="4096"
SMP="2"

# --- Helper Functions ---

# Function to display usage information
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This script boots a QEMU VM from a specified QCOW2 disk image."
    echo ""
    echo "Optional Arguments:"
    echo "  --disk <path>   Path to the QCOW2 disk image to boot."
    echo "                  (Default: $DISK_IMAGE)"
    echo "  -m, --mem <MB>  Memory to allocate to the VM in MB. (Default: $MEMORY)"
    echo "  --smp <cores>   Number of CPU cores for the VM. (Default: $SMP)"
    echo "  -h, --help      Display this help message and exit."
    echo ""
    echo "Example:"
    echo "  $0 --disk ./qemu/my-vm.qcow2 -m 2048"
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case "$1" in
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
if [ ! -f "$DISK_IMAGE" ]; then
    echo "ERROR: Disk image not found: $DISK_IMAGE" >&2
    echo "Please specify a valid path using the --disk option." >&2
    exit 1
fi

# --- QEMU Execution ---
echo "--- Booting QEMU VM ---"
echo "Disk Image: $DISK_IMAGE"
echo "Memory: ${MEMORY}MB"
echo "CPU Cores: $SMP"
echo "-----------------------"

qemu-system-x86_64 \
  -enable-kvm \
  -m "$MEMORY" \
  -smp "$SMP" \
  -cpu host \
  -drive file="$DISK_IMAGE",if=virtio,format=qcow2 \
  -nic user,hostfwd=tcp::2222-:22 \
  -display gtk