#!/bin/bash
#
# test_os_ubuntu_zfs.sh – Tests Ubuntu ZFS-on-root OS clone and restore.
#
# Exercises partclone.zfs against a ZFS-on-root golden image built with
# ../../build-ubuntu-zfs-image.sh (see usage.md). Image discovery reads the
# 'ubuntu-zfs' stanzas from qemu/cloudimages/cloud_images.conf, e.g.
#   ubuntu-zfs  24.04-uefi  amd64  PLACEHOLDER_...
#   ubuntu-zfs  24.04-bios  amd64  PLACEHOLDER_...
# -> qemu/cloudimages/ubuntu-zfs-<release>-<arch>.qcow2
#
# Minimum Clonezilla version: partclone.zfs first ships in Clonezilla Live
# 3.3.4-20 (stable) / 20261030 (daily); older zips are SKIPPED via
# skip_unless_clonezilla_version_or_newer in jobs/common.sh.
#
# Usage:   ./test_os_ubuntu_zfs.sh [--zip <path>] [--arch <arch>] [--type <type>] [--no-ssh-forward]
#

# Source the common script
. "$(dirname "$0")/common.sh"

NO_SSH_FORWARD_ARG=""

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
    -h | --help)
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

# --- Test for ubuntu zfs-on-root system clone and restore ---
test_ubuntu_zfs_clone_restore() {
    local os="ubuntu-zfs"

    # Find all ubuntu-zfs releases for the given arch in the conf file
    grep -E "^\s*${os}\s+.*\s+${ARCH}\s+" "$PROJECT_ROOT/qemu/cloudimages/cloud_images.conf" | while read -r config_line; do
        # Extract release from the line
        local release=$(echo "$config_line" | awk '{print $2}')
        local image_name="${os}-${release}-${ARCH}.qcow2"
        local image_path="$PROJECT_ROOT/qemu/cloudimages/${image_name}"

        if [ -f "$image_path" ]; then
            run_os_clone_restore "$image_path" "$PROJECT_ROOT/isos/cidata.iso" "$NO_SSH_FORWARD_ARG"
        else
            echo "Skipping test for ${os}-${release}-${ARCH}: image file not found at ${image_path}"
            echo "  (build it first: ./build-ubuntu-zfs-image.sh --firmware ${release##*-})"
        fi
    done
}

# --- Main execution ---

# Initialize common setup
initialize_test_environment

if [[ -z "$CLONEZILLA_ZIP" ]]; then
    echo "Error: Missing required argument --zip" >&2
    exit 1
fi

# ZFS (partclone.zfs) support requires Clonezilla Live >= 3.3.4-20 / 20261030-*
skip_unless_clonezilla_version_or_newer "Ubuntu ZFS-on-root OS test" "3.3.4-20" "20261030"

# Load shunit2
# shellcheck source=/dev/null
. shunit2
