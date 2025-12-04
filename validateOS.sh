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
DEFAULT_TIMEOUT=300 # seconds
KEEP_LOG=0          # 0 for false (delete log), 1 for true (keep log)
QEMU_PID=0
TIMEOUT_PID=0

# --- Helper Functions ---

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
    echo "  --keeplog       Do not delete the log file after execution."
    echo "  -h, --help      Display this help message and exit."
    echo ""
    echo "Example:"
    echo "  $0 --iso dev/cloudinit/cloud_init_config/cidata.iso --disk ./qemu/restore.qcow2 --timeout 600 --keeplog"
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
LOG_FILE="validate_$(basename "$DISK_IMAGE")_$(date +%s).log"

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

    # --- QEMU Execution with Intelligent Timeout ---
    # Run QEMU in the background
    stdbuf -oL qemu-system-x86_64 \
      -enable-kvm \
      -m 4096 \
      -cpu host \
      -drive file="$DISK_IMAGE",if=virtio,format=qcow2 \
      -cdrom "$ISO_PATH" \
      -nographic \
      -boot d \
      -nic user,hostfwd=tcp::2222-:22 > "$LOG_FILE" 2>&1 &
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
