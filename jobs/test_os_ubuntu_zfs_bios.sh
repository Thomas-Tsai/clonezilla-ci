#!/bin/bash
#
# test_os_ubuntu_zfs_bios.sh - Tests Ubuntu ZFS-on-root OS clone and restore (BIOS boot).
#
# Exercises partclone.zfs against the BIOS ZFS-on-root golden image built with
# ../../build-ubuntu-zfs-image.sh (see usage.md). Image discovery reads the
# 'ubuntu-zfs ... bios' stanza from qemu/cloudimages/cloud_images.conf.
#
# Minimum Clonezilla version: partclone.zfs first ships in Clonezilla Live
# 3.3.4-20 (stable) / 20261030 (daily); older zips are SKIPPED via
# skip_unless_clonezilla_version_or_newer in jobs/common.sh.
#
# Usage:   ./test_os_ubuntu_zfs_bios.sh [--zip <path>] [--arch <arch>] [--type <type>] [--no-ssh-forward]
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

# --- Test for ubuntu zfs-on-root system clone and restore (BIOS boot) ---
test_ubuntu_zfs_bios_clone_restore() {
    run_os_conf_suite "ubuntu-zfs" "$PROJECT_ROOT/isos/cidata.iso" "$NO_SSH_FORWARD_ARG" "bios" \
        "" "build it first: ./build-ubuntu-zfs-image.sh --firmware bios"
}

# --- Main execution ---

# Initialize common setup
initialize_test_environment

if [[ -z "$CLONEZILLA_ZIP" ]]; then
    echo "Error: Missing required argument --zip" >&2
    exit 1
fi

# ZFS (partclone.zfs) support requires Clonezilla Live >= 3.3.4-20 / 20261030-*
skip_unless_clonezilla_version_or_newer "Ubuntu ZFS-on-root OS test (BIOS)" "3.3.4-20" "20261030"

# Load shunit2
# shellcheck source=/dev/null
. shunit2
