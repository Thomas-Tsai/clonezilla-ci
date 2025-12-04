# Clonezilla CI Automation Tools

This project provides a suite of bash scripts to automate the use of Clonezilla within a QEMU virtual environment. It is designed to facilitate Continuous Integration (CI) workflows, such as automated disk imaging, restoration, and testing.

## Prerequisites

Before using these scripts, ensure the following dependencies are installed on your system:
- **QEMU/KVM**: `qemu-system-x86_64` must be installed and configured. KVM is recommended for performance.
- **libguestfs-tools**: The `virt-make-fs` command is required by the `clonezilla_zip2qcow.sh` script.
- **unzip**: Required for extracting Clonezilla live distributions.
- **curl**, **wget**: Required for auto-download features in `clonezilla-boot.sh` and `debian-install.sh`.
- **genisoimage** (or `mkisofs`): Required by `dev/cloudinit/prepareiso.sh` to create cloud-init ISOs.

## Directory Structure

- `isos/`: Place your downloaded ISO files here (e.g., Clonezilla, Debian). This is also the default download location for auto-downloaded ISOs.
- `qemu/`: Stores QEMU disk images (`.qcow2`), such as the Debian base image and restoration targets.
- `partimag/`: Default shared directory for Clonezilla to find and store disk images. This is shared into the VM via 9P.
- `dev/`: Contains development notes, logs, and helper scripts.
  - `dev/cloudinit/`: Contains scripts for cloud-init ISO preparation.
  - `dev/ocscmd/`: Contains Clonezilla `ocs-sr` command scripts used by orchestration.

## Scripts

Here is a breakdown of the available scripts and their functions.

### `linux-clone-restore.sh`

This is an orchestration script that automates the full backup, restore, and validation cycle for a Linux distribution. It uses `clonezilla_zip2qcow.sh`, `qemu_clonezilla_ci_run.sh`, and `validateOS.sh` internally.

**Features:**
- Uses long options (`--zip`, `--tmpl`, `--image-name`, `-h`/`--help`).
- Validates argument existence for input files.
- Makes the Clonezilla image name configurable via `--image-name`.
- Generates temporary `ocs-sr` command scripts to dynamically set the image name.
- Returns 0 for success and 1 for failure.

**Workflow:**
1.  **Prepare Clonezilla Live Media**: Converts the provided Clonezilla ZIP to QCOW2 format.
2.  **Prepare Source Disk**: Copies the template QCOW2 image to be used as the source for backup.
3.  **Backup the Source Disk**: Uses Clonezilla to create a backup image of the source disk.
4.  **Restore to a New Disk**: Creates a new QCOW2 disk and restores the backup onto it.
5.  **Validate the Restored Disk**: Boots the restored disk with a cloud-init ISO to verify functionality.

**Usage:**
```bash
# Run a full cycle with default image name
./linux-clone-restore.sh \
  --zip ./isos/clonezilla-live-20251124-resolute-amd64.zip \
  --tmpl ./qemu/debian-sid-generic-amd64-daily-20250805-2195.qcow2

# Run a full cycle with a custom image name
./linux-clone-restore.sh \
  --zip ./isos/clonezilla-live-20251124-resolute-amd64.zip \
  --tmpl ./qemu/debian-sid-generic-amd64-daily-20250805-2195.qcow2 \
  --image-name "my-custom-image"

# Display help
./linux-clone-restore.sh --help
```

### `validateOS.sh`

This script boots a restored QCOW2 image with a cloud-init ISO to verify that the OS starts and runs a cloud-init script successfully. It runs non-interactively and checks for a success keyword in the output log.

**Features:**
- Uses long options (`--iso`, `--disk`, `--timeout`, `--keeplog`, `-h`/`--help`).
- Validates argument existence.
- Implements an intelligent timeout mechanism using background processes and `wait -n`.
- Allows keeping log files for debugging with `--keeplog`.
- Returns 0 for success and 1 for failure.

