#!/bin/bash
# ----------------------------------------------------------------------
# OS Validation Script
#
# Function: Boots a restored QCOW2 image with a cloud-init ISO to
#           verify that the OS starts and runs a cloud-init script
#           successfully. It runs non-interactively and checks for a
#           success keyword in the output log.
# ----------------------------------------------------------------------

# --- Default values ---
ISO_PATH=""
DISK_IMAGE=""
SUCCESS_KEYWORD="ReStOrE"
DEFAULT_TIMEOUT=1200 # seconds
KEEP_LOG=0          # 0 for false (delete log), 1 for true (keep log)
ARCH="amd64"
SSH_FORWARD_ENABLED=1
QEMU_PID=0
TIMEOUT_PID=0
DISK_DRIVER="virtio-blk"
DEFAULT_LOGICAL_BLOCK_SIZE=""
DEFAULT_PHYSICAL_BLOCK_SIZE=""
EFI_ENABLED=0
TEMP_DIR_PATH=""

# --- Helper Functions ---

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

# Function to display usage information
print_usage() {
    echo "Usage: $0 --iso <CloudInitISO> --disk <QCOW2Image> [OPTIONS]"
    echo ""
    echo "This script validates a QCOW2 disk image by booting it with a"
    echo "cloud-init ISO and checking for a success keyword in the log."
    echo ""
    echo "Required Arguments:"
    echo "  --iso <path>    Path to the cloud-init ISO file (e.g., cidata.iso)."
    echo "  --disk <path>   Path to the QCOW2 disk image to validate."
    echo ""
    echo "Optional Arguments:"
    echo "  --timeout <sec>     Maximum time in seconds to wait for QEMU to finish. (Default: $DEFAULT_TIMEOUT)"
    echo "  --arch <arch>       Target architecture (amd64, arm64, riscv64). Default: amd64."
    echo "  --disk-driver <type>    Disk driver to use: 'virtio-blk' (default) or 'nvme'."
    echo "  --disk-lbas <size>      Logical block size for the disk (e.g., 512, 4096)."
    echo "  --disk-pbas <size>      Physical block size for the disk (e.g., 512, 4096)."
    echo "  --no-ssh-forward  Disable TCP port 2222 forwarding for SSH."
    echo "  --keeplog         Do not delete the log file after execution."
    echo "  -h, --help          Display this help message and exit."
    echo ""
    echo "Example:"
    echo "  $0 --iso isos/cidata.iso --disk ./qemu/restore.qcow2 --timeout 600 --keeplog"
}

# Cleanup function
# This function is called on EXIT. It receives the script's exit code as $1.
cleanup() {
    local exit_code=$1

    # Ensure background processes are killed if they are still running
    if [ -n "$QEMU_PID" ] && ps -p "$QEMU_PID" > /dev/null; then
        echo "--- Script exiting. Killing QEMU process $QEMU_PID ---"
        kill "$QEMU_PID"
    fi
    if [ -n "$TIMEOUT_PID" ] && ps -p "$TIMEOUT_PID" > /dev/null; then
        kill "$TIMEOUT_PID"
    fi

    # Keep the log if --keeplog is used, or if the run failed (exit code != 0)
    if [ "$KEEP_LOG" -eq 1 ]; then
        echo "--- Log file retained: $LOG_FILE (due to --keeplog) ---"
    elif [ "$exit_code" -ne 0 ]; then
        echo "--- Validation failed, log file retained for debugging: $LOG_FILE ---"
    else
        echo "--- Cleaning up temporary log file: $LOG_FILE ---"
        rm -f "$LOG_FILE"
    fi
}


# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --no-ssh-forward)
            SSH_FORWARD_ENABLED=0
            shift 1
            ;;
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --iso)
            ISO_PATH="$2"
            shift 2
            ;; 
        --disk)
            DISK_IMAGE="$2"
            shift 2
            ;; 
        --timeout)
            DEFAULT_TIMEOUT="$2"
            shift 2
            ;; 
        --keeplog)
            KEEP_LOG=1
            shift 1
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
        --efi)
            EFI_ENABLED=1
            shift 1
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
        -h|--help)
            print_usage
            exit 0
            ;; 
        *)
            echo "ERROR: Unknown argument: $1" >&2
            print_usage
            exit 1
            ;; 
    esac
done

# --- Argument Validation ---
if [[ -z "$ISO_PATH" || -z "$DISK_IMAGE" ]]; then
    echo "ERROR: Both --iso and --disk arguments are required." >&2
    exit 1
fi

