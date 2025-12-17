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
DEFAULT_TIMEOUT=480 # seconds
KEEP_LOG=0          # 0 for false (delete log), 1 for true (keep log)
ARCH="amd64"
QEMU_PID=0
TIMEOUT_PID=0

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
    echo "  --timeout <sec> Maximum time in seconds to wait for QEMU to finish. (Default: $DEFAULT_TIMEOUT)"
    echo "  --arch <arch>   Target architecture (amd64, arm64, riscv64). Default: amd64."
    echo "  --keeplog       Do not delete the log file after execution."
    echo "  -h, --help      Display this help message and exit."
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
LOG_FILE="logs/validate_$(basename "$DISK_IMAGE")_$(date +%s).log"

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
        "-cdrom" "$ISO_PATH"
        "-nographic"
        "-nic" "user,hostfwd=tcp::2222-:22"
    )

    # Use modern virtio-blk-pci for all architectures for consistent /dev/vdX naming.
    QEMU_ARGS+=("-drive" "id=drive0,file=$DISK_IMAGE,format=qcow2,if=none")
    QEMU_ARGS+=("-device" "virtio-blk-pci,drive=drive0")

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
