#!/bin/bash

# This script downloads cloud images to their respective directories.
# IMPORTANT: The AI agent cannot automatically find stable, direct download URLs for cloud images.
# You MUST manually replace the "PLACEHOLDER_..." URLs below with the actual direct download links.
#
# Usage: ./download_cloud_images.sh

set -euo pipefail

BASE_DIR="$(dirname "$(realpath "$0")")"

echo "Starting cloud image download script..."

# --- AlmaLinux ---
ALMALINUX_URL="https://repo.almalinux.org/almalinux/10/cloud/x86_64/images/AlmaLinux-10-OpenNebula-latest.x86_64.qcow2"
ALMALINUX_DIR="${BASE_DIR}/almalinux"
ALMALINUX_FILENAME="almalinux-cloud.qcow2" # You might want to adjust filename based on actual URL
echo "Processing AlmaLinux..."
if [[ "$ALMALINUX_URL" == "PLACEHOLDER_ALMALINUX_QCOW2_URL" ]]; then
    echo "  AlmaLinux URL is a placeholder. Please manually find the direct QCOW2 download URL and update this script."
else
    mkdir -p "${ALMALINUX_DIR}"
    echo "  Downloading AlmaLinux from ${ALMALINUX_URL}..."
    curl -L --fail --output "${ALMALINUX_DIR}/${ALMALINUX_FILENAME}" "${ALMALINUX_URL}" || { echo "  AlmaLinux download failed."; exit 1; }
    echo "  AlmaLinux image downloaded to ${ALMALINUX_DIR}/${ALMALINUX_FILENAME}"
fi

echo ""

# --- Debian ---
DEBIAN_URL="https://cdimage.debian.org/images/cloud/trixie/latest/debian-13-generic-arm64.qcow2"
DEBIAN_DIR="${BASE_DIR}/debian"
DEBIAN_FILENAME="debian-cloud.qcow2" # You might want to adjust filename based on actual URL
echo "Processing Debian..."
if [[ "$DEBIAN_URL" == "PLACEHOLDER_DEBIAN_QCOW2_URL" ]]; then
    echo "  Debian URL is a placeholder. Please manually find the direct QCOW2 download URL and update this script."
else
    mkdir -p "${DEBIAN_DIR}"
    echo "  Downloading Debian from ${DEBIAN_URL}..."
    curl -L --fail --output "${DEBIAN_DIR}/${DEBIAN_FILENAME}" "${DEBIAN_URL}" || { echo "  Debian download failed."; exit 1; }
    echo "  Debian image downloaded to ${DEBIAN_DIR}/${DEBIAN_FILENAME}"
fi

echo ""

# --- Fedora ---
FEDORA_URL="https://mirror.twds.com.tw/fedora/fedora/linux/releases/43/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-43-1.6.x86_64.qcow2"
FEDORA_DIR="${BASE_DIR}/fedora"
FEDORA_FILENAME="fedora-cloud.qcow2" # You might want to adjust filename based on actual URL
echo "Processing Fedora..."
if [[ "$FEDORA_URL" == "PLACEHOLDER_FEDORA_QCOW2_URL" ]]; then
    echo "  Fedora URL is a placeholder. Please manually find the direct QCOW2 download URL and update this script."
else
    mkdir -p "${FEDORA_DIR}"
    echo "  Downloading Fedora from ${FEDORA_URL}..."
    curl -L --fail --output "${FEDORA_DIR}/${FEDORA_FILENAME}" "${FEDORA_URL}" || { echo "  Fedora download failed."; exit 1; }
    echo "  Fedora image downloaded to ${FEDORA_DIR}/${FEDORA_FILENAME}"
fi

echo ""

# --- Ubuntu ---
UBUNTU_URL="https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img"
UBUNTU_DIR="${BASE_DIR}/ubuntu"
UBUNTU_FILENAME="ubuntu-cloud.qcow2" # You might want to adjust filename based on actual URL
echo "Processing Ubuntu..."
if [[ "$UBUNTU_URL" == "PLACEHOLDER_UBUNTU_QCOW2_URL" ]]; then
    echo "  Ubuntu URL is a placeholder. Please manually find the direct QCOW2 download URL and update this script."
else
    mkdir -p "${UBUNTU_DIR}"
    echo "  Downloading Ubuntu from ${UBUNTU_URL}..."
    curl -L --fail --output "${UBUNTU_DIR}/${UBUNTU_FILENAME}" "${UBUNTU_URL}" || { echo "  Ubuntu download failed."; exit 1; }
    echo "  Ubuntu image downloaded to ${UBUNTU_DIR}/${UBUNTU_FILENAME}"
fi

echo ""

# --- Windows ---
# Finding direct, stable QCOW2 download links for Windows is generally more complex
# due to licensing and requiring authenticated downloads.
# You will likely need to download Windows images manually from official Microsoft channels
# or convert a VHD/VHDX image to QCOW2 yourself.
WINDOWS_URL="PLACEHOLDER_WINDOWS_QCOW2_URL"
WINDOWS_DIR="${BASE_DIR}/windows"
WINDOWS_FILENAME="windows-cloud.qcow2" # You might want to adjust filename based on actual URL
echo "Processing Windows..."
if [[ "$WINDOWS_URL" == "PLACEHOLDER_WINDOWS_QCOW2_URL" ]]; then
    echo "  Windows URL is a placeholder. Manual download and/or conversion is often required."
    echo "  Please manually find the direct QCOW2 download URL (if available) and update this script."
else
    mkdir -p "${WINDOWS_DIR}"
    echo "  Downloading Windows from ${WINDOWS_URL}..."
    curl -L --fail --output "${WINDOWS_DIR}/${WINDOWS_FILENAME}" "${WINDOWS_URL}" || { echo "  Windows download failed."; exit 1; }
    echo "  Windows image downloaded to ${WINDOWS_DIR}/${WINDOWS_FILENAME}"
fi

echo ""
echo "Script finished. Please review the output for any failed downloads or placeholder URLs."
