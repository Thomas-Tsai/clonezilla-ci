#!/bin/bash

# This script prepares a cloud-init ISO image (cidata.iso) containing
# the necessary configuration files to be used for OS validation.

# Create a directory to hold the configuration files.
mkdir -p cloud_init_config
cd cloud_init_config

# Generate a unique UUID for the instance ID.
UUID=$(uuidgen)

# --- Create the meta-data file ---
# This file provides basic metadata about the instance.
# At a minimum, it must contain a unique instance-id.
cat <<EOF > meta-data
instance-id: test-clonezilla-vm-$UUID
local-hostname: restored-vm
EOF

# --- Create the user-data file ---
# This is your main configuration file, processed by cloud-init.
# The first line must be #cloud-config to indicate the format.
cat <<EOF > user-data
#cloud-config

# Configure users. This example sets up a user named 'user'.
users:
  - name: user
    # 'live' is the password, encrypted.
    passwd: \$6\$rounds=4096\$vh.Uh1TE8PdKhShg\$09s3YBUsBbwgEX0dbYm/RpX1fFkynxy2j4xyHLbAiMuzghdVTybAcvPhM5R18Agp.Omv7vzemBXR5AiDZvQqi.
    lock_passwd: false
    groups: sudo, admin
    shell: /bin/bash
    ssh_pwauth: True
    chpasswd: { expire: False }
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - sk-ecdsa-sha2-nistp256@openssh.com AAAAInNrLWVjZHNhLXNoYTItbmlzdHAyNTZAb3BlbnNzaC5jb20AAAAIbmlzdHAyNTYAAABBBOX+Ey0IIW5VLEwv+ICverplzkkASl5cmti+21kEzv214Ubv8j9QuYNNJ1avAiSbvVVbViYXdpqTOqg8yCb9sEMAAAAEc3NoOg== t@debian-lab

# Commands to run during the final boot stage.
runcmd:
  - echo "Cloud-init started successfully!"
  - sh -c "echo 'Verification finished at $(date)'"
  - echo "Cloud-init started successfully!" > /tmp/cloud_init_status.txt
  - echo "Running verification script..." >> /tmp/cloud_init_status.txt
  - touch /tmp/verification_complete
  - sh -c "echo 'Verification finished at $(date)' >> /tmp/cloud_init_status.txt"
  # This is the keyword that the validateOS.sh script looks for.
  - sh -c "echo 'ReStOrE VM Is DoNe!'"
  # Power off the VM automatically after the script runs.
  #- poweroff
EOF

# --- Create the network-config file ---
# An empty network-config file tells cloud-init to use DHCP,
# which is the default behavior if the file is absent or empty.
touch network-config


# --- Create the ISO image ---
# Use genisoimage (or mkisofs) to package the configuration files
# into a bootable ISO image.
# Ensure you have this tool installed (e.g., sudo apt-get install genisoimage).
genisoimage -output debugcidata.iso -volid cidata -rational-rock -joliet user-data meta-data network-config

echo "Cloud-init ISO (debugcidata.iso) has been created successfully in the cloud_init_config directory."
