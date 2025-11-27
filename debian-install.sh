#!/bin/bash
# 腳本用途：使用 QEMU 安裝 Debian 作業系統
# 準備工作：確保已下載 Debian 安裝映像並放置於 isos/ 目錄
iso_path="isos/debian-13.2.0-amd64-netinst.iso"
debian_image="qemu/debian.qcow2"
# 啟動安裝流程
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

