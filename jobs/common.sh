#!/bin/bash
#
# common.sh - Common functions and variables for Clonezilla CI test jobs.
#

# Define PROJECT_ROOT based on the location of this script.
# This assumes common.sh is always in the 'jobs' subdirectory of the project root.
readonly PROJECT_ROOT="$(realpath "$(dirname "$0")/..")"

# --- Configurable variables ---
SHUNIT_TIMER=1 # Enable test timing
CLONEZILLA_ZIP=""
ARCH="amd64"
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
}

# --- Auto-download Clonezilla ZIP if not provided ---
autodownload_clonezilla_zip() {
    if [[ -z "$CLONEZILLA_ZIP" ]]; then
        echo "INFO: --zip not specified. Attempting to auto-download the latest stable Clonezilla Live ZIP for '$ARCH'."
        CLONEZILLA_LIVE_STABLE_URL="http://free.nchc.org.tw/clonezilla-live/stable/"
        DEFAULT_DOWNLOAD_DIR="$PROJECT_ROOT/zip"
        
        mkdir -p "$DEFAULT_DOWNLOAD_DIR" || { echo "ERROR: Could not create download directory: $DEFAULT_DOWNLOAD_DIR" >&2; exit 1; }

        echo "INFO: Fetching latest filename from $CLONEZILLA_LIVE_STABLE_URL"
        LATEST_ZIP_FILENAME=$(curl -s "$CLONEZILLA_LIVE_STABLE_URL" | grep -oP "clonezilla-live-\d+\.\d+\.\d+-\d+-${ARCH}\.zip" | head -n 1)

        if [[ -z "$LATEST_ZIP_FILENAME" ]]; then
            echo "ERROR: Could not find the latest Clonezilla Live ZIP filename for '$ARCH' from $CLONEZILLA_LIVE_STABLE_URL" >&2
            exit 1
        fi

        DOWNLOAD_URL="${CLONEZILLA_LIVE_STABLE_URL}${LATEST_ZIP_FILENAME}"
        DEST_ZIP_PATH="${DEFAULT_DOWNLOAD_DIR}/${LATEST_ZIP_FILENAME}"

        if [ -f "$DEST_ZIP_PATH" ]; then
            echo "INFO: Latest ZIP file already exists: $DEST_ZIP_PATH. Skipping download."
            CLONEZILLA_ZIP=$(realpath "$DEST_ZIP_PATH")
        else
            echo "INFO: Downloading $DOWNLOAD_URL to $DEST_ZIP_PATH"
            if ! wget -q --show-progress -O "$DEST_ZIP_PATH" "$DOWNLOAD_URL"; then
                echo "ERROR: Failed to download Clonezilla Live ZIP from $DOWNLOAD_URL" >&2
                rm -f "$DEST_ZIP_PATH" # Clean up partial download
                exit 1
            fi
            CLONEZILLA_ZIP=$(realpath "$DEST_ZIP_PATH")
            echo "INFO: Download complete."
        fi
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
    local TEST_NAME="os_clone_restore_$(basename "$DISK_IMAGE" .qcow2)"
    local TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    local LOG_FILE="$LOG_DIR/${TEST_NAME}_${TIMESTAMP}.log"

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
    local TEST_NAME="fs_clone_restore_${fs}"
    local TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    local LOG_FILE="$LOG_DIR/${TEST_NAME}_${TIMESTAMP}.log"

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
    local TEST_NAME="liteserver_test"
    local TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    local LOG_FILE="$LOG_DIR/${TEST_NAME}_${TIMESTAMP}.log"

    echo "--- Running Lite Server Test ($ARCH) (Log: $LOG_FILE) ---"
    
    # The command to be tested. The zip file comes from the script's global var.
    # The disk and cmdpath are specific to this test case.
    (cd .. && ./liteserver.sh \
        --zip "$CLONEZILLA_ZIP" \
        --disk "qemu/cloudimages/debian-13-amd64.qcow2" \
        --cmdpath "dev/ocscmd/lite-bt.sh") 2>&1 | tee -a "$LOG_FILE"
    
    local SCRIPT_RESULT="${PIPESTATUS[0]}"
    local RESULT="$SCRIPT_RESULT"
    local TEST_END_TIME=$(date +%s)
    local TEST_DURATION=$((TEST_END_TIME - TEST_START_TIME))

    if [ "$RESULT" -eq 0 ]; then
        echo "--- Lite Server Test Passed (${TEST_DURATION} seconds) ---"
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
