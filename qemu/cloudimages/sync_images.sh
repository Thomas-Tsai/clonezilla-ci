#!/usr/bin/env bash
#
# sync_images.sh - Sync qcow2 cloud images with the central image repo over rsync/ssh.
#
# Usage:
#   ./sync_images.sh --pull [--yes] [config_file]
#   ./sync_images.sh --push [--yes] [config_file]
#   ./sync_images.sh --prune [--yes] [config_file]
#
# Modes:
#   --pull   Fetch config-referenced images that are missing or stale locally
#            (stale = sha256 differs from the repo MANIFEST.sha256). Downloads
#            are staged as .part files and verified against the manifest.
#   --push   Upload local config-referenced images to the repo, then rebuild the
#            remote MANIFEST.sha256 / manifest.tsv. Run this on the producer
#            machine (ASUS PN42) only. Symlinked images are uploaded as file
#            content (--copy-links).
#   --prune  Delete local *.qcow2 not referenced by the config (same as
#            download_cloud_images.sh --prune).
#
# Environment:
#   IMAGE_REPO_HOST     Repo host (default: 140.110.240.58; runners may also use
#                       a ~/.ssh/config Host alias, e.g. clonezilla-imgrepo).
#   IMAGE_REPO_USER     SSH user (default: cicd).
#   IMAGE_REPO_DIR      Remote image directory (default: /home/cicd/clonezilla-cicd-cloudimages).
#   IMAGE_REPO_SSH_PORT SSH port (default: 3322).
#   CLOUD_IMAGES_DIR    Local image directory (default: this script's directory;
#                       override e.g. to better suit PN42 layouts where images
#                       live in /data/cloudimages instead of the checkout).
#
# Exit codes:
#   0 success / nothing to do
#   1 usage/config error or aborted action
#   2 repo unreachable (ssh/rsync failure)
#   3 checksum verification failure
#
# SPDX-License-Identifier: GPL-2.0-or-later

set -euo pipefail

BASE_DIR="$(dirname "$(realpath "$0")")"
# shellcheck source=/dev/null
. "${BASE_DIR}/image_common.sh"

IMAGE_REPO_HOST="${IMAGE_REPO_HOST:-140.110.240.58}"
IMAGE_REPO_USER="${IMAGE_REPO_USER:-cicd}"
IMAGE_REPO_DIR="${IMAGE_REPO_DIR:-/home/cicd/clonezilla-cicd-cloudimages}"
IMAGE_REPO_SSH_PORT="${IMAGE_REPO_SSH_PORT:-3322}"

MODE=""
# Consumed by confirm_or_skip in image_common.sh.
# shellcheck disable=SC2034
YES="false"
CONFIG_FILE=""

usage() {
    cat <<EOF
Usage: ./sync_images.sh --pull|--push|--prune [--yes] [config_file]

Modes:
  --pull   Fetch missing/stale images from the repo (runners).
  --push   Upload local images and rebuild the remote manifest (producer only).
  --prune  Delete local *.qcow2 not referenced by the config.

Environment:
  IMAGE_REPO_HOST     Repo host (current: ${IMAGE_REPO_HOST})
  IMAGE_REPO_USER     SSH user (current: ${IMAGE_REPO_USER})
  IMAGE_REPO_DIR      Remote directory (current: ${IMAGE_REPO_DIR})
  IMAGE_REPO_SSH_PORT SSH port (current: ${IMAGE_REPO_SSH_PORT})
  CLOUD_IMAGES_DIR    Local image directory (current: ${CLOUD_IMAGES_DIR})
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
    --pull)
        MODE="pull"
        shift
        ;;
    --push)
        MODE="push"
        shift
        ;;
    --prune)
        MODE="prune"
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
    *)
        CONFIG_FILE="$1"
        shift
        ;;
    esac
done

if [[ -z "$MODE" ]]; then
    usage >&2
    exit 1
fi

CONFIG_FILE="${CONFIG_FILE:-${BASE_DIR}/cloud_images.conf}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[ERROR] Configuration file not found: $CONFIG_FILE" >&2
    exit 1
fi

require_cmds rsync ssh sha256sum awk

