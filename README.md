# Clonezilla CI Automation Tools

## Overview

This project provides a suite of bash scripts to automate testing and operations for Clonezilla in a Continuous Integration (CI) environment. It uses QEMU, KVM, and `shunit2` to create a framework for running end-to-end backup and restore tests for various operating systems and filesystems.

The primary goal is to enable fully automated, non-interactive validation of Clonezilla's core functionality.

## Key Features

- **Automated Test Suite**: `start.sh` runs a comprehensive suite of tests using `shunit2`.
- **OS Testing**: Automatically tests cloning and restoring full Linux distributions (e.g., Debian, Ubuntu) using `os-clone-restore.sh`.
- **Filesystem Testing**: Automatically tests cloning and restoring various filesystems (e.g., ext4, xfs, btrfs, ntfs) with data integrity checks using `data-clone-restore.sh`.
- **Flexible QEMU Runner**: `qemu-clonezilla-ci-run.sh` provides a powerful interface to run ad-hoc Clonezilla commands in a QEMU VM, with features like automatic ZIP extraction, script execution, and customizable kernel parameters.
- **Dependency Automation**: Scripts can automatically download necessary ISOs (Debian, Clonezilla) if they are not found locally.

## Getting Started

### Prerequisites

Ensure the following dependencies are installed. On a Debian-based system, you can use:

```bash
sudo apt update
sudo apt install qemu-utils qemu-system-riscv64 qemu-system-arm64 qemu-system-x86 qemu-system-arm qemu-efi-aarch64 guestfs-tools unzip curl wget uuid-runtime genisoimage guestfish guestmount
```
It is also recommended that your user be part of the `kvm` group for hardware-accelerated virtualization:
```bash
sudo usermod -aG kvm $USER
```
You will need to log out and log back in for this change to take effect.

## Running with Docker (Recommended)

This project includes a `Dockerfile` to build a container image with all the necessary dependencies. This is the recommended way to run the test suite, as it avoids having to install QEMU and other dependencies directly on your host machine.

### Prerequisites

-   [Docker](https://docs.docker.com/get-docker/) installed and running.

### Build the Docker Image

From the root of the project directory, run the following command:

```bash
docker build -t clonezilla-ci .
```

### Run the Test Suite in Docker

To run the test suite, you need to mount the directories containing your test data and images into the container.

```bash
docker run --rm -it \
  -v ./dev/testData:/app/dev/testData \
  -v ./qemu/cloudimages:/app/qemu/cloudimages \
  -v ./isos:/app/isos \
  -v ./zip:/app/zip \
  -v ./partimag:/app/partimag \
  -v ./logs:/app/logs \
  clonezilla-ci
```

You can pass arguments to `start.sh` as well:

```bash
docker run --rm -it \
  -v ./dev/testData:/app/dev/testData \
  -v ./qemu/cloudimages:/app/qemu/cloudimages \
  -v ./isos:/app/isos \
  -v ./zip:/app/zip \
  -v ./partimag:/app/partimag \
  -v ./logs:/app/logs \
  clonezilla-ci --arch arm64 --zip /app/zip/clonezilla-live-stable-arm64.zip
```
**Note:** For hardware acceleration, you may need to add `--device=/dev/kvm` to the `docker run` command if you are on a Linux host.

### Running the Test Suite

The main entry point for running all CI tests is `start.sh`.

```bash
# Run the full test suite with default architecture (amd64)
./start.sh
```

By default, it uses a pre-configured Clonezilla Live ZIP file specified within the script. You can override this:
```bash
./start.sh --zip /path/to/your/clonezilla.zip
```
You can also specify the architecture to test (defaults to `amd64`):
```bash
./start.sh --arch arm64
```
To run tests with a specific Clonezilla ZIP for a given architecture:
```bash
./start.sh --zip /path/to/your/clonezilla.zip --arch arm64
```
For help with available options:
```bash
./start.sh --help
```
Test results are shown in the console, and detailed logs for each major operation are saved in the `./logs/` directory.

## Core Scripts

- **`start.sh`**: The main test runner. It executes all `test_*` functions defined within it using `shunit2`.
- **`os-clone-restore.sh`**: An orchestration script that performs a full backup, restore, and boot validation cycle for a Linux OS disk image.
- **`data-clone-restore.sh`**: An orchestration script that tests backup and restore for a disk image containing a specific filesystem and data, verifying data integrity via checksums.
- **`qemu-clonezilla-ci-run.sh`**: The core component for executing commands within a Clonezilla QEMU VM. It handles the complexities of setting up the VM, storage, networking, and boot parameters.
- **`clonezilla-zip2qcow.sh`**: A utility to convert a Clonezilla Live ZIP archive into the QCOW2, kernel, and initrd files required for booting in QEMU.
- **`validate.sh`**: A helper script to verify that a restored OS disk image can boot successfully, using cloud-init for automation.

For detailed command-line options for each script, see the **[Usage Guide](usage.md)**.
