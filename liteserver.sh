#!/bin/bash

set -eou pipefail

# Default values
ZIP_FILE="" # For backward compatibility with --zip
SERVER_ZIP_FILE=""
CLIENT_ZIP_FILE=""
SERVER_DISKS=()
CMD=""
CMDPATH=""
KEEP_TEMP=false
LOG_DIR="logs"
PARTIMAG_DIR="partimag"
ARCH="amd64" # Default architecture

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
    --serverzip path/to/server-clonezilla.zip \
    --clientzip path/to/client-clonezilla.zip \
    --disk /path/to/disk1.qcow2 \
    --cmd "ocs-live-feed-img ... restoredisk my-image vda" \
    --arch arm64

Required Options:
  --zip <path>              (Deprecated) Path to the Clonezilla Live ZIP file for both server and client.
                            If used, --serverzip and --clientzip will be ignored unless explicitly set after --zip.
  --serverzip <path>        Path to the Clonezilla Live ZIP file for the server.
  --clientzip <path>        Path to the Clonezilla Live ZIP file for the client.
                            (If only --serverzip or --clientzip is provided, the other will default to it)
  --disk <path>             Path to a disk for the SERVER. Can be specified multiple times.
                            A corresponding empty disk of the same size will be created for the CLIENT.
  And one of the following:
  --cmd <command>           Command string for the SERVER to execute inside Clonezilla.
  --cmdpath <path>          Path to a script file for the SERVER to execute.

Optional Options:
  --arch <arch>             Target architecture (amd64, arm64, riscv64). Default: amd64.
  --no-ssh-forward      Disable SSH port forwarding in QEMU (for parallel CI runs).
  --keep-temp               Keep temporary files (e.g., restored client disks) on failure or completion.
  -h, --help                Display this help message and exit.

EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --zip)
            ZIP_FILE="$2" # For backward compatibility
            SERVER_ZIP_FILE="$2"
            CLIENT_ZIP_FILE="$2"
            shift 2
            ;;
        --serverzip)
            SERVER_ZIP_FILE="$2"
            shift 2
            ;;
        --clientzip)
            CLIENT_ZIP_FILE="$2"
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
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --no-ssh-forward)
            # Accept and ignore, as internal calls already use this flag.
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
if [[ -z "$SERVER_ZIP_FILE" ]] && [[ -z "$CLIENT_ZIP_FILE" ]]; then
    error "Either --zip, or --serverzip, or --clientzip is required."
fi

# If only one of serverzip/clientzip is set, default the other to it
if [[ -z "$SERVER_ZIP_FILE" ]] && [[ -n "$CLIENT_ZIP_FILE" ]]; then
    SERVER_ZIP_FILE="$CLIENT_ZIP_FILE"
    info "No --serverzip specified, defaulting to --clientzip: $SERVER_ZIP_FILE"
elif [[ -n "$SERVER_ZIP_FILE" ]] && [[ -z "$CLIENT_ZIP_FILE" ]]; then
    CLIENT_ZIP_FILE="$SERVER_ZIP_FILE"
    info "No --clientzip specified, defaulting to --serverzip: $CLIENT_ZIP_FILE"
fi

# Validate actual zip files
if [[ ! -f "$SERVER_ZIP_FILE" ]]; then
    error "Server ZIP file not found: $SERVER_ZIP_FILE"
fi
if [[ ! -f "$CLIENT_ZIP_FILE" ]]; then
    error "Client ZIP file not found: $CLIENT_ZIP_FILE"
fi

