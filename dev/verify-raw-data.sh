#!/bin/bash
#
# verify-raw-data.sh - Verifies the raw data on the last partition of a disk image.
#
# Usage: ./verify-raw-data.sh <disk_image> <expected_md5_file>

set -e

DISK_IMAGE="$1"
EXPECTED_MD5_FILE="$2"

if [[ -z "$DISK_IMAGE" || -z "$EXPECTED_MD5_FILE" ]]; then
    echo "Usage: $0 <disk_image> <expected_md5_file>"
    exit 1
fi

if [[ ! -f "$DISK_IMAGE" ]]; then
    echo "Error: Disk image not found: $DISK_IMAGE"
    exit 1
fi

if [[ ! -f "$EXPECTED_MD5_FILE" ]]; then
    echo "Error: MD5 file not found: $EXPECTED_MD5_FILE"
    exit 1
fi

EXPECTED_MD5=$(cat "$EXPECTED_MD5_FILE")

echo "--- Verifying Raw Data ---"
echo "Disk: $DISK_IMAGE"
echo "Expected MD5 from file: $EXPECTED_MD5"

# Find the last partition
LAST_PART=$(guestfish -a "$DISK_IMAGE" <<EOF
run
list-partitions | tail -n 1
EOF
)

if [[ -z "$LAST_PART" ]]; then
    echo "Error: No partitions found on $DISK_IMAGE"
    exit 1
fi

echo "Last partition: $LAST_PART"

# Read the first 1MB from the partition and calculate MD5
ACTUAL_MD5=$(guestfish -a "$DISK_IMAGE" <<EOF
run
# pread device count offset
pread-device "$LAST_PART" 1048576 0 | md5sum | awk '{print \$1}'
EOF
)

echo "Actual MD5:   $ACTUAL_MD5"

if [[ "$ACTUAL_MD5" == "$EXPECTED_MD5" ]]; then
    echo "Verification SUCCESSFUL"
    exit 0
else
    echo "Verification FAILED"
    exit 1
fi
