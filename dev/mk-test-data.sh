#!/usr/bin/env bash
#
# mk-test-data.sh - Generate a deterministic test payload directory for the
#                   Clonezilla CI data clone/restore tests (dev/testData,
#                   or /data/dataSets on runners).
#
# Every file's content is a pure function of (seed, relative path), so the
# same seed produces bit-identical trees on any machine (compared via the
# generated SHA256SUMS manifest). No network access is needed; runners can
# generate the exact same data set locally instead of syncing it.
#
# Layout (approximate, scaled by --profile):
#   files/small/   ~500 x 1-8K files (inode pressure)
#   files/mid/     ~50 x 100K-1M files
#   files/big/     a few large incompressible files (extent/block coverage)
#   files/text/    highly compressible lorem files
#   files/sparse/  sparse file(s) (partclone/fs handling)
#   files/edge/    empty file + 1-byte file
#   files/names/   tricky filenames (spaces, unicode, long names)
#   deep/...       deep nested dirs (unicode/space names, file at each level)
#   .hidden/       dotfiles
#   SHA256SUMS.txt checksum manifest of every file (excluding itself)
#
# Usage:   ./mk-test-data.sh [--profile small|std|large] [--seed N]
#                            [--out DIR] [--force] [--links] [--verify] [-h]
#
# Options:
#   --profile  small (~100M) | std (~1G, default) | large (~10G).
#   --seed     Integer seed (default: 42; same seed = same tree everywhere).
#   --out      Output directory (default: ./generated-testData).
#   --force    Wipe the output directory first (required if it is non-empty).
#   --links    Also create symlink fixtures (posix fs tests only; the default
#              tree has zero symlinks so vfat/exfat/ntfs copies work).
#   --verify   Verify the tree against its SHA256SUMS manifest and exit.
#
# Dependencies: openssl, dd, truncate, find, sort, xargs, sha256sum, awk, seq
#
# Author: Thomas (maintainer)
# SPDX-License-Identifier: GPL-2.0-or-later
#
set -euo pipefail

PROFILE="std"
SEED=42
OUT_DIR="./generated-testData"
FORCE=false
WITH_LINKS=false
VERIFY_ONLY=false
MARKER="generated-by-mk-test-data"

usage() {
    cat <<'EOF'
Usage: ./mk-test-data.sh [options]

Options:
  --profile <small|std|large>  Payload size profile (default: std ~1G).
  --seed <N>                   Deterministic seed (default: 42).
  --out <dir>                  Output directory (default: ./generated-testData).
  --force                      Wipe non-empty output directory first.
  --links                      Include symlink fixtures (posix fs only).
  --verify                     Verify an existing tree against its manifest.
  -h, --help                   Show this help.

Examples:
  ./mk-test-data.sh --out /data/dataSets --seed 42
  ./mk-test-data.sh --profile small --out /tmp/td --force
  ./mk-test-data.sh --out /data/dataSets --verify
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
    --profile)
        PROFILE="$2"
        shift 2
        ;;
    --seed)
        SEED="$2"
        shift 2
        ;;
    --out)
        OUT_DIR="$2"
        shift 2
        ;;
    --force)
        FORCE=true
        shift
        ;;
    --links)
        WITH_LINKS=true
        shift
        ;;
    --verify)
        VERIFY_ONLY=true
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "[ERROR] Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
done

require_cmds() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || {
            echo "[ERROR] required command missing: $cmd" >&2
            exit 127
        }
    done
}

require_cmds openssl dd truncate find sort xargs sha256sum awk seq head yes mkdir wc

# --- verify mode: cheap and dependency-light -------------------------------
if [[ "$VERIFY_ONLY" == "true" ]]; then
    if [[ ! -f "${OUT_DIR}/SHA256SUMS.txt" ]]; then
        echo "[ERROR] manifest not found: ${OUT_DIR}/SHA256SUMS.txt" >&2
        exit 1
    fi
    (cd "$OUT_DIR" && sha256sum --quiet -c SHA256SUMS.txt) && echo "[INFO] Verify OK: $OUT_DIR"
    exit $?
