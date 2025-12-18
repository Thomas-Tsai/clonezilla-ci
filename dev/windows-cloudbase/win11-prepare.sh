qemu-system-x86_64 -m 6G -cpu host -smp cores=4 -accel kvm -M q35,usb=on \
-drive file=win11.qcow2,format=qcow2,if=virtio \
-drive file=virtio-win-0.1.285.iso,media=cdrom \
-device usb-tablet \
-netdev user,id=net0,hostfwd=tcp::13389-:3389 \
-device virtio-net-pci,netdev=net0 \
-fsdev local,id=my_share,path=/home/thomas/Downloads/windows/cloudinit,security_model=none \
-device virtio-9p-pci,fsdev=my_share,mount_tag=qemu_share

