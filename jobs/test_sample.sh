#!/bin/bash
#
# test_sample.sh - sample test
#

# Source the common script
. "$(dirname "$0")/common.sh"

local NO_SSH_FORWARD_ARG=""

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

# Convert CLONEZILLA_ZIP to an absolute path if it was provided
if [[ -n "$CLONEZILLA_ZIP" ]]; then
    CLONEZILLA_ZIP="$(realpath "$CLONEZILLA_ZIP")"
fi

# --- Test for ubuntu system clone and restore ---
test_sample() {
    qemu-img create -f qcow2 ../qemu/sample_restore.qcow2 1G
    # Ensure cleanup happens when the function returns
    trap 'rm -f ../qemu/sample_restore.qcow2' RETURN

    # Run the command and capture its stdout/stderr
    local output
    echo "RUNNING: qemu-clonezilla-ci-run.sh --zip "$CLONEZILLA_ZIP" --disk qemu/sample_restore.qcow2  --arch "$ARCH" --cmd pwd"
    output=$((cd .. && ./qemu-clonezilla-ci-run.sh --zip "$CLONEZILLA_ZIP" --disk qemu/sample_restore.qcow2  --arch "$ARCH" --cmd pwd) 2>&1)
    echo "$output" # Show the output for debugging

    # Extract the log file path from the output, removing any carriage returns
    local log_file
    log_file=$(echo "$output" | grep "^Full log file located at:" | awk '{print $NF}' | tr -d '\r')

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

    # Grep for 'finish' and print the result. Grep's exit code will determine test pass/fail.
    echo "Grepping for 'finish' in $log_path..."
    grep "finish" "$log_path"
}

# --- Main execution ---

# Initialize common setup
initialize_test_environment

# Load shunit2
. shunit2
