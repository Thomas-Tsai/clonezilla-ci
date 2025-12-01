#!/bin/bash

# ----------------------------------------------------------------------
# Clonezilla Live QCOW2 Media Image Creation Script (v2)
# Function: Automatically packages Clonezilla Live ZIP into QCOW2 and 
#           outputs all Live files to a dedicated directory named after 
#           the ZIP file, with overwrite protection.
# ----------------------------------------------------------------------

# Check if required tools are installed
command -v unzip >/dev/null 2>&1 || { echo >&2 "ERROR: The 'unzip' command is required. Please install it."; exit 1; }
command -v virt-make-fs >/dev/null 2>&1 || { echo >&2 "ERROR: The 'virt-make-fs' command (libguestfs-tools) is required. Please install it."; exit 1; }

# Default values
FORCE_OVERWRITE=0
CLONEZILLA_ZIP=""
OUTPUT_BASE_DIR="."

# Processing arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -f|--force)
            FORCE_OVERWRITE=1
            ;;
        -o)
            if [ -n "$2" ]; then
                OUTPUT_BASE_DIR="$2"
                shift
            else
                echo "ERROR: -o requires a directory"
                exit 1
            fi
            ;;
        *)
            if [[ -z "$CLONEZILLA_ZIP" ]]; then
                CLONEZILLA_ZIP="$1"
            else
                echo "ERROR: Unknown argument or redundant ZIP file path: $1"
                echo "Usage: $0 <Clonezilla_ZIP_Path> [-f|--force] [-o <output_dir>]"
                exit 1
            fi
            ;;
    esac
    shift
done

# Check if ZIP file is provided
if [[ -z "$CLONEZILLA_ZIP" ]]; then
    echo "ERROR: Please provide the Clonezilla ZIP file path."
    echo "Usage: $0 <Clonezilla_ZIP_Path> [-f|--force] [-o <output_dir>]"
    exit 1
fi

# Check if input ZIP file exists
if [ ! -f "$CLONEZILLA_ZIP" ]; then
    echo "ERROR: Could not find the specified ZIP file: $CLONEZILLA_ZIP"
    exit 1
fi

# --- Set output paths based on ZIP filename (meets requirements 2 & 4) ---
# Get filename (e.g., clonezilla-live-3.1.2-9-amd64.zip)
FILENAME=$(basename "$CLONEZILLA_ZIP")
# Get base name without extension (e.g., clonezilla-live-3.1.2-9-amd64)
BASE_NAME="${FILENAME%.zip}"
# Set output directory
OUTPUT_DIR="$OUTPUT_BASE_DIR/$BASE_NAME"
# Set QCOW2 filename (requirement 4)
OUTPUT_IMAGE="$OUTPUT_DIR/$BASE_NAME.qcow2"
IMAGE_SIZE="1G"  # Output image size, adjust based on your ZIP file size

# --- Check output directory (meets requirement 1) ---
if [ -d "$OUTPUT_DIR" ]; then
    if [ "$FORCE_OVERWRITE" -eq 0 ]; then
        echo "ERROR: Output directory '$OUTPUT_DIR' already exists. Please remove it first or use the -f flag to force overwrite."
        exit 1
    else
        echo "WARNING: Using -f flag, overwriting or cleaning directory '$OUTPUT_DIR'..."
        rm -rf "$OUTPUT_DIR"
    fi
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
echo "--- Starting Packaging Process ---"
echo "1. Creating output directory: $OUTPUT_DIR"

# Create a temporary directory (using mktemp -d for uniqueness and security)
TEMP_DIR=$(mktemp -d -t clonezilla-ci-XXXXXXXX)
if [ ! -d "$TEMP_DIR" ]; then
    echo "ERROR: Could not create the temporary directory."
    exit 1
fi
echo "2. Creating temporary directory: $TEMP_DIR"

# Set trap to ensure cleanup of temporary directory upon script exit or interruption
trap "echo '--- Cleaning up temporary directory ---'; rm -rf $TEMP_DIR; exit" EXIT HUP INT TERM

# 3. Unzipping the ZIP file
echo "3. Unzipping $CLONEZILLA_ZIP to temp directory..."
if ! unzip -q "$CLONEZILLA_ZIP" -d "$TEMP_DIR"; then
    echo "ERROR: Unzip failed. Please check if the ZIP file is corrupted."
    exit 1
fi

SOURCE_ROOT="$TEMP_DIR"
if [ ! -d "$SOURCE_ROOT/live" ]; then
    echo "ERROR: Could not find the 'live' folder in the extracted contents. Please verify the ZIP file structure."
    exit 1
fi

# 4. Copying Kernel/Initrd files to the target directory (meets requirement 3)
echo "4. Copying vmlinuz and initrd.img to the target directory..."
# Search for vmlinuz-* OR vmlinuz inside the live folder
VMLINUZ_FILE=$(find "$SOURCE_ROOT/live" -maxdepth 1 -type f \( -name 'vmlinuz-*' -o -name 'vmlinuz' \) -print -quit)
# Search for initrd.img-* OR initrd.img inside the live folder
INITRD_FILE=$(find "$SOURCE_ROOT/live" -maxdepth 1 -type f \( -name 'initrd.img-*' -o -name 'initrd.img' \) -print -quit)

if [[ -z "$VMLINUZ_FILE" || -z "$INITRD_FILE" ]]; then
    echo "ERROR: Could not find the kernel file (vmlinuz or vmlinuz-*) or Initrd file (initrd.img or initrd.img-*)."
    exit 1
fi

cp "$VMLINUZ_FILE" "$OUTPUT_DIR/vmlinuz"
cp "$INITRD_FILE" "$OUTPUT_DIR/initrd.img"

# 5. Packaging into QCOW2 image using virt-make-fs
# Copy zip contents (live folder) to a new temp directory so virt-make-fs maintains structure
CLONEZILLA_CONTENT_FOR_QCOW2="$TEMP_DIR/qcow2_content"
mkdir -p "$CLONEZILLA_CONTENT_FOR_QCOW2"
cp -r "$SOURCE_ROOT/live" "$CLONEZILLA_CONTENT_FOR_QCOW2/"

echo "5. Creating QCOW2 image: $OUTPUT_IMAGE (Size $IMAGE_SIZE)..."
if virt-make-fs --format qcow2 --size "$IMAGE_SIZE" --partition --type ext4 "$CLONEZILLA_CONTENT_FOR_QCOW2" "$OUTPUT_IMAGE"; then
    echo "--- SUCCESS ---"
    echo "Image and Live files successfully created at: $OUTPUT_DIR/"
    echo ""
    echo "You can update the paths in QEMU to:"
    echo "  -hdb $OUTPUT_IMAGE \\"
    echo "  -kernel $OUTPUT_DIR/vmlinuz \\"
    echo "  -initrd $OUTPUT_DIR/initrd.img \\"
else
    echo "--- FAILURE ---"
    echo "ERROR: virt-make-fs failed. Check permissions or libguestfs installation."
    exit 1
fi

# Trap executes cleanup automatically upon script exit
