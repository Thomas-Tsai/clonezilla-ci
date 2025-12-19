#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Exit if an undefined variable is used.
set -u
# The exit status of a pipeline is the exit status of the last command that failed.
set -o pipefail

# --- Configuration ---
LOG_DIR="logs"
QCOW2_FILE=""
FS_TYPE=""
NBD_CONNECTED=false # Global flag to track if NBD was successfully connected

# --- Usage ---
usage() {
    cat <<EOF
Usage: $0 --qcow2 <path> --fstype <type>

A script to safely check the filesystem integrity of a QCOW2 image using qemu-nbd and fsck.
This script requires sudo privileges for device operations and kernel module loading.

Required arguments:
  --qcow2 <path>    Path to the QCOW2 image file to check.
  --fstype <type>   The type of the filesystem (e.g., ext4, vfat, xfs).

Options:
  --help            Display this help message and exit.
EOF
}

# --- Argument Parsing ---
while [ "$#" -gt 0 ]; do
    case "$1" in
        --qcow2)
            QCOW2_FILE="$2"
            shift 2
            ;;
        --fstype)
            FS_TYPE="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

# --- Argument Validation ---
if [ -z "$QCOW2_FILE" ] || [ -z "$FS_TYPE" ]; then
    echo "Error: Missing required arguments." >&2
    usage
    exit 1
fi

if [ ! -f "$QCOW2_FILE" ]; then
    echo "Error: QCOW2 file not found at '$QCOW2_FILE'" >&2
    exit 1
fi

# --- Pre-flight Checks ---
pre_flight_checks() {
    echo "--- Running pre-flight checks ---"

    # 1. Check for passwordless sudo permissions
    if ! sudo -n true 2>/dev/null; then
        echo "Error: This script requires passwordless sudo privileges." >&2
        echo "Please configure sudoers to allow the current user to run commands without a password." >&2
        exit 1
    fi
    echo "[OK] Sudo privileges"

    # 2. Check for required commands
    FSCK_COMMAND="fsck.${FS_TYPE}"
    for cmd in qemu-nbd "$FSCK_COMMAND"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "Error: Required command '$cmd' not found." >&2
            echo "Ensure qemu-utils and appropriate filesystem tools (e.g., e2fsprogs, dosfstools) are installed." >&2
            exit 1
        fi
    done
    echo "[OK] Required commands"

    # 3. Check and load nbd kernel module
    if ! lsmod | grep -q "^nbd "; then
        echo "NBD module not loaded. Attempting to load..."
        if ! sudo modprobe nbd max_part=8; then
            echo "Error: Failed to load nbd kernel module." >&2
            exit 1
        fi
        echo "NBD module loaded."
    else
        echo "[OK] NBD module"
    fi
    echo "---------------------------"
}

# --- Main Logic ---
main() {
    pre_flight_checks

    TEMP_LOG_FILE=$(mktemp)
    NBD_DEV=""
    FSCK_EXIT_CODE=0

    cleanup() {
        echo "--- Starting cleanup process ---"
        if [ -n "$NBD_DEV" ] && $NBD_CONNECTED; then # Only attempt disconnect if NBD_DEV was assigned and connect was successful
            echo "[Cleanup] NBD device '$NBD_DEV' was successfully connected. Attempting to disconnect..."
            # Using '|| true' to prevent cleanup from failing the script's exit status
            sudo qemu-nbd --disconnect "$NBD_DEV" || true
            local DISCONNECT_CODE=$?
            if [ $DISCONNECT_CODE -eq 0 ]; then
                echo "[Cleanup] Disconnect command executed successfully."
            else
                echo "[Cleanup] WARNING: Disconnect command failed with exit code $DISCONNECT_CODE." >&2
                echo "[Cleanup] The NBD device may still be connected. Manual intervention might be required: sudo qemu-nbd --disconnect $NBD_DEV" >&2
            fi
        else
            echo "[Cleanup] NBD device was not successfully connected (NBD_CONNECTED=$NBD_CONNECTED). No disconnect needed."
        fi
        rm -f "$TEMP_LOG_FILE"
        echo "--- Cleanup process finished ---"
    }
    trap cleanup EXIT SIGINT SIGTERM

    # Find a free nbd device
    for i in $(seq 0 15); do
        if ! [ -e "/sys/class/block/nbd${i}/pid" ]; then
            NBD_DEV="/dev/nbd${i}"
            break
        fi
    done

    if [ -z "$NBD_DEV" ]; then
        echo "Error: No free nbd device found." >&2
        exit 1
    fi
    echo "Found free NBD device: $NBD_DEV"

    # Connect the QCOW2 image to the nbd device
    echo "Connecting '$QCOW2_FILE' to '$NBD_DEV' (read-only mode)..."
    sudo qemu-nbd --connect=$NBD_DEV --read-only "$QCOW2_FILE"
    NBD_CONNECTED=true # Set flag after successful connection
    
    # Wait for partition device to appear
    sleep 2
    PARTITION="${NBD_DEV}p1" # Assuming first partition
    if [ ! -b "$PARTITION" ]; then
       echo "Error: Partition '$PARTITION' did not appear. Check the image's partition table." >&2
       exit 1
    fi

    # Run fsck and redirect output to temp file
    FSCK_COMMAND="fsck.${FS_TYPE}"
    echo "Running '$FSCK_COMMAND -n $PARTITION'..."
    sudo "$FSCK_COMMAND" -n "$PARTITION" >"$TEMP_LOG_FILE" 2>&1 || FSCK_EXIT_CODE=$?

    # Handle fsck result
    if [ $FSCK_EXIT_CODE -eq 0 ]; then
        echo "Success: Filesystem check passed for '$QCOW2_FILE'."
        exit 0
    else
        echo "Failure: Filesystem check failed with exit code $FSCK_EXIT_CODE."
        
        mkdir -p "$LOG_DIR"
        DATETIME=$(date +"%Y%m%d-%H%M%S")
        FINAL_LOG_FILE="${LOG_DIR}/fsck-${FS_TYPE}-${DATETIME}.log"
        mv "$TEMP_LOG_FILE" "$FINAL_LOG_FILE"
        
        echo "Log file saved to: $FINAL_LOG_FILE"
        echo "--- Log Content ---"
        cat "$FINAL_LOG_FILE"
        echo "-------------------"
        exit $FSCK_EXIT_CODE
    fi
}

main