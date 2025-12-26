#!/bin/bash

# ============================================================================
#
# download-clonezilla.sh
#
# Description:
#   This script automatically finds and downloads the latest Clonezilla Live
#   zip file based on the specified architecture and release type.
#   On success, it prints the full path of the downloaded file to stdout.
#
# ============================================================================

set -e

CURL_OPTS="-fsSL"

# --- Function to print usage information ---
print_usage() {
    echo "Usage: $0 [--arch <ARCH>] [--type <TYPE>] [--all] [-o <OUTPUT_DIR>] [--dry-run]" >&2
    echo "" >&2
    echo "Automatically finds and downloads Clonezilla Live zip files." >&2
    echo "" >&2
    echo "Modes:" >&2
    echo "  1. Single Download (default): Specify --arch and optionally --type." >&2
    echo "  2. Batch Download: Use --all to download all supported types and architectures." >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  --arch <ARCH>      Architecture: amd64, arm64, riscv64." >&2
    echo "  --type <TYPE>      For amd64: stable, testing, alternative-stable, alternative-testing (default: stable)." >&2
    echo "  --all              Download all known stable/testing versions for all architectures. Ignores --arch and --type." >&2
    echo "  -o, --output <DIR> Directory to save the downloaded files (default: .)." >&2
    echo "  --dry-run          Print the final URLs and exit without downloading." >&2
    echo "  -h, --help         Display this help message and exit." >&2
    exit 1
}

# --- Default values ---
ARCH=""
TYPE="stable"
OUTPUT_DIR="."
DRY_RUN=false
ALL_MODE=false

# --- Argument parsing ---
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        --type) TYPE="$2"; shift 2 ;;
        --all) ALL_MODE=true; shift 1 ;;
        -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift 1 ;;
        -h|--help) print_usage ;;
        *) echo "Error: Unknown option: $1" >&2; print_usage ;;
    esac
done

# --- Validation ---
if [[ "$ALL_MODE" = false && -z "$ARCH" ]]; then
    echo "Error: --arch is a required argument unless --all is specified." >&2
    print_usage
fi

if [[ "$ARCH" != "amd64" && "$TYPE" != "stable" && "$ALL_MODE" = false ]]; then
    echo "Warning: --type is only applicable for amd64. Ignoring --type '$TYPE'." >&2
fi

# --- Helper function to find matching links from a URL ---
# Arguments:
#   $1: URL to search
#   $2: A grep pattern to match the desired href links
find_links() {
    local search_url=$1
    local pattern=$2
    
    local html_content
    echo "Fetching from ${search_url} ..." >&2
    html_content=$(curl ${CURL_OPTS} "${search_url}")
    if [ $? -ne 0 ]; then
        echo "Error: curl failed to fetch from ${search_url}" >&2
        return 1
    fi

    # This function now only finds all matches and extracts the name.
    # Sorting and selection are handled by the caller.
    echo "${html_content}" | grep -Eo "${pattern}" | cut -d'"' -f2
}

