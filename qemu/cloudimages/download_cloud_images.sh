#!/usr/bin/env bash
#
# download_cloud_images.sh - Download cloud images listed in cloud_images.conf.
#
# Usage: ./download_cloud_images.sh [mode] [--force] [--yes] [config_file]
#
# Config schema: OS RELEASE ARCH [FIRMWARE] URL [SHA256]
# Filename contract: <OS>-<RELEASE>[-<FIRMWARE>]-<ARCH>.qcow2
# Non-http(s) URLs (e.g. PLACEHOLDER_*, MANUAL_*) are skipped with a hint.
#
# Modes:
#   (default)     Download missing images into this directory (atomic .part + mv).
#   --check       Report OK/MISSING/SHA-MISMATCH/MANUAL per entry; no downloads.
#   --prune       Delete local *.qcow2 not referenced by the config.
#   --migrate     Rename known legacy filenames to the contract names.
#
# Options:
#   --force       Re-download and overwrite existing images.
#   --yes         Skip interactive confirmations (for --prune/--migrate).
#
# Exit codes:
#   0 success (or nothing to do)
#   1 usage/config error or aborted action
#   2 download or checksum failure
#
# SPDX-License-Identifier: GPL-2.0-or-later

set -euo pipefail

BASE_DIR="$(dirname "$(realpath "$0")")"
# shellcheck source=/dev/null
. "${BASE_DIR}/image_common.sh"

MODE="download"
FORCE="false"
# Consumed by confirm_or_skip in image_common.sh.
# shellcheck disable=SC2034
YES="false"
CONFIG_FILE=""

usage() {
    cat <<'EOF'
Usage: ./download_cloud_images.sh [mode] [--force] [--yes] [config_file]

Modes:
  (default)   Download missing images listed in the config.
  --check     Report image state per config entry; no downloads.
  --prune     Delete local *.qcow2 not referenced by the config.
  --migrate   Rename known legacy filenames to contract names.

Options:
  --force     Re-download even if the image already exists.
  --yes       Skip interactive confirmations (for --prune/--migrate).

Config schema: OS RELEASE ARCH [FIRMWARE] URL [SHA256]
Filename:      <OS>-<RELEASE>[-<FIRMWARE>]-<ARCH>.qcow2
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
    --check)
        MODE="check"
        shift
        ;;
    --prune)
        MODE="prune"
        shift
        ;;
    --migrate)
        MODE="migrate"
        shift
        ;;
    --force)
        FORCE="true"
        shift
        ;;
    --yes)
        # Consumed by confirm_or_skip in image_common.sh.
        # shellcheck disable=SC2034
        YES="true"
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    -*)
        echo "[ERROR] Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
    *)
        CONFIG_FILE="$1"
        shift
        ;;
    esac
done

CONFIG_FILE="${CONFIG_FILE:-${BASE_DIR}/cloud_images.conf}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[ERROR] Configuration file not found: $CONFIG_FILE" >&2
    exit 1
fi

check_entry() {
    local filename
    filename="$(image_filename)"
    local path="${CLOUD_IMAGES_DIR}/${filename}"

    if ! conf_url_is_downloadable "$CI_URL"; then
        echo "MANUAL        ${filename}  (prepare by hand: ${CI_URL})"
        return
    fi
    if [[ ! -f "$path" ]]; then
        echo "MISSING       ${filename}  (${CI_URL})"
        return
    fi
    if [[ "$CI_SHA256" != "-" ]]; then
        local actual
        actual="$(sha256_of "$path")"
        if [[ "${actual,,}" != "${CI_SHA256,,}" ]]; then
            echo "SHA-MISMATCH  ${filename}  (local ${actual})"
            return
        fi
        echo "OK(SHA256)    ${filename}"
        return
    fi
    echo "OK            ${filename}"
}

