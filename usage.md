# Clonezilla CI Automation Tools

This project can be run inside a Docker container, which is the recommended method as it bundles all dependencies.

## Running with Docker

### 1. Build the Image

First, build the Docker image from the project root:
```bash
docker build -t clonezilla-ci .
```

### 2. Run the Scripts

To run any of the scripts, you use `docker run` and mount the necessary host directories as volumes. This ensures that the container can access required disk images, ISOs, and ZIP files, and that output artifacts (like logs and partimag backups) are saved to your host.

# Run the main test suite (`start.sh`)
```bash
docker run --rm -it \
  --device=/dev/kvm \
  -v ./dev/testData:/app/dev/testData \
  -v ./qemu/cloudimages:/app/qemu/cloudimages \
  -v ./isos:/app/isos \
  -v ./zip:/app/zip \
  -v ./partimag:/app/partimag \
  -v ./logs:/app/logs \
  clonezilla-ci --arch amd64
```
**Note:** The `--device=/dev/kvm` flag is for enabling KVM hardware acceleration on Linux hosts. It may not be needed or available on other operating systems.

**Example: Running an individual script (e.g., `clonezilla-boot.sh`)**
```bash
docker run --rm -it \
  --device=/dev/kvm \
  -v ./qemu:/app/qemu \
  -v ./isos:/app/isos \
  -v ./zip:/app/zip \
  clonezilla-ci ./clonezilla-boot.sh --disk /app/qemu/my-disk.qcow2



### CI Runner Sudo Configuration

For running scripts like `validate-fs.sh` directly on a CI runner (i.e., not inside the provided Docker container), passwordless `sudo` access is required for specific commands. This allows the scripts to perform system-level operations like loading kernel modules and managing block devices without manual intervention.

**Warning:** Modifying `sudoers` has significant security implications. Only grant permissions for the specific commands required by the scripts.

**Steps to Configure:**

1.  **Identify the CI runner user.** This is often `gitlab-runner`, `github-actions`, or `jenkins`.

2.  **Create a new `sudoers` configuration file.** It is best practice to add a new file rather than editing the main `/etc/sudoers` file. Use `visudo` to safely create and edit the file:
    ```bash
    sudo visudo -f /etc/sudoers.d/99-clonezilla-ci-runner
    ```

3.  **Add the necessary permissions.** Paste the following lines into the file, replacing `gitlab-runner` with your actual runner username if it's different.

    ```
    # Allow the CI runner to execute specific commands for clonezilla-ci
    # without a password prompt.
    gitlab-runner ALL=(ALL) NOPASSWD: /usr/sbin/modprobe, /sbin/modprobe
    gitlab-runner ALL=(ALL) NOPASSWD: /usr/bin/qemu-nbd, /sbin/qemu-nbd
    gitlab-runner ALL=(ALL) NOPASSWD: /usr/sbin/fsck.*, /sbin/fsck.*
    ```

4.  **Verify Command Paths:** The paths to the commands (`/usr/sbin/`, `/sbin/`, etc.) may differ on your system. Before adding them to the `sudoers` file, verify the correct path for each command using `which`:
    ```bash
    which modprobe
    which qemu-nbd
    which fsck.ext4
    ```
    Adjust the paths in the `sudoers` file to match the output of the `which` command. The example above includes common paths for Debian-based systems.

After saving the file, the CI runner will be able to execute the validation scripts that require elevated permissions.

---
The rest of the document describes the scripts and their options, which can be run inside the container as shown in the examples above.

This project provides a suite of bash scripts to automate the use of Clonezilla within a QEMU virtual environment. It is designed to facilitate Continuous Integration (CI) workflows, such as automated disk imaging, restoration, and testing.

## Prerequisites

Before using these scripts, ensure the following dependencies are installed on your Debian-based system:

```bash
sudo apt update
sudo apt install qemu-utils qemu-system-riscv64 qemu-system-arm64 qemu-system-x86 qemu-system-arm qemu-efi-aarch64 guestfs-tools unzip curl wget uuid-runtime genisoimage guestfish guestmount  e2fsprogs btrfs-progs xfsprogs ntfs-3g dosfstools exfatprogs bc
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

### `start.sh`

The main test runner script for the Clonezilla CI test suite. It orchestrates the execution of various OS and filesystem clone/restore tests using `shunit2`.

**Features:**
-   Supports specifying the Clonezilla Live ZIP file.
-   Allows selecting the target architecture (`amd64`, `arm64`, `riscv64`, etc.).
-   Automatically discovers and tests all available OS releases (Ubuntu, Debian, Fedora) for the selected architecture based on `qemu/cloudimages/cloud_images.conf`.
-   Provides a help message with `--help`.
-   Redirects detailed logs for each test to the `./logs/` directory.

