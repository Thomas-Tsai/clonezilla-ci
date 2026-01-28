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
    echo "Boot Media Options (choose one method):"
    echo "  1. From ZIP (recommended):"
    echo "     --zip <path>              Path to the Clonezilla live ZIP file. Automates the next 4 options."
    echo "     --zip-output <dir>      Directory to store the extracted QCOW2, kernel, and initrd. (Default: ./zip)"
    echo "     --zip-size <size>         Size of the live QCOW2 image to create. (Default: 2G)"
    echo "     --zip-force               Force re-extraction of the ZIP file if output files already exist."
    echo ""
    echo "  2. From extracted files:"
    echo "     --live <path>             Path to the Clonezilla live QCOW2 media."
    echo "     --kernel <path>           Path to the kernel file (e.g., vmlinuz)."
    echo "     --initrd <path>           Path to the initrd file."
    echo ""
    echo "VM and Task Options:"
    echo "  --disk <path>           Path to a virtual disk image (.qcow2). Can be specified multiple times."
    echo "  --disk-lbas <size>      Logical block size for data disks (e.g., 512, 4096)."
    echo "  --disk-pbas <size>      Physical block size for data disks (e.g., 512, 4096)."
    echo "  --disk-driver <type>    Disk driver to use: 'virtio-blk' (default) or 'nvme'."
    echo "  --image <path>          Path to the shared directory for Clonezilla images (default: ./partimag)."
    echo "  --cmd <command>         Command string to execute inside Clonezilla (e.g., 'sudo ocs-sr ...')."
    echo "  --cmdpath <path>        Path to a script file to execute inside Clonezilla."
    echo "  --append-args <args>    A string of custom kernel append arguments to override the default."
    echo "  --append-args-file <path> Path to a file containing custom kernel append arguments."
    echo "  --qemu-args <args>      A string of extra arguments to pass to the QEMU command. Can be specified multiple times."
    echo "  --log-dir <path>        Directory to store log files (default: ./logs)."
    echo "  --arch <arch>           Target architecture (amd64, arm64, riscv64). Default: amd64."
    echo "  --no-ssh-forward        Disable TCP port 2222 forwarding for SSH."
    echo "  -i, --interactive       Enable interactive mode (QEMU will not power off, output to terminal)."
    echo "  -h, --help              Display this help message and exit."
    echo ""
    echo "Example (Backup with ZIP):"
    echo "  $0 \\"
    echo "    --disk ./qemu/source.qcow2 \\"
    echo "    --zip ./zip/clonezilla-live-3.1.2-9-amd64.zip \\"
    echo "    --cmdpath ./dev/ocscmd/clone-first-disk.sh \\"
    echo "    --image ./partimag"
    echo ""
    echo "Example (Restore with extracted files):"
    echo "  $0 \\"
    echo "    --disk ./qemu/restore.qcow2 \\"
    echo "    --live ./isos/clonezilla.qcow2 \\"
    echo "    --kernel ./isos/vmlinuz \\"
    echo "    --initrd ./isos/initrd.img \\"
    echo "    --cmd 'sudo /usr/sbin/ocs-sr -g auto -e1 auto -e2 -c -r -j2 -p poweroff restoredisk my-img-name vda' \\"
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
LOG_DIR="./logs" # New default log directory
DISKS=()
LIVE_DISK=""
KERNEL_PATH=""
INITRD_PATH=""
OCS_COMMAND=""
CMDPATH=""
CUSTOM_APPEND_ARGS=""
APPEND_ARGS_FILE=""
HOST_SCRIPT_DIR="" # Ensure variable is declared for the trap
LOG_FILE="" # Initialize LOG_FILE
CLONEZILLA_ZIP=""
ZIP_OUTPUT_DIR="./zip"
ZIP_IMAGE_SIZE="2G"
ZIP_FORCE=0
ARCH="amd64"
ARCH_WAS_SET=0
DEFAULT_LOGICAL_BLOCK_SIZE=""
DEFAULT_PHYSICAL_BLOCK_SIZE=""
EXTRA_QEMU_ARGS=()
SSH_FORWARD_ENABLED=1
DISK_DRIVER="virtio-blk"
EFI_ENABLED=0
TEMP_DIR_PATH=""
PCI_BUS_NAME="pci.0"

