#!/bin/bash
#
# test_lite_bt_from_device.sh - Tests the lite bt from device functionality.
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

# --- Test for lite bt from device ---
test_lite_bt_from_device() {
    # Check if the required disk for the test exists.
    local test_disk="$PROJECT_ROOT/qemu/cloudimages/debian-13-amd64.qcow2"
    if [ -f "$test_disk" ]; then
        run_lite_bt_from_device_test # No --no-ssh-forward parameter is needed here
    else
        echo "Skipping Lite BT From Device test: required disk not found at ${test_disk}"
    fi
}

# --- Main execution ---

# Initialize common setup
initialize_test_environment

# Load shunit2
. shunit2
