#!/bin/bash
#
# test_lite_raw_data.sh - Tests lite server with a fresh disk containing a raw partition.
# Tests 4 modes: Lite-BT (dev/image) and Lite-Multicast (dev/image).
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
        --no-ssh-forward)
            # Consume the argument so shunit2 doesn't see it
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

# Convert CLONEZILLA_ZIP to an absolute path if it was provided
if [[ -n "$CLONEZILLA_ZIP" ]]; then
    CLONEZILLA_ZIP="$(realpath "$CLONEZILLA_ZIP")"
fi

# Global variables for the test
WORK_DIR="$PROJECT_ROOT/tmp_test_raw_data"
TEST_DISK="$WORK_DIR/test_raw.qcow2"
MD5_FILE="${TEST_DISK}.md5"

oneTimeSetUp() {
    mkdir -p "$WORK_DIR"
    info "Preparing fresh 1GB test image..."
    "$PROJECT_ROOT/dev/prepare-test-image.sh" --new "$TEST_DISK"
    ls -l "$TEST_DISK" || echo "ERROR: TEST_DISK NOT FOUND AFTER PREPARE"
    sync
}

oneTimeTearDown() {
    rm -rf "$WORK_DIR"
}

# Generic function to run the lite server test for a specific mode
run_lite_raw_check() {
    local mode_name="$1"
    local cmd_path="$2"
    local TEST_START_TIME=$(date +%s)
    local TEST_NAME="lite_raw_${mode_name}_${ARCH}"
    local TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    local LOG_FILE="$LOG_DIR/${TEST_NAME}_${TIMESTAMP}.log"

    info "--- Running Lite Raw Data Test: $mode_name ($ARCH) (Log: $LOG_FILE) ---"

    if [ ! -f "$TEST_DISK" ] || [ ! -f "$MD5_FILE" ]; then
        fail "Test disk or MD5 file not found."
        return
    fi

    # Run liteserver.sh with the prepared disk and MD5 check, skipping OS validation
    # Use timeout to prevent hanging on problematic modes.
    # Set timeout to 20 minutes (1200s) as some modes (like BitTorrent) are slow.
    local timeout_val=1200
    info "Starting liteserver.sh with ${timeout_val}s timeout..."
    
    (cd .. && timeout -k 10s "$timeout_val" ./liteserver.sh \
        --zip "$CLONEZILLA_ZIP" \
        --arch "$ARCH" \
        --disk "$TEST_DISK" \
        --imgname "$TEST_NAME" \
        --check-raw-md5 "$MD5_FILE" \
        --no-validate \
        --cmdpath "$cmd_path" --no-ssh-forward) 2>&1 | tee -a "$LOG_FILE"
    local SCRIPT_RESULT="${PIPESTATUS[0]}"
    local RESULT="$SCRIPT_RESULT"
    info "liteserver.sh (mode: $mode_name) exited with code: $RESULT"
    
    if [ "$RESULT" -eq 124 ]; then
        warn "Lite Raw Data Test ($mode_name) TIMED OUT after ${timeout_val}s"
    fi

    local TEST_END_TIME=$(date +%s)
    local TEST_DURATION=$((TEST_END_TIME - TEST_START_TIME))

    if [ "$RESULT" -eq 0 ]; then
        info "--- Lite Raw Data Test ($mode_name) Passed (${TEST_DURATION} seconds) ---"
    else
        echo "ERROR: --- Lite Raw Data Test ($mode_name) FAILED (${TEST_DURATION} seconds) ---"
    fi
    
    # Aggressive cleanup between modes to prevent resource leakage
    # Kill all QEMU processes and any remaining liteserver.sh orphans
    # Removed pkill commands as they can interfere with other parallel jobs.
    # liteserver.sh has its own robust cleanup.
    sleep 5
    
    if [ "$RESULT" -ne 0 ]; then
        fail "Lite Raw Data test ($mode_name) failed with exit code $RESULT. Check log: $LOG_FILE"
    else
        # Just to be sure shunit2 sees success
        assertTrue "Lite Raw Data test ($mode_name) passed" "[ $RESULT -eq 0 ]"
    fi

    return 0
}

# --- Test Cases ---

test_lite_bt_image() {
    run_lite_raw_check "BT-Image" "dev/ocscmd/lite-bt-image.sh"
}

test_lite_bt_dev() {
    run_lite_raw_check "BT-Dev" "dev/ocscmd/lite-bt-dev.sh"
}

test_lite_multicast_image() {
    run_lite_raw_check "Multicast-Image" "dev/ocscmd/lite-multicast-image.sh"
}

test_lite_multicast_dev() {
    run_lite_raw_check "Multicast-Dev" "dev/ocscmd/lite-multicast-dev.sh"
}

# --- Main execution ---

# Initialize common setup
initialize_test_environment

# Load shunit2
. shunit2