**Usage:**
```bash
# Run the full test suite with default settings (uses internal Clonezilla ZIP, targets amd64)
./start.sh

# Run with a specific Clonezilla Live ZIP file
./start.sh --zip /path/to/your/clonezilla-live.zip

# Run tests for a specific architecture (e.g., arm64)
./start.sh --arch arm64

# Run with a specific ZIP and target architecture
./start.sh --zip /path/to/your/clonezilla-live.zip --arch arm64

# Display help message
./start.sh --help
```

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

### `liteserver.sh`

This script orchestrates a Clonezilla Lite Server test, setting up a server VM and client VM for network-based backup/restore operations. It handles the preparation of server and client Clonezilla Live media, virtual disks, and network configuration to simulate a Lite Server environment.

**Features:**
-   Supports separate Clonezilla Live ZIP files for the server (`--serverzip`) and client (`--clientzip`).
-   Automatically creates Copy-on-Write (COW) disk images for the server to preserve original templates.
-   Prepares corresponding empty disks for clients to restore onto.
-   Uses `qemu-clonezilla-ci-run.sh` internally for VM orchestration.
-   Allows custom commands or scripts to define server behavior.
-   Provides a help message (`-h`/`--help`).

**Usage:**
```bash
# Run a Lite Server test with separate server and client Clonezilla ZIPs
./liteserver.sh \
  --serverzip ./zip/clonezilla-live-server.zip \
  --clientzip ./zip/clonezilla-live-client.zip \
  --disk ./qemu/fedora-base.qcow2 \
  --cmd "ocs-live-feed-img -g auto -e1 auto -e2 -r -x -j2 -k0 -sc0 -p true -md multicast --clients-to-wait 1 savedisk fedora-image vda"

# Run a Lite Server test, defaulting client ZIP to server ZIP, with a command script
./liteserver.sh \
  --serverzip ./zip/clonezilla-live-3.3.0-33-amd64.zip \
  --disk ./qemu/debian-13-amd64.qcow2 \
  --cmdpath ./dev/ocscmd/lite-bt.sh

# Display help
./liteserver.sh --help
```

### `os-clone-restore.sh`

This is an orchestration script that automates the full backup, restore, and validation cycle for a Linux distribution. It uses `clonezilla-zip2qcow.sh`, `qemu-clonezilla-ci-run.sh`, and `validate.sh` internally.

**Features:**
- Uses long options (`--zip`, `--tmpl`, `--image-name`, `-h`/`--help`).
- Validates argument existence for input files.
- Makes the Clonezilla image name configurable via `--image-name`.
- Generates temporary `ocs-sr` command scripts to dynamically set the image name.
- Returns 0 for success and 1 for failure.

**Workflow:**
1.  **Prepare Clonezilla Live Media**: Converts the provided Clonezilla ZIP to QCOW2 format.
2.  **Prepare Source Disk**: Creates a Copy-on-Write (COW) disk image based on the template QCOW2 image to be used as the source for backup.
3.  **Backup the Source Disk**: Uses Clonezilla to create a backup image of the source disk.
4.  **Restore to a New Disk**: Creates a new QCOW2 disk and restores the backup onto it.
5.  **Validate the Restored Disk**: Boots the restored disk with a cloud-init ISO to verify functionality.

**Usage:**
```bash
# Run a full cycle with default image name
./os-clone-restore.sh \
  --zip ./isos/clonezilla-live-20251124-resolute-amd64.zip \
  --tmpl ./qemu/debian-sid-generic-amd64-daily-20250805-2195.qcow2

# Run a full cycle with a custom image name
./os-clone-restore.sh \
  --zip ./isos/clonezilla-live-20251124-resolute-amd64.zip \
  --tmpl ./qemu/debian-sid-generic-amd64-daily-20250805-2195.qcow2 \
  --image-name "my-custom-image"

# Display help
./os-clone-restore.sh --help
```

### `validate.sh`

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
./validate.sh --iso dev/cloudinit/cloud_init_config/cidata.iso --disk ./qemu/restore.qcow2

# Validate with a longer timeout and keep the log file
./validate.sh --iso dev/cloudinit/cloud_init_config/cidata.iso --disk ./qemu/restore.qcow2 --timeout 600 --keeplog

