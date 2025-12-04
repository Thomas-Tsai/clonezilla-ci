#!/bin/bash
# ----------------------------------------------------------------------
# Linux Distro Clone/Restore/Validate Orchestration Script
#
# This script automates the entire process of:
# 1. Preparing a Clonezilla live medium.
# 2. Backing up a source Linux qcow2 image using Clonezilla.
# 3. Restoring the backup to a new qcow2 image.
# 4. Validating that the restored image boots and runs a cloud-init script.
# ----------------------------------------------------------------------

set -e # Exit immediately if a command exits with a non-zero status.

# --- Default values ---
CLONEZILLA_ZIP=""
TEMPLATE_QCOW=""
CLONE_IMAGE_NAME="debian-sid" # The image name used in the ocs-sr commands
PARTIMAG_DIR="./partimag"
QEMU_DIR="./qemu"
ISOS_DIR="./isos"
RESTORE_DISK_SIZE="30G"
VALIDATE_ISO="dev/cloudinit/cloud_init_config/cidata.iso"

# --- Helper Functions ---

# Function to display usage information
print_usage() {
    echo "Usage: $0 --zip <ClonezillaZip> --tmpl <TemplateQcow>"
    echo ""
    echo "This script runs a full backup, restore, and validation cycle."
    echo ""
    echo "Required Arguments:"
    echo "  --zip <path>   Path to the Clonezilla Live ZIP file."
    echo "  --tmpl <path>  Path to the source Linux distro QCOW2 template image."
    echo ""
    echo "Optional Arguments:"
    echo "  -h, --help     Display this help message and exit."
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --zip)
            CLONEZILLA_ZIP="$2"
            shift 2
            ;;
        --tmpl)
            TEMPLATE_QCOW="$2"
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

# Check for required scripts
for script in clonezilla_zip2qcow.sh qemu_clonezilla_ci_run.sh validateOS.sh; do
    if ! command -v "./${script}" &> /dev/null; then
        echo "ERROR: Required script ./${script} not found or not executable." >&2
        exit 1
    fi
done

# --- Main Workflow ---

echo "--- (Step 1/5) Preparing Clonezilla Live Media ---"
# The output directory will be named after the zip file, inside ISOS_DIR
CZ_ZIP_BASENAME=$(basename "$CLONEZILLA_ZIP" .zip)
CZ_LIVE_DIR="$ISOS_DIR/$CZ_ZIP_BASENAME"

./clonezilla_zip2qcow.sh --zip "$CLONEZILLA_ZIP" -o "$ISOS_DIR" --force

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
BACKUP_SOURCE_DISK="$QEMU_DIR/${TMPL_BASENAME}.sda.qcow2"
cp "$TEMPLATE_QCOW" "$BACKUP_SOURCE_DISK"
echo "Copied template to $BACKUP_SOURCE_DISK"
echo "--- Source Disk prepared successfully. ---"
echo

# Cleanup for temporary disks
trap 'echo "--- Cleaning up temporary disks ---"; rm -f "$BACKUP_SOURCE_DISK" "$RESTORE_DISK";' EXIT

echo "--- (Step 3/5) Backing up the Source Disk ---"
./qemu_clonezilla_ci_run.sh \
  --disk "$BACKUP_SOURCE_DISK" \
  --live "$CZ_LIVE_QCOW" \
  --kernel "$CZ_KERNEL" \
  --initrd "$CZ_INITRD" \
  --cmdpath "dev/ocscmd/clone-first-disk.sh" \
  --image "$PARTIMAG_DIR"
echo "--- Backup completed successfully. ---"
echo

echo "--- (Step 4/5) Restoring to a New Disk ---"
RESTORE_DISK="$QEMU_DIR/restore.qcow2"
echo "Creating new 30G disk at $RESTORE_DISK..."
qemu-img create -f qcow2 "$RESTORE_DISK" "$RESTORE_DISK_SIZE"

./qemu_clonezilla_ci_run.sh \
  --disk "$RESTORE_DISK" \
  --live "$CZ_LIVE_QCOW" \
  --kernel "$CZ_KERNEL" \
  --initrd "$CZ_INITRD" \
  --cmdpath "dev/ocscmd/restore-first-disk.sh" \
  --image "$PARTIMAG_DIR"
echo "--- Restore completed successfully. ---"
echo

echo "--- (Step 5/5) Validating the Restored Disk ---"
./validateOS.sh \
  --iso "$VALIDATE_ISO" \
  --disk "$RESTORE_DISK" \
  --timeout 300
echo "--- Validation completed successfully. ---"
echo

echo "===== Full Clone, Restore, and Validation Cycle Completed Successfully! ===="
# The trap will handle cleanup on successful exit.
exit 0
