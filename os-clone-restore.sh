#!/bin/bash
# ----------------------------------------------------------------------
# OS Clone/Restore/Validate Orchestration Script
#
# This script automates the entire process of:
# 1. Preparing a Clonezilla live medium.
# 2. Backing up a source OS qcow2 image using Clonezilla.
# 3. Restoring the backup to a new qcow2 image.
# 4. Validating that the restored image boots and runs a cloud-init script.
# ----------------------------------------------------------------------

set -e # Exit immediately if a command exits with a non-zero status.

# --- Default values ---
CLONEZILLA_ZIP=""
TEMPLATE_QCOW=""
CLONE_IMAGE_NAME="" # Default image name for the backup/restore process
PARTIMAG_DIR="./partimag"
QEMU_DIR="./qemu"
ISOS_DIR="./isos"
ZIP_DIR="./zip"
RESTORE_DISK_SIZE="80G"
VALIDATE_ISO="$ISOS_DIR/cidata.iso"
KEEP_TEMP_FILES=false # Default is to clean up temp files
ARCH="amd64"


# --- Helper Functions ---

# Function to display usage information
print_usage() {
    echo "Usage: $0 --zip <ClonezillaZip> --tmpl <TemplateQcow> [OPTIONS]"
    echo ""
    echo "This script runs a full backup, restore, and validation cycle."
    echo ""
    echo "Required Arguments:"
    echo "  --zip <path>   Path to the Clonezilla Live ZIP file."
    echo "  --tmpl <path>  Path to the source OS distro QCOW2 template image."
    echo ""
    echo "Optional Arguments:"
    echo "  --image-name <name>   Name for the Clonezilla image folder. (Default: based on template filename)"
    echo "  --arch <arch>         Target architecture (amd64, arm64, riscv64). Default: amd64."
    echo "  --validate-iso <path> Path to the validation ISO file. (Default: $VALIDATE_ISO)"
    echo "  --keep-temp           Do not delete the temporary working directory on failure, for debugging."
    echo "  -h, --help            Display this help message and exit."
}

# Cleanup for temporary files and directories
cleanup_on_exit() {
    local exit_code=$?
    echo "--- Running cleanup ---"

    if [ "$KEEP_TEMP_FILES" = "true" ]; then
        if [ "$exit_code" -ne 0 ]; then
            echo "ERROR: Script failed with exit code $exit_code. Temporary directory retained for debugging: $TEMP_DIR"
        else
            echo "INFO: Temporary directory retained as requested by --keep-temp: $TEMP_DIR"
        fi
    else
        echo "INFO: Cleaning up temporary files and disks."
        rm -f "$BACKUP_SOURCE_DISK" "$RESTORE_DISK"
        rm -rf "$TEMP_DIR"
    fi
}

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
        --tmpl)
            TEMPLATE_QCOW="$2"
            shift 2
            ;;
        --image-name)
            CLONE_IMAGE_NAME="$2"
            shift 2
            ;;
        --validate-iso)
            VALIDATE_ISO="$2"
            shift 2
            ;;
        --keep-temp)
            KEEP_TEMP_FILES=true
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
if [[ -z "$CLONEZILLA_ZIP" || -z "$TEMPLATE_QCOW" ]]; then
    echo "ERROR: Both --zip and --tmpl arguments are required." >&2
    print_usage
    exit 1
fi

if [ ! -f "$CLONEZILLA_ZIP" ]; then
    echo "ERROR: Clonezilla ZIP file not found: $CLONEZILLA_ZIP" >&2
    exit 1
fi

if [ ! -f "$TEMPLATE_QCOW" ]; then
    echo "ERROR: Template QCOW2 file not found: $TEMPLATE_QCOW" >&2
    exit 1
fi

if [ ! -f "$VALIDATE_ISO" ]; then
    echo "ERROR: Validation ISO file not found: $VALIDATE_ISO" >&2
    exit 1
fi

# If no image name is provided, derive it from the template filename
if [ -z "$CLONE_IMAGE_NAME" ]; then
    CLONE_IMAGE_NAME=$(basename "$TEMPLATE_QCOW" .qcow2)
    echo "INFO: --image-name not specified, deriving from template: $CLONE_IMAGE_NAME"
fi

# Check for required scripts
for script in clonezilla-zip2qcow.sh qemu-clonezilla-ci-run.sh validate.sh; do
    if ! command -v "./${script}" &> /dev/null; then
        echo "ERROR: Required script ./${script} not found or not executable." >&2
        exit 1
    fi
done

# --- Main Workflow ---

