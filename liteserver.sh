#!/bin/bash

set -eou pipefail

# Default values
ZIP_FILE=""
SERVER_DISKS=()
CMD=""
CMDPATH=""
KEEP_TEMP=false
LOG_DIR="logs"
PARTIMAG_DIR="partimag"

# --- Helper Functions ---
info() {
    echo "$(date +'%T') [INFO] - $*"
}

error() {
    echo "$(date +'%T') [ERROR] - $*" >&2
    exit 1
}

# --- Usage and Argument Parsing ---
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Orchestrates a Clonezilla Lite Server test.
Starts a server VM with specified disks and a custom command, then starts a client
VM to connect to the server.

Example:
  ./liteserver.sh \
    --zip path/to/clonezilla.zip \
    --disk /path/to/disk1.qcow2 \
    --cmd "ocs-live-feed-img ... restoredisk my-image vda"

Required Options:
  --zip <path>              Path to the Clonezilla Live ZIP file for both server and client.
  --disk <path>             Path to a disk for the SERVER. Can be specified multiple times.
                            A corresponding empty disk of the same size will be created for the CLIENT.
  And one of the following:
  --cmd <command>           Command string for the SERVER to execute inside Clonezilla.
  --cmdpath <path>          Path to a script file for the SERVER to execute.

Optional Options:
  --keep-temp               Keep temporary files (e.g., restored client disks) on failure or completion.
  -h, --help                Display this help message and exit.

EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --zip)
            ZIP_FILE="$2"
            shift 2
            ;;
        --disk)
            SERVER_DISKS+=("$2")
            shift 2
            ;;
        --cmd)
            CMD="$2"
            shift 2
            ;;
        --cmdpath)
            CMDPATH="$2"
            shift 2
            ;;
        --keep-temp)
            KEEP_TEMP=true
            shift 1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# --- Validate Arguments ---