# Argument parsing
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --no-ssh-forward)
            SSH_FORWARD_ENABLED=0
            shift 1
            ;;
        --qemu-args)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                # Read the space-separated string into a temporary array
                read -r -a temp_args <<< "$2"
                # Append the elements of the temporary array to the main extra args array
                EXTRA_QEMU_ARGS+=( "${temp_args[@]}" )
                shift 2
            else
                echo "Error: --qemu-args requires a value." >&2
                print_usage
            fi
            ;;
        --arch)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                ARCH="$2"
                ARCH_WAS_SET=1
                shift 2
            else
                echo "Error: --arch requires a value." >&2
                print_usage
            fi
            ;;
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
                shift 2
            else
                echo "Error: --disk requires a value." >&2
                print_usage
            fi
            ;;
        --zip)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                CLONEZILLA_ZIP="$2"
                shift 2
            else
                echo "Error: --zip requires a value." >&2
                print_usage
            fi
            ;;
        --zip-output)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                ZIP_OUTPUT_DIR="$2"
                shift 2
            else
                echo "Error: --zip-output requires a value." >&2
                print_usage
            fi
            ;;
        --zip-size)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                ZIP_IMAGE_SIZE="$2"
                shift 2
            else
                echo "Error: --zip-size requires a value." >&2
                print_usage
            fi
            ;;
        --zip-force)
            ZIP_FORCE=1
            shift 1
            ;;
        --live)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                LIVE_DISK="$2"
                shift 2
            else
                echo "Error: --live requires a value." >&2
                print_usage
            fi
            ;;
        --kernel)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                KERNEL_PATH="$2"
                shift 2
            else
                echo "Error: --kernel requires a value." >&2
                print_usage
            fi
            ;;
        --initrd)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                INITRD_PATH="$2"
                shift 2
            else
                echo "Error: --initrd requires a value." >&2
                print_usage
            fi
            ;;
        --cmd)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                OCS_COMMAND="$2"
                shift 2
            else
                echo "Error: --cmd requires a value." >&2
                print_usage
            fi
            ;;
        --cmdpath)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                CMDPATH="$2"
                shift 2
            else
                echo "Error: --cmdpath requires a value." >&2
                print_usage
            fi
            ;;
        --image)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                PARTIMAG_PATH="$2"
                shift 2
            else
                echo "Error: --image requires a value." >&2
                print_usage
            fi
            ;;
        --append-args)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                CUSTOM_APPEND_ARGS="$2"
                shift 2
            else
                echo "Error: --append-args requires a value." >&2
                print_usage
            fi
            ;;
        --append-args-file)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                APPEND_ARGS_FILE="$2"
                shift 2
            else
                echo "Error: --append-args-file requires a value." >&2
                print_usage
            fi
            ;;
        --log-dir)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                LOG_DIR="$2"
                shift 2
            else
                echo "Error: --log-dir requires a value." >&2
                print_usage
            fi
            ;;
        --temp-dir)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                TEMP_DIR_PATH="$2"
                shift 2
            else
                echo "Error: --temp-dir requires a value." >&2
                print_usage
            fi
            ;;
        --disk-lbas)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                DEFAULT_LOGICAL_BLOCK_SIZE="$2"
                shift 2
            else
                echo "Error: --disk-lbas requires a value." >&2
                print_usage
            fi
            ;;
        --disk-pbas)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                DEFAULT_PHYSICAL_BLOCK_SIZE="$2"
                shift 2
            else
                echo "Error: --disk-pbas requires a value." >&2
                print_usage
            fi
            ;;
        --disk-driver)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                if [[ "$2" == "virtio-blk" || "$2" == "nvme" ]]; then
                    DISK_DRIVER="$2"
                    shift 2
                else
                    echo "Error: Invalid value for --disk-driver. Must be 'virtio-blk' or 'nvme'." >&2
                    print_usage
                fi
            else
                echo "Error: --disk-driver requires a value." >&2
                print_usage
            fi
            ;;
        --efi)
            EFI_ENABLED=1
            shift 1
            ;;
        *)
            echo "Error: Unknown option or missing value for $1" >&2
            print_usage
            ;;
    esac