download_entry() {
    local filename
    filename="$(image_filename)"
    local path="${CLOUD_IMAGES_DIR}/${filename}"
    local part="${path}.part"

    if ! conf_url_is_downloadable "$CI_URL"; then
        echo "  ${filename}: not downloadable (hint: ${CI_URL}); skipping."
        return
    fi

    if [[ -f "$path" && "$FORCE" == "false" ]]; then
        if [[ "$CI_SHA256" != "-" ]]; then
            local actual
            actual="$(sha256_of "$path")"
            if [[ "${actual,,}" != "${CI_SHA256,,}" ]]; then
                echo "  ${filename}: local checksum mismatch (want ${CI_SHA256}, have ${actual})."
                echo "  Re-run with --force to re-download."
                FAILED="true"
                return
            fi
        fi
        echo "  ${filename}: already present, skipping (use --force to re-download)."
        return
    fi

    echo "  ${filename}: downloading ${CI_URL} ..."
    rm -f "$part"
    if ! curl --fail -L --retry 3 --retry-all-errors -C - --connect-timeout 30 -o "$part" "$CI_URL"; then
        echo "  [ERROR] Download failed for ${CI_URL}" >&2
        FAILED="true"
        return
    fi

    if [[ "$CI_SHA256" != "-" ]]; then
        local actual
        actual="$(sha256_of "$part")"
        if [[ "${actual,,}" != "${CI_SHA256,,}" ]]; then
            echo "  [ERROR] Checksum mismatch for ${filename} (want ${CI_SHA256}, got ${actual}); removing partial file." >&2
            rm -f "$part"
            FAILED="true"
            return
        fi
    fi

    mv "$part" "$path"
    echo "  ${filename}: downloaded."
}

migrate_legacy_names() {
    # Legacy name -> contract name (idempotent; skipped when target exists).
    local -A legacy_map=(
        ["win11-uefi.qcow2"]="windows-11-uefi-amd64.qcow2"
        ["windows-11-amd64.qcow2"]="windows-11-bios-amd64.qcow2"
    )
    local src dst moved=0
    local -a contract=()
    mapfile -t contract < <(list_conf_filenames "$CONFIG_FILE")

    for src in "${!legacy_map[@]}"; do
        [[ -f "${CLOUD_IMAGES_DIR}/${src}" ]] || continue
        dst="${legacy_map[$src]}"
        if ! printf '%s\n' "${contract[@]:-}" | grep -qxF "$dst"; then
            echo "  [WARN] ${dst} not referenced by ${CONFIG_FILE}; not renaming ${src}."
            continue
        fi
        if [[ -e "${CLOUD_IMAGES_DIR}/${dst}" ]]; then
            echo "  [WARN] ${dst} already exists; leaving ${src} untouched (dedupe by hand)."
            continue
        fi
        if ! confirm_or_skip "Rename ${src} -> ${dst}?"; then
            continue
        fi
        mv "${CLOUD_IMAGES_DIR}/${src}" "${CLOUD_IMAGES_DIR}/${dst}"
        echo "  Renamed ${src} -> ${dst}"
        moved=$((moved + 1))
    done

    if [[ "$moved" -eq 0 ]]; then
        echo "Nothing to migrate."
    fi
}

case "$MODE" in
check)
    echo "Image state (${CONFIG_FILE}):"
    each_conf_entry "$CONFIG_FILE" check_entry
    ;;
prune)
    require_cmds find grep xargs
    prune_orphans "$CONFIG_FILE"
    ;;
migrate)
    migrate_legacy_names
    ;;
download)
    require_cmds curl sha256sum awk
    FAILED="false"
    echo "Downloading cloud images (config: ${CONFIG_FILE}, force: ${FORCE})"
    each_conf_entry "$CONFIG_FILE" download_entry
    if [[ "$FAILED" == "true" ]]; then
        echo "[ERROR] One or more downloads failed (see above)." >&2
        exit 2
    fi
    echo "All images ready."
    ;;
esac