if [[ -z "$ZIP_FILE" ]] || [[ ${#SERVER_DISKS[@]} -eq 0 ]] || { [[ -z "$CMD" ]] && [[ -z "$CMDPATH" ]]; }; then
    error "Missing required arguments. --zip, at least one --disk, and --cmd or --cmdpath are mandatory."
fi

if [[ -n "$CMD" ]] && [[ -n "$CMDPATH" ]]; then
    error "Conflicting arguments. --cmd and --cmdpath cannot be used together."
fi

if [[ ! -f "$ZIP_FILE" ]]; then
    error "ZIP file not found: $ZIP_FILE"
fi

for disk in "${SERVER_DISKS[@]}"; do
    if [[ ! -f "$disk" ]]; then
        error "Server disk not found: $disk"
    fi
done

# --- Main Execution ---
TMP_DIR=""
RESTORE_DISK=""

cleanup() {
    # Reset trap to avoid recursive calls
    trap - EXIT

    info "--- Running final cleanup ---"

    if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        info "Forcefully terminating leftover server PID $SERVER_PID..."
        kill -9 "$SERVER_PID" 2>/dev/null
    fi

    if [ "$KEEP_TEMP" = true ]; then
        info "KEEP_TEMP is true. Skipping cleanup of temporary files."
        info "Temporary directory: $TMP_DIR"
        return
    fi

    if [ -d "$TMP_DIR" ]; then
        info "Removing temporary directory: $TMP_DIR"
        rm -rf "$TMP_DIR"
    fi
    info "Cleanup complete."
}
trap cleanup EXIT

main() {
    # --- Pre-flight Cleanup ---
    info "--- Pre-flight Cleanup: Checking for leftover server processes ---"
    # Identify QEMU processes that are acting as a listen server for this script
    LEFTOVER_PIDS=$(pgrep -f "qemu-system.*-netdev socket,id=privnet,listen=" || true)
    if [[ -n "$LEFTOVER_PIDS" ]]; then
        info "Found leftover server process(es) with PIDs: $LEFTOVER_PIDS. Terminating..."
        # Forcefully kill the processes to release file locks
        echo "$LEFTOVER_PIDS" | xargs kill -9
        sleep 2 # Brief pause to allow OS to reclaim resources
        info "Termination of leftover processes complete."
    else
        info "No leftover server processes found. Proceeding normally."
    fi

    # --- Phase 0: Preparation ---
    info "--- Phase 0: Preparation ---"
    TMP_DIR=$(mktemp -d -p "$PWD" "liteserver-XXXXXX")
    info "Temporary directory created at: $TMP_DIR"

    CLIENT_DISKS=()
    TEMP_SERVER_DISKS=()
    for i in "${!SERVER_DISKS[@]}"; do
        original_server_disk="${SERVER_DISKS[$i]}"
        
        # Create a temporary, writable COW overlay of the server disk to avoid modifying the original
        temp_server_disk_name="temp-$(basename "$original_server_disk")"
        temp_server_disk_path="$TMP_DIR/$temp_server_disk_name"
        info "Creating temporary COW overlay for server disk at: $temp_server_disk_path"
        qemu-img create -f qcow2 -b "$original_server_disk" -F qcow2 "$temp_server_disk_path"
        TEMP_SERVER_DISKS+=("$temp_server_disk_path")
        
        # Prepare a corresponding empty disk for the client
        client_disk_name="restore-$(basename "$original_server_disk")"
        client_disk_path="$TMP_DIR/$client_disk_name"
        
        info "Preparing client disk for server disk: $original_server_disk"
        
        server_disk_size_bytes=$(qemu-img info "$original_server_disk" | grep 'virtual size' | sed -E 's/.*\((\S+) bytes\).*/\1/')
        if [[ -z "$server_disk_size_bytes" ]]; then
            error "Could not determine size of server disk: $original_server_disk"
        fi

        info "Creating new empty client disk '$client_disk_path' with size $server_disk_size_bytes bytes."
        qemu-img create -f qcow2 "$client_disk_path" "$server_disk_size_bytes"
        CLIENT_DISKS+=("$client_disk_path")
    done

    # --- Phase 1: Start Server and Client ---
    info "--- Phase 1: Start Server and Client VMs ---"
    SERVER_PID=""
    PRIVATE_PORT=$((10000 + (RANDOM % 50000)))
    info "Using private network port: $PRIVATE_PORT"

    trap 'info "Forcefully terminating server PID $SERVER_PID..."; kill -9 $SERVER_PID 2>/dev/null; cleanup' EXIT

    # Prepare server command args
    SERVER_QEMU_RUN_ARGS=(
        "--zip" "$ZIP_FILE"
        "--image" "$PARTIMAG_DIR"
        "--no-ssh-forward"
    )
    for disk in "${TEMP_SERVER_DISKS[@]}"; do
        SERVER_QEMU_RUN_ARGS+=("--disk" "$disk")
    done
    if [[ -n "$CMD" ]]; then
        SERVER_QEMU_RUN_ARGS+=("--cmd" "$CMD")
    elif [[ -n "$CMDPATH" ]]; then
        SERVER_QEMU_RUN_ARGS+=("--cmdpath" "$CMDPATH")
    fi
    SERVER_QEMU_RUN_ARGS+=(
        "--qemu-args" "-netdev socket,id=privnet,listen=:$PRIVATE_PORT -device virtio-net-pci,netdev=privnet"
    )

    # Start Server
    info "Starting Lite Server in the background..."
    ./qemu-clonezilla-ci-run.sh "${SERVER_QEMU_RUN_ARGS[@]}" &
    SERVER_PID=$!
    info "Server started with PID: $SERVER_PID. Waiting for it to boot..."
    sleep 30

    # Prepare client command args
    CLIENT_QEMU_RUN_ARGS=(
        "--zip" "$ZIP_FILE"
        "--image" "$PARTIMAG_DIR"
        "--no-ssh-forward"
        "--cmd" "dhclient ens5; ocs-live-get-img 192.168.0.1"
        "--qemu-args" "-netdev socket,id=privnet,connect=:$PRIVATE_PORT -device virtio-net-pci,netdev=privnet"
    )
    for disk in "${CLIENT_DISKS[@]}"; do
        CLIENT_QEMU_RUN_ARGS+=("--disk" "$disk")
    done
    
    # Start Client
    info "Starting Client to receive the image..."
    ./qemu-clonezilla-ci-run.sh "${CLIENT_QEMU_RUN_ARGS[@]}"
    
    info "Client has finished."
    info "Forcefully terminating server PID $SERVER_PID..."
    kill -9 "$SERVER_PID"
    trap cleanup EXIT
    info "Server/Client phase complete."

    # --- Phase 2: Validate Restored Disk ---
    info "--- Phase 2: Validate Restored Disk ---"
    # TODO: Implement validation for multiple disks.
    info "Validation for multiple restored disks is not yet implemented. Skipping."

    # --- Phase 3: Final Cleanup ---
    info "--- Phase 3: Final Cleanup ---"
    info "Script finished successfully. Cleanup will be handled automatically on exit."

    info "Lite Server test cycle completed successfully!"
}

main "$@"

