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

# --- Helper Functions ---

# Function to display usage information
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This script boots a QEMU VM from a Clonezilla ISO. If --iso is not provided,"
    echo "it will attempt to download the latest stable AMD64 version."
    echo ""
    echo "Optional Arguments:"
    echo "  --iso <path>      Path to the Clonezilla Live ISO file. If omitted, downloads the latest."
    echo "  --disk <path>     Path to the QCOW2 disk image to attach. (Default: $DISK_IMAGE)"
    echo "  --partimag <path> Path to the shared directory for Clonezilla images. (Default: $PARTIMAG_PATH)"
    echo "  -h, --help        Display this help message and exit."
    echo ""
    echo "Example:"
    echo "  $0 --disk ./qemu/my-disk.qcow2  # Auto-downloads Clonezilla"
    echo "  $0 --iso ./isos/my-clonezilla.iso --disk ./qemu/my-disk.qcow2"
}

# Function to download the latest Clonezilla stable AMD64 ISO
download_latest_clonezilla() {
    echo "--- Auto-downloading latest Clonezilla ---"
    
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
    
    local iso_filename="clonezilla-live-${latest_version}-amd64.iso"
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
  -display gtk\
  -serial mon:stdio
