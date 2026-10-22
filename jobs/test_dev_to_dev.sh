#!/bin/bash
#
# test_dev_to_dev.sh - Automated dev-to-dev tests (Case 1: part-to-part, Case 2: disk-to-disk)
#

# Source the common script
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
            TYPE="$2"
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

if [[ -z "$CLONEZILLA_ZIP" ]]; then
    echo "Error: Missing require argument --zip"
    exit 1
fi

test_dev_to_dev() {
    echo "--- Preparing Disks ---"
    qemu-img create -f qcow2 ../qemu/disk-a.qcow2 20G
    qemu-img create -f qcow2 ../qemu/disk-b.qcow2 40G
    
    # Ensure cleanup happens when the function returns
    trap 'rm -f ../qemu/disk-a.qcow2 ../qemu/disk-b.qcow2 ../dev/ocscmd/dev_to_dev_test.sh' RETURN

    # Generate the internal test script for QEMU
    mkdir -p ../dev/ocscmd
    cat << 'EOF' > ../dev/ocscmd/dev_to_dev_test.sh
#!/bin/bash
# This script runs inside the Clonezilla Live environment

echo "=== [1/3] Preparing disk-a (vda) ==="
# Partition vda: two 8G partitions
sgdisk -Z /dev/vda
sgdisk -n 1:0:+8G -c 1:"part1" /dev/vda
sgdisk -n 2:0:+8G -c 2:"part2" /dev/vda
partprobe /dev/vda
udevadm settle
sleep 2

# Format vda1
mkfs.ext4 -F /dev/vda1
sync
sleep 2

# Create random files and checksum
mkdir -p /mnt/a
mount -t ext4 /dev/vda1 /mnt/a
mkdir -p /mnt/a/random_files
for i in $(seq 1 10); do
    echo "Creating file_$i.bin (10M)..."
    dd if=/dev/urandom of=/mnt/a/random_files/file_$i.bin bs=1M count=10 status=none
done
cd /mnt/a/random_files
md5sum *.bin > /mnt/a/checksum.md5
cat /mnt/a/checksum.md5 > /tmp/expected_checksum.md5
cd /
umount /mnt/a

echo "=== [2/3] Preparing target partition on disk-b (vdb) ==="
# Since Clonezilla 3.3.4-10, part-to-part mode forces -k (never create a
# partition table on the target disk) to protect the destination disk
# (upstream fix for issue #195): -k0/-k1/-k2 are honored in disk mode only.
# The target partition must therefore exist before cloning.
sgdisk -Z /dev/vdb
sgdisk -n 1:0:+8G -c 1:"part1" /dev/vdb
partprobe /dev/vdb
udevadm settle
sleep 2

echo "=== [2/3] Running Case 1: part to part (vda1 -> vdb1) ==="
# Case 1 Command (no -k1: partition table creation is not allowed in
# partition clone mode; with a pre-existing vdb1 this works on both old
# and new Clonezilla versions)
/usr/sbin/ocs-onthefly -b -e1 auto -e2 -j2 -r -sfsck -icds -p true -f vda1 -d vdb1
# Wait a moment for partprobe
sleep 2

# Verify Case 1
mkdir -p /mnt/b
mount -t ext4 /dev/vdb1 /mnt/b
cd /mnt/b/random_files
echo "Verifying checksums for Case 1..."
if md5sum -c /tmp/expected_checksum.md5 > /dev/null 2>&1; then
    echo "case1: 成功" > /tmp/case1_result.txt
else
    echo "case1: 失敗" > /tmp/case1_result.txt
fi
cd /
umount /mnt/b

echo "=== [3/3] Running Case 2: disk to disk (vda -> vdb) ==="
# Case 2 Command
/usr/sbin/ocs-onthefly -b -g auto -e1 auto -e2 -j2 -r -sfsck -k0 -p true -f vda -d vdb
# Wait a moment for partprobe
sleep 2

# Verify Case 2
mount -t ext4 /dev/vdb1 /mnt/b
cd /mnt/b/random_files
echo "Verifying checksums for Case 2..."
if md5sum -c /tmp/expected_checksum.md5 > /dev/null 2>&1; then
    echo "case2: 成功" > /tmp/case2_result.txt
else
    echo "case2: 失敗" > /tmp/case2_result.txt
fi
cd /
umount /mnt/b

echo "=== Final Results ==="
cat /tmp/case1_result.txt
cat /tmp/case2_result.txt
echo "finish_dev_to_dev_test"

# Make sure all data is flushed
sync
EOF
    chmod +x ../dev/ocscmd/dev_to_dev_test.sh

    # Handle libguestfs XDG_RUNTIME_DIR issue in containers
    unset XDG_RUNTIME_DIR

    # Run the command and capture its stdout/stderr.
    # A hung QEMU (e.g. a guest-side prompt such as ocs-sr's "Press Enter to
    # continue..." on error, which ignores batch mode) must fail this test
    # quickly instead of blocking until the CI job timeout kills everything
    # and no logs/artifacts are uploaded.
    local output rc=0
    local qemu_timeout="${TEST_TIMEOUT_SECONDS:-2700}"  # 45m; a healthy run takes ~11m
    echo "RUNNING: qemu-clonezilla-ci-run.sh --zip $CLONEZILLA_ZIP --disk qemu/disk-a.qcow2 --disk qemu/disk-b.qcow2 --arch $ARCH --cmdpath dev/ocscmd/dev_to_dev_test.sh $NO_SSH_FORWARD_ARG (timeout: ${qemu_timeout}s)"
    output=$( (cd .. && timeout -k 30 "$qemu_timeout" ./qemu-clonezilla-ci-run.sh --zip "$CLONEZILLA_ZIP" --disk qemu/disk-a.qcow2 --disk qemu/disk-b.qcow2 --arch "$ARCH" --cmdpath dev/ocscmd/dev_to_dev_test.sh $NO_SSH_FORWARD_ARG) 2>&1) || rc=$?
    echo "$output" # Show the output for debugging

    if [[ "$rc" -eq 124 || "$rc" -eq 137 ]]; then
        echo "Error: QEMU run timed out after ${qemu_timeout}s. The guest likely hung (see log above)." >&2
        return 1
    elif [[ "$rc" -ne 0 ]]; then
        echo "Error: qemu-clonezilla-ci-run.sh exited with code $rc." >&2
        return 1
    fi

    # Extract the log file path from the output, removing any carriage returns
    local log_file
    log_file=$(echo "$output" | grep "log file located at:" | awk '{print $NF}' | tr -d '\r')
    
    if [[ -z "$log_file" ]]; then
        # fallback for old script output or different format
        log_file=$(echo "$output" | grep "All output will be saved to log file:" | awk '{print $NF}' | tr -d '\r')
    fi

    if [[ -z "$log_file" ]]; then
        echo "Error: Could not find log file name in command output." >&2
        return 1 # Fail the test
    fi

    # The log file path is relative to project root. Adjust for being in `jobs/`.
    local log_path
    log_path="../${log_file#./}"

    # Wait for the log file to appear to avoid a race condition.
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

    # Read the summary results
    echo "=== Summary ==="
    grep -E "case1:|case2:" "$log_path" | tail -n 2

    # Grep for 'finish' and print the result. Grep's exit code will determine test pass/fail.
    echo "Grepping for completion marker in $log_path..."
    if ! grep "finish_dev_to_dev_test" "$log_path"; then
        echo "Test failed or 'finish_dev_to_dev_test' not found."
        return 1
    fi

    # Check for cases success
    if ! grep -q "case1: 成功" "$log_path"; then
        echo "Error: Case 1 failed"
        return 1
    fi

    if ! grep -q "case2: 成功" "$log_path"; then
        echo "Error: Case 2 failed"
        return 1
    fi

    echo "Test successfully completed."
    return 0
}

# --- Main execution ---

# Initialize common setup (if present in common.sh)
if type initialize_test_environment &>/dev/null; then
    initialize_test_environment
fi

# Load shunit2
. shunit2