done

# --- Architecture Inference ---
if [[ "$ARCH_WAS_SET" -eq 0 ]]; then
    # If --arch was not specified, try to infer it from the input files
    FILE_TO_INSPECT=""
    if [[ -n "$CLONEZILLA_ZIP" ]]; then
        FILE_TO_INSPECT="$CLONEZILLA_ZIP"
    elif [[ -n "$KERNEL_PATH" ]]; then
        # This case handles when user provides --kernel but not --zip
        FILE_TO_INSPECT="$KERNEL_PATH"
    fi

    if [[ -n "$FILE_TO_INSPECT" ]]; then
        if echo "$FILE_TO_INSPECT" | grep -q "arm64"; then
            ARCH="arm64"
            echo "INFO: Inferred architecture as 'arm64' from input file. Use --arch to override."
        elif echo "$FILE_TO_INSPECT" | grep -q "riscv64"; then
            ARCH="riscv64"
            echo "INFO: Inferred architecture as 'riscv64' from input file. Use --arch to override."
        elif echo "$FILE_TO_INSPECT" | grep -q "amd64"; then
            ARCH="amd64"
            # No message for the default case
        else
            echo "WARNING: Could not infer architecture from input file name. Defaulting to '$ARCH'. Use --arch to specify."
        fi
    fi
fi

# --- Automatic ZIP Extraction ---
if [ -n "$CLONEZILLA_ZIP" ]; then
    # Validate that mutually exclusive boot options are not used
    if [[ -n "$LIVE_DISK" || -n "$KERNEL_PATH" || -n "$INITRD_PATH" ]]; then
        echo "Error: --zip cannot be used with --live, --kernel, or --initrd." >&2
        print_usage
    fi

    # Check for the conversion script
    CONVERSION_SCRIPT="./clonezilla-zip2qcow.sh"
    if [ ! -x "$CONVERSION_SCRIPT" ]; then
        echo "Error: Conversion script not found or not executable: $CONVERSION_SCRIPT" >&2
        exit 1
    fi

    echo "--- Preparing boot media from ZIP ---"
    
    # Derive output paths from the zip name
    ZIP_BASENAME=$(basename "$CLONEZILLA_ZIP" .zip)
    OUTPUT_SUBDIR="$ZIP_OUTPUT_DIR/$ZIP_BASENAME"
    
    # Set the expected final paths for the boot files
    LIVE_DISK="$OUTPUT_SUBDIR/$ZIP_BASENAME.qcow2"
    KERNEL_PATH="$OUTPUT_SUBDIR/${ZIP_BASENAME}-vmlinuz"
    INITRD_PATH="$OUTPUT_SUBDIR/${ZIP_BASENAME}-initrd.img"

    # Check if all files exist or if --zip-force is used
    if [ "$ZIP_FORCE" -eq 1 ] || [ ! -f "$LIVE_DISK" ] || [ ! -f "$KERNEL_PATH" ] || [ ! -f "$INITRD_PATH" ]; then
        echo "Extracting Clonezilla ZIP. This may take a moment..."
        
        # Build the command
        CONVERT_CMD=("$CONVERSION_SCRIPT" --zip "$CLONEZILLA_ZIP" --output "$ZIP_OUTPUT_DIR" --size "$ZIP_IMAGE_SIZE" --arch "$ARCH")
        if [ "$ZIP_FORCE" -eq 1 ]; then
            CONVERT_CMD+=("--force")
        fi
        
        # Execute the command
        if ! "${CONVERT_CMD[@]}"; then
            echo "Error: Failed to process Clonezilla ZIP file. See output above." >&2
            exit 1
        fi
        echo "Extraction complete."
    else
        echo "Required boot files already exist. Skipping extraction."
    fi
    echo "-----------------------------------"
