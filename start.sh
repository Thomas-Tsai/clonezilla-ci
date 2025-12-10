#!/bin/bash
#
# start.sh - Run the clonezilla ci test suite.
#
# This script runs the clonezilla ci test suite, which includes tests for
# different operating systems and file systems. It uses shunit2 for testing.
#
# Usage: ./start.sh
#

# --- Configurable variables ---
SHUNIT_TIMER=1 # Enable test timing
CLONEZILLA_ZIP="zip/clonezilla-live-20251124-resolute-amd64.zip"
LOG_DIR="./logs"
testData="dev/testData"

# --- Argument Parsing ---
while [ "$#" -gt 0 ]; do
    case "$1" in
        --zip)
            CLONEZILLA_ZIP="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Check for shunit2
if ! command -v shunit2 >/dev/null 2>&1; then
    echo "shunit2 is not installed. Please install it to continue."
    echo "You can download it from https://github.com/kward/shunit2"
    exit 1
fi

# Create log directory before tests run
setUp() {
  mkdir -p "$LOG_DIR"
}

# Test for OS system clone and restore
run_os_clone_restore() {
    local TEST_NAME="os_clone_restore"
    local TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    local LOG_FILE="$LOG_DIR/${TEST_NAME}_${TIMESTAMP}.log"
    local DISK_IMAGE="$1"

    echo "--- Running OS $DISK_IMAGE Clone/Restore Test (Log: $LOG_FILE) ---"
    ./linux-clone-restore.sh --zip "$CLONEZILLA_ZIP" --tmpl $DISK_IMAGE > "$LOG_FILE" 2>&1
    assertEquals "OS $DISK_IMAGE clone/restore script failed. Check log: $LOG_FILE" 0 $?
    echo "--- OS $DISK_IMAGE Clone/Restore Test Passed ---"
}

# Test for file system clone and restore¬
run_fs_clone_restore() {
    local fs="$1"
    local TEST_NAME="fs_clone_restore_${fs}"
    local TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    local LOG_FILE="$LOG_DIR/${TEST_NAME}_${TIMESTAMP}.log"

    echo "--- Running FS Clone/Restore Test with $fs (Log: $LOG_FILE) ---"
    ./data-clone-restore.sh --zip "$CLONEZILLA_ZIP" --data $testData --fs "$fs" > "$LOG_FILE" 2>&1
    assertEquals "$fs clone/restore script failed for $fs. Check log: $LOG_FILE" 0 $?
    echo "--- $fs Clone/Restore Test with $fs Passed ---"}
}


# Test for ubuntu system clone and restore
test_ubuntu_clone_restore() {
    run_os_clone_restore "qemu/cloudimages/ubuntu-24.04.qcow2"
}

# Test for debian sid system clone and restore
test_debian_sid_clone_restore() {
    run_os_clone_restore "qemu/cloudimages/debian-sid-daily-amd64.qcow2"
}

# Test for exfat file system clone and restore
test_exfat_clone_restore() {
    run_fs_clone_restore "exfat"
}

# Test for ext4 file system clone and restore
test_exfat_clone_restore() {
    run_fs_clone_restore "ext4"
}

# Load shunit2
. shunit2