**Usage:**
```bash
# Validate a restored disk image with a cloud-init ISO
./validateOS.sh --iso dev/cloudinit/cloud_init_config/cidata.iso --disk ./qemu/restore.qcow2

# Validate with a longer timeout and keep the log file
./validateOS.sh --iso dev/cloudinit/cloud_init_config/cidata.iso --disk ./qemu/restore.qcow2 --timeout 600 --keeplog

# Display help
./validateOS.sh --help
```

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
  --kernel isos/clonezilla-live-20251124-resolute-amd64/clonezilla-live-20251124-resolute-amd64-vmlinuz \
  --initrd isos/clonezilla-live-20251124-resolute-amd64/clonezilla-live-20251124-resolute-amd64-initrd.img \
  --cmd "sudo /usr/sbin/ocs-sr -g auto -p poweroff restoredisk my-image sda" \
  --image ./partimag

# Example: Run a local script inside Clonezilla
./qemu_clonezilla_ci_run.sh \
  --disk qemu/restore.qcow2 \
  --live isos/clonezilla-live-20251124-resolute-amd64/clonezilla-live-20251124-resolute-amd64.qcow2 \
  --kernel isos/clonezilla-live-20251124-resolute-amd64/clonezilla-live-20251124-resolute-amd64-vmlinuz \
  --initrd isos/clonezilla-live-20251124-resolute-amd64/clonezilla-live-20251124-resolute-amd64-initrd.img \
  --cmdpath ./dev/ocscmd/clone-first-disk.sh \
  --image ./partimag
```

### `clonezilla_zip2qcow.sh`

This utility converts an official Clonezilla live ZIP distribution into a QCOW2 disk image, and extracts the kernel and initrd files. It uses long options for clarity, provides a help message, validates arguments, and names output files based on the ZIP\'s base name.

**Usage:**
```bash
# Basic usage, outputs to a directory named after the zip in the current folder
./clonezilla_zip2qcow.sh --zip ./isos/clonezilla-live-3.1.2-9-amd64.zip

# Specify output directory and force overwrite
./clonezilla_zip2qcow.sh --zip ./isos/clonezilla-live-3.1.2-9-amd64.zip --output ./isos/ --force

# Display help
./clonezilla_zip2qcow.sh --help
```

### `clonezilla-boot.sh`

This script boots a QEMU VM from a Clonezilla Live ISO. If `--iso` is not provided, it attempts to automatically download the latest stable AMD64 version from SourceForge. It attaches a disk image and a shared directory (`partimag/`) for manual operations.

**Features:**
- Uses long options (`--iso`, `--disk`, `--partimag`, `-h`/`--help`).
- Validates argument existence.
- **Auto-downloads** the latest stable AMD64 Clonezilla Live ISO if `--iso` is omitted.

**Usage:**
```bash
# Boot with auto-downloaded Clonezilla ISO and default disk
./clonezilla-boot.sh --disk ./qemu/my-disk.qcow2

# Boot with a specific ISO and disk image
./clonezilla-boot.sh --iso ./isos/my-clonezilla.iso --disk ./qemu/my-disk.qcow2

# Display help
./clonezilla-boot.sh --help
```

### `boot.sh` (Formerly `boot_qemu_image.sh`)

A simple script to quickly boot a QEMU virtual machine from a specified QCOW2 disk image.

**Features:**
- Uses long options (`--disk`, `-m`/`--mem`, `--smp`, `-h`/`--help`).
- Validates argument existence.

**Usage:**
```bash
# Boot the default debian image
./boot.sh

# Boot a specific image with 2GB RAM
./boot.sh --disk ./qemu/my-other-disk.qcow2 -m 2048

# Display help
./boot.sh --help
```

### `debian-install.sh`

This script starts a QEMU VM to install Debian from a netinst ISO onto a QCOW2 disk image. If `--iso` is not provided, it attempts to automatically download the latest stable AMD64 netinst ISO from Debian\'s official mirrors.

**Features:**
- Uses long options (`--iso`, `--disk`, `-m`/`--mem`, `--smp`, `-h`/`--help`).
- Validates argument existence.
- **Auto-downloads** the latest stable AMD64 Debian netinst ISO if `--iso` is omitted.

**Usage:**
```bash
# Install Debian with auto-downloaded ISO onto a new disk image
./debian-install.sh --disk ./qemu/new-debian.qcow2

# Install Debian with a specific ISO, 2GB RAM, and 4 CPU cores
./debian-install.sh --iso ./isos/debian-testing.iso --disk ./qemu/testing.qcow2 -m 2048 --smp 4

# Display help
./debian-install.sh --help
```