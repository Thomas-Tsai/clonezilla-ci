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
CLONEZILLA_ZIP=""
ARCH="amd64"
LOG_DIR="./logs"
MAIN_LOG_FILE="${LOG_DIR}/start_sh_main_$(date +%Y%m%d_%H%M%S).log"
testData="dev/testData"
START_TIME=$(date +%s)

# --- Setup Logging ---
mkdir -p "$LOG_DIR"
exec &> >(tee -a "$MAIN_LOG_FILE")


# --- Usage ---
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Run the clonezilla ci test suite."
    echo ""
    echo "Options:"
    echo "  --zip <file>    Specify the Clonezilla zip file to use."
    echo "  --arch <arch>   Specify the architecture to test (e.g., amd64, arm64). Defaults to amd64."
    echo "  --help          Display this help message and exit."
}

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
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

# --- Auto-download Clonezilla ZIP if not provided ---
if [[ -z "$CLONEZILLA_ZIP" ]]; then
    echo "INFO: --zip not specified. Attempting to auto-download the latest stable Clonezilla Live ZIP for '$ARCH'."
    CLONEZILLA_LIVE_STABLE_URL="http://free.nchc.org.tw/clonezilla-live/stable/"
    DEFAULT_DOWNLOAD_DIR="zip"
    
    mkdir -p "$DEFAULT_DOWNLOAD_DIR" || { echo "ERROR: Could not create download directory: $DEFAULT_DOWNLOAD_DIR" >&2; exit 1; }

    echo "INFO: Fetching latest filename from $CLONEZILLA_LIVE_STABLE_URL"
    LATEST_ZIP_FILENAME=$(curl -s "$CLONEZILLA_LIVE_STABLE_URL" | grep -oP "clonezilla-live-\\d+\\.\\d+\\.\\d+-\\d+-${ARCH}\\.zip" | head -n 1)

    if [[ -z "$LATEST_ZIP_FILENAME" ]]; then
        echo "ERROR: Could not find the latest Clonezilla Live ZIP filename for '$ARCH' from $CLONEZILLA_LIVE_STABLE_URL" >&2
        exit 1
    fi

    DOWNLOAD_URL="${CLONEZILLA_LIVE_STABLE_URL}${LATEST_ZIP_FILENAME}"
    DEST_ZIP_PATH="${DEFAULT_DOWNLOAD_DIR}/${LATEST_ZIP_FILENAME}"

    if [ -f "$DEST_ZIP_PATH" ]; then
        echo "INFO: Latest ZIP file already exists: $DEST_ZIP_PATH. Skipping download."
        CLONEZILLA_ZIP="$DEST_ZIP_PATH"
    else
        echo "INFO: Downloading $DOWNLOAD_URL to $DEST_ZIP_PATH"
        if ! wget -q --show-progress -O "$DEST_ZIP_PATH" "$DOWNLOAD_URL"; then
            echo "ERROR: Failed to download Clonezilla Live ZIP from $DOWNLOAD_URL" >&2
            rm -f "$DEST_ZIP_PATH" # Clean up partial download
            exit 1
        fi
        CLONEZILLA_ZIP="$DEST_ZIP_PATH"
        echo "INFO: Download complete."
    fi
fi
# ---


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
    local VALIDATE_ISO="$2"

    echo "--- Running OS $DISK_IMAGE ($ARCH) Clone/Restore Test (Log: $LOG_FILE) ---"
    ./os-clone-restore.sh --zip "$CLONEZILLA_ZIP" --tmpl "$DISK_IMAGE" --arch "$ARCH" --validate-iso "$VALIDATE_ISO" 2>&1 | tee -a "$LOG_FILE"
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
    local TEST_NAME="fs_clone_restore_${fs}"
    local TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    local LOG_FILE="$LOG_DIR/${TEST_NAME}_${TIMESTAMP}.log"

    echo "--- Running FS Clone/Restore Test with $fs ($ARCH) (Log: $LOG_FILE) ---"
    ./data-clone-restore.sh --zip "$CLONEZILLA_ZIP" --data $testData --fs "$fs" --arch "$ARCH" 2>&1 | tee -a "$LOG_FILE"
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


