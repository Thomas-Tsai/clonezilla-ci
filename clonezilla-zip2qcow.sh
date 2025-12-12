#!/bin/bash

# ----------------------------------------------------------------------
# Clonezilla Live QCOW2 Media Image Creation Script (v3)
#
# Function: Automatically packages a Clonezilla Live ZIP into a QCOW2 
#           image and outputs all necessary boot files (kernel, initrd)
#           to a dedicated directory.
#
# Features:
# - Uses long options for clarity.
# - Provides a help message.
# - Validates all required arguments.
# - Uses the ZIP's base name to name the output directory and files
#   for better organization.
# ----------------------------------------------------------------------

# --- Default values ---
FORCE_OVERWRITE=0
CLONEZILLA_ZIP=""
OUTPUT_BASE_DIR="."
IMAGE_SIZE="2G" # Default image size
ARCH="amd64"
CLONEZILLA_LIVE_STABLE_URL="http://free.nchc.org.tw/clonezilla-live/stable/"
DEFAULT_DOWNLOAD_DIR="zip"

# --- Helper Functions ---

# Function to display usage information
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This script converts a Clonezilla Live ZIP file into a QCOW2 disk image"
    echo "and extracts the kernel and initrd files. If no ZIP file is provided via --zip,"
    echo "it will automatically download the latest stable version for the specified architecture."
    echo ""
    echo "Arguments:"
    echo "  --zip <path>        Path to the source Clonezilla Live ZIP file. (Optional)"
    echo ""
    echo "Optional Arguments:"
    echo "  -o, --output <dir>  Base directory to create the output folder in. (Default: current directory)"
    echo "  -s, --size <size>   Size of the QCOW2 image to be created (e.g., '2G'). (Default: 2G)"
    echo "  --arch <arch>       Architecture for auto-download (e.g., amd64, arm64). Default: amd64."
    echo "  -f, --force         Force overwrite of the output directory if it already exists."
    echo "  -h, --help          Display this help message and exit."
    echo ""
    echo "Example:"
    echo "  $0 --zip ./zip/clonezilla-live-3.1.2-9-amd64.zip --output ./zip/ --force"
    echo "  $0 --arch arm64 --output ./zip/ # Auto-download for ARM64"
}

# --- Prerequisite Check ---
command -v unzip >/dev/null 2>&1 || { echo >&2 "ERROR: The 'unzip' command is required. Please install it."; exit 1; }
command -v virt-make-fs >/dev/null 2>&1 || { echo >&2 "ERROR: The 'virt-make-fs' command (from libguestfs-tools) is required. Please install it."; exit 1; }
command -v curl >/dev/null 2>&1 || { echo >&2 "ERROR: The 'curl' command is required. Please install it."; exit 1; }
command -v wget >/dev/null 2>&1 || { echo >&2 "ERROR: The 'wget' command is required. Please install it."; exit 1; }

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --zip)
            CLONEZILLA_ZIP="$2"
            shift 2
            ;; 
        -o|--output)
            OUTPUT_BASE_DIR="$2"
            shift 2
            ;; 
        -s|--size)
            IMAGE_SIZE="$2"
            shift 2
            ;; 
        -f|--force)
            FORCE_OVERWRITE=1
            shift 1
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

# Auto-download Clonezilla Live ZIP if not provided
if [[ -z "$CLONEZILLA_ZIP" ]]; then
    echo "The --zip argument was not provided. Attempting to auto-download the latest stable $ARCH Clonezilla Live ZIP."

    mkdir -p "$DEFAULT_DOWNLOAD_DIR" || { echo "ERROR: Could not create download directory: $DEFAULT_DOWNLOAD_DIR" >&2; exit 1; }

    echo "Fetching latest Clonezilla Live stable $ARCH ZIP from $CLONEZILLA_LIVE_STABLE_URL"
    LATEST_ZIP_FILENAME=$(curl -s "$CLONEZILLA_LIVE_STABLE_URL" | grep -oP "clonezilla-live-\d+\.\d+\.\d+-\d+-${ARCH}\.zip" | head -n 1)

    if [[ -z "$LATEST_ZIP_FILENAME" ]]; then
        echo "ERROR: Could not find the latest Clonezilla Live ZIP filename from $CLONEZILLA_LIVE_STABLE_URL" >&2
        exit 1
    fi

    DOWNLOAD_URL="${CLONEZILLA_LIVE_STABLE_URL}${LATEST_ZIP_FILENAME}"
    DEST_ZIP_PATH="${DEFAULT_DOWNLOAD_DIR}/${LATEST_ZIP_FILENAME}"

    if [ -f "$DEST_ZIP_PATH" ]; then
        echo "Latest ZIP file already exists: $DEST_ZIP_PATH. Skipping download."
        CLONEZILLA_ZIP="$DEST_ZIP_PATH"
    else
        echo "Downloading $DOWNLOAD_URL to $DEST_ZIP_PATH"
        if ! wget -q --show-progress -O "$DEST_ZIP_PATH" "$DOWNLOAD_URL"; then
            echo "ERROR: Failed to download Clonezilla Live ZIP from $DOWNLOAD_URL" >&2
            rm -f "$DEST_ZIP_PATH" # Clean up partial download
            exit 1
        fi
        CLONEZILLA_ZIP="$DEST_ZIP_PATH"
        echo "Download complete: $CLONEZILLA_ZIP"
    fi
fi

