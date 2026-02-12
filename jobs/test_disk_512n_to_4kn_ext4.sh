#!/bin/bash
#
# test_disk_512n_to_4kn_ext4.sh - End-to-end test: 512-byte source to 4Kn target.
#
#   * source disk : 512-byte block size, ext4, contains ./dev/testData/
#   * backup      : Clonezilla using default (512-byte) block size
#   * restore     : 4KiB NVMe disk (device name nvme0n1)
#   * verification: MD5 checksum of every file must match.
#

# Source the common script
. "$(dirname "$0")/common.sh"

# --- Argument Parsing ---
while [ "$#" -gt 0 ]; do
    case "$1" in
        --zip)
            CLONEZILLA_ZIP="$2"
            shift 2
            ;;
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --type)
            TYPE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --no-ssh-forward)
            NO_SSH_FORWARD_ARGS="--no-ssh-forward"
            shift 1
            ;;
        *)
            # Stop parsing at the first unknown argument
            break
            ;;
    esac
done

# Convert CLONEZILLA_ZIP to an absolute path if it was provided
if [[ -n "$CLONEZILLA_ZIP" ]]; then
    CLONEZILLA_ZIP="$(realpath "$CLONEZILLA_ZIP")"
fi

# Global variables
WORK_DIR="$PROJECT_ROOT/cci_test_512n_4kn_$(date +%s)"
SOURCE_DISK="$WORK_DIR/source-512n.qcow2"
TARGET_DISK="$WORK_DIR/target-4kn.qcow2"
SRC_MD5_FILE="$WORK_DIR/checksums_source.md5"
REST_MD5_FILE="$WORK_DIR/checksums_restore.md5"
IMG_NAME="4k-512n-ext4-$(date +%s)"
PARTIMAG_DIR="$WORK_DIR/partimag"

oneTimeSetUp() {
    # Create working directories
    mkdir -p "$WORK_DIR/qemu"
    mkdir -p "$PARTIMAG_DIR"
    
    info "Using temporary working directory: $WORK_DIR"
    info "Preparing source disk (512n, ext4)..."

    # Create source disk
    qemu-img create -f qcow2 "$SOURCE_DISK" 5G

    # Use guestfish directly to setup partitions and data
    guestfish --rw -a "$SOURCE_DISK" <<EOF
run
part-init /dev/sda mbr
part-add /dev/sda p 2048 -1
mkfs ext4 /dev/sda1
mount /dev/sda1 /
copy-in "${PROJECT_ROOT}/dev/testData" /
umount /
EOF

    # Generate source MD5 (relative to testData)
    info "Generating source MD5 checksums..."
    # checksums of files INSIDE dev/testData
    (cd "${PROJECT_ROOT}/dev/testData" && find . -type f -exec md5sum {} + | sort -k 2) > "$SRC_MD5_FILE"
}

oneTimeTearDown() {
    # Cleanup
    if [ -d "$WORK_DIR" ]; then
        info "Cleaning up working directory: $WORK_DIR"
        #rm -rf "$WORK_DIR"
    fi
}

