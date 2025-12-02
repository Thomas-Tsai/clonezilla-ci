#!/bin/bash
# Script purpose: Install Debian OS using QEMU
# Prerequisites: Ensure Debian installation image is downloaded and placed in the isos/ directory
iso_path="isos/debian-13.2.0-amd64-netinst.iso"
debian_image="qemu/debian.qcow2"
# Start installation process
qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -smp 2 \
  -cpu host \
  -drive file=${debian_image},if=virtio,format=qcow2 \
  -cdrom ${iso_path} \
  -boot d \
  -nic user,hostfwd=tcp::2222-:22 \
  -display gtk
#  -display none \
#  -serial mon:stdio

