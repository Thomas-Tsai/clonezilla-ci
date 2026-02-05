#!/bin/bash
#
# prepare-test-image.sh - Prepares a QCOW2 image with an extra raw partition and random data.
#
# Usage: ./prepare-test-image.sh <source_qcow2> <output_qcow2>

set -e

if [[ "$1" == "--new" ]]; then
    OUTPUT_IMAGE="$2"
    if [[ -z "$OUTPUT_IMAGE" ]]; then
        echo "Usage: $0 --new <output_qcow2>"
        exit 1
    fi
    echo "--- Creating Fresh 1GB Test Image ---"
    mkdir -p "$(dirname "$OUTPUT_IMAGE")"
    qemu-img create -f qcow2 "$OUTPUT_IMAGE" 1G
    DISK_SIZE_BYTES=1073741824
    # For a fresh 1GB disk, let's create a 100MB partition.
    # 100MB = 204800 sectors.
    # We'll start it after a small buffer (e.g., 2048 sectors)
    START_SECTOR=2048
    END_SECTOR=$((START_SECTOR + 204800 - 1)) # 2048 + 204800 - 1
else
    SOURCE_IMAGE="$1"
    OUTPUT_IMAGE="$2"

    if [[ -z "$SOURCE_IMAGE" || -z "$OUTPUT_IMAGE" ]]; then
        echo "Usage: $0 <source_qcow2> <output_qcow2> OR $0 --new <output_qcow2>"
        exit 1
    fi

    if [[ ! -f "$SOURCE_IMAGE" ]]; then
        echo "Error: Source image not found: $SOURCE_IMAGE"
        exit 1
    fi

    echo "--- Preparing Test Image from Source ---"
    echo "Source: $SOURCE_IMAGE"
    echo "Output: $OUTPUT_IMAGE"

    # 1. Copy source to output
    cp "$SOURCE_IMAGE" "$OUTPUT_IMAGE"

    # 2. Resize output image (+100MB)
    echo "Resizing image +100MB..."
    qemu-img resize "$OUTPUT_IMAGE" +100M
    
    DISK_SIZE_BYTES=$(qemu-img info "$OUTPUT_IMAGE" --output json | jq -r '."virtual-size"')
    DISK_SIZE_SECTORS=$((DISK_SIZE_BYTES / 512))

    # We want a 32MB partition at the end. 32MB = 65536 sectors.
    START_SECTOR=$((DISK_SIZE_SECTORS - 65536 - 2048)) # Extra buffer
    END_SECTOR=$((DISK_SIZE_SECTORS - 2048))
fi

# 3. Use guestfish to add a new partition and write random data
echo "Creating partition and writing 1MB random data..."
# We use guestfish to:
# - Add a primary partition at the end of the disk
# - The partition will be roughly 32MB (or 100MB for --new)
# - Write 1MB of random data to it

# Generate 1MB of random data locally first to calculate checksum
RANDOM_DATA_FILE="$(mktemp)"
head -c 1048576 /dev/urandom > "$RANDOM_DATA_FILE"
MD5_SUM=$(md5sum "$RANDOM_DATA_FILE" | awk '{print $1}')
echo "$MD5_SUM" > "${OUTPUT_IMAGE}.md5"
echo "Expected MD5: $MD5_SUM"

# Use guestfish to create the partition and upload the data
guestfish -a "$OUTPUT_IMAGE" <<EOF
run
# Find the last partition end offset to start the new one
# Or just use the whole remaining space.
# We'll use 'part-add' which takes start sector and end sector.
# Since we resized by 100MB, we can safely add a 32MB partition.
# Let's use 'part-disk' or similar if we want to be simple, but we want to KEEP existing partitions.

# Get current partitions
list-partitions
# Add a new partition. 0 means auto-align. -1 means end of disk.
# We'll try to find a safe range. 
# Better: use 'part-add' with byte offsets if possible, or just 'part-add /dev/sda primary -32M -1' if guestfish supports it.
# Actually, guestfish part-add uses sector numbers.

# Let's use a simpler approach: create a new partition at the end.
# We'll use sfdisk style if possible or just guess the last sector.
# Even better: use 'part-add' with sector numbers calculated from 'blockdev-getsize64'.

# Let's get the disk size in 512-byte sectors
# Total size of the disk
part-init /dev/sda mbr
part-add /dev/sda p $START_SECTOR $END_SECTOR
# Identify the new partition (usually it's the last one)
EOF

# Find the new partition name
NEW_PART=$(guestfish -a "$OUTPUT_IMAGE" <<EOF
run
list-partitions | tail -n 1
EOF
)

echo "New partition: $NEW_PART"

# Write the random data to the start of the partition
guestfish -a "$OUTPUT_IMAGE" <<EOF
run
upload "$RANDOM_DATA_FILE" "$NEW_PART"
EOF

rm "$RANDOM_DATA_FILE"

echo "Test image prepared successfully."
