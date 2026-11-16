#!/usr/bin/env bash
#
# build-ubuntu-zfs-image.sh – Build an Ubuntu Server golden image with root on ZFS
#                             (subiquity autoinstall, no interactive input).
#
# Usage:   ./build-ubuntu-zfs-image.sh [options]
#
# Options:
#   --firmware <mode>   uefi | bios | both (default: both).
#   --arch <arch>       Target architecture. Only amd64 is supported. (default: amd64)
#   --release <ver>     Ubuntu release (default: 24.04, codename noble).
#   --iso <path>        Use this Ubuntu live-server ISO instead of auto-downloading.
#   --output <dir>      Directory for the final image(s) (default: qemu/cloudimages).
#   --name <name>       Custom output base name (no extension); valid only with a
#                       single --firmware value (default: ubuntu-zfs-<release>-<fw>-<arch>).
#   --disk-size <size>  Virtual disk size of the golden image (default: 10G; the
#                       restored test disk grows to 80G via restoredisk -k1).
#   -m, --mem <MB>      VM memory during install (default: 4096).
#   --smp <cores>       VM vCPUs during install (default: 4).
#   --timeout-min <n>   Abort if one install run exceeds this many minutes
#                       (default: 90; KVM typically finishes in ~10).
#   --skip-smoke-test   Do not boot-validate the built image with validate.sh.
#   --keep-workdir      Keep temporary build directories (for debugging).
#   --force             Rebuild even if the target image already exists.
#   -h, --help          Show this help.
#
# Environment:
#   LOG_DIR – Directory for log files (default: ./logs).
#
# Dependencies: qemu-system-x86_64, qemu-img, guestfish, genisoimage, curl,
#               wget, openssl, timeout; ovmf firmware files for the uefi variant
#               (Debian/Ubuntu package: ovmf).
#
# Notes:
#   - Built images land in qemu/cloudimages/ as ubuntu-zfs-<release>-<fw>-<arch>.qcow2
#     where jobs/test_os_ubuntu_zfs.sh discovers them via cloud_images.conf.
#   - The default login is ubuntu / ubuntu (test-only image; change on first use).
#
# Author: Thomas (maintainer)
# SPDX-License-Identifier: GPL-2.0-or-later
#
set -euo pipefail
IFS=$'\n\t'

# --- Check external dependencies ---
REQUIRES=(qemu-system-x86_64 qemu-img genisoimage guestfish curl wget openssl timeout)
for cmd in "${REQUIRES[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "[ERROR] required command '$cmd' is missing." >&2
        exit 127
    }
done

# --- Default values ---
FIRMWARE="both"
ARCH="amd64"
RELEASE="24.04"
RELEASE_CODENAME="noble"
ISO_PATH=""
OUTPUT_DIR="qemu/cloudimages"
CUSTOM_NAME=""
DISK_SIZE="10G"
MEMORY="4096"
SMP="4"
TIMEOUT_MIN="90"
SKIP_SMOKE=0
KEEP_WORKDIR=0
FORCE=0
DOWNLOAD_DIR="isos"
TEMPLATE_DIR="dev/cloudinit/autoinstall-zfs"
LOG_DIR="${LOG_DIR:-./logs}"
OVMF_CODE_FILE="/usr/share/OVMF/OVMF_CODE_4M.fd"
OVMF_VARS_TEMPLATE="/usr/share/OVMF/OVMF_VARS_4M.fd"

WORKDIR=""
FINAL_IMAGE_PATH=""

# --- Helper Functions ---

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
error() { echo "[ERROR] $*" >&2; }

