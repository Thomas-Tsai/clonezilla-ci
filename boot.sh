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
ARCH="amd64"

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
    echo "  --arch <arch>   Target architecture (amd64, arm64, riscv64). Default: amd64."
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
        --arch)
            ARCH="$2"
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

# Set QEMU binary and machine type based on architecture
case "$ARCH" in
    "amd64")
        QEMU_BINARY="qemu-system-x86_64"
        QEMU_MACHINE_ARGS=()
        ;;
    "arm64")
        QEMU_BINARY="qemu-system-aarch64"
        QEMU_MACHINE_ARGS=("-machine" "virt" "-bios" "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd")
        ;;
    "riscv64")
        QEMU_BINARY="qemu-system-riscv64"
        QEMU_MACHINE_ARGS=("-machine" "virt" "-kernel" "/usr/lib/u-boot/qemu-riscv64_smode/uboot.elf" "-append" "root=LABEL=rootfs console=ttyS0")
        ;;
    *)
        echo "Error: Unsupported architecture for this script: $ARCH" >&2
        exit 1
        ;;
esac

# Check if QEMU binary exists
if ! command -v "$QEMU_BINARY" &> /dev/null; then
    echo "Error: QEMU binary not found for architecture '$ARCH': $QEMU_BINARY" >&2
    echo "Please ensure the QEMU system emulator for '$ARCH' is installed and in your PATH." >&2
    echo "On Debian/Ubuntu, you might need to install 'qemu-system-arm' (for arm64) or 'qemu-system-misc' (for riscv64)." >&2
    exit 1
fi

QEMU_ARGS=(
    "$QEMU_BINARY"
    "-m" "$MEMORY"
    "-smp" "$SMP"
    "-nic" "user,hostfwd=tcp::2222-:22"
)
if [[ "$ARCH" == "riscv64" ]]; then
    QEMU_ARGS+=("-nographic")
    QEMU_ARGS+=("-device" "virtio-blk-device,drive=hd")
    QEMU_ARGS+=("-drive" "file=$DISK_IMAGE,if=none,id=hd")
    QEMU_ARGS+=("-object" "rng-random,filename=/dev/urandom,id=rng")
    QEMU_ARGS+=("-device" "virtio-rng-device,rng=rng")
else
    QEMU_ARGS+=("-display" "gtk")
    QEMU_ARGS+=("-drive" "file=$DISK_IMAGE,if=virtio,format=qcow2")
fi

if [ ${#QEMU_MACHINE_ARGS[@]} -gt 0 ]; then
    QEMU_ARGS+=("${QEMU_MACHINE_ARGS[@]}")
fi

# KVM and CPU host are not always available/compatible
if [ -e "/dev/kvm" ] && [ "$(groups | grep -c kvm)" -gt 0 ]; then
    HOST_ARCH=$(uname -m)
    KVM_SUPPORTED=false
    if [[ "$ARCH" == "amd64" && "$HOST_ARCH" == "x86_64" ]]; then
        KVM_SUPPORTED=true
        QEMU_ARGS+=("-enable-kvm" "-cpu" "host")
    elif [[ "$ARCH" == "arm64" && "$HOST_ARCH" == "aarch64" ]]; then
        KVM_SUPPORTED=true
        QEMU_ARGS+=("-enable-kvm" "-cpu" "host")
    fi

    if [[ "$KVM_SUPPORTED" == "false" ]]; then
        echo "INFO: KVM is available on this host, but not for the target architecture '$ARCH'. Running in emulation mode."
        if [[ "$ARCH" == "arm64" ]]; then
            QEMU_ARGS+=("-cpu" "cortex-a57")
        fi
    fi
else
    # No KVM available at all.
    # For arm64 emulation, a CPU must be specified.
    if [[ "$ARCH" == "arm64" ]]; then
        QEMU_ARGS+=("-cpu" "cortex-a57")
    fi
fi

"${QEMU_ARGS[@]}"