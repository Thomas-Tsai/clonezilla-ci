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
START_TIME=$(date +%s)
ARCH="amd64"
ZIP_WAS_SET=0

# --- Argument Parsing ---
while [ "$#" -gt 0 ]; do
    case "$1" in
        --zip)
            CLONEZILLA_ZIP="$2"
            ZIP_WAS_SET=1
            shift 2
            ;;
        --arch)
            ARCH="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [ "$ZIP_WAS_SET" -eq 0 ]; then
    CLONEZILLA_ZIP="zip/clonezilla-live-20251124-resolute-${ARCH}.zip"
fi


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

# oneTimeTearDown: Executed once after all tests are finished.
oneTimeTearDown() {
    local END_TIME=$(date +%s)
    local DURATION=$((END_TIME - START_TIME))
    echo "------------------------------------------------------------------"
    echo "Total execution time: ${DURATION} seconds"
    echo "------------------------------------------------------------------"
}

# Test for OS system clone and restore
run_os_clone_restore() {
    local TEST_START_TIME=$(date +%s) # Record start time for this specific test
    local TEST_NAME="os_clone_restore"
    local TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    local LOG_FILE="$LOG_DIR/${TEST_NAME}_${TIMESTAMP}.log"
    local DISK_IMAGE="$1"

    echo "--- Running OS $DISK_IMAGE ($ARCH) Clone/Restore Test (Log: $LOG_FILE) ---"
    ./linux-clone-restore.sh --zip "$CLONEZILLA_ZIP" --tmpl $DISK_IMAGE --arch "$ARCH" > "$LOG_FILE" 2>&1
    local RESULT=$?
    local TEST_END_TIME=$(date +%s) # Record end time for this specific test
    local TEST_DURATION=$((TEST_END_TIME - TEST_START_TIME))

    if [ "$RESULT" -eq 0 ]; then
        echo "--- OS $DISK_IMAGE Clone/Restore Test Passed (${TEST_DURATION} seconds) ---"
    else
        echo "--- OS $DISK_IMAGE Clone/Restore Test FAILED (${TEST_DURATION} seconds) ---"
    fi
    assertEquals "OS $DISK_IMAGE clone/restore script failed. Check log: $LOG_FILE" 0 "$RESULT"
}

# Test for file system clone and restore¬
run_fs_clone_restore() {
    local TEST_START_TIME=$(date +%s) # Record start time for this specific test
    local fs="$1"
    local TEST_NAME="fs_clone_restore_${fs}"
    local TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    local LOG_FILE="$LOG_DIR/${TEST_NAME}_${TIMESTAMP}.log"

    echo "--- Running FS Clone/Restore Test with $fs ($ARCH) (Log: $LOG_FILE) ---"
    ./data-clone-restore.sh --zip "$CLONEZILLA_ZIP" --data $testData --fs "$fs" --arch "$ARCH" > "$LOG_FILE" 2>&1
    local RESULT=$?
    local TEST_END_TIME=$(date +%s) # Record end time for this specific test
    local TEST_DURATION=$((TEST_END_TIME - TEST_START_TIME))

    if [ "$RESULT" -eq 0 ]; then
        echo "--- $fs Clone/Restore Test with $fs Passed (${TEST_DURATION} seconds) ---"
    else
        echo "--- $fs Clone/Restore Test with $fs FAILED (${TEST_DURATION} seconds) ---"
    fi
    assertEquals "$fs clone/restore script failed for $fs. Check log: $LOG_FILE" 0 "$RESULT"
}


# Test for ubuntu system clone and restore
test_ubuntu_clone_restore() {
    run_os_clone_restore "qemu/cloudimages/ubuntu-24.04.qcow2"
}

# Test for debian sid system clone and restore
test_debian_sid_clone_restore() {
    local image_path="qemu/cloudimages/debian-sid-daily-${ARCH}.qcow2"
    if [ ! -f "$image_path" ]; then
        echo "Skipping Debian SID test for $ARCH, image not found: $image_path"
        return
    fi
    run_os_clone_restore "$image_path"
}

# Test for exfat file system clone and restore
test_exfat_clone_restore() {
    run_fs_clone_restore "exfat"
}

# Test for ext4 file system clone and restore
test_ext4_clone_restore() {
    run_fs_clone_restore "ext4"
}

# Load shunit2
. shunit2
