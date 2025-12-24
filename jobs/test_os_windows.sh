#!/bin/bash
#
# test_os_windows.sh - Tests Windows OS clone and restore.
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

# --- Test for windows clone and restore ---
test_windows11_clone_restore() {
    local image_path="$PROJECT_ROOT/qemu/cloudimages/windown-11-${ARCH}.qcow2"

    if [ -f "$image_path" ]; then
        run_os_clone_restore "$image_path" "$PROJECT_ROOT/isos/win11_cidata.iso"
    else
        echo "Skipping test for windown-11-${ARCH}: image file not found at ${image_path}"
    fi
}

# --- Main execution ---

# Initialize common setup
initialize_test_environment

# Load shunit2
. shunit2
