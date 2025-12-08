#!/bin/bash
# ----------------------------------------------------------------------
# Data Clone & Restore Test Script (dcr.sh)
#
# Function: This script orchestrates an end-to-end test of filesystem
#           backup and restore using Clonezilla. It prepares a source
#           disk with user data, backs it up, restores it to a new
#           disk, and verifies the integrity of the restored data.
#
# Exit Codes:
#   0: Success
#   1: Failure (due to argument error, command failure, or verification mismatch)
# ----------------------------------------------------------------------

# Exit immediately if a command exits with a non-zero status.
# This ensures that the script will stop if any step fails.
set -e

# --- Default values ---
CLONEZILLA_ZIP=""
SOURCE_DATA_DIR=""
FILESYSTEM_TYPE="ext4"
DISK_SIZE="10G"

# --- Helper Functions ---

# Function to display usage information
print_usage() {
    echo "Usage: $0 --zip <path> --data <dir> [OPTIONS]"
    echo ""
    echo "This script performs an end-to-end Clonezilla backup and restore test for a given data directory."
    echo ""
    echo "Required Arguments:"
    echo "  --zip <path>      Path to the Clonezilla Live ZIP file."
    echo "  --data <dir>      Path to the source directory with data to test."
    echo ""
    echo "Optional Arguments:"
    echo "  --fs <type>       Filesystem type to use (ext4, ntfs, vfat). (Default: $FILESYSTEM_TYPE)"
    echo "  --size <size>     Size of the source test disk (e.g., '10G'). (Default: $DISK_SIZE)"
    echo "  -h, --help        Display this help message and exit."
    echo ""
    echo "Example:"
    echo "  $0 --zip isos/clonezilla.zip --data ./my_test_data --fs ext4"
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --zip)
            CLONEZILLA_ZIP="$2"
            shift 2
            ;; 
        --data)
            SOURCE_DATA_DIR="$2"
            shift 2
            ;; 
        --fs)
            FILESYSTEM_TYPE="$2"
            shift 2
            ;; 
        --size)
            DISK_SIZE="$2"
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
echo "--- Validating arguments and dependencies ---"
if [[ -z "$CLONEZILLA_ZIP" || -z "$SOURCE_DATA_DIR" ]]; then
    echo "ERROR: Both --zip and --data arguments are required." >&2
    print_usage
    exit 1
fi

if [ ! -f "$CLONEZILLA_ZIP" ]; then
    echo "ERROR: Clonezilla ZIP file not found: $CLONEZILLA_ZIP" >&2
    exit 1
fi

if [ ! -d "$SOURCE_DATA_DIR" ]; then
    echo "ERROR: Source data directory not found: $SOURCE_DATA_DIR" >&2
    exit 1
fi

# Validate filesystem type
case "$FILESYSTEM_TYPE" in
    ext4|ntfs|vfat)
        ;;
    *)
        echo "ERROR: Unsupported filesystem type '$FILESYSTEM_TYPE'. Supported types are: ext4, ntfs, vfat." >&2
        exit 1
        ;; 
esac

# Validate that required tools exist
for cmd in ./clonezilla_zip2qcow.sh ./qemu_clonezilla_ci_run.sh qemu-img guestfish md5sum; do
    command -v "$cmd" >/dev/null 2>&1 || { echo >&2 "ERROR: Required command '$cmd' not found. Please ensure it is installed and in your PATH."; exit 1; }
done
echo "INFO: All dependencies found."
echo ""


echo "--- Data Clone & Restore Test ---"
echo "Clonezilla ZIP: $CLONEZILLA_ZIP"
echo "Source Data:    $SOURCE_DATA_DIR"
echo "Filesystem:     $FILESYSTEM_TYPE"
echo "Disk Size:      $DISK_SIZE"
echo "---------------------------------"

# --- Main Workflow ---

# Create a temporary working directory for this test run.
# The 'trap' command ensures this directory is cleaned up on script exit (success or failure).
WORK_DIR=$(mktemp -d -t dcr-test-XXXXXXXX)
echo "INFO: Using temporary working directory: $WORK_DIR"
trap 'echo "INFO: Cleaning up temporary directory $WORK_DIR"; rm -rf "$WORK_DIR"' EXIT

