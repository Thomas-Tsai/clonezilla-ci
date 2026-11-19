#!/bin/bash
#
# test_os_windows_efi.sh - Tests Windows OS clone and restore (EFI boot).
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

# EFI boot uses AMD64 OVMF only; other architectures skip cleanly.
if [ "$ARCH" != "amd64" ]; then
    echo "SKIPPED: EFI boot test is amd64-only (requested arch: $ARCH)."
    exit 0
fi

# Convert CLONEZILLA_ZIP to an absolute path if it was provided
if [[ -n "$CLONEZILLA_ZIP" ]]; then
    CLONEZILLA_ZIP="$(realpath "$CLONEZILLA_ZIP")"
fi

# --- Test for windows clone and restore (EFI boot) ---
test_windows_efi_clone_restore() {
    run_os_conf_suite "windows" "$PROJECT_ROOT/isos/win11_cidata.iso" "$NO_SSH_FORWARD_ARG" "uefi" \
        "" "windows images are prepared manually; see qemu/cloudimages/note"
}

# --- Main execution ---

# Initialize common setup
initialize_test_environment

# Load shunit2
. shunit2
