#!/bin/bash
# ----------------------------------------------------------------------
# QEMU Clonezilla Boot Script
#
# Function: Use QEMU to boot a Clonezilla Live ISO for manual backup 
#           or restoration tasks. If no ISO is specified, it will
#           attempt to download the latest stable AMD64 version.
# ----------------------------------------------------------------------

#!/bin/bash
# ----------------------------------------------------------------------
# QEMU Clonezilla Boot Script
#
# Function: Use QEMU to boot a Clonezilla Live ISO or ZIP for interactive use.
#           If no media is specified, it will automatically download the
#           latest version for the specified architecture and type.
# ----------------------------------------------------------------------

# --- Prerequisites Check ---
command -v curl >/dev/null 2>&1 || { echo >&2 "ERROR: 'curl' is required for auto-downloading. Please install it."; exit 1; }

# --- Default values ---
ISO_PATH=""
DISK_IMAGE="" # Optional
PARTIMAG_PATH="partimag"
ARCH="amd64"
TYPE="stable"
CLONEZILLA_ZIP=""
ZIP_OUTPUT_DIR="zip"
ZIP_IMAGE_SIZE="2G"
ZIP_FORCE=0

# --- Helper Functions ---

# Function to display usage information
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This script boots a QEMU VM from Clonezilla media for interactive use."
    echo "You can boot from an ISO or a ZIP file. If neither is provided, it will"
    echo "attempt to download the latest Clonezilla ZIP for the specified architecture and type."
    echo ""
    echo "Boot Media Options (choose one):"
    echo "  --iso <path>          Path to the Clonezilla Live ISO file."
    echo "  --zip <path>          Path to the Clonezilla live ZIP file."
    echo ""
    echo "VM and Other Options:"
    echo "  --disk <path>         Path to a QCOW2 disk image to attach (optional)."
    echo "  --partimag <path>     Path to the shared directory for Clonezilla images. (Default: $PARTIMAG_PATH)"
    echo "  --arch <arch>         Target architecture (amd64, arm64, riscv64). Default: amd64."
    echo "  --type <type>         Release type for auto-download (stable, testing, etc.). Default: stable."
    echo "  -h, --help            Display this help message and exit."
    echo ""
    echo "Zip Extraction Options (used with --zip or auto-download):"
    echo "  --zip-output <dir>    Directory to store extracted files. (Default: $ZIP_OUTPUT_DIR)"
    echo "  --zip-size <size>     Size of the live QCOW2 image to create. (Default: $ZIP_IMAGE_SIZE)"
    echo "  --zip-force           Force re-extraction of the ZIP file."
    echo ""
    echo "Examples:"
    echo "  # Boot with auto-downloaded Clonezilla ZIP and attach a disk"
    echo "  $0 --disk ./qemu/my-disk.qcow2"
    echo ""
    echo "  # Boot with auto-downloaded 'testing' amd64 version"
    echo "  $0 --arch amd64 --type testing"
    echo ""
    echo "  # Boot from a specific ISO without any extra disk"
    echo "  $0 --iso ./isos/my-clonezilla.iso"
    echo ""
    echo "  # Boot from a specific ZIP"
    echo "  $0 --zip ./zip/my-clonezilla.zip"
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        --type) TYPE="$2"; shift 2 ;;
        --iso) ISO_PATH="$2"; shift 2 ;;
        --zip) CLONEZILLA_ZIP="$2"; shift 2 ;;
        --zip-output) ZIP_OUTPUT_DIR="$2"; shift 2 ;;
        --zip-size) ZIP_IMAGE_SIZE="$2"; shift 2 ;;
        --zip-force) ZIP_FORCE=1; shift 1 ;;
        --disk) DISK_IMAGE="$2"; shift 2 ;;
        --partimag) PARTIMAG_PATH="$2"; shift 2 ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; print_usage; exit 1 ;;
    esac
done

# --- Main Logic and Validation ---

if [[ -n "$ISO_PATH" && -n "$CLONEZILLA_ZIP" ]]; then
    echo "ERROR: --iso and --zip cannot be used together. Please choose one." >&2
    exit 1
fi