fi

case "$PROFILE" in
small)
    P_SMALL_COUNT=300
    P_MID_COUNT=30
    P_MID_STEP_KB=50
    P_BIG_MB=(32 48)
    P_LOREM_MB=8
    P_SPARSE_MB=512
    ;;
std)
    P_SMALL_COUNT=500
    P_MID_COUNT=50
    P_MID_STEP_KB=100
    P_BIG_MB=(256 384)
    P_LOREM_MB=64
    P_SPARSE_MB=1024
    ;;
large)
    P_SMALL_COUNT=1500
    P_MID_COUNT=100
    P_MID_STEP_KB=250
    P_BIG_MB=(1024 1024 1024 1024 1024 2048 2048)
    P_LOREM_MB=256
    P_SPARSE_MB=4096
    ;;
*)
    echo "[ERROR] unknown --profile: $PROFILE (want small|std|large)" >&2
    exit 1
    ;;
esac

if [[ -d "$OUT_DIR" ]] && [[ -n "$(find "$OUT_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
    if [[ "$FORCE" != "true" ]]; then
        echo "[ERROR] output directory non-empty: $OUT_DIR (use --force to wipe)" >&2
        exit 1
    fi
    echo "[INFO] Wiping existing output directory: $OUT_DIR"
    find "$OUT_DIR" -mindepth 1 -delete
fi
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

# --- deterministic content primitives --------------------------------------

# derive_key_iv <relpath> -> sets K and IV (hex) from sha256(seed:relpath)
K=""
IV=""
derive_key_iv() {
    local h
    h="$(printf '%s' "${SEED}:${1}" | sha256sum | awk '{print $1}')"
    K="${h:0:32}"
    IV="${h:32:32}"
}

# rand_file <relpath> <bytes>
# Incompressible file: AES-128-CTR stream keyed by (seed, relpath) over zeros.
rand_file() {
    local rel="$1" bytes="$2" dst="${OUT_DIR}/${1}"
    mkdir -p "$(dirname "$dst")"
    derive_key_iv "$rel"
    # no early-closing reader (head) in the pipe: SIGPIPE + pipefail would kill the run
    dd if=/dev/zero bs=1M iflag=fullblock count=$(((bytes + 1048575) / 1048576)) 2>/dev/null |
        openssl enc -aes-128-ctr -K "$K" -iv "$IV" 2>/dev/null |
        dd of="$dst" bs=1M iflag=fullblock 2>/dev/null
    truncate -s "$bytes" "$dst"
    unset -v K IV
}

# text_file <relpath> <bytes>
# Highly compressible: repeated lorem line with a per-file marker.
text_file() {
    local rel="$1" bytes="$2" dst="${OUT_DIR}/${1}"
    mkdir -p "$(dirname "$dst")"
    # procsub keeps `yes` out of the current pipeline: its SIGPIPE cannot fail us
    head -c "$bytes" \
        < <(yes "lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt (${SEED}:${rel})") \
        >"$dst"
}

# zero_file <relpath> <bytes>
zero_file() {
    local rel="$1" bytes="$2" dst="${OUT_DIR}/${1}"
    mkdir -p "$(dirname "$dst")"
    dd if=/dev/zero of="$dst" bs=1M count=$(((bytes + 1048575) / 1048576)) 2>/dev/null
    truncate -s "$bytes" "$dst"
}

# sparse_file <relpath> <bytes>
sparse_file() {
    local rel="$1" bytes="$2" dst="${OUT_DIR}/${1}"
    mkdir -p "$(dirname "$dst")"
    truncate -s "$bytes" "$dst"
}

# seq_size <index> <count> <min_kb> <step_kb>
seq_size() {
    local i="$1" min_kb="$3" step_kb="$4"
    echo $(((min_kb + (i % 8) * step_kb) * 1024))
}

echo "[INFO] Generating test data: profile=${PROFILE} seed=${SEED} out=${OUT_DIR}"
START_TS=$(date +%s)

# marker (content must stay seed-stable for cross-machine comparison)
printf 'profile=%s seed=%s generator=%s\n' "$PROFILE" "$SEED" "$MARKER" >"${OUT_DIR}/${MARKER}.info"

# files/small: many 1-8K files
i=0
while [ "$i" -lt "$P_SMALL_COUNT" ]; do
    rel="files/small/s$(printf '%04d' "$i").dat"
    rand_file "$rel" "$(seq_size "$i" "$P_SMALL_COUNT" 1 1)"
    i=$((i + 1))
done

# files/mid: ~100K-1M files
i=0
while [ "$i" -lt "$P_MID_COUNT" ]; do
    rel="files/mid/m$(printf '%03d' "$i").bin"
    rand_file "$rel" "$(seq_size "$i" "$P_MID_COUNT" 64 "$P_MID_STEP_KB")"
    i=$((i + 1))
done

# files/big: large incompressible files
i=0
for mb in "${P_BIG_MB[@]}"; do
    rel="files/big/big$((i + 1)).bin"
    rand_file "$rel" $((mb * 1048576))
    i=$((i + 1))
done

# files/text: compressible lorem
text_file "files/text/lorem01.txt" $((P_LOREM_MB * 1048576))
zero_file "files/text/zeros.bin" $((P_LOREM_MB * 524288))

# files/sparse
sparse_file "files/sparse/sparse.img" $((P_SPARSE_MB * 1048576))

# files/edge
mkdir -p "${OUT_DIR}/files/edge"
truncate -s 0 "${OUT_DIR}/files/edge/empty.bin"
printf 'x' >"${OUT_DIR}/files/edge/one-byte.bin"

# files/names: tricky but portable filenames (no \/:*?"<>| for NTFS/exfat)
text_file "files/names/file with spaces.txt" 4096
rand_file "files/names/üñîçødé-檔案名-42.bin" 16384
LONG_NAME="$(printf 'long-name-%0100d' "$SEED")"
text_file "files/names/${LONG_NAME}.txt" 2048
rand_file "files/names/prefix--double-dash.dat" 8192
text_file "files/names/.dotfile.txt" 1024

# dotfiles
text_file ".hidden/.config/settings.conf" 512
text_file ".hidden/notes.txt" 2048

# deep nesting with unicode/space dir names, one file per level
DEEP_DIR="deep/d01-üñï/d02 with space/d03-檔案/d04-end/d05 deep space/d06-xyz/d07-tail/d08-末段"
i=1
cur="${OUT_DIR}/deep"
while [ "$i" -le 8 ]; do
    part="$(echo "$DEEP_DIR" | cut -d/ -f$((i + 1)))"
    cur="${cur}/${part}"
    mkdir -p "$cur"
    text_file "${cur#"$OUT_DIR"/}/level-${i}.txt" 4096
    i=$((i + 1))
done

if [[ "$WITH_LINKS" == "true" ]]; then
    ln -s "../big/big1.bin" "${OUT_DIR}/files/links/big1.link" 2>/dev/null || {
        mkdir -p "${OUT_DIR}/files/links"
        ln -s "../big/big1.bin" "${OUT_DIR}/files/links/big1.link"
    }
    mkdir -p "${OUT_DIR}/files/links"
    ln -s "../text/lorem01.txt" "${OUT_DIR}/files/links/lorem.link"
fi

# --- manifest ---------------------------------------------------------------
echo "[INFO] Building SHA256SUMS manifest..."
(
    cd "$OUT_DIR"
    find . -type f ! -name 'SHA256SUMS.txt' -print0 | sort -z | xargs -0 sha256sum >SHA256SUMS.txt
)

FILES_N=$(find "$OUT_DIR" -type f | wc -l)
SIZE_H=$(du -sh "$OUT_DIR" | awk '{print $1}')
DUR=$(($(date +%s) - START_TS))
echo "[INFO] Done: ${FILES_N} files, ${SIZE_H} (logical) in ${DUR}s -> ${OUT_DIR}"
echo "[INFO] Verify with: $0 --out \"$OUT_DIR\" --verify"
