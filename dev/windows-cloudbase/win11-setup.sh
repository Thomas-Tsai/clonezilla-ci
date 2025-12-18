# virtio-win-0.1.285.iso	Win11_25H2_EnglishInternational_x64.iso  win11.qcow2 Win11_25H2_Chinese_Traditional_x64.iso

qemu-system-x86_64 -m 6G -cpu host -smp cores=4 -accel kvm -M q35,usb=on \
-drive file=win11.qcow2,format=qcow2,if=virtio \
-drive file=Win11_25H2_Chinese_Traditional_x64.iso,media=cdrom \
-drive file=virtio-win-0.1.285.iso,media=cdrom \
-device usb-tablet -nic user,model=virtio-net-pci -boot menu=on