# If no boot media was provided, trigger the download
if [[ -z "$ISO_PATH" && -z "$CLONEZILLA_ZIP" ]]; then
    echo "INFO: No boot media specified. Attempting to auto-download."
    
    DOWNLOAD_SCRIPT="./download-clonezilla.sh"
    if [ ! -x "$DOWNLOAD_SCRIPT" ]; then
        echo "ERROR: Download helper script not found or not executable: $DOWNLOAD_SCRIPT" >&2
        exit 1
    fi
    
    echo "INFO: Calling download script with arch='$ARCH', type='$TYPE'..."
    # Run the download script, capturing the output path.
    DOWNLOADED_ZIP_PATH=$("$DOWNLOAD_SCRIPT" --arch "$ARCH" --type "$TYPE" -o "$ZIP_OUTPUT_DIR")
    
    if [ $? -ne 0 ] || [ -z "$DOWNLOADED_ZIP_PATH" ] || [ ! -f "$DOWNLOADED_ZIP_PATH" ]; then
        echo "ERROR: Failed to auto-download Clonezilla zip using $DOWNLOAD_SCRIPT." >&2
        exit 1
    fi
    
    CLONEZILLA_ZIP="$DOWNLOADED_ZIP_PATH"
    echo "INFO: Auto-download complete. Using ZIP: $CLONEZILLA_ZIP"
fi

# --- Automatic ZIP Extraction ---
if [ -n "$CLONEZILLA_ZIP" ]; then
    CONVERSION_SCRIPT="./clonezilla-zip2qcow.sh"
    if [ ! -x "$CONVERSION_SCRIPT" ]; then
        echo "Error: Conversion script not found or not executable: $CONVERSION_SCRIPT" >&2
        exit 1
    fi

    echo "--- Preparing boot media from ZIP ---"
    ZIP_BASENAME=$(basename "$CLONEZILLA_ZIP" .zip)
    OUTPUT_SUBDIR="$ZIP_OUTPUT_DIR/$ZIP_BASENAME"
    
    LIVE_DISK="$OUTPUT_SUBDIR/$ZIP_BASENAME.qcow2"
    KERNEL_PATH="$OUTPUT_SUBDIR/${ZIP_BASENAME}-vmlinuz"
    INITRD_PATH="$OUTPUT_SUBDIR/${ZIP_BASENAME}-initrd.img"

    if [ "$ZIP_FORCE" -eq 1 ] || [ ! -f "$LIVE_DISK" ] || [ ! -f "$KERNEL_PATH" ] || [ ! -f "$INITRD_PATH" ]; then
        echo "Extracting Clonezilla ZIP. This may take a moment..."
        CONVERT_CMD=("$CONVERSION_SCRIPT" --zip "$CLONEZILLA_ZIP" --output "$ZIP_OUTPUT_DIR" --size "$ZIP_IMAGE_SIZE" --arch "$ARCH")
        if [ "$ZIP_FORCE" -eq 1 ]; then CONVERT_CMD+=("--force"); fi
        
        if ! "${CONVERT_CMD[@]}"; then
            echo "Error: Failed to process Clonezilla ZIP file." >&2
            exit 1
        fi
    else
        echo "Required boot files already exist. Skipping extraction."
    fi
    echo "-----------------------------------"
fi

# --- Argument Validation ---
if [ -n "$ISO_PATH" ] && [ ! -f "$ISO_PATH" ]; then
    echo "ERROR: ISO file not found: $ISO_PATH" >&2; exit 1;
fi
if [ -n "$CLONEZILLA_ZIP" ] && [ ! -f "$CLONEZILLA_ZIP" ]; then
    echo "ERROR: ZIP file not found: $CLONEZILLA_ZIP" >&2; exit 1;
fi
if [ -n "$DISK_IMAGE" ] && [ ! -f "$DISK_IMAGE" ]; then
    echo "ERROR: Disk image not found: $DISK_IMAGE" >&2; exit 1;
fi
if [ ! -d "$PARTIMAG_PATH" ]; then
    echo "ERROR: The partimag directory does not exist: $PARTIMAG_PATH" >&2; exit 1;
fi

# --- QEMU Execution ---
echo "--- Starting QEMU with Clonezilla ---"

# Set QEMU binary and machine type based on architecture
case "$ARCH" in
    "amd64") QEMU_BINARY="qemu-system-x86_64"; QEMU_MACHINE_ARGS=() ;;
    "arm64") QEMU_BINARY="qemu-system-aarch64"; QEMU_MACHINE_ARGS=("-machine" "virt" "-bios" "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd") ;;
    "riscv64") QEMU_BINARY="qemu-system-riscv64"; QEMU_MACHINE_ARGS=("-machine" "virt") ;;
    *) echo "Error: Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

