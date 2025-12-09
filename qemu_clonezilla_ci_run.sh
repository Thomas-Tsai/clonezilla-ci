#!/bin/bash

# ----------------------------------------------------------------------
# Run Clonezilla QEMU CI test script
# This script starts QEMU in console mode to run automated Clonezilla tasks and powers off on completion.
# ----------------------------------------------------------------------

# Record start time
START_TIME=$(date +%s)

# Function to check for KVM availability
check_kvm_available() {
    if [ -e "/dev/kvm" ] && [ "$(groups | grep -c kvm)" -gt 0 ]; then
        echo "INFO: KVM is available and the current user is in the 'kvm' group."
        return 0 # KVM is available
    else
        echo "INFO: KVM is not available or the current user is not in the 'kvm' group. Running without KVM."
        return 1 # KVM is not available
    fi
}

# Function to print usage information
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Run a fully automated, non-interactive Clonezilla task in a QEMU VM."
    echo ""
    echo "Options:"
    echo "  --disk <path>           Path to a virtual disk image (.qcow2). Can be specified multiple times."
    echo "  --live <path>           Path to the Clonezilla live QCOW2 media."
    echo "  --kernel <path>         Path to the kernel file (e.g., vmlinuz)."
    echo "  --initrd <path>         Path to the initrd file."
    echo "  --image <path>          Path to the shared directory for Clonezilla images (default: ./partimag)."
    echo "  --cmd <command>         Command string to execute inside Clonezilla (e.g., 'sudo ocs-sr ...')."
    echo "  --cmdpath <path>        Path to a script file to execute inside Clonezilla."
    echo "  --append-args <args>    A string of custom kernel append arguments to override the default."
    echo "  --append-args-file <path> Path to a file containing custom kernel append arguments."
    echo "  -i, --interactive       Enable interactive mode (QEMU will not power off, output to terminal)."
    echo "  -h, --help              Display this help message and exit."
    echo ""
    echo "Example (Backup):"
    echo "  $0 \\"
    echo "    --disk ./qemu/source.qcow2 \\"
    echo "    --live ./isos/clonezilla.qcow2 \\"
    echo "    --kernel ./isos/vmlinuz \\"
    echo "    --initrd ./isos/initrd.img \\"
    echo "    --cmdpath ./dev/ocscmd/clone-first-disk.sh \\"
    echo "    --image ./partimag"
    echo ""
    echo "Example (Restore):"
    echo "  $0 \\"
    echo "    --disk ./qemu/restore.qcow2 \\"
    echo "    --live ./isos/clonezilla.qcow2 \\"
    echo "    --kernel ./isos/vmlinuz \\"
    echo "    --initrd ./isos/initrd.img \\"
    echo "    --cmd 'sudo /usr/sbin/ocs-sr -g auto -e1 auto -e2 -c -r -j2 -p poweroff restoredisk my-img-name sda' \\"
    echo "    --image ./partimag"
    exit 1
}

# Cleanup function to remove temporary files and directories
cleanup() {
    echo "--- Running cleanup ---"
    if [ -n "$HOST_SCRIPT_DIR" ] && [ -d "$HOST_SCRIPT_DIR" ]; then
        echo "Removing temporary script directory: $HOST_SCRIPT_DIR"
        rm -rf "$HOST_SCRIPT_DIR"
    fi

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    if [ "$INTERACTIVE_MODE" -eq 0 ]; then
        echo "Total execution time: ${DURATION} seconds" >> "$LOG_FILE"
        echo "INFO: Total execution time: ${DURATION} seconds (logged to $LOG_FILE)"
    else
        echo "INFO: Total execution time: ${DURATION} seconds"
    fi
}

# Set a trap to call the cleanup function on script exit
trap cleanup EXIT

# Default values
INTERACTIVE_MODE=0
PARTIMAG_PATH="./partimag"
DISKS=()
LIVE_DISK=""
KERNEL_PATH=""
INITRD_PATH=""
OCS_COMMAND=""
CMDPATH=""
CUSTOM_APPEND_ARGS=""
APPEND_ARGS_FILE=""
HOST_SCRIPT_DIR="" # Ensure variable is declared for the trap

