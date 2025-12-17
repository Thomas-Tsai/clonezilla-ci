#!/bin/bash

CONFIG_DIR="cloud_init_config"
METADATA_PATH="${CONFIG_DIR}/openstack/latest"
ISO_FILENAME="win11_cidata.iso"

rm -rf "${CONFIG_DIR}"
mkdir -p "${METADATA_PATH}"

UUID=$(uuidgen)

cat <<EOF > "${METADATA_PATH}/meta_data.json"
{
  "instance-id": "win11-ci-restore-test-$UUID",
  "local-hostname": "win11-restore-vm"
}
EOF

cat <<EOF > "${METADATA_PATH}/user_data"
#cloud-config

users:
  - name: ci-user
    passwd: MySecurePassw0rd1!
    groups: administrators
    lock_passwd: false
    
runcmd:
  - 'powershell -ExecutionPolicy Bypass -Command "Set-TimeZone -Name ''Taipei Standard Time''"'
  - 'powershell -ExecutionPolicy Bypass -Command "echo ReStOrE > C:\Verification_Flag.txt"'
  - 'powershell -ExecutionPolicy Bypass -Command "''ReStOrE VM Is DoNe!'' | Out-File -FilePath \\.\COM1 -Encoding ascii"'
  - 'shutdown /s /t 10'
  
hostname: WIN11-CI-TEST
EOF

# Use -V config-2 to match Cloudbase-Init default search label
genisoimage -output "${ISO_FILENAME}" -V config-2 -r -J "${CONFIG_DIR}"

echo "Done: ${ISO_FILENAME} created with label 'config-2'"
