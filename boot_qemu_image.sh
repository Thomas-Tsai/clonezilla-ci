#!/bin/bash

image_path="qemu/debian.qcow2"
if [[ -n "$1" ]]; then
  image_path="$1"
fi
qemu-system-x86_64 \
  -enable-kvm -m 4096 -cpu host \
  -drive file=${image_path},if=virtio,format=qcow2 \
  -nic user,hostfwd=tcp::2222-:22 \
#  -display none -serial mon:stdio
