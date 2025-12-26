#!/bin/bash
#
# common.sh - Common functions and variables for Clonezilla CI test jobs.
#

# Define PROJECT_ROOT based on the location of this script.
# This assumes common.sh is always in the 'jobs' subdirectory of the project root.
readonly PROJECT_ROOT="$(realpath "$(dirname "$0")/..")"

# Enforce execution from the 'jobs/' directory
if [[ "$(basename "$PWD")" != "jobs" ]]; then
    echo "ERROR: This script must be run from within the 'jobs/' directory." >&2
    echo "Please 'cd jobs/' first, then execute the script (e.g., './test_fs_btrfs.sh')." >&2
    exit 1
fi

# --- Configurable variables ---
SHUNIT_TIMER=1 # Enable test timing
CLONEZILLA_ZIP=""
ARCH="amd64"
TYPE="stable"
LOG_DIR="$PROJECT_ROOT/logs"
testData="$PROJECT_ROOT/dev/testData"
START_TIME=$(date +%s)

# --- Usage ---
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Run a clonezilla ci test."
    echo ""
    echo "Options:"
    echo "  -h, --help      Display this help message and exit."
    echo "  --zip <file>    Specify the Clonezilla zip file to use."
    echo "  --arch <arch>   Specify the architecture to test (e.g., amd64, arm64). Defaults to amd64."
    echo "  --type <type>   Specify the release type for auto-download (e.g., stable, testing). Defaults to stable."
}

# --- Auto-download Clonezilla ZIP if not provided ---
autodownload_clonezilla_zip() {
    if [[ -z "$CLONEZILLA_ZIP" ]]; then
        echo "INFO: --zip not specified. Attempting to auto-download."
        
        # The download script is in the project root
        local DOWNLOAD_SCRIPT="$PROJECT_ROOT/download-clonezilla.sh"
        if [ ! -x "$DOWNLOAD_SCRIPT" ]; then
            echo "ERROR: Download helper script not found or not executable: $DOWNLOAD_SCRIPT" >&2
            exit 1
        fi
        
        echo "INFO: Calling download script with arch='$ARCH', type='$TYPE'..."
        local DEFAULT_DOWNLOAD_DIR="$PROJECT_ROOT/zip"
        local DOWNLOADED_ZIP_PATH
        DOWNLOADED_ZIP_PATH=$("$DOWNLOAD_SCRIPT" --arch "$ARCH" --type "$TYPE" -o "$DEFAULT_DOWNLOAD_DIR")
        
        if [ $? -ne 0 ] || [ -z "$DOWNLOADED_ZIP_PATH" ] || [ ! -f "$DOWNLOADED_ZIP_PATH" ]; then
            echo "ERROR: Failed to auto-download Clonezilla zip using $DOWNLOAD_SCRIPT." >&2
            exit 1
        fi
        
        # Set the global CLONEZILLA_ZIP variable to the absolute path
        CLONEZILLA_ZIP=$(realpath "$DOWNLOADED_ZIP_PATH")
        echo "INFO: Auto-download complete. Using ZIP: $CLONEZILLA_ZIP"
    fi
}
# ---