SSH_OPTS=(-p "$IMAGE_REPO_SSH_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
RSYNC_SSH="ssh ${SSH_OPTS[*]}"
REMOTE="${IMAGE_REPO_USER}@${IMAGE_REPO_HOST}:${IMAGE_REPO_DIR}"

TMP_FILES=()
cleanup() {
    if [[ ${#TMP_FILES[@]} -gt 0 ]]; then
        rm -f "${TMP_FILES[@]}"
    fi
}
trap cleanup EXIT

# load_remote_manifest <path>
# Fills the REMOTE_SHA associative array: filename -> sha256.
declare -A REMOTE_SHA=()
load_remote_manifest() {
    local manifest_path="$1"
    local sha name
    while read -r sha name; do
        [[ -z "$sha" || -z "$name" ]] && continue
        REMOTE_SHA["$name"]="$sha"
    done <"$manifest_path"
}

pull_entry() {
    local filename
    filename="$(image_filename)"
    local path="${CLOUD_IMAGES_DIR}/${filename}"
    local remote_sha="${REMOTE_SHA[$filename]:-}"

    if [[ -z "$remote_sha" ]]; then
        echo "  ${filename}: not on repo yet; skipping."
        return
    fi
    if [[ -f "$path" ]]; then
        local actual
        actual="$(sha256_of "$path")"
        if [[ "${actual,,}" == "${remote_sha,,}" ]]; then
            echo "  ${filename}: up to date."
            return
        fi
        echo "  ${filename}: stale (local ${actual:0:12}... != repo ${remote_sha:0:12}...); updating."
    else
        echo "  ${filename}: missing; downloading."
    fi

    local part="${path}.part"
    rm -f "$part"
    if ! rsync -az --partial --timeout=300 -e "$RSYNC_SSH" "${REMOTE}/${filename}" "$part"; then
        echo "  [ERROR] rsync failed for ${filename}" >&2
        rm -f "$part"
        PULL_FAILED="true"
        return
    fi
    local got
    got="$(sha256_of "$part")"
    if [[ "${got,,}" != "${remote_sha,,}" ]]; then
        echo "  [ERROR] Checksum mismatch for ${filename} (want ${remote_sha}, got ${got}); removing partial file." >&2
        rm -f "$part"
        PULL_FAILED="true"
        PULL_SHA_FAILED="true"
        return
    fi
    mv "$part" "$path"
    echo "  ${filename}: synced."
}

do_pull() {
    local manifest_tmp
    manifest_tmp="$(mktemp)"
    TMP_FILES+=("$manifest_tmp")

    echo "Fetching manifest from ${REMOTE} ..."
    if ! rsync -az --partial --timeout=60 -e "$RSYNC_SSH" "${REMOTE}/MANIFEST.sha256" "$manifest_tmp"; then
        echo "[ERROR] Image repo unreachable: ${REMOTE} (deploy ssh keys / check connectivity first)" >&2
        exit 2
    fi
    load_remote_manifest "$manifest_tmp"

    PULL_FAILED="false"
    PULL_SHA_FAILED="false"
    each_conf_entry "$CONFIG_FILE" pull_entry

    if [[ "$PULL_SHA_FAILED" == "true" ]]; then
        exit 3
    fi
    if [[ "$PULL_FAILED" == "true" ]]; then
        exit 2
    fi
    echo "Local images in sync with ${REMOTE}."
}

push_entry() {
    local filename
    filename="$(image_filename)"
    if [[ -f "${CLOUD_IMAGES_DIR}/${filename}" ]]; then
        PUSH_LIST+=("$filename")
    fi
}

do_push() {
    local list_tmp
    list_tmp="$(mktemp)"
    TMP_FILES+=("$list_tmp")

    PUSH_LIST=()
    each_conf_entry "$CONFIG_FILE" push_entry

    if [[ ${#PUSH_LIST[@]} -eq 0 ]]; then
        echo "No local config-referenced images to push."
        exit 0
    fi

    echo "Images to upload:"
    printf '  %s\n' "${PUSH_LIST[@]}"
    if ! confirm_or_skip "Upload ${#PUSH_LIST[@]} image(s) to ${REMOTE} and rebuild the manifest?"; then
        echo "Aborted; nothing uploaded."
        exit 1
    fi

    printf '%s\n' "${PUSH_LIST[@]}" >"$list_tmp"
    if ! rsync -avz --copy-links --partial --timeout=600 -e "$RSYNC_SSH" --files-from="$list_tmp" "${CLOUD_IMAGES_DIR}/" "${REMOTE}/"; then
        echo "[ERROR] rsync push to ${REMOTE} failed" >&2
        exit 2
    fi

    echo "Rebuilding remote manifest ..."
    local remote_cmd
    remote_cmd="$(printf 'cd %q && sha256sum -- *.qcow2 > MANIFEST.sha256.part && mv MANIFEST.sha256.part MANIFEST.sha256 && stat -c %s -- *.qcow2 > manifest.tsv.part && mv manifest.tsv.part manifest.tsv' \
        "$IMAGE_REPO_DIR" "'%n %s %Y'")"
    # remote_cmd is assembled locally with printf %q (intentional client-side expansion).
    # shellcheck disable=SC2029
    if ! ssh "${SSH_OPTS[@]}" "${IMAGE_REPO_USER}@${IMAGE_REPO_HOST}" "$remote_cmd"; then
        echo "[ERROR] Remote manifest rebuild failed" >&2
        exit 2
    fi
    echo "Push complete; remote manifest rebuilt at ${REMOTE}."
}

case "$MODE" in
pull)
    do_pull
    ;;
push)
    do_push
    ;;
prune)
    require_cmds find grep xargs
    prune_orphans "$CONFIG_FILE"
    ;;
esac
