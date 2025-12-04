#!/bin/bash
# 建立一個目錄來存放設定檔
mkdir cloud_init_config
cd cloud_init_config

UUID=$(uuidgen)

# 建立 meta-data 檔案 (至少包含 instance-id)
cat <<EOF > meta-data
instance-id: test-clonezilla-vm-$UUID
local-hostname: restored-vm
EOF

# 建立 user-data 檔案 (這就是您的驗證腳本)
# 確保第一行是 #cloud-config 或 #!/bin/bash 來告訴 cloud-init 如何解析
cat <<EOF > user-data
#cloud-config
users:
  - name: user
    passwd: \$6\$rounds=4096\$vh.Uh1TE8PdKhShg\$09s3YBUsBbwgEX0dbYm/RpX1fFkynxy2j4xyHLbAiMuzghdVTybAcvPhM5R18Agp.Omv7vzemBXR5AiDZvQqi.
    lock_passwd: false
    groups: sudo, admin
    shell: /bin/bash
    ssh_pwauth: True
    chpasswd: { expire: False }
    sudo: ALL=(ALL) NOPASSWD:ALL
#    ssh_authorized_keys:
#      - sk-ecdsa-sha2-nistp256@openssh.com AAAAInNrLWVjZHNhLXNoYTItbmlzdHAyNTZAb3BlbnNzaC5jb20AAAAIbmlzdHAyNTYAAABBBOX+Ey0IIW5VLEwv+ICverplzkkASl5cmti+21kEzv214Ubv8j9QuYNNJ1avAiSbvVVbViYXdpqTOqg8yCb9sEMAAAAEc3NoOg== thomas@debian-lab
runcmd:
  - echo "Cloud-init started successfully!"
  - sh -c "echo 'Verification finished at $(date)'"
  - sh -c "echo 'Verification finished at $(date)'"
  - sh -c "echo 'Verification finished at $(date)'"
  - sh -c "echo 'Verification finished at $(date)'"
  - echo "Cloud-init started successfully!" > /tmp/cloud_init_status.txt
  - echo "Running verification script..." >> /tmp/cloud_init_status.txt
  - touch /tmp/verification_complete
  - sh -c "echo 'Verification finished at $(date)' >> /tmp/cloud_init_status.txt"
  - poweroff
EOF

# 建立空的 network-config 檔案 (使用 DHCP 的話可以留空)
touch network-config


# 建立 ISO 映像檔
#
# 使用 genisoimage 或 mkisofs 工具來建立 ISO
# 確保安裝了這些工具 (例如在 Ubuntu 上可以使用 sudo apt-get install genisoimage)
genisoimage -output cidata.iso -volid cidata -rational-rock -joliet user-data meta-data network-config
echo "Cloud-init ISO (cidata.iso) has been created successfully."