# Check for shunit2
check_shunit2() {
    if ! command -v shunit2 >/dev/null 2>&1; then
        echo "shunit2 is not installed. Please install it to continue."
        echo "You can download it from https://github.com/kward/shunit2"
        exit 1
    fi
}

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
    local DISK_IMAGE="$1"
    local VALIDATE_ISO="$2"
    local NO_SSH_FORWARD_PARAM="$3"
    # Standardize log file name based on the CI job name for easy linking
    local LOG_FILE="$LOG_DIR/${CI_JOB_NAME}.log"

    echo "--- Running OS $DISK_IMAGE ($ARCH) Clone/Restore Test (Log: $LOG_FILE) ---"
    (cd .. && ./os-clone-restore.sh --zip "$CLONEZILLA_ZIP" --tmpl "$DISK_IMAGE" --arch "$ARCH" --validate-iso "$VALIDATE_ISO" $NO_SSH_FORWARD_PARAM) 2>&1 | tee -a "$LOG_FILE"
    local SCRIPT_RESULT="${PIPESTATUS[0]}"
    local RESULT="$SCRIPT_RESULT"
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
    local NO_SSH_FORWARD_PARAM="$2"
    # Standardize log file name based on the CI job name for easy linking
    local LOG_FILE="$LOG_DIR/${CI_JOB_NAME}.log"

    echo "--- Running FS Clone/Restore Test with $fs ($ARCH) (Log: $LOG_FILE) ---"
    (cd .. && ./data-clone-restore.sh --zip "$CLONEZILLA_ZIP" --data "$testData" --fs "$fs" --arch "$ARCH" $NO_SSH_FORWARD_PARAM) 2>&1 | tee -a "$LOG_FILE"
    local SCRIPT_RESULT="${PIPESTATUS[0]}"
    local RESULT="$SCRIPT_RESULT"
    local TEST_END_TIME=$(date +%s) # Record end time for this specific test
    local TEST_DURATION=$((TEST_END_TIME - TEST_START_TIME))

    if [ "$RESULT" -eq 0 ]; then
        echo "--- $fs Clone/Restore Test with $fs Passed (${TEST_DURATION} seconds) ---"
    else
        echo "--- $fs Clone/Restore Test with $fs FAILED (${TEST_DURATION} seconds) ---"
    fi
    assertEquals "$fs clone/restore script failed for $fs. Check log: $LOG_FILE" 0 "$RESULT"
}

# Test for liteserver
run_liteserver_test() {
    local TEST_START_TIME=$(date +%s)
    local TEST_NAME="liteserver_test_${ARCH}"
    local TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    local LOG_FILE="$LOG_DIR/${TEST_NAME}_${TIMESTAMP}.log"

    echo "--- Running Lite Server Test ($ARCH) (Log: $LOG_FILE) ---"

    # Dynamically find a debian disk for the current architecture
    local os="debian"
    local config_file="$PROJECT_ROOT/qemu/cloudimages/cloud_images.conf"
    local test_disk_path=""
    local RESULT=0 # Default to success (for skip case)

    if [ -f "$config_file" ]; then
        # Find the first available debian image for the given architecture
        local config_line
        config_line=$(grep -E "^\s*${os}\s+.*\s+${ARCH}\s+" "$config_file" | head -n 1)

        if [ -n "$config_line" ]; then
            local release
            release=$(echo "$config_line" | awk '{print $2}')
            local image_name="${os}-${release}-${ARCH}.qcow2"
            test_disk_path="$PROJECT_ROOT/qemu/cloudimages/${image_name}"
        fi
    fi

    if [ -f "$test_disk_path" ]; then
        echo "INFO: Using disk image '$test_disk_path' for liteserver test."
        # The command to be tested. The zip file comes from the script's global var.
        (cd .. && ./liteserver.sh \
            --zip "$CLONEZILLA_ZIP" \
            --arch "$ARCH" \
            --disk "$test_disk_path" \
            --cmdpath "dev/ocscmd/lite-bt.sh" --no-ssh-forward) 2>&1 | tee -a "$LOG_FILE"
        
        local SCRIPT_RESULT="${PIPESTATUS[0]}"
        RESULT="$SCRIPT_RESULT"
    else
        echo "WARNING: Skipping Lite Server test for arch '$ARCH'. No suitable Debian disk image found."
        # Mark test as skipped by ensuring RESULT is 0.
        RESULT=0
    fi
    
    local TEST_END_TIME=$(date +%s)
    local TEST_DURATION=$((TEST_END_TIME - TEST_START_TIME))

    if [ "$RESULT" -eq 0 ]; then
        if [ ! -f "$test_disk_path" ]; then
            echo "--- Lite Server Test SKIPPED (${TEST_DURATION} seconds) ---"
        else
            echo "--- Lite Server Test Passed (${TEST_DURATION} seconds) ---"
        fi
    else
        echo "--- Lite Server Test FAILED (${TEST_DURATION} seconds) ---"
    fi
    assertEquals "Lite Server test failed. Check log: $LOG_FILE" 0 "$RESULT"
}

# Main initialization function
initialize_test_environment() {
    # Setup Logging
    mkdir -p "$LOG_DIR"
    autodownload_clonezilla_zip
    check_shunit2
}
