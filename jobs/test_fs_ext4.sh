#!/bin/bash
#
# test_fs_ext4.sh - Tests ext4 file system clone and restore.
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

# --- Test for ext4 file system clone and restore ---
test_ext4_clone_restore() {
    run_fs_clone_restore "ext4" "$NO_SSH_FORWARD_ARG"
}

# --- Main execution ---

# Initialize common setup
initialize_test_environment

# Load shunit2
. shunit2
