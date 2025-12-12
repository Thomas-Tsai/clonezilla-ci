#!/bin/bash

# This script downloads cloud images based on a configuration file.
#
# Usage: ./download_cloud_images.sh [--force] [config_file]
#
# If config_file is not provided, it defaults to "cloud_images.conf".
# Use --force to re-download existing images.

set -euo pipefail

BASE_DIR="$(dirname "$(realpath "$0")")"

FORCE_DOWNLOAD=false
if [[ "${1-}" == "--force" ]]; then
    FORCE_DOWNLOAD=true
    shift # remove --force from arguments
fi

CONFIG_FILE="${1:-${BASE_DIR}/cloud_images.conf}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

echo "Starting cloud image download script..."
echo "Using configuration file: $CONFIG_FILE"
if [[ "$FORCE_DOWNLOAD" == "true" ]]; then
    echo "Force download enabled."
fi
echo ""

# Read the config file, skipping comments and empty lines
grep -vE '^\s*#|^\s*$' "$CONFIG_FILE" | while read -r OS RELEASE URL; do
    if [[ -z "$OS" || -z "$RELEASE" || -z "$URL" ]]; then
        echo "Skipping invalid line: $OS $RELEASE $URL"
        continue
    fi

    FILENAME="${OS}-${RELEASE}.qcow2"
    OUTPUT_PATH="${BASE_DIR}/${FILENAME}"

    echo "Processing ${OS} ${RELEASE}..."

    if [[ -f "${OUTPUT_PATH}" && "${FORCE_DOWNLOAD}" == "false" ]]; then
        echo "  Image ${FILENAME} already exists. Skipping download. Use --force to re-download."
        echo ""
        continue
    fi

    if [[ "$URL" == "PLACEHOLDER_"* ]]; then
        echo "  URL is a placeholder for ${OS}. Please manually find the direct download URL and update the config file."
    else
        echo "  Downloading from ${URL}..."
        curl -L --fail --output "${OUTPUT_PATH}" "${URL}" || {
            echo "  Download for ${OS} ${RELEASE} failed."
            # Continue to next image instead of exiting
            continue
        }
        echo "  Image downloaded to ${OUTPUT_PATH}"
    fi
    echo ""
done

echo "Script finished. Please review the output for any failed downloads or placeholder URLs."
