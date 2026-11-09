#!/bin/bash
#
# test_dev_to_dev_lvm_thin.sh - Automated local disk LVM to LVM cloning test with thin provisioning.
#
# Usage:   ./test_dev_to_dev_lvm_thin.sh [options]
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

test_dev_to_dev_lvm_thin() {
    echo "--- Preparing Disks for LVM Thin Dev-to-Dev Test ---"
    qemu-img create -f qcow2 ../qemu/disk-lvm-a.qcow2 15G
    qemu-img create -f qcow2 ../qemu/disk-lvm-b.qcow2 20G

    # Ensure cleanup happens when the function returns
    trap 'rm -f ../qemu/disk-lvm-a.qcow2 ../qemu/disk-lvm-b.qcow2 ../dev/ocscmd/lvm_thin_dev_to_dev_test.sh' RETURN

    # Generate the internal test script for QEMU
    mkdir -p ../dev/ocscmd
    cat << 'EOF' > ../dev/ocscmd/lvm_thin_dev_to_dev_test.sh
#!/bin/bash
# This script runs inside the Clonezilla Live environment to test
# local disk LVM to LVM cloning where thin provisioning is included.

echo "=== [1/4] Preparing source disk with LVM and Thin Provisioning (/dev/vda) ==="
# Load device-mapper kernel modules if not already loaded
modprobe dm-mod 2>/dev/null || true
modprobe dm-thin-pool 2>/dev/null || true

# Deactivate existing LVM or swap
swapoff -a 2>/dev/null || true
vgchange -an 2>/dev/null || true

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
(cd /mnt/a_boot && md5sum boot_info.txt) > /tmp/expected_boot.md5
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
(cd /mnt/a_reg/data && md5sum ./*.bin) > /tmp/expected_reg.md5
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
(cd /mnt/a_thin1/data && md5sum ./*.bin) > /tmp/expected_thin1.md5
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
(cd /mnt/a_thin2/data && md5sum ./*.bin) > /tmp/expected_thin2.md5
umount /mnt/a_thin2

# Display source LVM layout
echo "Source LVM layout:"
lvs -a -o lv_name,vg_name,segtype,lv_size,pool_lv,data_percent vg_ci

# Deactivate source Volume Group cleanly before cloning
sync
vgchange -an vg_ci
udevadm settle
sleep 2

echo "=== [2/4] Preparing target disk (/dev/vdb) ==="
sgdisk -Z /dev/vdb || true
wipefs -a /dev/vdb || true
partprobe /dev/vdb || true
udevadm settle
sleep 2

echo "=== [3/4] Running local disk LVM to LVM clone (vda -> vdb) ==="
# Execute Clonezilla on-the-fly local disk-to-disk clone:
# -b: batch mode (non-interactive)
# -g auto: reinstall grub if present
# -e1 auto: auto-detect and fix mbr/gpt
# -e2: do not run grub-install
# -j2: clone hidden data
# -r: resize filesystem
# -sfsck: skip fsck
# -k0: recreate partition table based on source disk
# -p true: post-action is 'true' to allow continuing script execution
/usr/sbin/ocs-onthefly -b -g auto -e1 auto -e2 -j2 -r -sfsck -k0 -p true -f vda -d vdb
CLONE_RC=$?
echo "ocs-onthefly exited with code: $CLONE_RC"
sync
sleep 2

if [ "$CLONE_RC" -ne 0 ]; then
    echo "ERROR: ocs-onthefly failed with exit code $CLONE_RC"
    echo "clone_status: FAILED" > /tmp/clone_res.txt
    echo "finish_lvm_thin_dev_to_dev_test"
    sync
    exit 1
fi

echo "=== [4/4] Verifying cloned target disk (/dev/vdb) ==="
# Deactivate all active Volume Groups
vgchange -an 2>/dev/null || true

# Zero out the front of source disk /dev/vda (50MB) to ensure:
# 1. No duplicate VG name or PV UUID collisions exist on the bus.
# 2. Target disk /dev/vdb is verified completely independently.
echo "Zeroing out /dev/vda to isolate target /dev/vdb..."
dd if=/dev/zero of=/dev/vda bs=1M count=50 conv=notrunc status=none || true
partprobe /dev/vda 2>/dev/null || true
udevadm settle
sleep 2

# Probe /dev/vdb
partprobe /dev/vdb
udevadm settle
sleep 2

# 1. Verify boot partition /dev/vdb1
echo "Verifying boot partition on /dev/vdb1..."
mkdir -p /mnt/b_boot
mount /dev/vdb1 /mnt/b_boot
if (cd /mnt/b_boot && md5sum -c /tmp/expected_boot.md5 > /dev/null 2>&1); then
    echo "check_boot: SUCCESS" > /tmp/check_boot.txt
else
    echo "check_boot: FAILED" > /tmp/check_boot.txt
fi
umount /mnt/b_boot

# 2. Rescan and activate LVM on target disk /dev/vdb
echo "Activating LVM on /dev/vdb..."
pvscan --cache
vgscan --mknodes
vgchange -ay
udevadm settle
sleep 2

# 3. Verify LVM structural layout on target
echo "Verifying LVM layout on target..."
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
mkdir -p /mnt/b_reg
mount "$dev_reg" /mnt/b_reg
if (cd /mnt/b_reg/data && md5sum -c /tmp/expected_reg.md5 > /dev/null 2>&1); then
    echo "check_reg_lv: SUCCESS" > /tmp/check_reg.txt
else
    echo "check_reg_lv: FAILED" > /tmp/check_reg.txt
fi
umount /mnt/b_reg

# 5. Verify data integrity on thin LV 1
echo "Verifying thin volume 1 /dev/vg_ci/thin_vol1..."
dev_thin1="/dev/vg_ci/thin_vol1"
[ -b "$dev_thin1" ] || dev_thin1="/dev/mapper/vg_ci-thin_vol1"
mkdir -p /mnt/b_thin1
mount "$dev_thin1" /mnt/b_thin1
if (cd /mnt/b_thin1/data && md5sum -c /tmp/expected_thin1.md5 > /dev/null 2>&1); then
    echo "check_thin_lv1: SUCCESS" > /tmp/check_thin1.txt
else
    echo "check_thin_lv1: FAILED" > /tmp/check_thin1.txt
fi
umount /mnt/b_thin1

# 6. Verify data integrity on thin LV 2
echo "Verifying thin volume 2 /dev/vg_ci/thin_vol2..."
dev_thin2="/dev/vg_ci/thin_vol2"
[ -b "$dev_thin2" ] || dev_thin2="/dev/mapper/vg_ci-thin_vol2"
mkdir -p /mnt/b_thin2
mount "$dev_thin2" /mnt/b_thin2
if (cd /mnt/b_thin2/data && md5sum -c /tmp/expected_thin2.md5 > /dev/null 2>&1); then
    echo "check_thin_lv2: SUCCESS" > /tmp/check_thin2.txt
else
    echo "check_thin_lv2: FAILED" > /tmp/check_thin2.txt
fi
umount /mnt/b_thin2

# Deactivate Volume Group
vgchange -an vg_ci 2>/dev/null || true

# Summary output
echo "=== Summary Results ==="
cat /tmp/check_boot.txt
cat /tmp/check_struct.txt
cat /tmp/check_reg.txt
cat /tmp/check_thin1.txt
cat /tmp/check_thin2.txt
echo "finish_lvm_thin_dev_to_dev_test"

sync
EOF
    chmod +x ../dev/ocscmd/lvm_thin_dev_to_dev_test.sh

    # Handle libguestfs XDG_RUNTIME_DIR issue in containers
    unset XDG_RUNTIME_DIR

    local output rc=0
    local qemu_timeout="${TEST_TIMEOUT_SECONDS:-2700}" # 45m default
    echo "RUNNING: qemu-clonezilla-ci-run.sh --zip $CLONEZILLA_ZIP --disk qemu/disk-lvm-a.qcow2 --disk qemu/disk-lvm-b.qcow2 --arch $ARCH --cmdpath dev/ocscmd/lvm_thin_dev_to_dev_test.sh $NO_SSH_FORWARD_ARG (timeout: ${qemu_timeout}s)"
    output=$( (cd .. && timeout -k 30 "$qemu_timeout" ./qemu-clonezilla-ci-run.sh \
        --zip "$CLONEZILLA_ZIP" \
        --disk qemu/disk-lvm-a.qcow2 \
        --disk qemu/disk-lvm-b.qcow2 \
        --arch "$ARCH" \
        --cmdpath dev/ocscmd/lvm_thin_dev_to_dev_test.sh \
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
    if ! grep -q "finish_lvm_thin_dev_to_dev_test" "$log_path"; then
        echo "Test failed or 'finish_lvm_thin_dev_to_dev_test' not found."
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

    assertEquals "LVM Thin dev-to-dev clone verification failed. Check log: $log_path" 0 "$test_failed"
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
skip_unless_clonezilla_version_or_newer "LVM thin dev-to-dev clone test" "3.3.4-23" "20261108"

# Load shunit2
# shellcheck source=/dev/null
. shunit2