# Argument parsing
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -i|--interactive)
            INTERACTIVE_MODE=1
            shift # past argument
            ;;
        -h|--help)
            print_usage
            ;;
        --disk)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                DISKS+=("$2")
                shift # past argument
                shift # past value
            else
                echo "Error: --disk requires a value." >&2
                print_usage
            fi
            ;;
        --live)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                LIVE_DISK="$2"
                shift # past argument
                shift # past value
            else
                echo "Error: --live requires a value." >&2
                print_usage
            fi
            ;;
        --kernel)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                KERNEL_PATH="$2"
                shift # past argument
                shift # past value
            else
                echo "Error: --kernel requires a value." >&2
                print_usage
            fi
            ;;
        --initrd)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                INITRD_PATH="$2"
                shift # past argument
                shift # past value
            else
                echo "Error: --initrd requires a value." >&2
                print_usage
            fi
            ;;
        --cmd)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                OCS_COMMAND="$2"
                shift # past argument
                shift # past value
            else
                echo "Error: --cmd requires a value." >&2
                print_usage
            fi
            ;;
        --cmdpath)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                CMDPATH="$2"
                shift # past argument
                shift # past value
            else
                echo "Error: --cmdpath requires a value." >&2
                print_usage
            fi
            ;;
        --image)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                PARTIMAG_PATH="$2"
                shift # past argument
                shift # past value
            else
                echo "Error: --image requires a value." >&2
                print_usage
            fi
            ;;
        --append-args)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                CUSTOM_APPEND_ARGS="$2"
                shift # past argument
                shift # past value
            else
                echo "Error: --append-args requires a value." >&2
                print_usage
            fi
            ;;
        --append-args-file)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                APPEND_ARGS_FILE="$2"
                shift # past argument
                shift # past value
            else
                echo "Error: --append-args-file requires a value." >&2
                print_usage
            fi
            ;;
        *)
            echo "Error: Unknown option or missing value for $1" >&2
            print_usage
            ;;
    esac
done

# --- Argument Validation ---

# Ensure either --cmd or --cmdpath is provided, but not both.
if [[ -z "$OCS_COMMAND" && -z "$CMDPATH" ]]; then
    echo "Error: Missing command. Please provide either --cmd or --cmdpath." >&2
    print_usage
fi
if [[ -n "$OCS_COMMAND" && -n "$CMDPATH" ]]; then
    echo "Error: Conflicting arguments. --cmd and --cmdpath cannot be used together." >&2
    print_usage
fi

# Ensure --append-args and --append-args-file are not used together.
if [[ -n "$CUSTOM_APPEND_ARGS" && -n "$APPEND_ARGS_FILE" ]]; then
    echo "Error: Conflicting arguments. --append-args and --append-args-file cannot be used together." >&2
    print_usage
fi