# Display help
./validate.sh --help
```

### `validate-fs.sh`

A standalone script to safely check the filesystem integrity of a QCOW2 image. It uses `qemu-nbd` to expose the disk image as a read-only block device and then runs the appropriate `fsck` utility. This is a reliable way to verify filesystem health after a restore operation.

**Features:**
-   Checks for necessary permissions (`sudo`), commands (`qemu-nbd`, `fsck.*`), and ensures the `nbd` kernel module is loaded.
-   Requires passwordless `sudo` access, making it suitable for automated CI/CD environments.
-   If `fsck` detects an error, the script exits with a non-zero status and saves a detailed log to the `logs/` directory.

**Usage:**
```bash
# Check an ext4 filesystem within a QCOW2 image
./validate-fs.sh --qcow2 ./qemu/restored-debian.qcow2 --fstype ext4

# Check an ntfs filesystem
./validate-fs.sh --qcow2 ./qemu/restored-windows.qcow2 --fstype ntfs

# Display help
./validate-fs.sh --help
```

### `qemu-clonezilla-ci-run.sh`

This is the primary script for running fully automated, non-interactive Clonezilla tasks. It can prepare boot media directly from a Clonezilla ZIP file or use pre-extracted files. It boots a Clonezilla "live" environment, mounts a shared directory for images, and executes a specified command.

**Usage:**
```
Usage: ./qemu-clonezilla-ci-run.sh [OPTIONS]
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
  --qemu-args <args>      A string of extra arguments to pass to the QEMU command. Can be specified multiple times.
  --log-dir <path>        Directory to store log files (default: ./logs).
  -i, --interactive       Enable interactive mode (QEMU will not power off, output to terminal).
  -h, --help              Display this help message and exit.

Example (Backup with ZIP):
  ./qemu-clonezilla-ci-run.sh \
    --disk ./qemu/source.qcow2 \
    --zip ./zip/clonezilla-live-3.1.2-9-amd64.zip \
    --cmdpath ./dev/ocscmd/clone-first-disk.sh \
    --image ./partimag

Example (Restore with extracted files):
  ./qemu-clonezilla-ci-run.sh \
    --disk ./qemu/restore.qcow2 \
    --live ./isos/clonezilla.qcow2 \
    --kernel ./isos/vmlinuz \
    --initrd ./isos/initrd.img \
    --cmd 'sudo /usr/sbin/ocs-sr -g auto -e1 auto -e2 -c -r -j2 -p poweroff restoredisk my-img-name sda' \
    --image ./partimag
```

### `clonezilla-zip2qcow.sh`

This utility converts an official Clonezilla live ZIP distribution into a QCOW2 disk image, and extracts the kernel and initrd files. It uses long options for clarity, provides a help message, validates arguments, and names output files based on the ZIP\'s base name.

**Usage:**
```bash
# Basic usage, outputs to a directory named after the zip in the current folder
./clonezilla-zip2qcow.sh --zip ./isos/clonezilla-live-3.1.2-9-amd64.zip

# Specify output directory and force overwrite
./clonezilla-zip2qcow.sh --zip ./isos/clonezilla-live-3.1.2-9-amd64.zip --output ./isos/ --force

# Display help
./clonezilla-zip2qcow.sh --help
```

### `clonezilla-boot.sh`

This script boots a QEMU VM from Clonezilla media for interactive use. It can boot from a ZIP file or an ISO. If no boot media is specified, it attempts to automatically download the latest stable ZIP for the chosen architecture. The user disk is optional.

**Features:**
- Boot from ISO (`--iso`) or ZIP (`--zip`).
- **Auto-downloads** the latest stable Clonezilla Live ZIP if no media is provided.
- Attaching a user disk with `--disk` is optional.
- Forwards port 2222 to the VM's port 22.

**Usage:**
```bash
# Boot with auto-downloaded Clonezilla ZIP and attach a disk
./clonezilla-boot.sh --disk ./qemu/my-disk.qcow2

# Boot from a specific ISO without attaching any extra disk
./clonezilla-boot.sh --iso ./isos/my-clonezilla.iso

# Boot from a specific ZIP file
./clonezilla-boot.sh --zip ./zip/clonezilla-live-stable-amd64.zip

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

## Troubleshooting

### `virt-make-fs` Fails on `clonezilla-zip2qcow.sh`

On some systems, particularly when not running inside the provided Docker container, you may encounter an error when running `./clonezilla-zip2qcow.sh` or other scripts that call it.

**Symptom:**

The script fails with an error message similar to this:
```
libguestfs: error: /usr/bin/supermin exited with error status 1.
...
ERROR: virt-make-fs failed. Check permissions or libguestfs installation.
```

**Cause:**

This error is often caused by `libguestfs` (specifically, its `supermin` helper) not having read permissions for the host system's kernel files located in `/boot`. It needs to inspect the host kernel to build a minimal appliance for its tasks.

**Solution:**

You can resolve this by granting read permissions to the kernel files for all users:
```bash
sudo chmod +r /boot/vmlinuz-*
```
This command makes the kernel images readable, allowing `virt-make-fs` to proceed.