if [[ ${#SERVER_DISKS[@]} -eq 0 ]]; then
    error "Missing required argument: at least one --disk."
fi

if [[ -n "$CMD" ]] && [[ -n "$CMDPATH" ]]; then
    error "Conflicting arguments. --cmd and --cmdpath cannot be used together."
fi

if [[ -z "$CMD" ]] && [[ -z "$CMDPATH" ]]; then
    error "Missing required argument: either --cmd or --cmdpath."
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
    TMP_DIR=$(mktemp -d -p "$PWD" "cci_liteserver_XXXXXX")
    info "Temporary directory created at: $TMP_DIR"

    # Process Server ZIP
    SERVER_CZ_ZIP_BASENAME=$(basename "$SERVER_ZIP_FILE" .zip)
    SERVER_CZ_OUTPUT_DIR="$TMP_DIR/server_cz_live"
    mkdir -p "$SERVER_CZ_OUTPUT_DIR"
    info "Preparing server Clonezilla Live Media from $SERVER_ZIP_FILE..."
    ./clonezilla-zip2qcow.sh --zip "$SERVER_ZIP_FILE" -o "$SERVER_CZ_OUTPUT_DIR" --force --arch "$ARCH"

    # The zip2qcow script creates a subdirectory named after the zip file.
    SERVER_CZ_LIVE_DIR="$SERVER_CZ_OUTPUT_DIR/$SERVER_CZ_ZIP_BASENAME"

    SERVER_CZ_LIVE_QCOW="$SERVER_CZ_LIVE_DIR/${SERVER_CZ_ZIP_BASENAME}.qcow2"
    SERVER_CZ_KERNEL="$SERVER_CZ_LIVE_DIR/${SERVER_CZ_ZIP_BASENAME}-vmlinuz"
    SERVER_CZ_INITRD="$SERVER_CZ_LIVE_DIR/${SERVER_CZ_ZIP_BASENAME}-initrd.img"
    
    if [ ! -f "$SERVER_CZ_LIVE_QCOW" ] || [ ! -f "$SERVER_CZ_KERNEL" ] || [ ! -f "$SERVER_CZ_INITRD" ]; then
        error "Failed to prepare server Clonezilla live media from $SERVER_ZIP_FILE."
    fi
    info "Server Clonezilla Live Media ready."

    # Process Client ZIP
    CLIENT_CZ_ZIP_BASENAME=$(basename "$CLIENT_ZIP_FILE" .zip)
    CLIENT_CZ_OUTPUT_DIR="$TMP_DIR/client_cz_live"
    mkdir -p "$CLIENT_CZ_OUTPUT_DIR"
    info "Preparing client Clonezilla Live Media from $CLIENT_ZIP_FILE..."
    ./clonezilla-zip2qcow.sh --zip "$CLIENT_ZIP_FILE" -o "$CLIENT_CZ_OUTPUT_DIR" --force --arch "$ARCH"

    # The zip2qcow script creates a subdirectory named after the zip file.
    CLIENT_CZ_LIVE_DIR="$CLIENT_CZ_OUTPUT_DIR/$CLIENT_CZ_ZIP_BASENAME"

    CLIENT_CZ_LIVE_QCOW="$CLIENT_CZ_LIVE_DIR/${CLIENT_CZ_ZIP_BASENAME}.qcow2"
    CLIENT_CZ_KERNEL="$CLIENT_CZ_LIVE_DIR/${CLIENT_CZ_ZIP_BASENAME}-vmlinuz"
    CLIENT_CZ_INITRD="$CLIENT_CZ_LIVE_DIR/${CLIENT_CZ_ZIP_BASENAME}-initrd.img"

    if [ ! -f "$CLIENT_CZ_LIVE_QCOW" ] || [ ! -f "$CLIENT_CZ_KERNEL" ] || [ ! -f "$CLIENT_CZ_INITRD" ]; then
        error "Failed to prepare client Clonezilla live media from $CLIENT_ZIP_FILE."
    fi
    info "Client Clonezilla Live Media ready."

    CLIENT_DISKS=()
    TEMP_SERVER_DISKS=()
    for i in "${!SERVER_DISKS[@]}"; do
        original_server_disk="${SERVER_DISKS[$i]}"
        
        # Create a temporary, writable copy of the server disk to avoid modifying the original
        temp_server_disk_name="temp-$(basename "$original_server_disk")"
        temp_server_disk_path="$TMP_DIR/$temp_server_disk_name"
        info "Creating temporary copy of server disk at: $temp_server_disk_path"
        # Create a temporary, writable COW disk from the original server disk
        # Use realpath to ensure the backing file path is absolute for qemu-img
        local ABS_ORIGINAL_SERVER_DISK
        ABS_ORIGINAL_SERVER_DISK=$(realpath "$original_server_disk")
        qemu-img create -f qcow2 -F qcow2 -b "$ABS_ORIGINAL_SERVER_DISK" "$temp_server_disk_path" > /dev/null
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
        "--live" "$SERVER_CZ_LIVE_QCOW"
        "--kernel" "$SERVER_CZ_KERNEL"
        "--initrd" "$SERVER_CZ_INITRD"
        "--image" "$PARTIMAG_DIR"
        "--no-ssh-forward"
        "--arch" "$ARCH"
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
    sleep 60

    # Prepare client command args
    CLIENT_QEMU_RUN_ARGS=(
        "--live" "$CLIENT_CZ_LIVE_QCOW"
        "--kernel" "$CLIENT_CZ_KERNEL"
        "--initrd" "$CLIENT_CZ_INITRD"
        "--image" "$PARTIMAG_DIR"
        "--no-ssh-forward"
        "--cmd" "dhclient ens5; ocs-live-get-img 192.168.0.1"
        "--arch" "$ARCH"
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

