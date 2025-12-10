#!/bin/bash

# This script downloads cloud images based on a configuration file.
#
# Usage: ./download_cloud_images.sh [config_file]
#
# If config_file is not provided, it defaults to "cloud_images.conf"

set -euo pipefail

BASE_DIR="$(dirname "$(realpath "$0")")"
CONFIG_FILE="${1:-${BASE_DIR}/cloud_images.conf}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

echo "Starting cloud image download script..."
echo "Using configuration file: $CONFIG_FILE"
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
