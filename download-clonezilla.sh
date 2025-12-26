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
    echo "Usage: $0 --arch <ARCH> [--type <TYPE>] [-o <OUTPUT_DIR>] [--dry-run]" >&2
    echo "" >&2
    echo "Automatically finds and downloads the latest Clonezilla Live zip file." >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  --arch <ARCH>      Architecture: amd64, arm64, riscv64 (required)." >&2
    echo "  --type <TYPE>      For amd64 architecture: stable, testing, alternative-stable," >&2
    echo "                     alternative-testing (default: stable)." >&2
    echo "  -o, --output <DIR> Directory to save the downloaded file (default: .)." >&2
    echo "  --dry-run          Print the final URL and exit without downloading." >&2
    echo "  -h, --help         Display this help message and exit." >&2
    exit 1
}

# --- Default values ---
ARCH=""
TYPE="stable"
OUTPUT_DIR="."
DRY_RUN=false

# --- Argument parsing ---
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        --type) TYPE="$2"; shift 2 ;;
        -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift 1 ;;
        -h|--help) print_usage ;;
        *) echo "Error: Unknown option: $1" >&2; print_usage ;;
    esac
done

# --- Validation ---
if [ -z "$ARCH" ]; then
    echo "Error: --arch is a required argument." >&2
    print_usage
fi

if [[ "$ARCH" != "amd64" && "$TYPE" != "stable" ]]; then
    echo "Warning: --type is only applicable for amd64. Ignoring --type '$TYPE'." >&2
fi

# --- Helper function to find the latest directory/file from a URL ---
# Arguments:
#   $1: URL to search
#   $2: A grep pattern to match the desired href links
find_latest() {
    local search_url=$1
    local pattern=$2
    
    local html_content
    echo "Fetching from ${search_url} ..." >&2
    html_content=$(curl ${CURL_OPTS} "${search_url}")
    if [ $? -ne 0 ]; then
        echo "Error: curl failed to fetch from ${search_url}" >&2
        return 1
    fi

    # The pattern should match the full href attribute
    # Example: href="clonezilla-live-*.zip"
    echo "${html_content}" | grep -Eo "${pattern}" | cut -d'"' -f2 | sort -V | tail -n1
}


# --- Main Logic ---
BASE_URL=""
ZIP_NAME=""
DOWNLOAD_URL=""

echo "Starting search for arch='$ARCH', type='$TYPE'..." >&2

case "$ARCH" in
    "amd64")
        case "$TYPE" in
            "stable")
                BASE_URL="https://free.nchc.org.tw/clonezilla-live/stable/"
                ;;
            "testing")
                BASE_URL="https://free.nchc.org.tw/clonezilla-live/testing/"
                ;;
            "alternative-stable")
                BASE_URL="https://free.nchc.org.tw/clonezilla-live/alternative/stable/"
                ;;
            "alternative-testing")
                BASE_URL="https://free.nchc.org.tw/clonezilla-live/alternative/testing/"
                ;;
            *)
                echo "Error: Invalid type '$TYPE' for arch 'amd64'." >&2
                print_usage
                ;;
        esac
        
        # For testing branches, we need to find the latest dated directory first
        if [[ "$TYPE" == "testing" || "$TYPE" == "alternative-testing" ]]; then
            # Directories are like 20240101-noble/
            LATEST_DIR=$(find_latest "$BASE_URL" 'href="[0-9]+-[a-z]+/"')
            if [ -z "$LATEST_DIR" ]; then
                echo "Error: Could not find latest testing directory in $BASE_URL" >&2
                exit 1
            fi
            # Update base URL to point to the latest testing dir
            BASE_URL="${BASE_URL}${LATEST_DIR}"
        fi
        
        ZIP_NAME=$(find_latest "$BASE_URL" "href=\"clonezilla-live-[^\"]*${ARCH}[^\"]*\\.zip\"")
        DOWNLOAD_URL="${BASE_URL}${ZIP_NAME}"
        ;;

    "arm64")
        BASE_URL="https://free.nchc.org.tw/clonezilla-live/experimental/arm/"
        # Directories are like 3.1.2-9/
        LATEST_DIR=$(find_latest "$BASE_URL" 'href="[0-9.-]+/"')
        if [ -z "$LATEST_DIR" ]; then
            echo "Error: Could not find latest arm64 directory in $BASE_URL" >&2
            exit 1
        fi
        BASE_URL="${BASE_URL}${LATEST_DIR}"
        
        ZIP_NAME=$(find_latest "$BASE_URL" "href=\"clonezilla-live-[^\"]*${ARCH}[^\"]*\\.zip\"")
        DOWNLOAD_URL="${BASE_URL}${ZIP_NAME}"
        ;;

    "riscv64")
        BASE_URL="https://free.nchc.org.tw/clonezilla-live/experimental/riscv64/"
        # Directories are like 3.1.1-2/
        LATEST_DIR=$(find_latest "$BASE_URL" 'href="[0-9.-]+/"')
        if [ -z "$LATEST_DIR" ]; then
            echo "Error: Could not find latest riscv64 directory in $BASE_URL" >&2
            exit 1
        fi
        BASE_URL="${BASE_URL}${LATEST_DIR}"
        
        ZIP_NAME=$(find_latest "$BASE_URL" "href=\"clonezilla-live-[^\"]*${ARCH}[^\"]*\\.zip\"")
        DOWNLOAD_URL="${BASE_URL}${ZIP_NAME}"
        ;;
    *)
        echo "Error: Unsupported architecture '$ARCH'." >&2
        print_usage
        ;;
esac

# --- Final checks and execution ---
if [ -z "$ZIP_NAME" ]; then
    echo "Error: Failed to determine zip file name for arch '$ARCH' and type '$TYPE'." >&2
    exit 1
fi

echo "=================================================" >&2
echo "Found latest zip: ${ZIP_NAME}" >&2
echo "Download URL: ${DOWNLOAD_URL}" >&2
echo "=================================================" >&2


if [ "$DRY_RUN" = true ]; then
    echo "Dry run complete. Final URL is ${DOWNLOAD_URL}" >&2
    echo "Exiting without download." >&2
    # For dry-run, we can just output the URL
    echo "${DOWNLOAD_URL}"
    exit 0
fi

# --- Download ---
mkdir -p "$OUTPUT_DIR"
# Make output dir absolute
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)
DEST_FILE="${OUTPUT_DIR}/${ZIP_NAME}"

echo "" >&2
echo "Downloading to ${DEST_FILE}..." >&2
# Use curl with -fL but without -sS to show progress meter
curl -fL -o "${DEST_FILE}" "${DOWNLOAD_URL}"

if [ $? -eq 0 ]; then
    echo "" >&2
    echo "Download finished successfully." >&2
    echo "File saved to ${DEST_FILE}" >&2
    # On success, print the absolute path of the file to stdout
    echo "${DEST_FILE}"
else
    echo "" >&2
    echo "Error: Download failed from ${DOWNLOAD_URL}." >&2
    # Clean up partially downloaded file on failure
    rm -f "${DEST_FILE}"
    exit 1
fi