cleanup_workdir() {
    if [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then
        if [[ "$KEEP_WORKDIR" -eq 1 ]]; then
            warn "Keeping work directory: $WORKDIR"
        else
            rm -rf "$WORKDIR"
        fi
    fi
}

on_exit() {
    local rc=$?
    cleanup_workdir
    if [[ $rc -ne 0 && -n "$FINAL_IMAGE_PATH" ]]; then
        error "Build FAILED for $FINAL_IMAGE_PATH (exit code $rc). See logs in $LOG_DIR."
    fi
    exit $rc
}
trap on_exit EXIT

print_usage() {
    sed -n '2,/^set -euo/p' "$0" | sed 's/^# \?//' | head -n -1
}

image_name_for() {
    local fw="$1"
    if [[ -n "$CUSTOM_NAME" ]]; then
        echo "${CUSTOM_NAME}.qcow2"
    else
        echo "ubuntu-zfs-${RELEASE}-${fw}-${ARCH}.qcow2"
    fi
}

# Resolve the Ubuntu live-server ISO: explicit --iso > newest local file > download.
resolve_iso() {
    if [[ -n "$ISO_PATH" ]]; then
        [[ -f "$ISO_PATH" ]] || {
            error "ISO not found: $ISO_PATH"
            exit 1
        }
        return 0
    fi

    local newest_local
    newest_local=$(find "$DOWNLOAD_DIR" -maxdepth 1 -name "ubuntu-${RELEASE}*-live-server-${ARCH}.iso" -print 2>/dev/null | sort -V | tail -n 1 || true)
    if [[ -n "$newest_local" ]]; then
        info "Using existing ISO: $newest_local"
        ISO_PATH="$newest_local"
        return 0
    fi

    info "Downloading latest Ubuntu ${RELEASE} (${RELEASE_CODENAME}) live-server ISO for ${ARCH}..."
    local base_url="https://releases.ubuntu.com/${RELEASE_CODENAME}/"
    local iso_filename
    iso_filename=$(curl -fsSL "$base_url" | grep -oP "href=\"\Kubuntu-${RELEASE//./\\.}[0-9.]*-live-server-${ARCH}\.iso(?=\")" | sort -V | tail -n 1 || true)
    if [[ -z "$iso_filename" ]]; then
        error "Could not determine the latest live-server ISO from ${base_url}. Use --iso manually."
        exit 1
    fi
    mkdir -p "$DOWNLOAD_DIR"
    info "Downloading ${iso_filename} ..."
    wget --show-progress -c -O "${DOWNLOAD_DIR}/${iso_filename}" "${base_url}${iso_filename}" || {
        rm -f "${DOWNLOAD_DIR}/${iso_filename}"
        error "ISO download failed."
        exit 1
    }
    ISO_PATH="${DOWNLOAD_DIR}/${iso_filename}"
}

# Extract the installer kernel/initrd from the ISO (guestfish is already a project dep).
# NOTE: issue one copy-out per guestfish invocation; multiple commands on one
# guestfish line misparse the second command's arguments.
extract_installer_files() {
    info "Extracting casper/vmlinuz and casper/initrd from $ISO_PATH ..."
    guestfish --ro -a "$ISO_PATH" -m /dev/sda copy-out /casper/vmlinuz "$WORKDIR/" </dev/null || {
        error "Failed to extract /casper/vmlinuz from $ISO_PATH"
        exit 1
    }
    guestfish --ro -a "$ISO_PATH" -m /dev/sda copy-out /casper/initrd "$WORKDIR/" </dev/null || {
        error "Failed to extract /casper/initrd from $ISO_PATH"
        exit 1
    }
    [[ -s "$WORKDIR/vmlinuz" && -s "$WORKDIR/initrd" ]] || {
        error "Extracted kernel/initrd missing."
        exit 1
    }
}

# Build the NoCloud seed ISO carrying the autoinstall user-data.
build_seed_iso() {
    local fw="$1"
    local template_user_data="$TEMPLATE_DIR/user-data.${fw}"
    [[ -f "$template_user_data" ]] || {
        error "Template not found: $template_user_data"
        exit 1
    }

    local password_hash
    password_hash=$(openssl passwd -6 "ubuntu")
    sed "s|__USER_PASSWORD_HASH__|${password_hash}|" "$template_user_data" >"$WORKDIR/user-data"
    cp "$TEMPLATE_DIR/meta-data" "$WORKDIR/meta-data"

    info "Creating seed ISO (cidata) for firmware '$fw' ..."
    (cd "$WORKDIR" && genisoimage -output seed.iso -volid cidata -rational-rock -joliet user-data meta-data >/dev/null 2>&1)
    [[ -s "$WORKDIR/seed.iso" ]] || {
        error "seed.iso was not created."
        exit 1
    }
}

run_install() {
    local fw="$1"
    local disk_image="$WORKDIR/disk.qcow2"

    qemu-img create -f qcow2 "$disk_image" "$DISK_SIZE" >/dev/null

    # NOTE: the subiquity initramfs lacks IDE/ATA drivers, so CD-ROMs on the
    # default i440fx IDE bus are never probed ("Unable to find a medium
    # containing a live file system"). Attach both the install ISO and the
    # NoCloud seed as virtio-blk drives; casper / cloud-init find them by
    # filesystem label regardless of the bus.
    local qemu_args=(
        qemu-system-x86_64
        -m "$MEMORY"
        -smp "$SMP"
        -drive "file=${disk_image},format=qcow2,if=virtio"
        -drive "file=${ISO_PATH},format=raw,readonly=on,if=virtio"
        -drive "file=${WORKDIR}/seed.iso,format=raw,readonly=on,if=virtio"
        -kernel "$WORKDIR/vmlinuz"
        -initrd "$WORKDIR/initrd"
        -append "autoinstall --- console=ttyS0,115200n8"
        -nographic
        -no-reboot
        -nic "user,model=virtio-net-pci"
    )

    if [[ "$fw" == "uefi" ]]; then
        [[ -f "$OVMF_CODE_FILE" ]] || {
            error "OVMF CODE not found: $OVMF_CODE_FILE (install 'ovmf')."
            exit 1
        }
        [[ -f "$OVMF_VARS_TEMPLATE" ]] || {
            error "OVMF VARS not found: $OVMF_VARS_TEMPLATE (install 'ovmf')."
            exit 1
        }
        cp "$OVMF_VARS_TEMPLATE" "$WORKDIR/OVMF_VARS.fd"
        qemu_args+=(
            -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE_FILE}"
            -drive "if=pflash,format=raw,file=${WORKDIR}/OVMF_VARS.fd"
        )
    fi

    if [[ -e /dev/kvm && -w /dev/kvm ]]; then
        qemu_args+=(-enable-kvm -cpu host)
        info "KVM enabled for build."
    else
        warn "KVM not available; install runs in TCG emulation and can take a long time (consider --timeout-min 180+)."
    fi

    local install_log="$LOG_DIR/${FINAL_IMAGE_PATH##*/}.install.log"
    info "Starting unattended install for '$FINAL_IMAGE_PATH' (log: $install_log) ..."
    set +e
    timeout -k 30 "${TIMEOUT_MIN}m" "${qemu_args[@]}" 2>&1 | tee "$install_log"
    local rc=${PIPESTATUS[0]}
    set -e

    if [[ $rc -eq 124 ]]; then
        error "Install timed out after ${TIMEOUT_MIN} minutes."
        exit 1
    elif [[ $rc -ne 0 ]]; then
        error "QEMU install exited with code $rc (see $install_log)."
        exit 1
    fi
    verify_install "$fw" "$disk_image" "$install_log"
}