if [ ! -f "$ISO_PATH" ]; then
    echo "ERROR: ISO file not found: $ISO_PATH" >&2
    exit 1
fi

if [ ! -f "$DISK_IMAGE" ]; then
    echo "ERROR: Disk image not found: $DISK_IMAGE" >&2
    exit 1
fi

# --- Main Logic ---
LOG_FILE="logs/cci_validate_$(basename "$DISK_IMAGE")_$(date +%s).log"

# Use a subshell to pass the exit code to the cleanup function
# The script's main logic is inside this subshell
(
    # The subshell now traps its own exit
    trap 'cleanup $?' EXIT

    echo "--- Starting OS Validation via cloud-init ---"
    echo "Disk Image: $DISK_IMAGE"
    echo "Cloud-init ISO: $ISO_PATH"
    echo "Log File: $LOG_FILE"
    echo "Timeout: ${DEFAULT_TIMEOUT}s"
    echo "---------------------------------------------"

    # Set QEMU binary and machine type based on architecture
    case "$ARCH" in
        "amd64")
            QEMU_BINARY="qemu-system-x86_64"
            QEMU_MACHINE_ARGS=()
            if [ "$EFI_ENABLED" -eq 1 ]; then
                echo "INFO: EFI boot enabled for amd64."
                
                # Determine the base directory for temp files. Use TEMP_DIR_PATH if set, otherwise default to "logs".
                if [ -n "$TEMP_DIR_PATH" ]; then
                    base_temp_dir="$TEMP_DIR_PATH"
                else
                    base_temp_dir="logs"
                fi

                # Create a temporary, writable copy of the OVMF_VARS file for this VM instance.
                OVMF_VARS_TEMPLATE="/usr/share/OVMF/OVMF_VARS_4M.fd"
                OVMF_CODE_FILE="/usr/share/OVMF/OVMF_CODE_4M.fd" # Use standard non-Secure Boot firmware
                TEMP_OVMF_VARS="${base_temp_dir}/temp_ovmf_vars_$(basename "$DISK_IMAGE")_$(date +%s)_$RANDOM.fd"
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
            ;;
        "riscv64")
            QEMU_BINARY="qemu-system-riscv64"
            QEMU_MACHINE_ARGS=("-machine" "virt" "-kernel" "/usr/lib/u-boot/qemu-riscv64_smode/uboot.elf" "-append" "root=LABEL=rootfs console=ttyS0")
            ;;
        *)
            echo "Error: Unsupported architecture: $ARCH" >&2
            exit 1
            ;;
    esac

    # Check if QEMU binary exists
    if ! command -v "$QEMU_BINARY" &> /dev/null; then
        echo "Error: QEMU binary not found for architecture '$ARCH': $QEMU_BINARY" >&2
        echo "Please ensure the QEMU system emulator for '$ARCH' is installed and in your PATH." >&2
        exit 1
    fi
    
    # Build QEMU command arguments
    QEMU_ARGS=(
        "$QEMU_BINARY"
        "-m" "4096"
        "-nographic"
    )

    # Networking
    NETDEV_ARGS="user"
    if [ "$SSH_FORWARD_ENABLED" -eq 1 ]; then
        NETDEV_ARGS+=",hostfwd=tcp::2222-:22"
        echo "INFO: SSH port forwarding enabled (host 2222 -> guest 22)."
    else
        echo "INFO: SSH port forwarding disabled."
    fi
    QEMU_ARGS+=("-nic" "$NETDEV_ARGS")

    # --- Dynamic Disk Configuration ---
    if [[ "$DISK_DRIVER" == "nvme" ]]; then
        # When using NVMe, q35 machine type is preferred for compatibility.
        # This check prevents adding it multiple times if already set for other reasons.
        if [[ ! " ${QEMU_MACHINE_ARGS[@]} " =~ " -machine " ]]; then
            QEMU_MACHINE_ARGS+=("-machine" "q35")
        fi
        
        # For NVMe, block sizes are properties of the device. Serial is also required.
        drive_properties="id=drive0,file=$DISK_IMAGE,format=qcow2,if=none"
        device_properties="drive=drive0,serial=validationsn0"

        if [ -n "$DEFAULT_LOGICAL_BLOCK_SIZE" ]; then
            device_properties+=",logical_block_size=${DEFAULT_LOGICAL_BLOCK_SIZE}"
        fi
        if [ -n "$DEFAULT_PHYSICAL_BLOCK_SIZE" ]; then
            device_properties+=",physical_block_size=${DEFAULT_PHYSICAL_BLOCK_SIZE}"
        fi
        
        QEMU_ARGS+=("-drive" "$drive_properties")
        QEMU_ARGS+=("-device" "nvme,$device_properties")

    else # Default to virtio-blk
        # For virtio-blk, logical_block_size is a drive property. Physical is not supported.
        drive_properties="id=drive0,file=$DISK_IMAGE,format=qcow2,if=none"
        if [ -n "$DEFAULT_LOGICAL_BLOCK_SIZE" ]; then
            drive_properties+=",logical_block_size=${DEFAULT_LOGICAL_BLOCK_SIZE}"
        fi
        
        QEMU_ARGS+=("-drive" "$drive_properties")
        QEMU_ARGS+=("-device" "virtio-blk-pci,drive=drive0")
    fi

    # For riscv64, the CD-ROM must be attached as a virtio-blk device because the
    # standard IDE CD-ROM is not well-supported. For other architectures, -cdrom
    # is sufficient and simpler.
    if [[ "$ARCH" == "riscv64" ]]; then
        QEMU_ARGS+=("-drive" "if=none,id=seed,media=cdrom,file=$ISO_PATH")
        QEMU_ARGS+=("-device" "virtio-blk-device,drive=seed")
    else
        QEMU_ARGS+=("-cdrom" "$ISO_PATH")
    fi

    # For architectures that require it, set the boot order.
    # RISC-V boot is typically handled by the bootloader/kernel, so we don't set -boot.
    if [[ "$ARCH" != "riscv64" ]]; then
        QEMU_ARGS+=("-boot" "c")
    fi

    # Add virtio RNG for non-amd64 architectures for better entropy.
    if [[ "$ARCH" == "riscv64" ]]; then
      QEMU_ARGS+=("-object" "rng-random,filename=/dev/urandom,id=rng")
      QEMU_ARGS+=("-device" "virtio-rng-device,rng=rng")
    fi

    if [ ${#QEMU_MACHINE_ARGS[@]} -gt 0 ]; then
        QEMU_ARGS+=("${QEMU_MACHINE_ARGS[@]}")
    fi

    # KVM and CPU host are not always available/compatible
    if check_kvm_available; then
        HOST_ARCH=$(uname -m)
        KVM_SUPPORTED=false
        if [[ "$ARCH" == "amd64" && "$HOST_ARCH" == "x86_64" ]]; then
            KVM_SUPPORTED=true
            QEMU_ARGS+=("-enable-kvm" "-cpu" "host")
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

    # Run QEMU in the background
    stdbuf -oL "${QEMU_ARGS[@]}" > "$LOG_FILE" 2>&1 &
    QEMU_PID=$!
    echo "QEMU started in background with PID: $QEMU_PID"

    # Start the sleep command as a background watchdog
    sleep "$DEFAULT_TIMEOUT" &
    TIMEOUT_PID=$!

    # Wait for the first of the two PIDs to exit
    wait -n "$QEMU_PID" "$TIMEOUT_PID"
    
    QEMU_EXIT_CODE=0
    
    # Check which process finished
    if ! ps -p "$QEMU_PID" > /dev/null; then
        # QEMU finished first. It either succeeded or failed on its own.
        kill "$TIMEOUT_PID" 2>/dev/null # Kill the watchdog
        wait "$QEMU_PID" # Capture the exit code
        QEMU_EXIT_CODE=$?
        echo "--- QEMU process finished on its own with exit code: $QEMU_EXIT_CODE ---"
    else
        # Sleep finished first, so we have a timeout.
        echo "--- VALIDATION FAILED (Timeout) ---"
        echo "QEMU execution timed out after ${DEFAULT_TIMEOUT} seconds."
        echo "Killing QEMU process $QEMU_PID..."
        kill "$QEMU_PID"
        QEMU_EXIT_CODE=124 # Simulate timeout exit code
    fi

    # --- Keyword Validation ---
    echo "--- Checking for success keyword in log ---"
    if grep -q "$SUCCESS_KEYWORD" "$LOG_FILE"; then
        echo "--- VALIDATION SUCCESSFUL ---"
        echo "Success keyword '$SUCCESS_KEYWORD' found in the log."
        exit 0
    else
        echo "--- VALIDATION FAILED (Keyword Not Found or QEMU error) ---"
        if [ "$QEMU_EXIT_CODE" -eq 124 ]; then
            echo "Reason: Timeout."
        elif [ "$QEMU_EXIT_CODE" -ne 0 ]; then
            echo "Reason: QEMU exited with error code $QEMU_EXIT_CODE."
        else
            echo "Reason: QEMU finished but success keyword was not found."
        fi
        exit 1
    fi
)