if ! command -v "$QEMU_BINARY" &> /dev/null; then
    echo "Error: QEMU binary not found for '$ARCH': $QEMU_BINARY" >&2; exit 1;
fi

QEMU_ARGS=("$QEMU_BINARY" "-m" "4096" "-smp" "2")

# --- Add boot media ---
if [ -n "$CLONEZILLA_ZIP" ]; then
    echo "Booting from ZIP..."

    # Set console based on architecture for ZIP boot
    CONSOLE_ARG="console=ttyS0,38400n81"
    if [ "$ARCH" = "arm64" ]; then
        CONSOLE_ARG="console=ttyAMA0,38400n8"
    fi
    
    # Construct append arguments
    APPEND_ARGS="boot=live config union=overlay noswap nomodeset noninteractive locales=en_US.UTF-8 keyboard-layouts=us live-getty ${CONSOLE_ARG} live-media=/dev/vda1 live-media-path=/live toram ocs_prerun1=\"mkdir -p /home/partimag\" ocs_prerun2=\"mount -t 9p -o trans=virtio,version=9p2000.L hostshare /home/partimag\" noeject noprompt"

    # Booting from extracted kernel, initrd and live media qcow2
    QEMU_ARGS+=(
        "-kernel" "$KERNEL_PATH"
        "-initrd" "$INITRD_PATH"
        "-drive" "id=livemedia,file=$LIVE_DISK,format=qcow2,if=virtio"
        "-append" "$APPEND_ARGS"
    )
elif [ -n "$ISO_PATH" ]; then
    echo "Booting from ISO..."
    QEMU_ARGS+=("-cdrom" "$ISO_PATH" "-boot" "d")
fi

# --- Conditionally add user disk ---
if [ -n "$DISK_IMAGE" ]; then
    echo "Attaching disk: $DISK_IMAGE"
    # Attach user disk as the next available virtio device
    if [ -n "$CLONEZILLA_ZIP" ]; then
        QEMU_ARGS+=("-drive" "id=userdisk,file=$DISK_IMAGE,format=qcow2,if=virtio") # vdb
    else
        QEMU_ARGS+=("-drive" "id=userdisk,file=$DISK_IMAGE,format=qcow2,if=virtio") # vda
    fi
fi

# --- Add common devices ---
QEMU_ARGS+=(
    "-fsdev" "local,id=hostshare,path=$PARTIMAG_PATH,security_model=mapped-xattr"
    "-device" "virtio-9p-pci,fsdev=hostshare,mount_tag=hostshare"
    "-nic" "user,hostfwd=tcp::2222-:22"
)

if [ ${#QEMU_MACHINE_ARGS[@]} -gt 0 ]; then
    QEMU_ARGS+=("${QEMU_MACHINE_ARGS[@]}")
fi

# --- Set QEMU display and serial arguments based on architecture ---
if [[ "$ARCH" == "amd64" ]]; then
    QEMU_ARGS+=("-display" "gtk")
    QEMU_ARGS+=("-serial" "mon:stdio") # Keep serial for GUI modes
else
    # For arm64/riscv64, prefer nographic console output
    QEMU_ARGS+=("-nographic")
    # -nographic usually implies serial to stdio, so no need for -serial mon:stdio explicitly
fi

# --- KVM acceleration ---
if [ -e "/dev/kvm" ] && [ "$(groups | grep -c kvm)" -gt 0 ]; then
    HOST_ARCH=$(uname -m)
    if [[ "$ARCH" == "amd64" && "$HOST_ARCH" == "x86_64" ]] || [[ "$ARCH" == "arm64" && "$HOST_ARCH" == "aarch64" ]]; then
        QEMU_ARGS+=("-enable-kvm" "-cpu" "host")
    else
        echo "INFO: KVM available but not for target arch '$ARCH'. Emulating."
        if [[ "$ARCH" == "arm64" ]]; then QEMU_ARGS+=("-cpu" "cortex-a57"); fi
    fi
else
    if [[ "$ARCH" == "arm64" ]]; then QEMU_ARGS+=("-cpu" "cortex-a57"); fi
fi

echo "--- Executing QEMU ---"
echo "Command: ${QEMU_ARGS[*]}"
"${QEMU_ARGS[@]}"