# Validation for other required arguments
if [[ ${#DISKS[@]} -eq 0 || -z "$LIVE_DISK" || -z "$KERNEL_PATH" || -z "$INITRD_PATH" ]]; then
    echo "Error: Missing one or more required arguments: --disk, --live, --kernel, --initrd." >&2
    print_usage
fi


# --- Command and Script Handling ---

if [ -n "$CMDPATH" ]; then
    # If --cmdpath is used, prepare the script for execution in the VM.
    if [ ! -f "$CMDPATH" ]; then
        echo "Error: Script file not found at path: $CMDPATH" >&2
        print_usage
    fi
    
    # Create a temporary directory within the shared 'partimag' folder to hold the script.
    # This keeps the root of the image directory clean.
    SCRIPT_DIR_NAME="cmd_script_$(date +%s)_$RANDOM"
    HOST_SCRIPT_DIR="$PARTIMAG_PATH/$SCRIPT_DIR_NAME"
    mkdir -p "$HOST_SCRIPT_DIR"
    
    # Copy the user's script to the temporary directory.
    cp "$CMDPATH" "$HOST_SCRIPT_DIR/"
    SCRIPT_BASENAME=$(basename "$CMDPATH")
    
    # The command to be run in the VM is now 'bash' on the script's path in the shared folder.
    VM_SCRIPT_PATH="/home/partimag/$SCRIPT_DIR_NAME/$SCRIPT_BASENAME"
    OCS_COMMAND="bash $VM_SCRIPT_PATH"
fi

# If --append-args-file is used, read the content into CUSTOM_APPEND_ARGS.
if [ -n "$APPEND_ARGS_FILE" ]; then
    if [ ! -f "$APPEND_ARGS_FILE" ]; then
        echo "Error: Append args file not found at path: $APPEND_ARGS_FILE" >&2
        print_usage
    fi
    CUSTOM_APPEND_ARGS=$(cat "$APPEND_ARGS_FILE")
fi

# Set log file name (only needed in non-interactive mode)
if [ "$INTERACTIVE_MODE" -eq 0 ]; then
    LOG_FILE="./clonezilla_ci_$(date +%Y%m%d_%H%M%S).log"
fi

# Check if files exist
for disk in "${DISKS[@]}"; do
    if [ ! -f "$disk" ]; then
        echo "Error: Disk image file not found: $disk" >&2
        print_usage
    fi
done
if [ ! -f "$LIVE_DISK" ]; then
    echo "Error: Live media disk file not found: $LIVE_DISK" >&2
    print_usage
fi
if [ ! -f "$KERNEL_PATH" ]; then
    echo "Error: Kernel file not found: $KERNEL_PATH" >&2
    print_usage
fi
if [ ! -f "$INITRD_PATH" ]; then
    echo "Error: Initrd file not found: $INITRD_PATH" >&2
    print_usage
fi
if [ ! -d "$PARTIMAG_PATH" ]; then
    echo "Error: Image storage directory not found: $PARTIMAG_PATH" >&2
    echo "Please ensure the directory exists, or specify the correct path with the --image option." >&2
    print_usage
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

# --- Disk and Boot Argument Configuration ---

# If --append-args-file is used, read its content.
if [ -n "$APPEND_ARGS_FILE" ]; then
    if [ ! -f "$APPEND_ARGS_FILE" ]; then
        echo "Error: Append args file not found at path: $APPEND_ARGS_FILE" >&2
        print_usage
    fi
    # Read the raw content from the file.
    CUSTOM_APPEND_ARGS=$(cat "$APPEND_ARGS_FILE")
    # Sanitize the input by removing a single pair of leading/trailing single or double quotes.
    # This prevents issues if the file content is wrapped in quotes, which would break kernel argument parsing.
    CUSTOM_APPEND_ARGS=$(echo "$CUSTOM_APPEND_ARGS" | sed -e "s/^'//" -e "s/'$//" -e 's/^"//' -e 's/"$//')
fi

# Combine user-specified disks and the live disk into a single array.
ALL_DISKS=("${DISKS[@]}" "$LIVE_DISK")
LIVE_DISK_INDEX=$((${#DISKS[@]}))

# Define mappings for QEMU drive letters and guest OS device names.
DRIVE_LETTERS=('a' 'b' 'c' 'd' 'e' 'f')
DEVICE_NAMES=('sda' 'sdb' 'sdc' 'sdd' 'sde' 'sdf')

QEMU_DISK_ARGS_ARRAY=()
LIVE_MEDIA_DEVICE=""

# Build the -hdX arguments for QEMU and identify the device name for the live media.
for i in "${!ALL_DISKS[@]}"; do
    if [ $i -lt ${#DRIVE_LETTERS[@]} ]; then
        drive_letter=${DRIVE_LETTERS[$i]}
        QEMU_DISK_ARGS_ARRAY+=("-hd${drive_letter}" "${ALL_DISKS[$i]}")
        
        if [ $i -eq $LIVE_DISK_INDEX ]; then
            LIVE_MEDIA_DEVICE="${DEVICE_NAMES[$i]}"
        fi
    else
        echo "Warning: Maximum number of disks (${#DRIVE_LETTERS[@]}) exceeded. Ignoring extra disks."
        break
    fi
done

if [ -z "$LIVE_MEDIA_DEVICE" ]; then
    echo "Error: Could not determine the device for the live media disk." >&2
    print_usage
fi

# Build kernel append arguments.
if [ -n "$CUSTOM_APPEND_ARGS" ]; then
    APPEND_ARGS="$CUSTOM_APPEND_ARGS"
else
    # Construct the default kernel command line, dynamically setting 'live-media'.
    APPEND_ARGS="boot=live config union=overlay noswap edd=on nomodeset noninteractive"
    APPEND_ARGS+=" locales=en_US.UTF-8 keyboard-layouts=us live-getty console=ttyS0,38400n81"
    APPEND_ARGS+=" live-media=/dev/${LIVE_MEDIA_DEVICE}1 live-media-path=/live toram"
    APPEND_ARGS+=" ocs_prerun=\"dhclient\" ocs_prerun1=\"mkdir -p /home/partimag\""
    APPEND_ARGS+=" ocs_prerun2=\"mount -t 9p -o trans=virtio,version=9p2000.L hostshare /home/partimag\""
    APPEND_ARGS+=" ocs_daemonon=\"ssh\" ocs_live_run=\"$OCS_COMMAND\""

    if [ "$INTERACTIVE_MODE" -eq 0 ]; then
        APPEND_ARGS+=" ocs_postrun=\"sudo poweroff\""
    fi
    APPEND_ARGS+=" noeject noprompt"
fi

# --- QEMU Execution ---

# Build the QEMU command using a bash array for robustness.
# This avoids all the quoting issues associated with building a command string and using eval.
QEMU_ARGS=(
    "qemu-system-x86_64"
    "-m" "2048"
    "-smp" "2"
    "-nographic"
    "-kernel" "$KERNEL_PATH"
    "-initrd" "$INITRD_PATH"
)

# Conditionally add -enable-kvm if available
if check_kvm_available; then
    QEMU_ARGS+=("-enable-kvm")
fi
QEMU_ARGS+=( "${QEMU_DISK_ARGS_ARRAY[@]}" )
QEMU_ARGS+=(
    "-device" "virtio-net-pci,netdev=net0"
    "-netdev" "user,id=net0,hostfwd=tcp::2222-:22"
    "-fsdev" "local,id=hostshare,path=$PARTIMAG_PATH,security_model=mapped-xattr"
    "-device" "virtio-9p-pci,fsdev=hostshare,mount_tag=hostshare"
    "-append" "$APPEND_ARGS"
)

echo "--- Starting QEMU for CI test ---"

# Determine output redirection and execute the command.
if [ "$INTERACTIVE_MODE" -eq 0 ]; then
    echo "Mode: Automated CI mode (output to log file)"
    echo "All output will be saved to log file: $LOG_FILE"
    echo "Executing command: ${QEMU_ARGS[*]}"
    echo "Executing command: ${QEMU_ARGS[*]}" > "$LOG_FILE"
    "${QEMU_ARGS[@]}" >> "$LOG_FILE" 2>&1
else
    echo "Mode: Interactive debug mode (output directly to terminal)"
    echo "Executing command: ${QEMU_ARGS[*]}"
    "${QEMU_ARGS[@]}"
fi

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