test_512n_to_4kn_ext4() {
    info "--- Starting Test: 512n Source to 4Kn Target ---"

    # 1. Backup
    # -b: run in batch mode
    # -senc: skip encfs check
    # -sfsck: skip fsck
    # -j2: cloning hidden data area
    # -q2: partclone legacy
    # -z1: gzip compression
    # -p poweroff: poweroff after completion
    local OCS_BACKUP="sudo /usr/sbin/ocs-sr -b -senc -sfsck -j2 -q2 -z1 -p poweroff savedisk ${IMG_NAME} vda"
    
    info "Running Clonezilla Backup..."
    ${PROJECT_ROOT}/qemu-clonezilla-ci-run.sh \
        --disk "$SOURCE_DISK" \
        --zip "$CLONEZILLA_ZIP" \
        --image "$PARTIMAG_DIR" \
        --arch "$ARCH" \
        --cmd "$OCS_BACKUP" \
        $NO_SSH_FORWARD_ARGS \
        --log-dir "$LOG_DIR"

    assertEquals "Backup failed" 0 $?

    # 2. Prepare Target Disk (4kn)
    info "Creating target disk (4kn)..."
    qemu-img create -f qcow2 "$TARGET_DISK" 5G

    # 3. Restore
    # -k0: Create partition table proportionally
    # restoredisk to nvme0n1
    local OCS_RESTORE="sudo /usr/sbin/ocs-sr -b -k0 -j2 -p poweroff restoredisk ${IMG_NAME} nvme0n1"
    
    info "Running Clonezilla Restore to NVMe (4Kn)..."
    ${PROJECT_ROOT}/qemu-clonezilla-ci-run.sh \
        --disk "$TARGET_DISK" \
        --disk-driver nvme \
        --disk-lbas 4096 \
        --disk-pbas 4096 \
        --zip "$CLONEZILLA_ZIP" \
        --image "$PARTIMAG_DIR" \
        --arch "$ARCH" \
        --cmd "$OCS_RESTORE" \
        $NO_SSH_FORWARD_ARGS \
        --log-dir "$LOG_DIR"

    assertEquals "Restore failed" 0 $?

    info "Verifying restored data using QEMU VM..."
    local VM_MD5_FILE="checksums_restore_vm.md5"
    local VERIFY_SCRIPT="$WORK_DIR/verify_restore.sh"

    # Create the verification script
    cat > "$VERIFY_SCRIPT" <<EOF
#!/bin/bash
sudo mount /dev/nvme0n1p1 /mnt
if [ -d /mnt/testData ]; then
  cd /mnt/testData && find . -type f -exec md5sum {} + | sort -k 2 > /home/partimag/$VM_MD5_FILE
else
  echo 'ERROR: testData directory not found' > /home/partimag/error.log
fi
sudo poweroff
EOF
    chmod +x "$VERIFY_SCRIPT"

    info "Booting restored disk for verification..."
    
    # Run QEMU with the verification script
    # We use --cmdpath to execute the script inside the VM.
    ${PROJECT_ROOT}/qemu-clonezilla-ci-run.sh \
        --disk "$TARGET_DISK" \
        --disk-driver nvme \
        --disk-lbas 4096 \
        --disk-pbas 4096 \
        --zip "$CLONEZILLA_ZIP" \
        --image "$PARTIMAG_DIR" \
        --arch "$ARCH" \
        --cmdpath "$VERIFY_SCRIPT" \
        --no-ssh-forward \
        --log-dir "$LOG_DIR"
    
    local VM_EXIT=$?
    if [ $VM_EXIT -ne 0 ]; then
        fail "Verification VM failed to run or exit cleanly (Exit code: $VM_EXIT)."
        return 1
    fi

    # Check if error log exists
    if [ -f "$PARTIMAG_DIR/error.log" ]; then
        error "Verification failed inside VM:"
        cat "$PARTIMAG_DIR/error.log"
        fail "Verification failed inside VM"
        return 1
    fi

    # Check if MD5 file exists
    if [ ! -f "$PARTIMAG_DIR/$VM_MD5_FILE" ]; then
        error "Verification failed: MD5 file not created by VM at $PARTIMAG_DIR/$VM_MD5_FILE"
        fail "MD5 file missing"
        return 1
    fi

    # Move the generated file to the expected location variable
    mv "$PARTIMAG_DIR/$VM_MD5_FILE" "$REST_MD5_FILE"

    # Compare
    diff -u "$SRC_MD5_FILE" "$REST_MD5_FILE" > "$WORK_DIR/md5_diff.log"
    local DIFF_RES=$?

    if [ $DIFF_RES -eq 0 ]; then
        info "MD5 verification succeeded!"
    else
        error "MD5 verification failed! See $WORK_DIR/md5_diff.log"
        cat "$WORK_DIR/md5_diff.log"
    fi

    assertEquals "MD5 verification mismatch" 0 $DIFF_RES
}

# Initialize common setup
initialize_test_environment

# Load shunit2
. shunit2
