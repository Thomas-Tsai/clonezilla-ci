#!/bin/bash
# ----------------------------------------------------------------------
# QEMU Debian Installation Script
#
# Function: Starts a QEMU VM to install Debian from a network
#           installation ISO. If no ISO is specified, it attempts to
#           download the latest stable AMD64 version.
# ----------------------------------------------------------------------

# --- Prerequisites Check ---
command -v curl >/dev/null 2>&1 || { echo >&2 "ERROR: 'curl' is required for auto-downloading. Please install it."; exit 1; }
command -v wget >/dev/null 2>&1 || { echo >&2 "ERROR: 'wget' is required for auto-downloading. Please install it."; exit 1; }

# --- Default values ---
ISO_PATH=""
# Default to empty, logic will handle it
DISK_IMAGE="qemu/debian.qcow2"
MEMORY="4096"
SMP="2"
DOWNLOAD_DIR="isos"

# --- Helper Functions ---

# Function to display usage information
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This script starts a QEMU VM to install Debian. If --iso is not provided,"
    echo "it will attempt to download the latest stable AMD64 netinst ISO."
    echo ""
    echo "Optional Arguments:"
    echo "  --iso <path>    Path to the Debian netinst ISO file. If omitted, downloads the latest."
    echo "  --disk <path>   Path to the QCOW2 disk image to install to. (Default: $DISK_IMAGE)"
    echo "  -m, --mem <MB>  Memory to allocate to the VM in MB. (Default: $MEMORY)"
    echo "  --smp <cores>   Number of CPU cores for the VM. (Default: $SMP)"
    echo "  -h, --help      Display this help message and exit."
    echo ""
    echo "Example:"
    echo "  $0 --disk ./qemu/new-debian.qcow2  # Auto-downloads Debian netinst"
    echo "  $0 --iso ./isos/debian.iso --disk ./qemu/debian.qcow2"
}

# Function to download the latest Debian stable AMD64 netinst ISO
download_latest_debian() {
    echo "--- Auto-downloading latest Debian netinst ISO ---"
    
    local base_url="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/"
    
    echo "1. Finding the latest ISO filename from Debian's server..."
    
    # Fetch the directory listing and find the ...-amd64-netinst.iso filename
    # We grep for the specific pattern, and take the first match.
    local iso_filename
    iso_filename=$(curl -sL "$base_url" | grep -oP 'href="\K(debian-[0-9.]+-amd64-netinst\.iso)(?=")' | head -n 1)
    
    if [ -z "$iso_filename" ]; then
        echo "ERROR: Could not determine the latest Debian netinst ISO from the server." >&2
        echo "Please specify an ISO manually using the --iso flag." >&2
        exit 1
    fi
    
    echo "Latest ISO filename found: $iso_filename"
    
    local download_url="${base_url}${iso_filename}"
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
# Need to know if --iso was passed before deciding to download
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

# --- Main Logic ---

# If no ISO was provided by the user, trigger the download
if [ -z "$ISO_PATH" ]; then
    download_latest_debian
fi

# --- Argument Validation ---
if [ ! -f "$ISO_PATH" ]; then
    echo "ERROR: ISO file not found: $ISO_PATH" >&2
    echo "Download may have failed or an incorrect path was provided." >&2
    exit 1
fi

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
