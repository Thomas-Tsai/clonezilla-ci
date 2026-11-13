#!/usr/bin/env bash
#
# image_common.sh - Shared parsing helpers for cloud image tooling
#                   (download_cloud_images.sh / sync_images.sh).
#
# Source this file; it defines functions only. CLOUD_IMAGES_DIR defaults to the
# directory containing this file (i.e. qemu/cloudimages).
#
# Config schema (cloud_images.conf), whitespace separated columns:
#   OS RELEASE ARCH [FIRMWARE] URL [SHA256]
# FIRMWARE is bios|uefi and is only present for firmware-specific images.
# Filename contract: <OS>-<RELEASE>[-<FIRMWARE>]-<ARCH>.qcow2
#
# SPDX-License-Identifier: GPL-2.0-or-later
# Globals below are consumed by the scripts sourcing this file.
# shellcheck disable=SC2034

: "${CLOUD_IMAGES_DIR:=$(dirname "$(realpath "${BASH_SOURCE[0]}")")}"
readonly CLOUD_IMAGES_DIR

CI_OS=""
CI_RELEASE=""
CI_ARCH=""
CI_FIRMWARE=""
CI_URL=""
CI_SHA256=""

_is_firmware_token() {
    [[ "$1" == "bios" || "$1" == "uefi" ]]
}

# parse_conf_entry <raw conf line>
# Parses one config line into the CI_OS/CI_RELEASE/CI_ARCH/CI_FIRMWARE/CI_URL/CI_SHA256
# globals. FIRMWARE and SHA256 default to "" and "-" when absent.
parse_conf_entry() {
    local IFS=$' \t\n'
    local -a f
    read -r -a f <<<"$1"
    CI_OS="${f[0]:-}"
    CI_RELEASE="${f[1]:-}"
    CI_ARCH="${f[2]:-}"
    CI_FIRMWARE=""
    CI_SHA256="-"
    if _is_firmware_token "${f[3]:-}"; then
        CI_FIRMWARE="${f[3]}"
        CI_URL="${f[4]:-}"
        CI_SHA256="${f[5]:--}"
    else
        CI_URL="${f[3]:-}"
        CI_SHA256="${f[4]:--}"
    fi
}

# image_name_from_conf_line <raw conf line>
# Prints the contract filename for one config line.
image_name_from_conf_line() {
    parse_conf_entry "$1"
    image_filename
}

# image_filename
# Prints the contract filename from the current CI_* globals.
image_filename() {
    if [[ -n "$CI_FIRMWARE" ]]; then
        echo "${CI_OS}-${CI_RELEASE}-${CI_FIRMWARE}-${CI_ARCH}.qcow2"
    else
        echo "${CI_OS}-${CI_RELEASE}-${CI_ARCH}.qcow2"
    fi
}

# conf_url_is_downloadable <url>
conf_url_is_downloadable() {
    [[ "$1" =~ ^https?:// ]]
}

# each_conf_entry <config_file> <callback>
# Runs <callback> for every non-comment config line, with CI_* globals set.
each_conf_entry() {
    local config_file="$1"
    local callback="$2"
    local line
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# || "$line" =~ ^[[:space:]]*$ ]] && continue
        parse_conf_entry "$line"
        if [[ -z "$CI_OS" || -z "$CI_RELEASE" || -z "$CI_ARCH" || -z "$CI_URL" ]]; then
            echo "[WARN] Skipping invalid config line: $line" >&2
            continue
        fi
        "$callback"
    done <"$config_file"
}

# list_conf_filenames <config_file>
# Prints every contract filename referenced by the config.
list_conf_filenames() {
    each_conf_entry "$1" image_filename
}

# sha256_of <file>
sha256_of() {
    sha256sum "$1" | awk '{print $1}'
}

# confirm_or_skip <prompt>
# Returns 0 to proceed, 1 to abort. Honors YES=true to skip the prompt.
confirm_or_skip() {
    local prompt="$1"
    if [[ "${YES:-false}" == "true" ]]; then
        return 0
    fi
    local answer
    read -r -p "$prompt [y/N] " answer
    [[ "$answer" == [yY]* ]]
}

# prune_orphans <config_file>
# Deletes local *.qcow2 files in CLOUD_IMAGES_DIR not referenced by the config.
prune_orphans() {
    local config_file="$1"
    local -a contract=()
    local name orphan
    local -a orphans=()
    mapfile -t contract < <(list_conf_filenames "$config_file")

    while IFS= read -r -d '' path; do
        name="$(basename "$path")"
        if ! printf '%s\n' "${contract[@]:-}" | grep -qxF "$name"; then
            orphans+=("$name")
        fi
    done < <(find "$CLOUD_IMAGES_DIR" -maxdepth 1 -name '*.qcow2' -print0)

    if [[ ${#orphans[@]} -eq 0 ]]; then
        echo "No orphan images found."
        return 0
    fi
    echo "Orphan images (not referenced by $config_file):"
    printf '  %s\n' "${orphans[@]}"
    if ! confirm_or_skip "Delete ${#orphans[@]} orphan image(s) from ${CLOUD_IMAGES_DIR}?"; then
        echo "Aborted; nothing deleted."
        return 1
    fi
    for orphan in "${orphans[@]}"; do
        rm -f "${CLOUD_IMAGES_DIR}/${orphan}"
        echo "  Deleted ${orphan}"
    done
}

# require_cmds <cmd>...
require_cmds() {
    local cmd
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "[ERROR] required command missing: $cmd" >&2
            exit 127
        fi
    done
}
