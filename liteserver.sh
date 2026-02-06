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
PARTIMAG_DIR="" # Default to empty, will be set in main
IMG_NAME="vda" # Default image name
ARCH="amd64" # Default architecture
VALIDATE_ISO="isos/cidata.iso"
VALIDATE_TIMEOUT=1200
NO_SSH_FORWARD=false
EFI_ENABLED=false
DEBUG_MODE=false

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
  --imgname <name>          Custom image name (default: vda).
  --keep-temp               Keep temporary files (e.g., restored client disks) on failure or completion.
  --validate-iso <path>     Path to the cloud-init ISO for validation (default: isos/cidata.iso).
  --timeout <seconds>       Timeout for the validation process (default: 1200).
  --efi                     Enable EFI boot mode.
  --check-raw-md5 <path>    Path to an MD5 file to verify the last partition's raw data.
  --no-validate             Skip the OS validation phase.
  -h, --help                Display this help message and exit.
EOF
}

CHECK_RAW_MD5=""
NO_VALIDATE=false

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
            NO_SSH_FORWARD=true
            shift 1
            ;;
        --imgname)
            IMG_NAME="$2"
            shift 2
            ;;
        --validate-iso)
            VALIDATE_ISO="$2"
            shift 2
            ;;
        --timeout)
            VALIDATE_TIMEOUT="$2"
            shift 2
            ;;
        --efi)
            EFI_ENABLED=true
            shift 1
            ;;
        --check-raw-md5)
            CHECK_RAW_MD5="$2"
            shift 2
            ;;
        --no-validate)
            NO_VALIDATE=true
            shift 1
            ;;
        --debug)
            DEBUG_MODE=true
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

if [[ ! -f "$VALIDATE_ISO" ]]; then
    error "Validation ISO not found: $VALIDATE_ISO"
fi

# --- Main Execution ---
TMP_DIR=""
RESTORE_DISK=""

