# Clonezilla CI Automation Tools

This project provides a suite of bash scripts to automate the use of Clonezilla within a QEMU virtual environment. It is designed to facilitate Continuous Integration (CI) workflows, such as automated disk imaging, restoration, and testing.

## Prerequisites

Before using these scripts, ensure the following dependencies are installed on your Debian-based system:

```bash
sudo apt update
sudo apt install qemu-utils qemu-system-x86 guestfs-tools unzip curl wget uuid-runtime genisoimage guestfish guestmount
```

Here's a breakdown of what each package provides:
- **`qemu-utils`**: Provides `qemu-img` for disk image manipulation.
- **`qemu-system-x86`**: Provides `qemu-system-x86_64` for QEMU virtual machine emulation.
- **`guestfs-tools`**: Provides `guestfish`, `guestmount`, `guestunmount`, and `virt-make-fs` for guest filesystem access and manipulation.
- **`unzip`**: For extracting `.zip` archives.
- **`curl`**: For transferring data with URLs.
- **`wget`**: For retrieving files from the web.
- **`uuid-runtime`**: Provides `uuidgen` for generating unique identifiers.
- **`genisoimage`**: For creating ISO-9660 filesystem images.

## Directory Structure

- `isos/`: Place your downloaded ISO files here (e.g., Clonezilla, Debian). This is also the default download location for auto-downloaded ISOs.
- `qemu/`: Stores QEMU disk images (`.qcow2`), such as the Debian base image and restoration targets.
- `partimag/`: Default shared directory for Clonezilla to find and store disk images. This is shared into the VM via 9P.
- `zip/`: Stores Clonezilla Live ZIP distributions.
- `dev/`: Contains development notes, logs, and helper scripts.
  - `dev/cloudinit/`: Contains scripts for cloud-init ISO preparation.
  - `dev/ocscmd/`: Contains Clonezilla `ocs-sr` command scripts used by orchestration.

## Scripts

Here is a breakdown of the available scripts and their functions.

### `data-clone-restore.sh`

This orchestration script is designed for end-to-end testing of filesystem backup and restoration. It creates a temporary disk image, formats it with a specified filesystem, copies a local data directory into it, backs up the disk using Clonezilla, restores it to a new disk, and finally verifies the integrity of the restored data by comparing checksums.

**Features:**
- Uses long options (`--zip`, `--data`, `--fs`, `--size`, `--partimag`, `--keep-temp`, `-h`/`--help`).
- Supports a wide range of filesystems (e.g., ext2/3/4, btrfs, xfs, ntfs, vfat).
- Calculates MD5 checksums of the source data before backup.
- Verifies restored data efficiently using `guestmount` to avoid full data extraction.
- Allows keeping the temporary directory for debugging with `--keep-temp`.
- Returns 0 for success and 1 for failure.

**Workflow:**
1.  **Prepare Clonezilla Live Media**: Converts the provided Clonezilla ZIP to QCOW2 format.
2.  **Prepare Source Disk**: Creates a new QCOW2 disk, partitions and formats it, and copies the source data directory into it.
3.  **Calculate Checksums**: Generates an MD5 checksum file for all files in the source data.
4.  **Backup the Source Disk**: Uses Clonezilla to create a backup image of the data disk.
5.  **Restore to a New Disk**: Creates a new, larger QCOW2 disk and restores the backup onto it.
6.  **Verify the Restored Disk**: Mounts the restored disk using `guestmount` and verifies the MD5 checksums of the files against the pre-calculated checksum file.

**Usage:**
```bash
# Run a full data backup/restore cycle with a directory and ext4 filesystem
./data-clone-restore.sh \
  --zip ./isos/clonezilla-live-stable-amd64.zip \
  --data ./my-important-data/ \
  --fs ext4

# Run with a different filesystem and keep the temp files for debugging
./data-clone-restore.sh \
  --zip ./isos/clonezilla-live-stable-amd64.zip \
  --data ./my-xfs-data/ \
  --fs xfs \
  --keep-temp

# Display help
./data-clone-restore.sh --help
```

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

This is the primary script for running fully automated, non-interactive Clonezilla tasks. It can prepare boot media directly from a Clonezilla ZIP file or use pre-extracted files. It boots a Clonezilla "live" environment, mounts a shared directory for images, and executes a specified command.

**Usage:**
```
Usage: ./qemu_clonezilla_ci_run.sh [OPTIONS]
Run a fully automated, non-interactive Clonezilla task in a QEMU VM.

Boot Media Options (choose one method):
  1. From ZIP (recommended):
     --zip <path>              Path to the Clonezilla live ZIP file. Automates the next 4 options.
     --zip-output <dir>      Directory to store the extracted QCOW2, kernel, and initrd. (Default: ./zip)
     --zip-size <size>         Size of the live QCOW2 image to create. (Default: 2G)
     --zip-force               Force re-extraction of the ZIP file if output files already exist.

  2. From extracted files:
     --live <path>             Path to the Clonezilla live QCOW2 media.
     --kernel <path>           Path to the kernel file (e.g., vmlinuz).
     --initrd <path>           Path to the initrd file.

VM and Task Options:
  --disk <path>           Path to a virtual disk image (.qcow2). Can be specified multiple times.
  --image <path>          Path to the shared directory for Clonezilla images (default: ./partimag).
  --cmd <command>         Command string to execute inside Clonezilla (e.g., 'sudo ocs-sr ...').
  --cmdpath <path>        Path to a script file to execute inside Clonezilla.
  --append-args <args>    A string of custom kernel append arguments to override the default.
  --append-args-file <path> Path to a file containing custom kernel append arguments.
  --log-dir <path>        Directory to store log files (default: ./logs).
  -i, --interactive       Enable interactive mode (QEMU will not power off, output to terminal).
  -h, --help              Display this help message and exit.

Example (Backup with ZIP):
  ./qemu_clonezilla_ci_run.sh \
    --disk ./qemu/source.qcow2 \
    --zip ./zip/clonezilla-live-3.1.2-9-amd64.zip \
    --cmdpath ./dev/ocscmd/clone-first-disk.sh \
    --image ./partimag

Example (Restore with extracted files):
  ./qemu_clonezilla_ci_run.sh \
    --disk ./qemu/restore.qcow2 \
    --live ./isos/clonezilla.qcow2 \
    --kernel ./isos/vmlinuz \
    --initrd ./isos/initrd.img \
    --cmd 'sudo /usr/sbin/ocs-sr -g auto -e1 auto -e2 -c -r -j2 -p poweroff restoredisk my-img-name sda' \
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
