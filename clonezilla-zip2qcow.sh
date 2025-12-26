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
TYPE="stable"
CLONEZILLA_LIVE_STABLE_URL="http://free.nchc.org.tw/clonezilla-live/stable/"
DEFAULT_DOWNLOAD_DIR="zip"

# --- Helper Functions ---

# Function to display usage information
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This script converts a Clonezilla Live ZIP file into a QCOW2 disk image"
    echo "and extracts the kernel and initrd files. If no ZIP file is provided via --zip,"
    echo "it will automatically download the latest version for the specified architecture and type."
    echo ""
    echo "Arguments:"
    echo "  --zip <path>        Path to the source Clonezilla Live ZIP file. (Optional)"
    echo ""
    echo "Optional Arguments:"
    echo "  -o, --output <dir>  Base directory to create the output folder in. (Default: current directory)"
    echo "  -s, --size <size>   Size of the QCOW2 image to be created (e.g., '2G'). (Default: 2G)"
    echo "  --arch <arch>       Architecture for auto-download (e.g., amd64, arm64). Default: amd64."
    echo "  --type <type>       Release type for auto-download (e.g., stable, testing). Default: stable."
    echo "  -f, --force         Force overwrite of the output directory if it already exists."
    echo "  -h, --help          Display this help message and exit."
    echo ""
    echo "Example:"
    echo "  $0 --zip ./zip/clonezilla-live-3.1.2-9-amd64.zip --output ./zip/ --force"
    echo "  $0 --arch arm64 --output ./zip/ # Auto-download for ARM64"
    echo "  $0 --arch amd64 --type testing # Auto-download latest testing for AMD64"
}

# --- Prerequisite Check ---
command -v unzip >/dev/null 2>&1 || { echo >&2 "ERROR: The 'unzip' command is required. Please install it."; exit 1; }
command -v virt-make-fs >/dev/null 2>&1 || { echo >&2 "ERROR: The 'virt-make-fs' command (from libguestfs-tools) is required. Please install it."; exit 1; }
command -v curl >/dev/null 2>&1 || { echo >&2 "ERROR: The 'curl' command is required. Please install it."; exit 1; }

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --type)
            TYPE="$2"
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
    echo "INFO: The --zip argument was not provided. Attempting to auto-download."
    
    DOWNLOAD_SCRIPT="./download-clonezilla.sh"
    if [ ! -x "$DOWNLOAD_SCRIPT" ]; then
        echo "ERROR: Download helper script not found or not executable: $DOWNLOAD_SCRIPT" >&2
        exit 1
    fi
    
    echo "INFO: Calling download script with arch='$ARCH', type='$TYPE'..."
    # Run the download script, capturing the output path.
    # The new script downloads to the specified dir, defaulting to './zip'.
    DOWNLOADED_ZIP_PATH=$("$DOWNLOAD_SCRIPT" --arch "$ARCH" --type "$TYPE" -o "$DEFAULT_DOWNLOAD_DIR")
    
    if [ $? -ne 0 ] || [ -z "$DOWNLOADED_ZIP_PATH" ] || [ ! -f "$DOWNLOADED_ZIP_PATH" ]; then
        echo "ERROR: Failed to auto-download Clonezilla zip using $DOWNLOAD_SCRIPT." >&2
        exit 1
    fi
    
    CLONEZILLA_ZIP="$DOWNLOADED_ZIP_PATH"
    echo "INFO: Auto-download complete. Using ZIP: $CLONEZILLA_ZIP"
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
TEMP_DIR=$(mktemp -d cci_zip2qcow.XXXXXXXX)
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
