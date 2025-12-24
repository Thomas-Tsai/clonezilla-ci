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
PARTIMAG_LOCATION="" # Default is to use a temporary directory
KEEP_TEMP_FILES=false # Default is to clean up temp files
TMP_PATH="" # Default is to let mktemp decide
CHECKSUM_FILE_PATH="" # Path to external checksum file
ARCH="amd64"
VALIDATE_FS=false # Default is not to run the new fs validation
QEMU_EXTRA_ARGS=""


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
    echo "  --fs <type>       Filesystem type to use (e.g., ext2/34, btrfs, xfs, ntfs, vfat, exfat). (Default: $FILESYSTEM_TYPE)"
    echo "  --size <size>     Size of the source test disk (e.g., '10G'). (Default: $DISK_SIZE)"
    echo "  --partimag <dir>  Directory to store Clonezilla image backups. (Default: temporary directory)"
    echo "  --validate-fs     Run an external filesystem check using validate-fs.sh after restore. (Requires sudo)"
    echo "  --no-ssh-forward  Disable SSH port forwarding in QEMU (for parallel runs)."
    echo "  --keep-temp       Do not delete the temporary working directory on failure, for debugging."
    echo "  --tmp-path <dir>  Specify a base directory for temporary files. (Default: system temporary directory)"
    echo "  --checksum-file <path> Specify a file to load/save checksums. If exists, load; else, generate and save."
    echo "  --arch <arch>     Target architecture (amd64, arm64, riscv64). Default: amd64."
    echo "  -h, --help        Display this help message and exit."
    echo ""
    echo "Example:"
    echo "  $0 --zip zip/clonezilla.zip --data ./my_test_data --fs ext4 --partimag /mnt/my_backups --validate-fs"
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --no-ssh-forward)
            QEMU_EXTRA_ARGS+=" --no-ssh-forward"
            shift 1
            ;;
        --arch)
            ARCH="$2"
            shift 2
            ;;
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
        --partimag)
            PARTIMAG_LOCATION="$2"
            shift 2
            ;;
        --validate-fs)
            VALIDATE_FS=true
            shift 1
            ;;
        --keep-temp)
            KEEP_TEMP_FILES=true
            shift 1
            ;;
        --tmp-path)
            TMP_PATH="$2"
            shift 2
            ;;
        --checksum-file)
            CHECKSUM_FILE_PATH="$2"
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

if [ -n "$PARTIMAG_LOCATION" ]; then
    if [ ! -d "$PARTIMAG_LOCATION" ]; then
        echo "ERROR: User-specified partimag directory not found: $PARTIMAG_LOCATION" >&2
        exit 1
    fi
fi

if [ -n "$TMP_PATH" ]; then
    if [ ! -d "$TMP_PATH" ]; then
        echo "ERROR: User-specified temporary path not found: $TMP_PATH" >&2
        exit 1
    fi
fi

# Validate filesystem type
case "$FILESYSTEM_TYPE" in
    ext2|ext3|ext4|xfs|btrfs|ntfs|vfat|exfat)
        ;;
    *)
        echo "ERROR: Unsupported filesystem type '$FILESYSTEM_TYPE'. Supported types are: ext2, ext3, ext4, xfs, btrfs, ntfs, vfat, exfat." >&2
        exit 1
        ;;
esac
# Validate that required tools exist
for cmd in ./clonezilla-zip2qcow.sh ./qemu-clonezilla-ci-run.sh ./validate-fs.sh qemu-img guestfish guestmount guestunmount md5sum; do
    command -v "$cmd" >/dev/null 2>&1 || { echo >&2 "ERROR: Required command '$cmd' not found. Please ensure it is in your PATH."; exit 1; }
done
echo "INFO: All dependencies found."
echo ""


echo "--- Data Clone & Restore Test ---"
echo "Clonezilla ZIP: $CLONEZILLA_ZIP"
echo "Source Data:    $SOURCE_DATA_DIR"
echo "Filesystem:     $FILESYSTEM_TYPE"
echo "Disk Size:      $DISK_SIZE"
if [ -n "$CHECKSUM_FILE_PATH" ]; then
    echo "Checksum File:  $CHECKSUM_FILE_PATH"
fi
if [ "$VALIDATE_FS" = "true" ]; then
    echo "FS Validation:  Enabled"
fi
echo "---------------------------------"

# --- Main Workflow ---

# Create a temporary working directory for this test run.
if [ -n "$TMP_PATH" ]; then
    WORK_DIR=$(mktemp -d -p "$TMP_PATH" cci_dcr_test.XXXXXXXX)
else
    WORK_DIR=$(mktemp -d cci_dcr_test.XXXXXXXX)
fi
echo "INFO: Using temporary working directory: $WORK_DIR"