# Test for ubuntu system clone and restore
test_ubuntu_clone_restore() {
    local os="ubuntu"
    
    # Find all ubuntu releases for the given arch in the conf file
    grep -E "^\s*${os}\s+.*\s+${ARCH}\s+" qemu/cloudimages/cloud_images.conf | while read -r config_line; do
        # Extract release from the line
        local release=$(echo "$config_line" | awk '{print $2}')
        local image_name="${os}-${release}-${ARCH}.qcow2"
        local image_path="qemu/cloudimages/${image_name}"

        if [ -f "$image_path" ]; then
            run_os_clone_restore "$image_path" "isos/cidata.iso"
        else
            echo "Skipping test for ${os}-${release}-${ARCH}: image file not found at ${image_path}"
        fi
    done
}

# Test for debian system clone and restore
test_debian_clone_restore() {
    local os="debian"
    
    # Find all debian releases for the given arch in the conf file
    grep -E "^\s*${os}\s+.*\s+${ARCH}\s+" qemu/cloudimages/cloud_images.conf | while read -r config_line; do
        # Extract release from the line
        local release=$(echo "$config_line" | awk '{print $2}')
        local image_name="${os}-${release}-${ARCH}.qcow2"
        local image_path="qemu/cloudimages/${image_name}"

        if [ -f "$image_path" ]; then
            run_os_clone_restore "$image_path" "isos/cidata.iso"
        else
            echo "Skipping test for ${os}-${release}-${ARCH}: image file not found at ${image_path}"
        fi
    done
}

# Test for fedora system clone and restore
test_fedora_clone_restore() {
    local os="fedora"

    # Find all fedora releases for the given arch in the conf file
    grep -E "^\s*${os}\s+.*\s+${ARCH}\s+" qemu/cloudimages/cloud_images.conf | while read -r config_line; do
        # Extract release from the line
        local release=$(echo "$config_line" | awk '{print $2}')
        local image_name="${os}-${release}-${ARCH}.qcow2"
        local image_path="qemu/cloudimages/${image_name}"

        if [ -f "$image_path" ]; then
            run_os_clone_restore "$image_path" "isos/cidata.iso" 
        else
            echo "Skipping test for ${os}-${release}-${ARCH}: image file not found at ${image_path}"
        fi
    done
}

# Test for windows clone and restore
test_windows11_clone_restore() {
    local image_path="qemu/cloudimages/windown-11-${ARCH}.qcow2"

    if [ -f "$image_path" ]; then
        run_os_clone_restore "$image_path" "isos/win11_cidata.iso"
    else
        echo "Skipping test for ${os}-${release}-${ARCH}: image file not found at ${image_path}"
    fi
}

# Test for exfat file system clone and restore
test_exfat_clone_restore() {
    run_fs_clone_restore "exfat"
}

# Test for ntfs file system clone and restore
test_ntfs_clone_restore() {
    run_fs_clone_restore "ntfs"
}


# Test for vfat file system clone and restore
test_vfat_clone_restore() {
    run_fs_clone_restore "vfat"
}

# Test for ext4 file system clone and restore
test_ext4_clone_restore() {
    run_fs_clone_restore "ext4"
}

# Test for xfs file system clone and restore
test_xfs_clone_restore() {
    run_fs_clone_restore "xfs"
}

# Test for btrfs file system clone and restore
test_btrfs_clone_restore() {
    run_fs_clone_restore "btrfs"
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
    ./liteserver.sh \
        --zip "$CLONEZILLA_ZIP" \
        --disk "qemu/cloudimages/debian-13-amd64.qcow2" \
        --cmdpath "dev/ocscmd/lite-bt.sh" 2>&1 | tee -a "$LOG_FILE"
    
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

test_liteserver() {
    # Check if the required disk for the test exists.
    local test_disk="qemu/cloudimages/debian-13-amd64.qcow2"
    if [ -f "$test_disk" ]; then
        run_liteserver_test
    else
        echo "Skipping Lite Server test: required disk not found at ${test_disk}"
    fi
}


# Load shunit2
. shunit2