# --- Function to download a single zip file ---
download_single_zip() {
    local arch=$1
    local type=$2
    local base_url=""
    local zip_name=""
    local download_url=""

    echo "Starting search for arch='$arch', type='$type'..." >&2

    case "$arch" in
        "amd64")
            case "$type" in
                "stable") base_url="https://free.nchc.org.tw/clonezilla-live/stable/" ;;
                "testing") base_url="https://free.nchc.org.tw/clonezilla-live/testing/" ;;
                "alternative-stable") base_url="https://free.nchc.org.tw/clonezilla-live/alternative/stable/" ;;
                "alternative-testing") base_url="https://free.nchc.org.tw/clonezilla-live/alternative/testing/" ;;
                *)
                    echo "Error: Invalid type '$type' for arch 'amd64'." >&2
                    return 1
                    ;;
            esac
            
            if [[ "$type" == "testing" ]]; then
                # Directories are version numbers, e.g., 3.3.1-15/
                local latest_dir
                latest_dir=$(find_links "$base_url" 'href="[0-9.-]+/"' | sort -V | tail -n1)
                if [ -z "$latest_dir" ]; then
                    echo "Error: Could not find latest testing directory in $base_url" >&2
                    return 1
                fi
                base_url="${base_url}${latest_dir}"
            elif [[ "$type" == "alternative-testing" ]]; then
                # Directories are like 20240101-noble/
                local latest_dir
                latest_dir=$(find_links "$base_url" 'href="[0-9]+-[a-z0-9]+/"' | sort -V | tail -n1)
                if [ -z "$latest_dir" ]; then
                    echo "Error: Could not find latest alternative-testing directory in $base_url" >&2
                    return 1
                fi
                base_url="${base_url}${latest_dir}"
            fi
            
            zip_name=$(find_links "$base_url" "href=\"clonezilla-live-[^\"]*${arch}[^\"]*\\.zip\"" | sort -V | tail -n1)
            download_url="${base_url}${zip_name}"
            ;;

        "arm64")
            base_url="https://free.nchc.org.tw/clonezilla-live/experimental/arm/"
            local latest_dir
            latest_dir=$(find_links "$base_url" 'href="[0-9.-]+/"' | grep -v '^old/$' | sort -V | tail -n1)
            if [ -z "$latest_dir" ]; then
                echo "Error: Could not find latest arm64 directory in $base_url" >&2
                return 1
            fi
            base_url="${base_url}${latest_dir}"
            
            zip_name=$(find_links "$base_url" "href=\"clonezilla-live-[^\"]*${arch}[^\"]*\\.zip\"" | sort -V | tail -n1)
            download_url="${base_url}${zip_name}"
            ;;

        "riscv64")
            base_url="https://free.nchc.org.tw/clonezilla-live/experimental/riscv64/"
            local latest_dir
            latest_dir=$(find_links "$base_url" 'href="[0-9.-]+/"' | grep -v '^old/$' | sort -V | tail -n1)
            if [ -z "$latest_dir" ]; then
                echo "Error: Could not find latest riscv64 directory in $base_url" >&2
                return 1
            fi
            base_url="${base_url}${latest_dir}"
            
            zip_name=$(find_links "$base_url" "href=\"clonezilla-live-[^\"]*${arch}[^\"]*\\.zip\"" | sort -V | tail -n1)
            download_url="${base_url}${zip_name}"
            ;;
        *)
            echo "Error: Unsupported architecture '$arch'." >&2
            return 1
            ;;
    esac

    if [ -z "$zip_name" ]; then
        echo "Error: Failed to determine zip file name for arch '$arch' and type '$type'." >&2
        return 1
    fi

    echo "=================================================" >&2
    echo "Found latest zip: ${zip_name}" >&2
    echo "Download URL: ${download_url}" >&2
    echo "=================================================" >&2

    if [ "$DRY_RUN" = true ]; then
        echo "${download_url}" # Print URL for dry run
        return 0
    fi

    mkdir -p "$OUTPUT_DIR"
    local output_dir_abs
    output_dir_abs=$(cd "$OUTPUT_DIR" && pwd)
    local dest_file="${output_dir_abs}/${zip_name}"

    echo "" >&2
    echo "Downloading to ${dest_file}..." >&2
    curl -fL -o "${dest_file}" "${download_url}"

    if [ $? -eq 0 ]; then
        echo "" >&2
        echo "Download finished successfully." >&2
        echo "${dest_file}" # Print final path to stdout
    else
        echo "" >&2
        echo "Error: Download failed from ${download_url}." >&2
        rm -f "${dest_file}"
        return 1
    fi
}

# --- Main Execution ---
if [ "$ALL_MODE" = true ]; then
    echo "--- Batch mode enabled: processing all known versions ---" >&2
    
    ALL_COMBINATIONS=(
        "amd64 stable"
        "amd64 testing"
        "amd64 alternative-stable"
        "amd64 alternative-testing"
        "arm64 stable"
        "riscv64 stable"
    )

    if [ "$DRY_RUN" = true ]; then
        echo "--- Dry Run: Listing all URLs ---" >&2
        URL_LIST=()
        for combo in "${ALL_COMBINATIONS[@]}"; do
            read -r arch type <<< "$combo"
            url=$(download_single_zip "$arch" "$type")
            if [ -n "$url" ]; then
                URL_LIST+=("$url")
            fi
        done
        # Print all URLs at the end
        printf "%s\n" "${URL_LIST[@]}"
    else
        for combo in "${ALL_COMBINATIONS[@]}"; do
            read -r arch type <<< "$combo"
            download_single_zip "$arch" "$type" || echo "WARNING: Failed to process $arch/$type, continuing..." >&2
        done
    fi
else
    download_single_zip "$ARCH" "$TYPE"
fi
