#!/bin/bash
#
# test_os_debian.sh - Tests Debian OS clone and restore.
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

# --- Test for debian system clone and restore ---
test_debian_clone_restore() {
    local os="debian"
    
    # Find all debian releases for the given arch in the conf file
    grep -E "^\s*${os}\s+.*\s+${ARCH}\s+" "$PROJECT_ROOT/qemu/cloudimages/cloud_images.conf" | while read -r config_line; do
        # Extract release from the line
        local release=$(echo "$config_line" | awk '{print $2}')
        local image_name="${os}-${release}-${ARCH}.qcow2"
        local image_path="$PROJECT_ROOT/qemu/cloudimages/${image_name}"

        if [ -f "$image_path" ]; then
            run_os_clone_restore "$image_path" "$PROJECT_ROOT/isos/cidata.iso" "$NO_SSH_FORWARD_ARG"
        else
            echo "Skipping test for ${os}-${release}-${ARCH}: image file not found at ${image_path}"
        fi
    done
}

# --- Main execution ---

# Initialize common setup
initialize_test_environment

# Load shunit2
. shunit2
