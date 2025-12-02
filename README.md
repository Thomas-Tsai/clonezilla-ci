# Clonezilla CI Automation Tools

This project provides a suite of bash scripts to automate the use of Clonezilla within a QEMU virtual environment. It is designed to facilitate Continuous Integration (CI) workflows, such as automated disk imaging, restoration, and testing.

## Prerequisites

Before using these scripts, ensure the following dependencies are installed on your system:
- **QEMU/KVM**: `qemu-system-x86_64` must be installed and configured. KVM is recommended for performance.
- **libguestfs-tools**: The `virt-make-fs` command is required by the `clonezilla_zip2qcow.sh` script.
- **unzip**: Required for extracting Clonezilla live distributions.

## Directory Structure

- `isos/`: Place your downloaded ISO files here (e.g., Clonezilla, Debian).
- `qemu/`: Stores QEMU disk images (`.qcow2`), such as the Debian base image and restoration targets.
- `partimag/`: Default shared directory for Clonezilla to find and store disk images. This is shared into the VM via 9P.
- `dev/`: Contains development notes, logs, and test data.

## Scripts

Here is a breakdown of the available scripts and their functions.

### `qemu_clonezilla_ci_run.sh`

This is the primary script for running fully automated, non-interactive Clonezilla tasks. It boots a Clonezilla "live" environment directly from kernel and initrd files, mounts a shared directory for images, and executes a specified command.

**Features:**
- Boots a QCOW2-based Clonezilla live medium.
- Supports multiple virtual hard disks.
- Executes commands or shell scripts within the running Clonezilla environment.
- Shares a local directory (`partimag/` by default) into the VM for Clonezilla images.
- Can be run in non-interactive (for CI) or interactive modes (for debugging).
- Supports overriding kernel boot parameters.

**Usage:**
```bash
# Example: Run a command to restore a disk
./qemu_clonezilla_ci_run.sh \
  --disk qemu/restore.qcow2 \
  --live isos/clonezilla-live-20251124-resolute-amd64/clonezilla-live-20251124-resolute-amd64.qcow2 \
  --kernel isos/clonezilla-live-20251124-resolute-amd64/vmlinuz \
  --initrd isos/clonezilla-live-20251124-resolute-amd64/initrd.img \
  --cmd "sudo /usr/sbin/ocs-sr -g auto -p poweroff restoredisk my-image sda" \
  --image ./partimag

# Example: Run a local script inside Clonezilla
./qemu_clonezilla_ci_run.sh \
  --disk qemu/restore.qcow2 \
  --live isos/clonezilla-live-20251124-resolute-amd64/clonezilla-live-20251124-resolute-amd64.qcow2 \
  --kernel isos/clonezilla-live-20251124-resolute-amd64/vmlinuz \
  --initrd isos/clonezilla-live-20251124-resolute-amd64/initrd.img \
  --cmdpath ./partimag/testScripts/test001.sh \
  --image ./partimag
```

### `clonezilla_zip2qcow.sh`

This utility converts an official Clonezilla live ZIP distribution into the format required by `qemu_clonezilla_ci_run.sh`. It extracts the `live` filesystem, packages it into a bootable QCOW2 disk image, and copies the `vmlinuz` and `initrd.img` files alongside it.

**Usage:**
```bash
# Basic usage
./clonezilla_zip2qcow.sh isos/clonezilla-live-20251124-resolute-amd64.zip -o isos/

# This will create a directory:
# isos/clonezilla-live-20251124-resolute-amd64/
# containing:
# - clonezilla-live-20251124-resolute-amd64.qcow2
# - vmlinuz
# - initrd.img
```

### `clonezilla-boot.sh`

A simple wrapper script to quickly boot a QEMU virtual machine from a Clonezilla ISO file. It attaches a disk image and the `partimag` directory for manual operations.

**Usage:**
```bash
# Boot with default ISO and disk image
./clonezilla-boot.sh

# Boot with a specific ISO and disk image
./clonezilla-boot.sh isos/my-clonezilla.iso qemu/my-disk.qcow2
```

### `debian-install.sh`

A convenience script to install a fresh Debian OS onto a QCOW2 image. This is useful for creating base images that can later be used as targets for Clonezilla.

**Usage:**
```bash
# The script will create/use qemu/debian.qcow2 and boot from isos/debian-13.2.0-amd64-netinst.iso
./debian-install.sh
```

### `boot_qemu_image.sh`

The most basic script. It boots a QEMU VM directly from a specified QCOW2 disk image.

**Usage:**
```bash
# Boot the default debian image
./boot_qemu_image.sh

# Boot a specific image
./boot_qemu_image.sh qemu/my-other-disk.qcow2
```