# The cleanup function is called on EXIT. It checks the exit code and the
# --keep-temp flag to decide whether to remove the temporary directory.
cleanup() {
    exit_code=$?

    # First, handle unmounting if a guestmount was performed
    MOUNT_POINT="$WORK_DIR/mnt"
    if [ -d "$MOUNT_POINT" ] && mountpoint -q "$MOUNT_POINT"; then
        echo "INFO: Attempting to unmount FUSE filesystem at $MOUNT_POINT..."
        if ! guestunmount "$MOUNT_POINT"; then
            echo "WARNING: Failed to unmount $MOUNT_POINT. Manual intervention may be required." >&2
        fi
    fi

    if [ $exit_code -ne 0 ]; then
        echo "ERROR: Script failed. Temporary directory retained for debugging: $WORK_DIR"
    elif [ "$KEEP_TEMP_FILES" = "true" ]; then
        echo "INFO: Temporary directory retained as requested by --keep-temp: $WORK_DIR"
    else
        echo "INFO: Cleaning up temporary directory $WORK_DIR"
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

# --- Step 1: Convert Clonezilla zip to QCOW2 ---
echo "INFO: [Step 1/6] Converting Clonezilla ZIP to QCOW2 format..."
./clonezilla-zip2qcow.sh --zip "$CLONEZILLA_ZIP" --output "$WORK_DIR" --force --arch "$ARCH" > /dev/null

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
echo "INFO: [Step 2/6] Preparing source disk..."
SOURCE_DISK_QCOW2="$WORK_DIR/source.qcow2"

echo "INFO: Creating blank source disk: $SOURCE_DISK_QCOW2"
qemu-img create -f qcow2 "$SOURCE_DISK_QCOW2" "$DISK_SIZE"

echo "INFO: Partitioning and formatting disk with filesystem: $FILESYSTEM_TYPE"
GUESTFISH_DRIVE="sda" # Use a more standard device name
case "$FILESYSTEM_TYPE" in
    ext2) MKFS_COMMAND="mkfs ext2 /dev/${GUESTFISH_DRIVE}1" ;;
    ext3) MKFS_COMMAND="mkfs ext3 /dev/${GUESTFISH_DRIVE}1" ;;
    ext4) MKFS_COMMAND="mkfs ext4 /dev/${GUESTFISH_DRIVE}1" ;;
    xfs) MKFS_COMMAND="mkfs xfs /dev/${GUESTFISH_DRIVE}1" ;;
    btrfs) MKFS_COMMAND="mkfs btrfs /dev/${GUESTFISH_DRIVE}1" ;;
    ntfs) MKFS_COMMAND="mkfs ntfs /dev/${GUESTFISH_DRIVE}1" ;;
    vfat|fat32) MKFS_COMMAND="mkfs vfat /dev/${GUESTFISH_DRIVE}1" ;;
    exfat) MKFS_COMMAND="mkfs exfat /dev/${GUESTFISH_DRIVE}1" ;;
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

# Determine the checksum file to use. The final path must be absolute for verification.
_ABS_CHECKSUM_FILE=""
if [ -n "$CHECKSUM_FILE_PATH" ]; then
    _ABS_CHECKSUM_FILE=$(realpath -m "$CHECKSUM_FILE_PATH")
fi

if [ -n "$_ABS_CHECKSUM_FILE" ] && [ -f "$_ABS_CHECKSUM_FILE" ]; then
    echo "INFO: Using existing checksum file: $_ABS_CHECKSUM_FILE"
    SOURCE_CHECKSUM_FILE="$_ABS_CHECKSUM_FILE"
else
    # If no file is specified, or it doesn't exist, generate one.
    if [ -n "$_ABS_CHECKSUM_FILE" ]; then
        # User specified a file path, but it doesn't exist. We will create it.
        SOURCE_CHECKSUM_FILE="$_ABS_CHECKSUM_FILE"
    else
        # No file specified, use a temporary one.
        SOURCE_CHECKSUM_FILE="$WORK_DIR/source_checksums.md5"
    fi
    echo "INFO: Calculating checksums of source data..."
    SOURCE_DATA_DIR_PARENT=$(dirname "$_ABS_SOURCE_DATA_DIR")
    SOURCE_DATA_DIR_BASENAME=$(basename "$_ABS_SOURCE_DATA_DIR")
    (cd "$SOURCE_DATA_DIR_PARENT" && find "$SOURCE_DATA_DIR_BASENAME" -type f -exec md5sum {} + | sort -k 2) > "$SOURCE_CHECKSUM_FILE"
    echo "INFO: Source checksums saved to $SOURCE_CHECKSUM_FILE"
fi

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
echo "INFO: [Step 3/6] Backing up source disk using Clonezilla..."
# Determine the partimag directory: use user-specified or create a temporary one.
if [ -n "$PARTIMAG_LOCATION" ]; then
    PARTIMAG_DIR="$PARTIMAG_LOCATION"
    echo "INFO: Using user-specified partimag directory: $PARTIMAG_DIR"
else
    PARTIMAG_DIR="$WORK_DIR/partimag"
    mkdir -p "$PARTIMAG_DIR"
    echo "INFO: Using temporary partimag directory: $PARTIMAG_DIR"
fi