fi


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
    echo "Error: Missing one or more required arguments." >&2
    echo "Please provide --disk and boot media (e.g., --zip, or --live/--kernel/--initrd)." >&2
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
    mkdir -p "$LOG_DIR" # Ensure log directory exists
    LOG_FILE="$LOG_DIR/clonezilla_ci_$(date +%Y%m%d_%H%M%S).log"
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

# --- QEMU Execution ---

# Set QEMU binary and machine type based on architecture
case "$ARCH" in
    "amd64")
        QEMU_BINARY="qemu-system-x86_64"
        QEMU_MACHINE_ARGS=()
        if [ "$EFI_ENABLED" -eq 1 ]; then
            echo "INFO: EFI boot enabled for amd64."
            
            # Determine the base directory for temp files. Use TEMP_DIR_PATH if set, otherwise default to LOG_DIR.
            if [ -n "$TEMP_DIR_PATH" ]; then
                base_temp_dir="$TEMP_DIR_PATH"
            else
                base_temp_dir="$LOG_DIR"
            fi
            
            # Create a temporary, writable copy of the OVMF_VARS file for this VM instance.
            # This prevents instances from interfering with each other's NVRAM.
            OVMF_VARS_TEMPLATE="/usr/share/OVMF/OVMF_VARS_4M.fd"
            OVMF_CODE_FILE="/usr/share/OVMF/OVMF_CODE_4M.fd" # Use standard non-Secure Boot firmware
            TEMP_OVMF_VARS="${base_temp_dir}/temp_ovmf_vars_$(date +%s)_$RANDOM.fd"
            if [ ! -f "$OVMF_VARS_TEMPLATE" ]; then
                echo "ERROR: UEFI VARS template not found at $OVMF_VARS_TEMPLATE" >&2
                exit 1
            fi
            if [ ! -f "$OVMF_CODE_FILE" ]; then
                echo "ERROR: UEFI CODE file not found at $OVMF_CODE_FILE" >&2
                exit 1
            fi
            cp "$OVMF_VARS_TEMPLATE" "$TEMP_OVMF_VARS"
            
            QEMU_MACHINE_ARGS+=("-drive" "if=pflash,format=raw,readonly=on,file=$OVMF_CODE_FILE")
            QEMU_MACHINE_ARGS+=("-drive" "if=pflash,format=raw,file=$TEMP_OVMF_VARS")
        fi
        ;;
    "arm64")
        QEMU_BINARY="qemu-system-aarch64"
        QEMU_MACHINE_ARGS=("-machine" "virt" "-bios" "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd")
        PCI_BUS_NAME="pcie.0"
        ;;
    "riscv64")
        QEMU_BINARY="qemu-system-riscv64"
        QEMU_MACHINE_ARGS=("-machine" "virt")
        PCI_BUS_NAME="pcie.0"
        ;;
    *)
        echo "Error: Unsupported architecture: $ARCH" >&2
        print_usage
        ;;
esac

# Check if QEMU binary exists
if ! command -v "$QEMU_BINARY" &> /dev/null; then
    echo "Error: QEMU binary not found for architecture '$ARCH': $QEMU_BINARY" >&2
    echo "Please ensure the QEMU system emulator for '$ARCH' is installed and in your PATH." >&2
    echo "On Debian/Ubuntu, you might need to install 'qemu-system-arm' (for arm64) or 'qemu-system-misc' (for riscv64)." >&2
    exit 1
fi

# --- Disk and Boot Argument Configuration ---

QEMU_DISK_ARGS_ARRAY=()
QEMU_DATA_DISK_IDX=0 # Counter for data disks
LAST_PCI_ADDR=3 # PCI address counter, start addresses from 0x4

# --- 1. Configure Data Disks ---
if [[ "$DISK_DRIVER" == "virtio-blk" ]]; then
    DATA_PARTITION_SUFFIX='1'
else # nvme
    DATA_PARTITION_SUFFIX='p1'
fi