cleanup() {
    # Reset trap to avoid recursive calls
    trap - EXIT

    info "--- Running final cleanup ---"

    if [ "$DEBUG_MODE" = false ]; then
        # Function to kill a process and all its descendants
        kill_descendants() {
            local target_pid=$1
            local signal=${2:-TERM}
            if [[ -n "$target_pid" ]] && kill -0 "$target_pid" 2>/dev/null; then
                # Get children recursively
                local children=$(pgrep -P "$target_pid" || true)
                for child in $children; do
                    kill_descendants "$child" "$signal"
                done
                kill -"$signal" "$target_pid" 2>/dev/null
            fi
        }

        if [[ -n "${SERVER_PID:-}" ]]; then
            info "Terminating server process (PID $SERVER_PID) and its descendants..."
            kill_descendants "$SERVER_PID" "TERM"
            sleep 2
            if kill -0 "$SERVER_PID" 2>/dev/null; then
                info "Server still alive, force killing..."
                kill_descendants "$SERVER_PID" "KILL"
            fi
        fi

        if [[ -n "${CLIENT_PID:-}" ]]; then
            info "Terminating client process (PID $CLIENT_PID) and its descendants..."
            kill_descendants "$CLIENT_PID" "TERM"
            sleep 2
            if kill -0 "$CLIENT_PID" 2>/dev/null; then
                info "Client still alive, force killing..."
                kill_descendants "$CLIENT_PID" "KILL"
            fi
        fi

        # Final safety check: kill any other children of this script
        local REMAINING_CHILDREN=$(pgrep -P $$ || true)
        if [[ -n "$REMAINING_CHILDREN" ]]; then
            info "Killing remaining child processes of this script: $REMAINING_CHILDREN"
            kill $REMAINING_CHILDREN 2>/dev/null || true
            sleep 1
            kill -9 $REMAINING_CHILDREN 2>/dev/null || true
        fi
    else
        info "Debug mode is active. Skipping VM termination."
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
    # Iterate over temp directories from potentially failed previous runs
    find . -maxdepth 1 -name 'cci_liteserver_*' -type d 2>/dev/null | while read -r dir; do
        PID_FILE="$dir/liteserver.pid"
        if [[ -f "$PID_FILE" ]]; then
            PID=$(cat "$PID_FILE")
            # Check if a process with that PID is still running.
            # We check the full command line (args) because 'comm' might just show 'bash'.
            if ! ps -p "$PID" -o args= | grep -q "liteserver.sh"; then
                # The script that created this directory is no longer running.
                # This means any QEMU process using this directory is an orphan.
                info "Found orphan temp directory '$dir' from finished process $PID."

                # Find any QEMU process that has the directory name in its command line.
                LEFTOVER_PIDS=$(pgrep -f "qemu-system.*$dir" || true)

                if [[ -n "$LEFTOVER_PIDS" ]]; then
                    info "Found leftover QEMU process(es) for '$dir': $LEFTOVER_PIDS. Terminating..."
                    echo "$LEFTOVER_PIDS" | xargs kill -9
                fi

                info "Removing orphan temp directory '$dir'."
                rm -rf "$dir"
            fi
        fi
    done
    info "Pre-flight cleanup check complete."

    # --- Phase 0: Preparation ---
    info "--- Phase 0: Preparation ---"
    TMP_DIR=$(mktemp -d -p "$PWD" "cci_liteserver_XXXXXX")
    echo $$ > "$TMP_DIR/liteserver.pid"
    info "Temporary directory created at: $TMP_DIR"

    # Set PARTIMAG_DIR if not provided
    if [[ -z "$PARTIMAG_DIR" ]]; then
        PARTIMAG_DIR="$TMP_DIR/partimag"
        mkdir -p "$PARTIMAG_DIR"
        info "No --image specified. Using isolated directory: $PARTIMAG_DIR"
    fi

    # Export IMG_NAME for scripts
    export OCS_IMG_NAME="$IMG_NAME"
    info "Using image name: $IMG_NAME"

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
    CLIENT_PID=""
    PRIVATE_PORT=$((10000 + (RANDOM % 50000)))
    info "Using private network port: $PRIVATE_PORT"

    if [ "$DEBUG_MODE" = true ]; then
        info "--- Running in DEBUG MODE ---"
        local SERVER_SSH_PORT=2222
        local CLIENT_SSH_PORT=2223

        # Prepare server command args for debug
        SERVER_QEMU_RUN_ARGS=(
            "--live" "$SERVER_CZ_LIVE_QCOW"
            "--kernel" "$SERVER_CZ_KERNEL"
            "--initrd" "$SERVER_CZ_INITRD"
            "--image" "$PARTIMAG_DIR"
            "--arch" "$ARCH"
            "--ssh-port" "$SERVER_SSH_PORT"
            "--interactive"
            "--cmd" "bash"
        )
        for disk in "${TEMP_SERVER_DISKS[@]}"; do
            SERVER_QEMU_RUN_ARGS+=("--disk" "$disk")
        done
        SERVER_QEMU_RUN_ARGS+=(
            "--qemu-args" "-netdev socket,id=privnet,listen=127.0.0.1:$PRIVATE_PORT -device virtio-net-pci,netdev=privnet"
        )

        # Start Server in debug mode
        info "Starting Lite Server in DEBUG mode..."
        ./qemu-clonezilla-ci-run.sh "${SERVER_QEMU_RUN_ARGS[@]}" &
        SERVER_PID=$!
        info "Server started with PID: $SERVER_PID"

        # Prepare client command args for debug
        CLIENT_QEMU_RUN_ARGS=(
            "--live" "$CLIENT_CZ_LIVE_QCOW"
            "--kernel" "$CLIENT_CZ_KERNEL"
            "--initrd" "$CLIENT_CZ_INITRD"
            "--image" "$PARTIMAG_DIR"
            "--arch" "$ARCH"
            "--ssh-port" "$CLIENT_SSH_PORT"
            "--interactive"
            "--cmd" "bash"
            "--qemu-args" "-netdev socket,id=privnet,connect=127.0.0.1:$PRIVATE_PORT -device virtio-net-pci,netdev=privnet"
        )
        for disk in "${CLIENT_DISKS[@]}"; do
            CLIENT_QEMU_RUN_ARGS+=("--disk" "$disk")
        done
        
        # Start Client in debug mode
        info "Starting Client in DEBUG mode..."
        ./qemu-clonezilla-ci-run.sh "${CLIENT_QEMU_RUN_ARGS[@]}" &
        CLIENT_PID=$!
        info "Client started with PID: $CLIENT_PID"

        info "------------------------------------------------------------"
        info "               VMs are running in DEBUG MODE"
        info "------------------------------------------------------------"
        info "SSH into SERVER: ssh -p $SERVER_SSH_PORT user@localhost"
        info "SSH into CLIENT: ssh -p $CLIENT_SSH_PORT user@localhost"
        info "Temporary directory with disks: $TMP_DIR"
        info "Press Ctrl+C to terminate this script and the VMs."
        info "------------------------------------------------------------"
        
        # Wait for user to Ctrl+C
        wait
    else
        # The main cleanup trap, defined at the top of the script, is sufficient.

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
            "--qemu-args" "-netdev socket,id=privnet,listen=127.0.0.1:$PRIVATE_PORT -device virtio-net-pci,netdev=privnet"
        )

        # Start Server
        info "Starting Lite Server in the background..."
        ./qemu-clonezilla-ci-run.sh "${SERVER_QEMU_RUN_ARGS[@]}" &
        SERVER_PID=$!
        info "Server started with PID: $SERVER_PID. Waiting for it to boot..."
        info "sleep 60 seconds to wait for server to boot..."
        sleep 60

        # Prepare client command args
        CLIENT_QEMU_RUN_ARGS=(
            "--live" "$CLIENT_CZ_LIVE_QCOW"
            "--kernel" "$CLIENT_CZ_KERNEL"
            "--initrd" "$CLIENT_CZ_INITRD"
            "--image" "$PARTIMAG_DIR"
            "--no-ssh-forward"
            "--cmdpath" "dev/ocscmd/lite-client.sh"
            "--arch" "$ARCH"
            "--qemu-args" "-netdev socket,id=privnet,connect=127.0.0.1:$PRIVATE_PORT -device virtio-net-pci,netdev=privnet"
        )
        
        # Pass OCS_IMG_NAME to the client via environment variable in the script command
        if [ -n "${OCS_IMG_NAME:-}" ]; then
            # We override the default bash command constructed by qemu-clonezilla-ci-run.sh
            # to include the environment variable.
            # qemu-clonezilla-ci-run.sh will mount the script at /home/partimag/cmd_scripts/lite-client.sh
            local CLIENT_CMD="export OCS_IMG_NAME=$OCS_IMG_NAME; bash /home/partimag/cmd_scripts/lite-client.sh"
            CLIENT_QEMU_RUN_ARGS+=(
                "--cmd" "$CLIENT_CMD"
            )
            # Since we are using --cmd, qemu-clonezilla-ci-run.sh won't copy the script.
            # We must do it manually here.
            mkdir -p "$PARTIMAG_DIR/cmd_scripts"
            cp "dev/ocscmd/lite-client.sh" "$PARTIMAG_DIR/cmd_scripts/"

            # Remove --cmdpath as we are using --cmd now
            local NEW_CLIENT_ARGS=()
            local SKIP_NEXT=false
            for arg in "${CLIENT_QEMU_RUN_ARGS[@]}"; do
                if [ "$SKIP_NEXT" = true ]; then
                    SKIP_NEXT=false
                    continue
                fi
                if [[ "$arg" == "--cmdpath" ]]; then
                    SKIP_NEXT=true
                    continue
                fi
                NEW_CLIENT_ARGS+=("$arg")
            done
            CLIENT_QEMU_RUN_ARGS=("${NEW_CLIENT_ARGS[@]}")
        fi
        for disk in "${CLIENT_DISKS[@]}"; do
            CLIENT_QEMU_RUN_ARGS+=("--disk" "$disk")
        done
        
        # Start Client
        info "Starting Client to receive the image..."
        ./qemu-clonezilla-ci-run.sh "${CLIENT_QEMU_RUN_ARGS[@]}"
        
        info "Client has finished."
        # The cleanup trap, triggered on script exit, will handle terminating the server.
        info "Server/Client phase complete."

        # --- Phase 2: Validate Restored Disk ---
        info "--- Phase 2: Validate Restored Disk ---"
        for disk in "${CLIENT_DISKS[@]}"; do
            if [[ -n "$CHECK_RAW_MD5" ]]; then
                info "Verifying raw data integrity for disk: $disk"
                if [[ ! -f "${CHECK_RAW_MD5}" ]]; then
                    error "MD5 file not found: ${CHECK_RAW_MD5}"
                fi
                #EXPECTED_MD5=$(cat "${CHECK_RAW_MD5}")
                ./dev/verify-raw-data.sh "$disk" "${CHECK_RAW_MD5}"
                info "Raw data verification passed for $disk."
            fi

            if [ "$NO_VALIDATE" = false ]; then
                info "Validating restored disk: $disk"
                VALIDATE_ARGS=(
                    "--iso" "$VALIDATE_ISO"
                    "--disk" "$disk"
                    "--timeout" "$VALIDATE_TIMEOUT"
                    "--arch" "$ARCH"
                    "--temp-dir" "$TMP_DIR"
                )
                if [ "$NO_SSH_FORWARD" = true ]; then
                    VALIDATE_ARGS+=("--no-ssh-forward")
                fi
                if [ "$EFI_ENABLED" = true ]; then
                    VALIDATE_ARGS+=("--efi")
                fi

                ./validate.sh "${VALIDATE_ARGS[@]}"
            else
                info "Skipping OS validation as requested (--no-validate)."
            fi
        done
        info "Validation phase complete."

        # --- Phase 3: Final Cleanup ---
        info "--- Phase 3: Final Cleanup ---"
        info "Script finished successfully. Cleanup will be handled automatically on exit."

        info "Lite Server test cycle completed successfully!"
    fi
}

main "$@"

