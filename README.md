# Clonezilla CI Automation Tools

## Overview

This project provides a suite of bash scripts to automate testing and operations for Clonezilla in a Continuous Integration (CI) environment. It uses QEMU, KVM, and `shunit2` to create a framework for running end-to-end backup and restore tests for various operating systems and filesystems.

The primary goal is to enable fully automated, non-interactive validation of Clonezilla's core functionality.

## Key Features

- **Automated Test Suite**: `start.sh` runs a comprehensive suite of tests using `shunit2`.
- **OS Testing**: Automatically tests cloning and restoring full Linux distributions (e.g., Debian, Ubuntu) using `linux-clone-restore.sh`.
- **Filesystem Testing**: Automatically tests cloning and restoring various filesystems (e.g., ext4, xfs, btrfs, ntfs) with data integrity checks using `data-clone-restore.sh`.
- **Flexible QEMU Runner**: `qemu_clonezilla_ci_run.sh` provides a powerful interface to run ad-hoc Clonezilla commands in a QEMU VM, with features like automatic ZIP extraction, script execution, and customizable kernel parameters.
- **Dependency Automation**: Scripts can automatically download necessary ISOs (Debian, Clonezilla) if they are not found locally.

## Getting Started

### Prerequisites

Ensure the following dependencies are installed. On a Debian-based system, you can use:

```bash
sudo apt update
sudo apt install qemu-utils qemu-system-x86 libguestfs-tools shunit2 unzip curl wget uuid-runtime genisoimage
```
It is also recommended that your user be part of the `kvm` group for hardware-accelerated virtualization:
```bash
sudo usermod -aG kvm $USER
```
You will need to log out and log back in for this change to take effect.

### Running the Test Suite

The main entry point for running all CI tests is `start.sh`.

```bash
# Run the full test suite
./start.sh
```

By default, it uses a pre-configured Clonezilla Live ZIP file specified within the script. You can override this:
```bash
./start.sh --zip /path/to/your/clonezilla.zip
```
Test results are shown in the console, and detailed logs for each major operation are saved in the `./logs/` directory.

## Core Scripts

- **`start.sh`**: The main test runner. It executes all `test_*` functions defined within it using `shunit2`.
- **`linux-clone-restore.sh`**: An orchestration script that performs a full backup, restore, and boot validation cycle for a Linux OS disk image.
- **`data-clone-restore.sh`**: An orchestration script that tests backup and restore for a disk image containing a specific filesystem and data, verifying data integrity via checksums.
- **`qemu_clonezilla_ci_run.sh`**: The core component for executing commands within a Clonezilla QEMU VM. It handles the complexities of setting up the VM, storage, networking, and boot parameters.
- **`clonezilla_zip2qcow.sh`**: A utility to convert a Clonezilla Live ZIP archive into the QCOW2, kernel, and initrd files required for booting in QEMU.
- **`validateOS.sh`**: A helper script to verify that a restored OS disk image can boot successfully, using cloud-init for automation.

For detailed command-line options for each script, see the **[Usage Guide](usage.md)**.
