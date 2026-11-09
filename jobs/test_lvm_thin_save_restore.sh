#!/bin/bash
#
# test_lvm_thin_save_restore.sh - Automated test for saving LVM (including thin provisioning) as an image, cleaning destination disk, and restoring the image.
#
# Usage:   ./test_lvm_thin_save_restore.sh [options]
#
# Options:
#   --zip <path>         Path to Clonezilla Live ZIP.
#   --arch <arch>        Target architecture (amd64, arm64, ...).
#   --type <type>        Release type (stable, testing).
#   --no-ssh-forward     Disable SSH port forwarding.
#   -h|--help            Show this help message.
#
# Environment:
#   LOG_DIR - Directory for log files (default: ./logs).
#
# Dependencies: qemu-system-x86_64, shunit2
#
# Minimum Clonezilla Live version: 3.3.4-23 / 20261108-* (LVM thin provisioning
# support); with an older zip the test exits 0 as SKIPPED via
# skip_unless_clonezilla_version_or_newer in jobs/common.sh.
#
# Author: Thomas (maintainer)
# SPDX-License-Identifier: GPL-2.0-or-later
#

# Source the common script
# shellcheck source=/dev/null
. "$(dirname "$0")/common.sh"

NO_SSH_FORWARD_ARG=""

# --- Argument Parsing ---
while [ "$#" -gt 0 ]; do
    case "$1" in
        --zip)
            CLONEZILLA_ZIP="$(realpath "$2")"
            shift 2
            ;;
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --type)
            export TYPE="$2"
            shift 2
            ;;
        --no-ssh-forward)
            NO_SSH_FORWARD_ARG="--no-ssh-forward"
            shift 1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            # Stop parsing at the first unknown argument
            break
            ;;
    esac
done