if [ ! -f "$CLONEZILLA_ZIP" ]; then
    echo "ERROR: Could not find the specified ZIP file: $CLONEZILLA_ZIP" >&2
    print_usage
    exit 1
fi


if [ ! -d "$OUTPUT_BASE_DIR" ]; then
    echo "ERROR: The output directory does not exist: $OUTPUT_BASE_DIR" >&2
    exit 1
fi

# --- Set Output Paths ---
FILENAME=$(basename "$CLONEZILLA_ZIP")
BASE_NAME="${FILENAME%.zip}"
OUTPUT_DIR="$OUTPUT_BASE_DIR/$BASE_NAME"
OUTPUT_IMAGE="$OUTPUT_DIR/$BASE_NAME.qcow2"

# --- Handle Existing Directory ---
if [ -d "$OUTPUT_DIR" ]; then
    if [ "$FORCE_OVERWRITE" -eq 0 ]; then
        echo "ERROR: Output directory '$OUTPUT_DIR' already exists. Please remove it first or use the --force flag." >&2
        exit 1
    else
        echo "WARNING: --force specified. Overwriting directory '$OUTPUT_DIR'..."
        rm -rf "$OUTPUT_DIR"
    fi
fi

# --- Main Execution ---
echo "--- Starting Packaging Process ---"

# Create output directory
mkdir -p "$OUTPUT_DIR"
echo "1. Created output directory: $OUTPUT_DIR"

# Create a temporary directory for extraction
TEMP_DIR=$(mktemp -d -t clonezilla-ci-XXXXXXXX)
if [ ! -d "$TEMP_DIR" ]; then
    echo "ERROR: Could not create the temporary directory." >&2
    exit 1
fi
echo "2. Created temporary directory: $TEMP_DIR"

# Set trap to ensure cleanup of temporary directory upon script exit
trap "echo '--- Cleaning up temporary directory ---'; rm -rf '$TEMP_DIR'; exit" EXIT HUP INT TERM

# Unzip the archive
echo "3. Unzipping $CLONEZILLA_ZIP to temp directory..."
if ! unzip -q "$CLONEZILLA_ZIP" -d "$TEMP_DIR"; then
    echo "ERROR: Unzip failed. Please check if the ZIP file is corrupted." >&2
    exit 1
fi

SOURCE_ROOT="$TEMP_DIR"
if [ ! -d "$SOURCE_ROOT/live" ]; then
    echo "ERROR: Could not find the 'live' folder in the extracted contents. Please verify the ZIP file structure." >&2
    exit 1
fi

# Find and copy kernel/initrd, renaming them to include the zip's base name
echo "4. Copying kernel and initrd files to the target directory..."
# Look for standard kernel names first (vmlinuz)
VMLINUZ_FILE=$(find "$SOURCE_ROOT/live" -maxdepth 1 -type f \( -name 'vmlinuz' -o -name 'vmlinuz-*' \) -print -quit)

if [[ -z "$VMLINUZ_FILE" ]]; then
    # If not found, look for vmlinux variants (common on RISC-V, etc.)
    VMLINUZ_FILE=$(find "$SOURCE_ROOT/live" -maxdepth 1 -type f \( -name 'vmlinux' -o -name 'vmlinux-*' \) -print -quit)
    if [[ -n "$VMLINUZ_FILE" ]]; then
        echo "WARNING: Standard 'vmlinuz' kernel not found. Using non-standard name: $(basename "$VMLINUZ_FILE")"
    fi
fi

INITRD_FILE=$(find "$SOURCE_ROOT/live" -maxdepth 1 -type f \( -name 'initrd.img-*' -o -name 'initrd.img' \) -print -quit)

if [[ -z "$VMLINUZ_FILE" || -z "$INITRD_FILE" ]]; then
    echo "ERROR: Could not find the kernel (vmlinuz*/vmlinux*) or initrd (initrd.img*) files in the ZIP." >&2
    exit 1
fi

# Copy and rename using the base name as a prefix
cp "$VMLINUZ_FILE" "$OUTPUT_DIR/${BASE_NAME}-vmlinuz"
cp "$INITRD_FILE" "$OUTPUT_DIR/${BASE_NAME}-initrd.img"

# Package the 'live' directory into a QCOW2 image
CLONEZILLA_CONTENT_FOR_QCOW2="$TEMP_DIR/qcow2_content"
mkdir -p "$CLONEZILLA_CONTENT_FOR_QCOW2"
cp -r "$SOURCE_ROOT/live" "$CLONEZILLA_CONTENT_FOR_QCOW2/"

echo "5. Creating QCOW2 image: $OUTPUT_IMAGE (Size: $IMAGE_SIZE)..."
if virt-make-fs --format qcow2 --size "$IMAGE_SIZE" --partition --type vfat "$CLONEZILLA_CONTENT_FOR_QCOW2" "$OUTPUT_IMAGE"; then
    echo "--- SUCCESS ---"
    echo "Image and boot files successfully created at: $OUTPUT_DIR/"
    echo ""
    echo "Example for qemu-clonezilla-ci-run.sh:"
    echo "  --live $OUTPUT_IMAGE \\"
    echo "  --kernel $OUTPUT_DIR/${BASE_NAME}-vmlinuz \\"
    echo "  --initrd $OUTPUT_DIR/${BASE_NAME}-initrd.img \\"
else
    echo "--- FAILURE ---"
    echo "ERROR: virt-make-fs failed. Check permissions or libguestfs installation." >&2
    exit 1
fi

# The trap will handle cleanup automatically on exit