for data_disk_path in "${DISKS[@]}"; do
    data_drive_id="data_drive${QEMU_DATA_DISK_IDX}"
    data_drive_properties="id=${data_drive_id},file=${data_disk_path},format=qcow2,if=none"
    
    LAST_PCI_ADDR=$((LAST_PCI_ADDR + 1))
    CURRENT_PCI_ADDR=$(printf '0x%x' "$LAST_PCI_ADDR")
    
    if [[ "$DISK_DRIVER" == "virtio-blk" ]]; then
        QEMU_DISK_ARGS_ARRAY+=("-drive" "${data_drive_properties}")
        QEMU_DISK_ARGS_ARRAY+=("-device" "virtio-blk-pci,drive=${data_drive_id},bus=${PCI_BUS_NAME},addr=${CURRENT_PCI_ADDR}")
    else # nvme
        nvme_device_properties="drive=${data_drive_id},serial=data_sn${QEMU_DATA_DISK_IDX}"
        if [ -n "$DEFAULT_LOGICAL_BLOCK_SIZE" ]; then
            nvme_device_properties+=",logical_block_size=${DEFAULT_LOGICAL_BLOCK_SIZE}"
        fi
        if [ -n "$DEFAULT_PHYSICAL_BLOCK_SIZE" ]; then
            nvme_device_properties+=",physical_block_size=${DEFAULT_PHYSICAL_BLOCK_SIZE}"
        fi
        QEMU_DISK_ARGS_ARRAY+=("-drive" "${data_drive_properties}")
        QEMU_DISK_ARGS_ARRAY+=("-device" "nvme,${nvme_device_properties},bus=${PCI_BUS_NAME},addr=${CURRENT_PCI_ADDR}")
    fi
    QEMU_DATA_DISK_IDX=$((QEMU_DATA_DISK_IDX + 1))
done

# --- 2. Configure Clonezilla Live Media (always virtio-blk and always last) ---
live_drive_id="clz_live_drive"
live_drive_properties="id=${live_drive_id},file=${LIVE_DISK},format=qcow2,if=none,readonly=on"

LAST_PCI_ADDR=$((LAST_PCI_ADDR + 1))
CURRENT_PCI_ADDR=$(printf '0x%x' "$LAST_PCI_ADDR")
QEMU_DISK_ARGS_ARRAY+=("-drive" "${live_drive_properties}")
QEMU_DISK_ARGS_ARRAY+=("-device" "virtio-blk-pci,drive=${live_drive_id},bus=${PCI_BUS_NAME},addr=${CURRENT_PCI_ADDR}")

# --- Determine Live Media Device Name for Kernel Args ---
LIVE_MEDIA_PARTITION_SUFFIX="1" # Partition 1 for virtio-blk
if [[ "$DISK_DRIVER" == "nvme" ]]; then
    # If data disks are NVMe, they don't use 'vd' names, so the live disk will be 'vda'
    LIVE_MEDIA_DEVICE_NAME="vda"
else
    # If data disks are virtio-blk, they will be vda, vdb, ...
    # The live disk will be the next one in the sequence.
    # ASCII value of 'a' is 97.
    LIVE_MEDIA_DEVICE_NAME_ASCII=$((97 + QEMU_DATA_DISK_IDX))
    # Check for multi-character device names, although unlikely for this script
    if (( LIVE_MEDIA_DEVICE_NAME_ASCII > 122 )); then # 'z'
      echo "ERROR: Too many virtio-blk disks, cannot determine live media device name." >&2
      exit 1
    fi
    LIVE_MEDIA_DEVICE_NAME_CHAR=$(printf "\\$(printf '%03o' "$LIVE_MEDIA_DEVICE_NAME_ASCII")")
    LIVE_MEDIA_DEVICE_NAME="vd${LIVE_MEDIA_DEVICE_NAME_CHAR}"
fi


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

# Build kernel append arguments.
if [ -n "$CUSTOM_APPEND_ARGS" ]; then
    APPEND_ARGS="$CUSTOM_APPEND_ARGS"