test_lvm_thin_save_restore() {
    echo "--- Preparing Disk for LVM Thin Save and Restore Test ---"
    qemu-img create -f qcow2 ../qemu/disk-lvm-sr.qcow2 15G

    # Ensure cleanup happens when the function returns
    trap 'rm -f ../qemu/disk-lvm-sr.qcow2 ../dev/ocscmd/lvm_thin_save_restore_test.sh; rm -rf ../partimag/lvm-thin-backup ../partimag/expected_*.md5' RETURN

    # Ensure partimag directory exists
    mkdir -p ../partimag

    # Generate the internal test script for QEMU
    mkdir -p ../dev/ocscmd
    cat << 'EOF' > ../dev/ocscmd/lvm_thin_save_restore_test.sh
#!/bin/bash
# This script runs inside the Clonezilla Live environment to test:
# 1. Setting up LVM with thin provisioning on /dev/vda
# 2. Saving /dev/vda as an image to /home/partimag
# 3. Cleaning the destination disk /dev/vda completely
# 4. Restoring the saved image back to the destination disk /dev/vda
# 5. Verifying LVM structure, thin pool reconstruction, and data integrity

echo "=== [1/5] Setting up LVM with Thin Provisioning on source disk (/dev/vda) ==="
# Load device-mapper kernel modules if not already loaded
modprobe dm-mod 2>/dev/null || true
modprobe dm-thin-pool 2>/dev/null || true

# Deactivate existing LVM or swap
swapoff -a 2>/dev/null || true
vgchange -an 2>/dev/null || true

# Clean up any leftover image or checksums in /home/partimag
rm -rf /home/partimag/lvm-thin-backup
rm -f /home/partimag/expected_*.md5

# Partition vda:
#   vda1: 1G standard Linux partition (boot/system simulation)
#   vda2: ~14G Linux LVM Physical Volume
sgdisk -Z /dev/vda
sgdisk -n 1:2048:+1G -c 1:"boot" -t 1:8300 /dev/vda
sgdisk -n 2:0:0      -c 2:"lvm"  -t 2:8e00 /dev/vda
partprobe /dev/vda
udevadm settle
sleep 2

# Format and prepare boot partition (vda1)
mkfs.ext4 -F /dev/vda1
mkdir -p /mnt/a_boot
mount /dev/vda1 /mnt/a_boot
echo "Clonezilla CI Boot File $(date)" > /mnt/a_boot/boot_info.txt
(cd /mnt/a_boot && md5sum boot_info.txt) > /home/partimag/expected_boot.md5
umount /mnt/a_boot

# Initialize LVM Physical Volume and Volume Group
pvcreate -ff -y /dev/vda2
vgcreate -y vg_ci /dev/vda2

# Create regular Linear Logical Volume (1G)
lvcreate -y -L 1G -n reg_vol vg_ci
mkfs.ext4 -F /dev/vg_ci/reg_vol
mkdir -p /mnt/a_reg
mount /dev/vg_ci/reg_vol /mnt/a_reg
mkdir -p /mnt/a_reg/data
for i in $(seq 1 5); do
    dd if=/dev/urandom of=/mnt/a_reg/data/file_"$i".bin bs=1M count=2 status=none
done
(cd /mnt/a_reg/data && md5sum ./*.bin) > /home/partimag/expected_reg.md5
umount /mnt/a_reg

# Create LVM Thin Pool (8G pool in vg_ci)
lvcreate -y -L 8G -T vg_ci/thin_pool

# Create Thin Logical Volume 1 (2G virtual size)
lvcreate -y -V 2G -T vg_ci/thin_pool -n thin_vol1
mkfs.ext4 -F /dev/vg_ci/thin_vol1
mkdir -p /mnt/a_thin1
mount /dev/vg_ci/thin_vol1 /mnt/a_thin1
mkdir -p /mnt/a_thin1/data
for i in $(seq 1 5); do
    dd if=/dev/urandom of=/mnt/a_thin1/data/file_"$i".bin bs=1M count=2 status=none
done
(cd /mnt/a_thin1/data && md5sum ./*.bin) > /home/partimag/expected_thin1.md5
umount /mnt/a_thin1

# Create Thin Logical Volume 2 (2G virtual size)
lvcreate -y -V 2G -T vg_ci/thin_pool -n thin_vol2
mkfs.ext4 -F /dev/vg_ci/thin_vol2
mkdir -p /mnt/a_thin2
mount /dev/vg_ci/thin_vol2 /mnt/a_thin2
mkdir -p /mnt/a_thin2/data
for i in $(seq 1 5); do
    dd if=/dev/urandom of=/mnt/a_thin2/data/file_"$i".bin bs=1M count=2 status=none
done
(cd /mnt/a_thin2/data && md5sum ./*.bin) > /home/partimag/expected_thin2.md5
umount /mnt/a_thin2

# Display initial LVM layout
echo "Source LVM layout before save:"
lvs -a -o lv_name,vg_name,segtype,lv_size,pool_lv,data_percent vg_ci

# Deactivate Volume Group cleanly before saving
sync
vgchange -an vg_ci
udevadm settle
sleep 2

echo "=== [Step 2/5] Saving LVM (including thin provisioning) as an image ==="
# Options:
# -b: batch mode (non-interactive)
# -senc: skip encfs
# -sfsck: skip fsck
# -j2: clone hidden data between MBR and 1st partition
# -q2: use partclone -> partimage -> dd
# -z1: gzip compression
# -p true: post-action is true to allow continuing script execution
/usr/sbin/ocs-sr -b -senc -sfsck -j2 -q2 -z1 -p true savedisk lvm-thin-backup vda
SAVE_RC=$?
echo "ocs-sr savedisk exit code: $SAVE_RC"
sync
sleep 2

if [ "$SAVE_RC" -ne 0 ] || [ ! -d "/home/partimag/lvm-thin-backup" ]; then
    echo "ERROR: Failed to save image to /home/partimag/lvm-thin-backup (exit code: $SAVE_RC)"
    echo "finish_lvm_thin_save_restore_test"
    sync
    exit 1
fi
echo "Image successfully saved in /home/partimag/lvm-thin-backup."

echo "=== [Step 3/5] Cleaning the destination disk (/dev/vda) ==="
# Deactivate active Volume Group
vgchange -an 2>/dev/null || true

# Wipe all partition, filesystem, and LVM signatures
wipefs -a -f /dev/vda1 /dev/vda2 /dev/vda 2>/dev/null || true
sgdisk -Z /dev/vda

# Overwrite first 100MB with zeros to ensure disk is completely clean
dd if=/dev/zero of=/dev/vda bs=1M count=100 conv=notrunc status=none
partprobe /dev/vda 2>/dev/null || true
udevadm settle
sleep 2

# Verify disk is completely clean
if vgs vg_ci 2>/dev/null; then
    echo "ERROR: vg_ci still active or detected after cleaning destination disk!"
    exit 1
fi
if lsblk -n -o NAME /dev/vda | grep -q "vda[0-9]"; then
    echo "ERROR: Partitions still present on destination disk after cleaning!"
    exit 1
fi
echo "Destination disk /dev/vda is completely clean."

echo "=== [Step 4/5] Restoring image to the destination disk (/dev/vda) ==="
# Options:
# -b: batch mode
# -k0: recreate partition table based on source partition table in image
# -j2: clone hidden data
# -sfsck: skip fsck
# -p true: do not reboot/poweroff
/usr/sbin/ocs-sr -b -k0 -j2 -sfsck -p true restoredisk lvm-thin-backup vda
RESTORE_RC=$?
echo "ocs-sr restoredisk exit code: $RESTORE_RC"
sync
sleep 2

if [ "$RESTORE_RC" -ne 0 ]; then
    echo "ERROR: ocs-sr restoredisk failed with exit code $RESTORE_RC"
    echo "finish_lvm_thin_save_restore_test"
    sync
    exit 1
fi

echo "=== [Step 5/5] Verifying restored destination disk (/dev/vda) ==="
partprobe /dev/vda
udevadm settle
sleep 2

# 1. Verify boot partition /dev/vda1
echo "Verifying restored boot partition /dev/vda1..."
mkdir -p /mnt/restored_boot
mount /dev/vda1 /mnt/restored_boot
if (cd /mnt/restored_boot && md5sum -c /home/partimag/expected_boot.md5 > /dev/null 2>&1); then
    echo "check_boot: SUCCESS" > /tmp/check_boot.txt
else
    echo "check_boot: FAILED" > /tmp/check_boot.txt
fi
umount /mnt/restored_boot

# 2. Rescan and activate LVM
echo "Activating LVM on restored disk..."
pvscan --cache
vgscan --mknodes
vgchange -ay
udevadm settle
sleep 2

# 3. Verify LVM structural layout on restored disk
echo "Verifying LVM layout on restored disk..."
lvs_out=$(lvs -a -o lv_name,vg_name,segtype,lv_size,pool_lv --noheadings)
echo "$lvs_out"

struct_ok=1
if echo "$lvs_out" | grep -E "\<thin_pool\>.*\<thin-pool\>" >/dev/null; then
    echo "Thin pool verified (segtype: thin-pool)"
else
    echo "ERROR: thin_pool missing or invalid segtype"
    struct_ok=0
fi

if echo "$lvs_out" | grep -E "\<thin_vol1\>.*\<thin\>.*\<thin_pool\>" >/dev/null; then
    echo "Thin vol1 verified (segtype: thin, pool: thin_pool)"
else
    echo "ERROR: thin_vol1 missing or invalid"
    struct_ok=0
fi

if echo "$lvs_out" | grep -E "\<thin_vol2\>.*\<thin\>.*\<thin_pool\>" >/dev/null; then
    echo "Thin vol2 verified (segtype: thin, pool: thin_pool)"
else
    echo "ERROR: thin_vol2 missing or invalid"
    struct_ok=0
fi

if echo "$lvs_out" | grep -E "\<reg_vol\>.*\<linear\>" >/dev/null; then
    echo "Regular volume verified (segtype: linear)"
else
    echo "ERROR: reg_vol missing or invalid"
    struct_ok=0
fi

if [ "$struct_ok" -eq 1 ]; then
    echo "check_lvs_structure: SUCCESS" > /tmp/check_struct.txt
else
    echo "check_lvs_structure: FAILED" > /tmp/check_struct.txt
fi

# 4. Verify data integrity on regular LV
echo "Verifying regular volume /dev/vg_ci/reg_vol..."
dev_reg="/dev/vg_ci/reg_vol"
[ -b "$dev_reg" ] || dev_reg="/dev/mapper/vg_ci-reg_vol"
mkdir -p /mnt/restored_reg
mount "$dev_reg" /mnt/restored_reg
if (cd /mnt/restored_reg/data && md5sum -c /home/partimag/expected_reg.md5 > /dev/null 2>&1); then
    echo "check_reg_lv: SUCCESS" > /tmp/check_reg.txt
else
    echo "check_reg_lv: FAILED" > /tmp/check_reg.txt
fi
umount /mnt/restored_reg

# 5. Verify data integrity on thin LV 1
echo "Verifying thin volume 1 /dev/vg_ci/thin_vol1..."
dev_thin1="/dev/vg_ci/thin_vol1"
[ -b "$dev_thin1" ] || dev_thin1="/dev/mapper/vg_ci-thin_vol1"
mkdir -p /mnt/restored_thin1
mount "$dev_thin1" /mnt/restored_thin1
if (cd /mnt/restored_thin1/data && md5sum -c /home/partimag/expected_thin1.md5 > /dev/null 2>&1); then
    echo "check_thin_lv1: SUCCESS" > /tmp/check_thin1.txt
else
    echo "check_thin_lv1: FAILED" > /tmp/check_thin1.txt
fi
umount /mnt/restored_thin1

# 6. Verify data integrity on thin LV 2
echo "Verifying thin volume 2 /dev/vg_ci/thin_vol2..."
dev_thin2="/dev/vg_ci/thin_vol2"
[ -b "$dev_thin2" ] || dev_thin2="/dev/mapper/vg_ci-thin_vol2"
mkdir -p /mnt/restored_thin2
mount "$dev_thin2" /mnt/restored_thin2
if (cd /mnt/restored_thin2/data && md5sum -c /home/partimag/expected_thin2.md5 > /dev/null 2>&1); then
    echo "check_thin_lv2: SUCCESS" > /tmp/check_thin2.txt
else
    echo "check_thin_lv2: FAILED" > /tmp/check_thin2.txt
fi
umount /mnt/restored_thin2

# Deactivate Volume Group
vgchange -an vg_ci 2>/dev/null || true

# Summary output
echo "=== Summary Results ==="
cat /tmp/check_boot.txt
cat /tmp/check_struct.txt
cat /tmp/check_reg.txt
cat /tmp/check_thin1.txt
cat /tmp/check_thin2.txt
echo "finish_lvm_thin_save_restore_test"

sync
EOF
    chmod +x ../dev/ocscmd/lvm_thin_save_restore_test.sh

    # Handle libguestfs XDG_RUNTIME_DIR issue in containers
    unset XDG_RUNTIME_DIR

    local output rc=0
    local qemu_timeout="${TEST_TIMEOUT_SECONDS:-2700}" # 45m default
    echo "RUNNING: qemu-clonezilla-ci-run.sh --zip $CLONEZILLA_ZIP --disk qemu/disk-lvm-sr.qcow2 --arch $ARCH --image partimag --cmdpath dev/ocscmd/lvm_thin_save_restore_test.sh $NO_SSH_FORWARD_ARG (timeout: ${qemu_timeout}s)"
    output=$( (cd .. && timeout -k 30 "$qemu_timeout" ./qemu-clonezilla-ci-run.sh \
        --zip "$CLONEZILLA_ZIP" \
        --disk qemu/disk-lvm-sr.qcow2 \
        --arch "$ARCH" \
        --image partimag \
        --cmdpath dev/ocscmd/lvm_thin_save_restore_test.sh \
        $NO_SSH_FORWARD_ARG) 2>&1) || rc=$?
    echo "$output"

    if [[ "$rc" -eq 124 || "$rc" -eq 137 ]]; then
        echo "Error: QEMU run timed out after ${qemu_timeout}s. The guest likely hung." >&2
        return 1
    elif [[ "$rc" -ne 0 ]]; then
        echo "Error: qemu-clonezilla-ci-run.sh exited with code $rc." >&2
        return 1
    fi

    # Extract the log file path from the output
    local log_file
    log_file=$(echo "$output" | grep "log file located at:" | awk '{print $NF}' | tr -d '\r')
    if [[ -z "$log_file" ]]; then
        log_file=$(echo "$output" | grep "All output will be saved to log file:" | awk '{print $NF}' | tr -d '\r')
    fi

    if [[ -z "$log_file" ]]; then
        echo "Error: Could not find log file name in command output." >&2
        return 1
    fi

    local log_path
    log_path="../${log_file#./}"

    # Wait for the log file to appear
    local attempts=5
    while [[ ! -f "$log_path" && "$attempts" -gt 0 ]]; do
        echo "Log file not found at '$log_path', waiting 1s... ($attempts attempts left)"
        sleep 1
        attempts=$((attempts - 1))
    done

    if [[ ! -f "$log_path" ]]; then
        echo "Error: Log file still not found after waiting: $log_path" >&2
        return 1
    fi

    # Display summary from log
    echo "=== Summary ==="
    grep -E "check_boot:|check_lvs_structure:|check_reg_lv:|check_thin_lv1:|check_thin_lv2:" "$log_path" | tail -n 5

    # Check for test completion marker
    echo "Checking for completion marker in $log_path..."
    if ! grep -q "finish_lvm_thin_save_restore_test" "$log_path"; then
        echo "Test failed or 'finish_lvm_thin_save_restore_test' not found."
        return 1
    fi

    local test_failed=0

    if ! grep -q "check_boot: SUCCESS" "$log_path"; then
        echo "Error: Boot partition check failed"
        test_failed=1
    fi

    if ! grep -q "check_lvs_structure: SUCCESS" "$log_path"; then
        echo "Error: LVS structure check failed"
        test_failed=1
    fi

    if ! grep -q "check_reg_lv: SUCCESS" "$log_path"; then
        echo "Error: Regular LV check failed"
        test_failed=1
    fi

    if ! grep -q "check_thin_lv1: SUCCESS" "$log_path"; then
        echo "Error: Thin LV 1 check failed"
        test_failed=1
    fi

    if ! grep -q "check_thin_lv2: SUCCESS" "$log_path"; then
        echo "Error: Thin LV 2 check failed"
        test_failed=1
    fi

    assertEquals "LVM Thin save and restore verification failed. Check log: $log_path" 0 "$test_failed"
    return "$test_failed"
}

# --- Main execution ---

# Initialize common setup
if type initialize_test_environment &>/dev/null; then
    initialize_test_environment
fi

if [[ -z "$CLONEZILLA_ZIP" ]]; then
    echo "Error: Missing required argument --zip" >&2
    exit 1
fi

# LVM thin provisioning support requires Clonezilla Live >= 3.3.4-23 / 20261108-*
skip_unless_clonezilla_version_or_newer "LVM thin save/restore test" "3.3.4-23" "20261108"

# Load shunit2
# shellcheck source=/dev/null
. shunit2