# Authoritative completion gate: qemu exits 0 even when SIGTERMed from a stuck
# prompt, so a quiet log is not enough. Inspect the built disk instead and
# require the partition layout the autoinstall template declares.
verify_install() {
    local fw="$1"
    local disk_image="$2"
    local install_log="$3"
    # Official Ubuntu ZFS layout check: ESP (uefi) + bpool + swap + rpool.
    # Probe each partition with blkid (libguestfs list-filesystems omits
    # zfs_member, and /boot lives on ZFS for this layout).
    local parts p kv fstype fslabel
    parts=$(guestfish --ro -a "$disk_image" run : list-partitions </dev/null 2>/dev/null || true)
    if [[ -z "$parts" ]]; then
        error "Installed disk has no partitions; install did not complete (see $install_log)."
        exit 1
    fi

    local have_vfat=0 have_swap=0 have_bpool=0 have_rpool=0
    info "Partition table:"
    while read -r p; do
        kv=$(guestfish --ro -a "$disk_image" run : blkid "$p" </dev/null 2>/dev/null || true)
        fstype=$(awk -F': ' '/^TYPE: /{print $2}' <<<"$kv")
        fslabel=$(awk -F': ' '/^LABEL: /{print $2}' <<<"$kv")
        echo "  $p: TYPE=${fstype:-none} LABEL=${fslabel:-none}"
        case "$fstype" in
        vfat) have_vfat=1 ;;
        swap) have_swap=1 ;;
        esac
        [[ "$fslabel" == "bpool" ]] && have_bpool=1
        [[ "$fslabel" == "rpool" ]] && have_rpool=1
    done <<<"$parts"

    [[ "$have_bpool" -eq 1 ]] || {
        error "Missing bpool partition (official ZFS layout) on the built image."
        exit 1
    }
    [[ "$have_rpool" -eq 1 ]] || {
        error "Missing rpool partition (official ZFS layout) on the built image."
        exit 1
    }
    [[ "$have_swap" -eq 1 ]] || {
        error "Missing swap partition on the built image."
        exit 1
    }
    if [[ "$fw" == "uefi" && "$have_vfat" -ne 1 ]]; then
        error "Missing EFI system partition (vfat) on the UEFI image."
        exit 1
    fi
    if ! grep -q "Power down" "$install_log"; then
        warn "Install log does not show a clean power-down; filesystem layout looks right, continuing."
    fi
    info "Install verified: official bpool+rpool ZFS layout present."
}

smoke_test() {
    local fw="$1"
    local efi_arg=""
    [[ "$fw" == "uefi" ]] && efi_arg="--efi"
    [[ -f isos/cidata.iso ]] || {
        warn "isos/cidata.iso missing; skipping smoke test (run dev/cloudinit/prepareiso.sh)."
        return 0
    }
    # Boot a throwaway COW overlay, NEVER the golden image itself: the validate
    # cidata's instance-id is fixed, so booting the master would consume the
    # per-instance cloud-init run and break later clone-restore validation.
    local overlay="$WORKDIR/smoke-overlay.qcow2"
    local abs_final_image
    abs_final_image=$(realpath "$FINAL_IMAGE_PATH")
    qemu-img create -f qcow2 -F qcow2 -b "$abs_final_image" "$overlay" >/dev/null
    info "Smoke-testing boot of $FINAL_IMAGE_PATH (COW overlay) with validate.sh ..."
    ./validate.sh --iso isos/cidata.iso --disk "$overlay" --timeout 1200 --arch "$ARCH" $efi_arg || {
        error "Smoke test FAILED for $FINAL_IMAGE_PATH"
        exit 1
    }
}

