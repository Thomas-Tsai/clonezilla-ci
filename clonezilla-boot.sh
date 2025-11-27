#!/bin/bash
# 腳本用途：使用 QEMU 啟動 Clonezilla 以備份或還原磁碟映像
# 準備工作：確保已下載 Clonezilla 映像並放置於 isos/ 目錄

# Default paths (can be overridden by positional arguments)

# Usage: $0 [iso_path] [qcow2_image]
#   iso_path      Path to Clonezilla ISO (default: isos/clonezilla-live-3.3.0-33-amd64.iso)
#   qcow2_image   Path to QCOW2 image (default: qemu/debian.qcow2)
#   Use -h or --help to display this message.

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  echo -e "Usage: $0 [iso_path] [qcow2_image]\n\n"
  echo "   iso_path      Path to Clonezilla ISO (default: isos/clonezilla-live-3.3.0-33-amd64.iso)"
  echo "   qcow2_image   Path to QCOW2 image (default: qemu/debian.qcow2)"
  exit 0
fi
iso_path="isos/clonezilla-live-3.3.0-33-amd64.iso"
# Default QCOW2 image
debian_image="qemu/debian.qcow2"
# Directory for Clonezilla images
partimag_path="partimag"

# Override defaults if arguments are provided
if [[ -n "$1" ]]; then
  iso_path="$1"
fi
if [[ -n "$2" ]]; then
  debian_image="$2"
fi


# 啟動 QEMU，使用 9p 共享
qemu-system-x86_64 \
  -enable-kvm -m 4096 -cpu host \
  -drive file=${debian_image},if=virtio,format=qcow2 \
  -cdrom ${iso_path} \
  -boot d \
  -fsdev local,id=hostshare,path=${partimag_path},security_model=mapped-xattr \
  -device virtio-9p-pci,fsdev=hostshare,mount_tag=hostshare \
  -nic user,hostfwd=tcp::2222-:22 \
  -display gtk \
  -serial mon:stdio <<'QEMU_EOF'
# 這段文字會被送到 QEMU 的「monitor / serial」介面
# 只要 guest 已經啟動到可以執行 shell（Clonezilla boot 完成後的 console），
# 下面的指令就會在 guest 裡跑。

# 1) 建立掛載點
mkdir -p /home/partimag

# 2) 掛載 9p（mount_tag 必須與上面的 -device 參數相同）
mount -t 9p -o trans=virtio,version=9p2000.L hostshare /home/partimag

# 3) 顯示提示，讓使用者在圖形介面中自行操作 Clonezilla
echo "=== 9p 已掛載於 /home/partimag ==="
QEMU_EOF