TEMP_DIR=$(mktemp -d)
BACKUP_SOURCE_DISK="" # Initialize for trap
RESTORE_DISK=""       # Initialize for trap

# Set the trap to call the cleanup function
trap cleanup_on_exit EXIT


echo "--- (Step 1/5) Preparing Clonezilla Live Media ---"
# The output directory will be named after the zip file, inside ZIP_DIR
CZ_ZIP_BASENAME=$(basename "$CLONEZILLA_ZIP" .zip)
CZ_LIVE_DIR="$ZIP_DIR/$CZ_ZIP_BASENAME"

./clonezilla-zip2qcow.sh --zip "$CLONEZILLA_ZIP" -o "$ZIP_DIR" --force --arch "$ARCH"
# Define paths to the generated Clonezilla files
CZ_LIVE_QCOW="$CZ_LIVE_DIR/$CZ_ZIP_BASENAME.qcow2"
CZ_KERNEL="$CZ_LIVE_DIR/${CZ_ZIP_BASENAME}-vmlinuz"
CZ_INITRD="$CZ_LIVE_DIR/${CZ_ZIP_BASENAME}-initrd.img"

# Check that the files were created
if [ ! -f "$CZ_LIVE_QCOW" ] || [ ! -f "$CZ_KERNEL" ] || [ ! -f "$CZ_INITRD" ]; then
    echo "ERROR: Failed to create Clonezilla live media files. Aborting." >&2
    exit 1
fi
echo "--- Clonezilla Live Media created successfully. ---"
echo

echo "--- (Step 2/5) Preparing Source Disk for Backup ---"
TMPL_BASENAME=$(basename "$TEMPLATE_QCOW")
BACKUP_SOURCE_DISK="$QEMU_DIR/${TMPL_BASENAME}.vda.qcow2"
cp "$TEMPLATE_QCOW" "$BACKUP_SOURCE_DISK"
echo "Copied template to $BACKUP_SOURCE_DISK"
echo "--- Source Disk prepared successfully. ---"
echo


echo "--- (Step 3/5) Backing up the Source Disk ---"
# Generate a temporary clone script with the specified image name
CLONE_SCRIPT_PATH="$TEMP_DIR/clone-disk.sh"
echo "Generating clone script at: $CLONE_SCRIPT_PATH"
# Read the base command and replace the hardcoded name with the desired one
sed "s/\"debian-sid\"/\"$CLONE_IMAGE_NAME\"/" "dev/ocscmd/clone-first-disk.sh" > "$CLONE_SCRIPT_PATH"

./qemu-clonezilla-ci-run.sh \
  --disk "$BACKUP_SOURCE_DISK" \
  --live "$CZ_LIVE_QCOW" \
  --kernel "$CZ_KERNEL" \
  --initrd "$CZ_INITRD" \
  --cmdpath "$CLONE_SCRIPT_PATH" \
  --image "$PARTIMAG_DIR" \
  --arch "$ARCH"
echo "--- Backup completed successfully. ---"
echo

echo "--- (Step 4/5) Restoring to a New Disk ---"
RESTORE_DISK="$QEMU_DIR/restore.qcow2"
echo "Creating new 30G disk at $RESTORE_DISK..."
qemu-img create -f qcow2 "$RESTORE_DISK" "$RESTORE_DISK_SIZE"

# Generate a temporary restore script with the specified image name
RESTORE_SCRIPT_PATH="$TEMP_DIR/restore-disk.sh"
echo "Generating restore script at: $RESTORE_SCRIPT_PATH"
sed "s/\"debian-sid\"/\"$CLONE_IMAGE_NAME\"/" "dev/ocscmd/restore-first-disk.sh" > "$RESTORE_SCRIPT_PATH"

./qemu-clonezilla-ci-run.sh \
  --disk "$RESTORE_DISK" \
  --live "$CZ_LIVE_QCOW" \
  --kernel "$CZ_KERNEL" \
  --initrd "$CZ_INITRD" \
  --cmdpath "$RESTORE_SCRIPT_PATH" \
  --image "$PARTIMAG_DIR" \
  --arch "$ARCH"
echo "--- Restore completed successfully. ---"
echo

echo "--- (Step 5/5) Validating the Restored Disk ---"
./validate.sh \
  --iso "$VALIDATE_ISO" \
  --disk "$RESTORE_DISK" \
  --timeout 300 \
  --arch "$ARCH"
echo "--- Validation completed successfully. ---"
echo

echo "===== Full Clone, Restore, and Validation Cycle Completed Successfully! ===="
# The trap will handle cleanup on successful exit.
exit 0