# --- Step 1: Convert Clonezilla zip to QCOW2 ---
echo "INFO: [Step 1/5] Converting Clonezilla ZIP to QCOW2 format..."
./clonezilla_zip2qcow.sh --zip "$CLONEZILLA_ZIP" --output "$WORK_DIR" --force > /dev/null

# Define paths for the generated Clonezilla live media
CZ_ZIP_BASENAME=$(basename "${CLONEZILLA_ZIP%.zip}")
CZ_MEDIA_DIR="$WORK_DIR/$CZ_ZIP_BASENAME"
CZ_LIVE_QCOW2="$CZ_MEDIA_DIR/$CZ_ZIP_BASENAME.qcow2"
CZ_KERNEL="$CZ_MEDIA_DIR/${CZ_ZIP_BASENAME}-vmlinuz"
CZ_INITRD="$CZ_MEDIA_DIR/${CZ_ZIP_BASENAME}-initrd.img"

if [ ! -f "$CZ_LIVE_QCOW2" ] || [ ! -f "$CZ_KERNEL" ] || [ ! -f "$CZ_INITRD" ]; then
    echo "ERROR: Failed to create Clonezilla live media. Aborting." >&2
    exit 1
fi
echo "INFO: Clonezilla media successfully created."
echo ""

# --- Step 2: Prepare source disk and copy data ---
echo "INFO: [Step 2/5] Preparing source disk..."
SOURCE_DISK_QCOW2="$WORK_DIR/source.qcow2"

echo "INFO: Creating blank source disk: $SOURCE_DISK_QCOW2"
qemu-img create -f qcow2 "$SOURCE_DISK_QCOW2" "$DISK_SIZE"

echo "INFO: Partitioning and formatting disk with filesystem: $FILESYSTEM_TYPE"
GUESTFISH_DRIVE="sda" # Use a more standard device name
case "$FILESYSTEM_TYPE" in
    ext4) MKFS_COMMAND="mkfs ext4 /dev/${GUESTFISH_DRIVE}1" ;;
    ntfs) MKFS_COMMAND="mkfs.ntfs -F /dev/${GUESTFISH_DRIVE}1" ;;
    vfat) MKFS_COMMAND="mkfs.vfat -F 32 /dev/${GUESTFISH_DRIVE}1" ;;
esac

# Use guestfish to script disk setup. This runs inside a temporary appliance.
guestfish --rw -a "$SOURCE_DISK_QCOW2" <<-EOF
    run
    part-init /dev/${GUESTFISH_DRIVE} mbr
    part-add /dev/${GUESTFISH_DRIVE} p 2048 -1
    ${MKFS_COMMAND}
EOF

# Define absolute path for source data for consistency
_ABS_SOURCE_DATA_DIR=$(realpath "$SOURCE_DATA_DIR")

echo "INFO: Calculating checksums of source data..."
SOURCE_CHECKSUM_FILE="$WORK_DIR/source_checksums.md5"
# We 'cd' to the parent of the source directory and use the basename in `find`.
# This creates checksum paths that include the source directory's name,
# which matches the structure created by 'guestfish copy-in'.
SOURCE_DATA_DIR_PARENT=$(dirname "$_ABS_SOURCE_DATA_DIR")
SOURCE_DATA_DIR_BASENAME=$(basename "$_ABS_SOURCE_DATA_DIR")
(cd "$SOURCE_DATA_DIR_PARENT" && find "$SOURCE_DATA_DIR_BASENAME" -type f -exec md5sum {} + | sort -k 2) > "$SOURCE_CHECKSUM_FILE"
echo "INFO: Source checksums saved to $SOURCE_CHECKSUM_FILE"

echo "INFO: Copying data to source disk..."
guestfish --rw -a "$SOURCE_DISK_QCOW2" <<-EOF
    run
    mount /dev/${GUESTFISH_DRIVE}1 /
    copy-in "${_ABS_SOURCE_DATA_DIR}" /
    umount /