build_variant() {
    local fw="$1"
    local image_name
    image_name=$(image_name_for "$fw")
    FINAL_IMAGE_PATH="${OUTPUT_DIR%/}/${image_name}"
    WORKDIR=""

    if [[ -f "$FINAL_IMAGE_PATH" && "$FORCE" -eq 0 ]]; then
        info "Image already exists: $FINAL_IMAGE_PATH (use --force to rebuild). Skipped."
        return 0
    fi

    WORKDIR=$(mktemp -d "build-zfs-${fw}.XXXXXX")
    info "=== Building $image_name (firmware: $fw) in $WORKDIR ==="

    cp "$SHARED_WORKDIR/vmlinuz" "$SHARED_WORKDIR/initrd" "$WORKDIR/"
    build_seed_iso "$fw"
    run_install "$fw"

    mkdir -p "$OUTPUT_DIR"
    mv "$WORKDIR/disk.qcow2" "$FINAL_IMAGE_PATH"
    info "Golden image ready: $FINAL_IMAGE_PATH ($(du -h "$FINAL_IMAGE_PATH" | cut -f1) on disk)"

    if [[ "$SKIP_SMOKE" -eq 0 ]]; then
        smoke_test "$fw"
    else
        warn "Smoke test skipped (--skip-smoke-test)."
    fi

    echo "--- Build PASSED: $FINAL_IMAGE_PATH ---"

    cleanup_workdir
    WORKDIR=""
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case "$1" in
    --firmware)
        FIRMWARE="$2"
        shift 2
        ;;
    --arch)
        ARCH="$2"
        shift 2
        ;;
    --release)
        RELEASE="$2"
        shift 2
        ;;
    --iso)
        ISO_PATH="$2"
        shift 2
        ;;
    --output)
        OUTPUT_DIR="$2"
        shift 2
        ;;
    --name)
        CUSTOM_NAME="$2"
        shift 2
        ;;
    --disk-size)
        DISK_SIZE="$2"
        shift 2
        ;;
    -m | --mem)
        MEMORY="$2"
        shift 2
        ;;
    --smp)
        SMP="$2"
        shift 2
        ;;
    --timeout-min)
        TIMEOUT_MIN="$2"
        shift 2
        ;;
    --skip-smoke-test)
        SKIP_SMOKE=1
        shift
        ;;
    --keep-workdir)
        KEEP_WORKDIR=1
        shift
        ;;
    --force)
        FORCE=1
        shift
        ;;
    -h | --help)
        print_usage
        exit 0
        ;;
    *)
        error "Unknown argument: $1"
        print_usage
        exit 1
        ;;
    esac
done

# --- Argument Validation ---
[[ "$ARCH" == "amd64" ]] || {
    error "Only amd64 is supported for now (arm64 reserved for future work)."
    exit 1
}
[[ "$RELEASE" == "24.04" ]] || {
    error "Only Ubuntu 24.04 (noble) is supported by the autoinstall templates."
    exit 1
}
case "$FIRMWARE" in
uefi | bios | both) ;;
*)
    error "--firmware must be one of: uefi, bios, both"
    exit 1
    ;;
esac
if [[ "$FIRMWARE" == "both" && -n "$CUSTOM_NAME" ]]; then
    error "--name can only be used with a single --firmware (uefi or bios)."
    exit 1
fi
[[ -d "$TEMPLATE_DIR" ]] || {
    error "Template dir not found: $TEMPLATE_DIR (run from repository root)."
    exit 1
}

mkdir -p "$LOG_DIR"
info "Build plan: firmware=$FIRMWARE arch=$ARCH release=$RELEASE disk=$DISK_SIZE output=$OUTPUT_DIR"

resolve_iso

# Extract kernel/initrd once into a shared workdir; each variant copies them.
SHARED_WORKDIR=$(mktemp -d "build-zfs-shared.XXXXXX")
WORKDIR="$SHARED_WORKDIR"
extract_installer_files

if [[ "$FIRMWARE" == "both" ]]; then
    VARIANTS=(uefi bios)
else
    VARIANTS=("$FIRMWARE")
fi

for fw in "${VARIANTS[@]}"; do
    # Per-variant workdir seeds from the shared one.
    build_variant "$fw"
done

WORKDIR="$SHARED_WORKDIR"
cleanup_workdir
WORKDIR=""

echo "--- Build PASSED: all requested firmware variants ($FIRMWARE) ---"