else
    # Construct the default kernel command line, dynamically setting 'live-media'.
    APPEND_ARGS="boot=live config union=overlay noswap nomodeset noninteractive"
    if [ "$ARCH" = "amd64" ]; then
        APPEND_ARGS+=" edd=on"
    fi
    
    CONSOLE_ARG="console=ttyS0,38400n81" # Default console for amd64, riscv64
    if [ "$ARCH" = "arm64" ]; then
        CONSOLE_ARG="console=ttyAMA0,38400n8"
    fi
    # Construct the live-media path with the correct partition suffix
    LIVE_MEDIA_WITH_PARTITION="/dev/${LIVE_MEDIA_DEVICE_NAME}${LIVE_MEDIA_PARTITION_SUFFIX}"

    APPEND_ARGS+=" locales=en_US.UTF-8 keyboard-layouts=us live-getty ${CONSOLE_ARG}"
    APPEND_ARGS+=" live-media=${LIVE_MEDIA_WITH_PARTITION} live-media-path=/live toram"
    APPEND_ARGS+=" ocs_prerun=\"dhclient\" ocs_prerun1=\"mkdir -p /home/partimag\""
    ocs_prerun2_mount="mount -t 9p -o trans=virtio,version=9p2000.L hostshare /home/partimag"
    # For NVMe, the QEMU machine needs to be explicitly specified for 9p to work reliably on some systems
    if [[ "$DISK_DRIVER" == "nvme" ]]; then
        QEMU_MACHINE_ARGS+=("-machine" "q35") # Ensure q35 is used for NVMe and 9p
    fi
    APPEND_ARGS+=" ocs_prerun2=\"${ocs_prerun2_mount}\""
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
    "$QEMU_BINARY"
    "-m" "2048"
    "-smp" "2"
    "-nographic"
)
if [ ${#QEMU_MACHINE_ARGS[@]} -gt 0 ]; then
    QEMU_ARGS+=("${QEMU_MACHINE_ARGS[@]}")
fi
QEMU_ARGS+=(
    "-kernel" "$KERNEL_PATH"
    "-initrd" "$INITRD_PATH"
)

# Conditionally add -enable-kvm if available AND the architecture is compatible.
if check_kvm_available; then
    HOST_ARCH=$(uname -m)
    KVM_SUPPORTED=false
    if [[ "$ARCH" == "amd64" && "$HOST_ARCH" == "x86_64" ]]; then
        KVM_SUPPORTED=true
        QEMU_ARGS+=("-enable-kvm")
    elif [[ "$ARCH" == "arm64" && "$HOST_ARCH" == "aarch64" ]]; then
        KVM_SUPPORTED=true
        QEMU_ARGS+=("-enable-kvm" "-cpu" "host")
    fi

    if [[ "$KVM_SUPPORTED" == "false" ]]; then
        echo "INFO: KVM is available on this host, but not for the target architecture '$ARCH'. Running in emulation mode."
        if [[ "$ARCH" == "arm64" ]]; then
            QEMU_ARGS+=("-cpu" "cortex-a57")
        fi
    fi
else
    # No KVM available at all.
    # For arm64 emulation, a CPU must be specified.
    if [[ "$ARCH" == "arm64" ]]; then
        QEMU_ARGS+=("-cpu" "cortex-a57")
    fi
fi
QEMU_ARGS+=( "${QEMU_DISK_ARGS_ARRAY[@]}" )
# Append any extra user-defined QEMU arguments
if [ ${#EXTRA_QEMU_ARGS[@]} -gt 0 ]; then
    QEMU_ARGS+=( "${EXTRA_QEMU_ARGS[@]}" )
fi

# Networking
NETDEV_ARGS="user,id=net0"
if [ "$SSH_FORWARD_ENABLED" -eq 1 ]; then
    NETDEV_ARGS+=",hostfwd=tcp::2222-:22"
    echo "INFO: SSH port forwarding enabled (host 2222 -> guest 22)."
else
    echo "INFO: SSH port forwarding disabled."
fi

QEMU_ARGS+=(
    "-device" "virtio-net-pci,netdev=net0"
    "-netdev" "$NETDEV_ARGS"
    "-fsdev" "local,id=hostshare,path=$PARTIMAG_PATH,security_model=mapped-xattr"
    "-device" "virtio-9p-pci,fsdev=hostshare,mount_tag=hostshare,bus=${PCI_BUS_NAME}"
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
