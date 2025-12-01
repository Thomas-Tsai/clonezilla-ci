#!/bin/bash

# ----------------------------------------------------------------------
# Run Clonezilla QEMU CI test script
# This script starts QEMU in console mode to run automated Clonezilla tasks and powers off on completion.
# ----------------------------------------------------------------------

# Default values
INTERACTIVE_MODE=0
PARTIMAG_PATH="./partimag"
ARGS=()

# Argument parsing: handle flags and other positional arguments
# Allow -i/--interactive flag at any position
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -i|--interactive)
            INTERACTIVE_MODE=1
            shift # Consume flag
            ;;
        *)
            ARGS+=("$1") # Store positional argument
            shift
            ;;
    esac
done

# Check the number of required positional arguments
if [ "${#ARGS[@]}" -lt 5 ]; then
    echo "Error: Not enough arguments."
    echo "Usage: $0 [Options] <RestoreDisk> <LiveDisk> <KernelPath> <InitrdPath> \"<OCS_Live_Run_Command>\" [Optional_Image_Path]"
    echo ""
    echo "Options:"
    echo "  -i, --interactive: Enable interactive mode (output to terminal, no log file)."
    echo ""
    echo "Example:"
    echo "$0 -i restore.qcow2 live.qcow2 ./clonezilla/vmlinuz ./clonezilla/initrd.img \"sudo /usr/sbin/ocs-sr -g auto -p poweroff restoredisk ask_user sda\" \"/path/to/my/images\""
    echo "  * If [Optional_Image_Path] is omitted, defaults to './partimag'."
    exit 1
fi

# Reassign positional arguments
RESTORE_DISK="${ARGS[0]}"  # 1. Destination disk (hda)
LIVE_DISK="${ARGS[1]}"     # 2. Live media disk (hdb)
KERNEL_PATH="${ARGS[2]}"   # 3. Kernel file path
INITRD_PATH="${ARGS[3]}"   # 4. Initrd file path
OCS_COMMAND="${ARGS[4]}"   # 5. Full OCS_Live_Run command

# 6. Image storage directory (Host) - use if the 6th argument is provided
if [ "${#ARGS[@]}" -ge 6 ]; then
    PARTIMAG_PATH="${ARGS[5]}"
fi
# Otherwise, use the default "./partimag" (set at the beginning)

# Set log file name (only needed in non-interactive mode)
if [ "$INTERACTIVE_MODE" -eq 0 ]; then
    LOG_FILE="./clonezilla_ci_$(date +%Y%m%d_%H%M%S).log"
fi

# Check if files exist (logic unchanged)
if [ ! -f "$RESTORE_DISK" ]; then
    echo "Error: Destination disk file not found: $RESTORE_DISK"
    exit 1
fi
if [ ! -f "$LIVE_DISK" ]; then
    echo "Error: Live media disk file not found: $LIVE_DISK"
    exit 1
fi
if [ ! -f "$KERNEL_PATH" ]; then
    echo "Error: Kernel file not found: $KERNEL_PATH"
    exit 1
fi
if [ ! -f "$INITRD_PATH" ]; then
    echo "Error: Initrd file not found: $INITRD_PATH"
    exit 1
fi
if [ ! -d "$PARTIMAG_PATH" ]; then
    echo "Error: Image storage directory not found: $PARTIMAG_PATH"
    echo "Please ensure the directory exists, or specify the correct path with the sixth argument."
    exit 1
fi

echo "--- Starting QEMU for CI test ---"

# Determine output redirection
if [ "$INTERACTIVE_MODE" -eq 0 ]; then
    echo "Mode: Automated CI mode (output to log file)"
    echo "All output will be saved to log file: $LOG_FILE"
    # Set redirection string
    REDIRECTION="> \"$LOG_FILE\" 2>&1"
else
    echo "Mode: Interactive debug mode (output directly to terminal)"
    # Do not set redirection string
    REDIRECTION=""
fi
echo "-------------------------------------"

# Key fix: combine all -append parameter content into a single string
# Use double quotes (") internally to wrap parameter values containing spaces, like ocs_prerun1 and ocs_live_run.
# The outer single quotes (see QEMU_CMD) will ensure this string is passed completely.
#APPEND_ARGS="boot=live config union=overlay noswap edd=on nomodeset noninteractive locales=en_US.UTF-8 keyboard-layouts=us live-getty console=ttyS0,38400n81 live-media=/dev/sdb1 live-media-path=/live toram ocs_prerun=\"dhclient\" ocs_prerun1=\"mkdir -p /home/partimag\" ocs_prerun2=\"mount -t 9p -o trans=virtio,version=9p2000.L hostshare /home/partimag\" ocs_daemonon=\"ssh\" ocs_live_run=\"$OCS_COMMAND\" noeject noprompt"
APPEND_ARGS="boot=live config union=overlay noswap edd=on nomodeset noninteractive locales=en_US.UTF-8 keyboard-layouts=us live-getty console=ttyS0,38400n81 live-media=/dev/sdb1 live-media-path=/live toram ocs_prerun=\"dhclient\" ocs_prerun1=\"mkdir -p /home/partimag\" ocs_prerun2=\"mount -t 9p -o trans=virtio,version=9p2000.L hostshare /home/partimag\" ocs_daemonon=\"ssh\" ocs_live_run=\"$OCS_COMMAND\" ocs_postrun=\"sudo poweroff\" noeject noprompt"

# QEMU startup command (build command string)
# Use eval to execute the command to correctly handle quotes and redirection
# Fix: Change the double quotes outside the -append parameter to single quotes (') to prevent eval from breaking the internal quote structure.
QEMU_CMD="qemu-system-x86_64 \
    -enable-kvm \
    -m 2048 \
    -smp 2 \
    -nographic \
    -kernel \"$KERNEL_PATH\" \
    -initrd \"$INITRD_PATH\" \
    -hda \"$RESTORE_DISK\" \
    -hdb \"$LIVE_DISK\" \
    -device virtio-net-pci,netdev=net0 \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -fsdev local,id=hostshare,path=\"$PARTIMAG_PATH\",security_model=mapped-xattr \
    -device virtio-9p-pci,fsdev=hostshare,mount_tag=hostshare \
    -append '$APPEND_ARGS' \
    ${REDIRECTION}"

# Execute QEMU command
eval $QEMU_CMD

# Check QEMU exit code
QEMU_EXIT_CODE=$?
if [ $QEMU_EXIT_CODE -eq 0 ]; then
    echo "QEMU executed successfully and exited cleanly (possibly triggered by poweroff)."
    if [ "$INTERACTIVE_MODE" -eq 0 ]; then
        echo "Full log file located at: $LOG_FILE"
    fi
else
    echo "QEMU terminated unexpectedly. Please check for error messages."
    if [ "$INTERACTIVE_MODE" -eq 0 ]; then
        echo "Detailed log file located at: $LOG_FILE"
    fi
fi
