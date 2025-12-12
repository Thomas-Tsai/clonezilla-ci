#!/bin/bash
# ----------------------------------------------------------------------
# QEMU Clonezilla Boot Script
#
# Function: Use QEMU to boot a Clonezilla Live ISO for manual backup 
#           or restoration tasks. If no ISO is specified, it will
#           attempt to download the latest stable AMD64 version.
# ----------------------------------------------------------------------

# --- Prerequisites Check ---
command -v curl >/dev/null 2>&1 || { echo >&2 "ERROR: 'curl' is required for auto-downloading. Please install it."; exit 1; }
command -v wget >/dev/null 2>&1 || { echo >&2 "ERROR: 'wget' is required for auto-downloading. Please install it."; exit 1; }

# --- Default values ---
ISO_PATH="" # Now defaults to empty, will be set by logic
DISK_IMAGE="qemu/debian.qcow2"
PARTIMAG_PATH="partimag"
DOWNLOAD_DIR="isos"
ARCH="amd64"

# --- Helper Functions ---

# Function to display usage information
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This script boots a QEMU VM from a Clonezilla ISO. If --iso is not provided,"
    echo "it will attempt to download the latest stable version for the specified architecture."
    echo ""
    echo "Optional Arguments:"
    echo "  --iso <path>      Path to the Clonezilla Live ISO file. If omitted, downloads the latest."
    echo "  --disk <path>     Path to the QCOW2 disk image to attach. (Default: $DISK_IMAGE)"
    echo "  --partimag <path> Path to the shared directory for Clonezilla images. (Default: $PARTIMAG_PATH)"
    echo "  --arch <arch>     Target architecture (amd64, arm64). Default: amd64."
    echo "  -h, --help        Display this help message and exit."
    echo ""
    echo "Example:"
    echo "  $0 --disk ./qemu/my-disk.qcow2  # Auto-downloads Clonezilla"
    echo "  $0 --iso ./isos/my-clonezilla.iso --disk ./qemu/my-disk.qcow2"
}

# Function to download the latest Clonezilla stable ISO for the specified architecture
download_latest_clonezilla() {
    echo "--- Auto-downloading latest Clonezilla ($ARCH) ---"
    
    # URL of the stable directory on SourceForge
    local stable_url="https://sourceforge.net/projects/clonezilla/files/clonezilla_live_stable/"
    
    echo "1. Finding the latest version from SourceForge..."
    
    # Fetch the directory listing and find the latest version folder (numeric, e.g., "3.1.2-9")
    # We look for links pointing to directories, sort them by version, and take the last one.
    local latest_version
    latest_version=$(curl -sL "$stable_url" | grep -oP 'href="/projects/clonezilla/files/clonezilla_live_stable/\K[0-9.-]+(?=/")' | sort -V | tail -n 1)
    
    if [ -z "$latest_version" ]; then
        echo "ERROR: Could not determine the latest version from SourceForge." >&2
        echo "Please specify an ISO manually using the --iso flag." >&2
        exit 1
    fi
    
    echo "Latest version found: $latest_version"
    
    local iso_filename="clonezilla-live-${latest_version}-${ARCH}.iso"
    local download_url="${stable_url}${latest_version}/${iso_filename}/download"
    local target_iso_path="${DOWNLOAD_DIR}/${iso_filename}"
    
    # Check if the ISO already exists
    if [ -f "$target_iso_path" ]; then
        echo "2. ISO file already exists: $target_iso_path. Skipping download."
        ISO_PATH="$target_iso_path"
        return 0
    fi
    
    echo "2. Downloading ISO: $iso_filename"
    
    # Create the download directory if it doesn't exist
    mkdir -p "$DOWNLOAD_DIR"
    
    # Use wget to download, with resume capability
    wget --show-progress -c -O "$target_iso_path" "$download_url"
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Download failed. Please try again or specify an ISO manually." >&2
        rm -f "$target_iso_path" # Clean up partial file
        exit 1
    fi
    
    echo "Download complete: $target_iso_path"
    ISO_PATH="$target_iso_path"
}


# --- Argument Parsing ---
# We need to parse --iso first to see if we need to download
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --arch)
            ARCH="$2"
            shift 2
            ;;
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

# --- Main Logic ---

# If no ISO was provided, trigger the download
if [ -z "$ISO_PATH" ]; then
    download_latest_clonezilla
fi

# --- Argument Validation ---
if [ ! -f "$ISO_PATH" ]; then
    echo "ERROR: ISO file not found: $ISO_PATH" >&2
    echo "Download may have failed or an incorrect path was provided." >&2
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
    "-m" "4096"
    "-drive" "file=$DISK_IMAGE,if=virtio,format=qcow2"
    "-cdrom" "$ISO_PATH"
    "-boot" "d"
    "-fsdev" "local,id=hostshare,path=$PARTIMAG_PATH,security_model=mapped-xattr"
    "-device" "virtio-9p-pci,fsdev=hostshare,mount_tag=hostshare"
    "-nic" "user,hostfwd=tcp::2222-:22"
    "-display" "gtk"
    "-serial" "mon:stdio"
)

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