EOF
echo "INFO: Source disk prepared successfully."
echo ""

# --- Step 3: Backup source disk ---
echo "INFO: [Step 3/5] Backing up source disk using Clonezilla..."
PARTIMAG_DIR="$WORK_DIR/partimag"
mkdir -p "$PARTIMAG_DIR"

CLONE_IMAGE_NAME="dcr-image-$(date +%s)"
# Use -b and -y for non-interactive batch mode
OCS_COMMAND="sudo /usr/sbin/ocs-sr -b -y -j2 -p poweroff savedisk ${CLONE_IMAGE_NAME} sda"

./qemu_clonezilla_ci_run.sh \
    --disk "$SOURCE_DISK_QCOW2" \
    --live "$CZ_LIVE_QCOW2" \
    --kernel "$CZ_KERNEL" \
    --initrd "$CZ_INITRD" \
    --cmd "$OCS_COMMAND" \
    --image "$PARTIMAG_DIR"

if [ ! -d "$PARTIMAG_DIR/$CLONE_IMAGE_NAME" ]; then
    echo "ERROR: Backup failed. Image directory '$PARTIMAG_DIR/$CLONE_IMAGE_NAME' not found." >&2
    exit 1
fi
echo "INFO: Backup completed successfully to $PARTIMAG_DIR/$CLONE_IMAGE_NAME"
echo ""

# --- Step 4: Restore to new disk ---
echo "INFO: [Step 4/5] Restoring image to a new disk..."
RESTORE_DISK_QCOW2="$WORK_DIR/restore.qcow2"

# Create a new disk for restoration, 20% larger than the original.
SIZE_VALUE=$(echo "$DISK_SIZE" | sed 's/[gG]//')
RESTORE_DISK_SIZE_RAW=$(echo "$SIZE_VALUE * 1.2" | bc)
RESTORE_DISK_SIZE=$(printf "%.0fG" "$RESTORE_DISK_SIZE_RAW")
echo "INFO: Creating blank restore disk: $RESTORE_DISK_QCOW2 (Size: $RESTORE_DISK_SIZE)"
qemu-img create -f qcow2 "$RESTORE_DISK_QCOW2" "$RESTORE_DISK_SIZE"

OCS_COMMAND_RESTORE="sudo /usr/sbin/ocs-sr -b -y -j2 -p poweroff restoredisk ${CLONE_IMAGE_NAME} sda"

./qemu_clonezilla_ci_run.sh \
    --disk "$RESTORE_DISK_QCOW2" \
    --live "$CZ_LIVE_QCOW2" \
    --kernel "$CZ_KERNEL" \
    --initrd "$CZ_INITRD" \
    --cmd "$OCS_COMMAND_RESTORE" \
    --image "$PARTIMAG_DIR"
echo "INFO: Restore process finished."
echo ""

# --- Step 5: Verify restored data ---
echo "INFO: [Step 5/5] Verifying restored data..."
RESTORED_DATA_DIR="$WORK_DIR/restored_data"
mkdir -p "$RESTORED_DATA_DIR"

# Use guestfish to export the restored data back to the host
echo "INFO: Exporting restored data from disk image..."
guestfish --ro -a "$RESTORE_DISK_QCOW2" <<!
    run
    mount /dev/${GUESTFISH_DRIVE}1 /
    tar-out / - | (cd ${RESTORED_DATA_DIR} && tar -xf -)
!

echo "INFO: Comparing source and restored checksums..."
# Use md5sum -c to check the restored files against the original checksums.
# We cd into the restored data directory because the paths in the checksum
# file are relative to the parent of the original source directory.
if (cd "$RESTORED_DATA_DIR" && md5sum -c "$SOURCE_CHECKSUM_FILE"); then
    echo ""
    echo "------------------------------------------"
    echo "--- ✅ SUCCESS: All file checksums match. ---"
    echo "------------------------------------------"
    exit 0
else
    echo ""
    echo "-------------------------------------------"
    echo "--- ❌ FAILURE: Checksum mismatch detected! ---"
    echo "-------------------------------------------"
    exit 1
fi