CLONE_IMAGE_NAME="dcr-image-$(date +%s)"
OCS_COMMAND="sudo /usr/sbin/ocs-sr -b -senc -sfsck -j2 -q2 -z1 -p poweroff savedisk ${CLONE_IMAGE_NAME} vda"
# Use -b and -y for non-interactive batch mode
./qemu-clonezilla-ci-run.sh \
    --disk "$SOURCE_DISK_QCOW2" \
    --live "$CZ_LIVE_QCOW2" \
    --kernel "$CZ_KERNEL" \
    --initrd "$CZ_INITRD" \
    --cmd "$OCS_COMMAND" \
    --image "$PARTIMAG_DIR" \
    --arch "$ARCH" \
    $QEMU_EXTRA_ARGS

if [ ! -d "$PARTIMAG_DIR/$CLONE_IMAGE_NAME" ]; then
    echo "ERROR: Backup failed. Image directory '$PARTIMAG_DIR/$CLONE_IMAGE_NAME' not found." >&2
    exit 1
fi
echo "INFO: Backup completed successfully to $PARTIMAG_DIR/$CLONE_IMAGE_NAME"
echo ""

# --- Step 4: Restore to new disk ---
echo "INFO: [Step 4/6] Restoring image to a new disk..."
RESTORE_DISK_QCOW2="$WORK_DIR/restore.qcow2"

# Create a new disk for restoration, 20% larger than the original.
SIZE_VALUE=$(echo "$DISK_SIZE" | sed 's/[gG]//')
RESTORE_DISK_SIZE_RAW=$(echo "$SIZE_VALUE * 1.2" | bc)
RESTORE_DISK_SIZE=$(printf "%.0fG" "$RESTORE_DISK_SIZE_RAW")
echo "INFO: Creating blank restore disk: $RESTORE_DISK_QCOW2 (Size: $RESTORE_DISK_SIZE)"
qemu-img create -f qcow2 "$RESTORE_DISK_QCOW2" "$RESTORE_DISK_SIZE"

OCS_COMMAND_RESTORE="sudo /usr/sbin/ocs-sr -b -k0 -j2 -p poweroff restoredisk ${CLONE_IMAGE_NAME} vda"

./qemu-clonezilla-ci-run.sh \
    --disk "$RESTORE_DISK_QCOW2" \
    --live "$CZ_LIVE_QCOW2" \
    --kernel "$CZ_KERNEL" \
    --initrd "$CZ_INITRD" \
    --cmd "$OCS_COMMAND_RESTORE" \
    --image "$PARTIMAG_DIR" \
    --arch "$ARCH" \
    $QEMU_EXTRA_ARGS
echo "INFO: Restore process finished."
echo ""

# --- Step 5: Validate Filesystem Health (Optional) ---
echo "INFO: [Step 5/6] Validating filesystem health of restored disk..."
if [ "$VALIDATE_FS" = "true" ]; then
    echo "INFO: --validate-fs flag is set. Running external filesystem check."
    # The 'set -e' at the top of the script will cause it to exit on failure.
    ./validate-fs.sh --qcow2 "$RESTORE_DISK_QCOW2" --fstype "$FILESYSTEM_TYPE"
    echo "INFO: Filesystem check via validate-fs.sh passed."
else
    echo "INFO: Skipping filesystem health check (--validate-fs not specified)."
fi
echo ""

# --- Step 6: Verify restored data ---
echo "INFO: [Step 6/6] Verifying restored data integrity via checksums..."

MOUNT_POINT="$WORK_DIR/mnt"
CHECKSUM_LOG="$WORK_DIR/checksum_verification.log"
mkdir -p "$MOUNT_POINT"

# Mount the restored disk image read-only
echo "INFO: Mounting restored disk image..."
guestmount -a "$RESTORE_DISK_QCOW2" -m "/dev/sda1" --ro "$MOUNT_POINT"

echo "INFO: Comparing source and restored checksums..."
# Use md5sum -c to check the restored files against the original checksums.
# The --quiet flag suppresses 'OK' messages for matching files.
# The full output (only errors, if any) is saved to a log file.
# We temporarily disable 'exit on error' to handle the md5sum result manually.
set +e
# The paths in the checksum file are relative, and guestmount presents the
# restored files at the root of the mount point, so we cd there to run the check.
(cd "$MOUNT_POINT" && md5sum --quiet -c "$SOURCE_CHECKSUM_FILE") &> "$CHECKSUM_LOG"
result=$?
set -e

# Unmount the disk image
echo "INFO: Unmounting restored disk image."
guestunmount "$MOUNT_POINT"

if [ $result -eq 0 ]; then
    echo ""
    echo "------------------------------------------"
    echo "--- ✅ SUCCESS: All file checksums match. ---"
    echo "------------------------------------------"
    # Overwrite the log with a success message since there were no errors.
    echo "All files passed checksum verification." > "$CHECKSUM_LOG"
    echo "INFO: Full verification report is in $CHECKSUM_LOG"
    exit 0
else
    echo ""
    echo "-------------------------------------------"
    echo "--- ❌ FAILURE: Checksum mismatch detected! ---"
    echo "-------------------------------------------"
    # The log file only contains the failed checksum lines, so just cat it.
    cat "$CHECKSUM_LOG"
    echo "-------------------------------------------"
    echo "INFO: Full verification report is in $CHECKSUM_LOG"
    exit 1
fi
