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
  --device /dev/kvm \
  --device /dev/fuse \
  --cap-add SYS_ADMIN \
  --security-opt apparmor=unconfined \
  -v $(pwd)/dev/testData:/app/dev/testData \
  -v $(pwd)/qemu/cloudimages:/app/qemu/cloudimages \
  -v $(pwd)/isos:/app/isos \
  -v $(pwd)/zip:/app/zip \
  -v $(pwd)/partimag:/app/partimag \
  -v $(pwd)/logs:/app/logs \
  clonezilla-ci ./start.sh
```
**Note:** The `--device=/dev/kvm` flag is for enabling KVM hardware acceleration on Linux hosts. It may not be needed or available on other operating systems.

**Example: Running an individual script (e.g., `clonezilla-boot.sh`)**
```bash
docker run --rm -it \
  --device=/dev/kvm \
  --security-opt apparmor=unconfined \
  -v ./qemu:/app/qemu \
  -v ./isos:/app/isos \
  -v ./zip:/app/zip \
  clonezilla-ci ./clonezilla-boot.sh --disk /app/qemu/my-disk.qcow2


**Example: Running an individual job script (e.g., `test_disk_512n_to_4kn_ext4.sh`)**

**Example: Running an individual script in the jobs directory (e.g., `test_disk_512n_to_4kn_ext4.sh`)**
```bash
docker run --rm -it \
  --device=/dev/kvm \
  --device /dev/fuse \
  --cap-add SYS_ADMIN \
  --security-opt apparmor=unconfined \
  -w /app/jobs \
  -v $(pwd)/dev/testData:/app/dev/testData \
  -v $(pwd)/qemu:/app/qemu \
  -v $(pwd)/isos:/app/isos \
  -v $(pwd)/zip:/app/zip \
  -v $(pwd)/partimag:/app/partimag \
  -v $(pwd)/logs:/app/logs \

**Example: Running an individual script in the jobs directory (e.g., `test_disk_512n_to_4kn_ext4.sh`)**
```bash
docker run --rm -it \
  --device=/dev/kvm \
  --device /dev/fuse \
  --cap-add SYS_ADMIN \
  --security-opt apparmor=unconfined \
  -w /app/jobs \
  -v $(pwd)/dev/testData:/app/dev/testData \
  -v $(pwd)/qemu:/app/qemu \
  -v $(pwd)/isos:/app/isos \
  -v $(pwd)/zip:/app/zip \
  -v $(pwd)/partimag:/app/partimag \
  -v $(pwd)/logs:/app/logs \
```bash
docker run --rm -it \
  --device /dev/kvm \
  --device /dev/fuse \
  --cap-add SYS_ADMIN \
  --security-opt apparmor=unconfined \
  -w /app/jobs \
  -v $(pwd)/dev/testData:/app/dev/testData \
  -v $(pwd)/qemu:/app/qemu \
  -v $(pwd)/isos:/app/isos \
  -v $(pwd)/zip:/app/zip \
  -v $(pwd)/partimag:/app/partimag \
  -v $(pwd)/logs:/app/logs \
  clonezilla-ci ./test_disk_512n_to_4kn_ext4.sh
```



### CI Pipeline Selective Runs (`TEST_FILTER`)

Manual pipelines support an optional `TEST_FILTER` variable to run only a subset of
test jobs while keeping the needs/report chain intact. It is a `grep -E` regex
matched against each test job's name; non-matching jobs exit 0 within seconds, and
`publish_reports` only expects the selected jobs.

**Usage:** Web UI → *Run pipeline* → 選擇 ref（如 `main`）→ Variables 加入
`TEST_FILTER=<regex>` → Run，再手動播放目標 trigger job（如 `trigger:amd64-testing`）。
例如：

| `TEST_FILTER` | 效果 |
|---|---|
| `lvm_thin` | 只跑 `test:dev_to_dev_lvm_thin`、`test:lvm_thin_save_restore`（及其相依的 download/build jobs）|
| `fs:(ext4|xfs)` | 只跑兩個檔案系統測試 |
| (留空) | 完整套件（預設行為不變）|

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
sudo apt install qemu-utils qemu-system-riscv64 qemu-system-arm64 qemu-system-x86 qemu-system-arm qemu-efi-aarch64 ovmf guestfs-tools unzip curl wget uuid-runtime genisoimage guestfish guestmount  e2fsprogs btrfs-progs xfsprogs ntfs-3g dosfstools exfatprogs bc shunit2 jq u-boot-qemu
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
- **`ovmf`**: Provides AMD64 UEFI firmware (`/usr/share/OVMF/OVMF_*_4M.fd`) for `--efi` runs and UEFI image builds.

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

### `download-clonezilla.sh`

A powerful, standalone script to automatically find and download the latest Clonezilla Live ZIP file based on architecture and release type. This script is the core download engine used by other scripts in this project.

**Features:**
-   Supports `amd64`, `arm64`, and `riscv64` architectures.
-   For `amd64`, supports different release types: `stable`, `testing`, `unstable`, `alternative-stable`, `alternative-testing`, and codename-scoped `alternative-testing-<codename>` (e.g. `alternative-testing-stonking`, for Ubuntu-based builds published side by side per codename).
-   For `arm64` and `riscv64`, automatically finds the latest experimental version.
-   `--dry-run` option to see the final URL without downloading.

**Exit codes:**
-   `0`: success.
-   `1`: general error (network/curl failure, invalid arguments, download failed).
-   `3`: the mirror currently offers no matching version (e.g. the `testing/` tree
    is emptied right after a testing → stable promotion). CI scripts map this to
    `VERSION_STATUS=mirror_empty` and skip the run instead of failing the pipeline.

**Usage:**
```
Usage: ./download-clonezilla.sh --arch <ARCH> [--type <TYPE>] [-o <OUTPUT_DIR>] [--dry-run]

Automatically finds and downloads the latest Clonezilla Live zip file.

Options:
  --arch <ARCH>      Architecture: amd64, arm64, riscv64 (required).
  --type <TYPE>      For amd64 architecture: stable, testing, unstable,
                     alternative-stable, alternative-testing, or
                     alternative-testing-<codename> (default: stable).
  -o, --output <DIR> Directory to save the downloaded file (default: .).
  --dry-run          Print the final URL and exit without downloading.
  -h, --help         Display this help message and exit.
```

**Usage Examples:**
```bash
# Download the latest 'testing' release for amd64 to the 'zip/' directory
./download-clonezilla.sh --arch amd64 --type testing -o zip/

# See the URL for the latest arm64 release without downloading
./download-clonezilla.sh --arch arm64 --dry-run
```

### `qemu/cloudimages/` – 雲端映像庫與中央 repo

`qemu/cloudimages/` 是所有 OS/FS 測試所用 qcow2 的目錄。Git 只追蹤 `cloud_images.conf`、`download_cloud_images.sh`、`sync_images.sh`、`image_common.sh` 與 `note`；`*.qcow2` 一律 gitignore。

**Config schema（`cloud_images.conf`）**：每行 `OS RELEASE ARCH [FIRMWARE] URL [SHA256]`
- 檔名契約：`<OS>-<RELEASE>[-<FIRMWARE>]-<ARCH>.qcow2`。
- `FIRMWARE`（`bios`/`uefi`）僅在影像為韌體專屬時填寫（`ubuntu-zfs`、`windows`）；BIOS/UEFI 通吃的通用 cloud image 不填（沿用舊檔名）。
- `URL`：直接下載的 `https://` 位址；非 http(s) 的值（如 `PLACEHOLDER_*`、`MANUAL_*`）代表需本機建置／手動準備，下載流程會略過並提示。
- `SHA256`：選填；填寫後下載與既有檔案皆會校驗。

#### `download_cloud_images.sh`
```bash
./download_cloud_images.sh              # 下載 conf 中缺少的 image（.part 暫存 + mv，原子）
./download_cloud_images.sh --force      # 全部重新下載
./download_cloud_images.sh --check      # 只回報狀態（OK/MISSING/SHA-MISMATCH/MANUAL）
./download_cloud_images.sh --prune      # 刪除不在 conf 內的 qcow2（互動確認；--yes 跳過）
./download_cloud_images.sh --migrate    # 舊檔名 → 契約檔名（例如 win11-uefi.qcow2）
```

#### 中央 image repo 架構（同步方式）
```
PN42（producer, tag: windows）  --rsync/ssh push-->  140.110.240.58  <--rsync/ssh pull--  test runners
                                                    cicd@140.110.240.58:3322
                                                    /home/cicd/clonezilla-cicd-cloudimages
                                                    + MANIFEST.sha256 / manifest.tsv
```
- runner 不再各自上網抓 image；由 PN42 統一下載／建置（含未來 ZFS golden image 與 Windows 匯入）後推送。
- repo 上的 `MANIFEST.sha256` 是完整性錨點：pull 端以 sha256 判斷「缺漏／過期」，`.part` 暫存驗證後才換名。
- 各 runner 的 ssh key 已部署：PN42 等以 `gitlab-runner` 使用者跑 job（私鑰在 `/home/gitlab-runner/.ssh/`），F1 以 `u1597171` 跑 job（key 在該帳號 `~/.ssh/`）；三台皆有 `clonezilla-imgrepo` ssh config 別名可用。

#### `sync_images.sh`
```bash
# runner 端：依 conf 需求，向 repo 補齊缺漏或 sha256 不符的 image
./sync_images.sh --pull [--yes]

# producer 端（PN42）：上傳 conf 引用的本機 image 並重建遠端 manifest
./sync_images.sh --push [--yes]

./sync_images.sh --prune [--yes]     # 清理本機 orphan（同 download_cloud_images.sh --prune）
```
- 環境變數：`IMAGE_REPO_HOST`（預設 `140.110.240.58`，runner 上也可用 `clonezilla-imgrepo` 別名）、`IMAGE_REPO_USER`（預設 `cicd`）、`IMAGE_REPO_DIR`（預設 `/home/cicd/clonezilla-cicd-cloudimages`）、`IMAGE_REPO_SSH_PORT`（預設 `3322`）。
- exit code：`2`＝repo 不可達（CI 應退回舊行為）；`3`＝校驗失敗。
- 取用協定採 rsync/ssh。http（唯讀 nginx）之後再加。

#### runner 上影像的取用（CI 現況與目標）
- 現況（`child-pipeline.yml` before_script）：優先將 `/data/cloudimages/*.qcow2` 以符號連結掛進 job workspace 的 `qemu/cloudimages/`；Slurm 模式則 bind mount `/data/cloudimages`。本地缺 image 的測試依 conf 跳過或失敗。
- 目標（Phase 2）：before_script 在發現缺漏時先 `sync_images.sh --pull --yes` 補齊，再走既有 symlink 流程。
- 本地手動取用範例：測試腳本（`jobs/test_os_*.sh`）依 `cloud_images.conf` 的 `OS`+`ARCH` 找到對應檔名（`jobs/common.sh` 的 `image_name_from_conf_line`），存在才跑。

#### Windows image
- conf 登錄 `windows 11 amd64 bios` 與 `windows 11 amd64 uefi` 兩行（`MANUAL_*`，不下載）。
- 取得方式：cloudbase.it 提供 Windows cloud images（見 `qemu/cloudimages/note`），需手動轉 qcow2、以 cloud-init（`isos/win11_cidata.iso`）完成首次開機設定後複製為模板，檔名依契約置於 `qemu/cloudimages/`。
- `windows-11-uefi-amd64.qcow2` 檔名含 `uefi`，`os-clone-restore.sh` 會自動帶 `--efi`。

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
  --cmdpath ./dev/ocscmd/lite-bt-dev.sh

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
- **Automatically detects UEFI boot mode** if the `--tmpl` QCOW2 filename contains "uefi".
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

# Run a full cycle with a custom image name and an UEFI template (will auto-detect EFI)
./os-clone-restore.sh \
  --zip ./isos/clonezilla-live-20251124-resolute-amd64.zip \
  --tmpl ./qemu/cloudimages/windows-11-uefi-amd64.qcow2 \
  --image-name "my-windows-efi-image"

# Display help
./os-clone-restore.sh --help
```

### `validate.sh`

This script boots a restored QCOW2 image with a cloud-init ISO to verify that the OS starts and runs a cloud-init script successfully. It runs non-interactively and checks for a success keyword in the output log.

**Features:**
- Uses long options (`--iso`, `--disk`, `--timeout`, `--keeplog`, `-h`/`--help`).
- Supports NVMe (`--disk-driver nvme`) and custom block sizes (`--disk-lbas`, `--disk-pbas`) for validating restored images.
- Validates argument existence.
- Implements an intelligent timeout mechanism using background processes and `wait -n`.
- Allows keeping log files for debugging with `--keeplog`.
- Returns 0 for success and 1 for failure.

**Usage:**
```bash
# Validate a restored disk image with a cloud-init ISO
./validate.sh --iso dev/cloudinit/cloud_init_config/cidata.iso --disk ./qemu/restore.qcow2

# Validate a restored 4Kn NVMe disk
./validate.sh \
  --iso dev/cloudinit/cloud_init_config/cidata.iso \
  --disk ./qemu/restored-4kn-nvme.qcow2 \
  --disk-driver nvme \
  --disk-lbas 4096 \
  --disk-pbas 4096

# Validate a restored EFI disk image
./validate.sh \
  --iso dev/cloudinit/cloud_init_config/cidata.iso \
  --disk ./qemu/restored-efi-disk.qcow2 \
  --efi

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
  --disk-driver <type>    Disk driver for data disks: 'virtio-blk' (default) or 'nvme'.
  --disk-lbas <size>      Logical block size for data disks (e.g., 512, 4096).
  --disk-pbas <size>      Physical block size for data disks (e.g., 512, 4096, for NVMe).
  --image <path>          Path to the shared directory for Clonezilla images (default: ./partimag).
  --cmd <command>         Command string to execute inside Clonezilla (e.g., 'sudo ocs-sr ...').
  --cmdpath <path>        Path to a script file to execute inside Clonezilla.
  --append-args <args>    A string of custom kernel append arguments to override the default.
  --append-args-file <path> Path to a file containing custom kernel append arguments.
  --qemu-args <args>      A string of extra arguments to pass to the QEMU command. Can be specified multiple times.
  --log-dir <path>        Directory to store log files (default: ./logs).
  --temp-dir <path>       Directory to store temporary files (e.g., UEFI VARS). Defaults to --log-dir if not set.
  --arch <arch>           Target architecture (amd64, arm64, riscv64). Default: amd64.
  --efi                   Enable UEFI boot mode for amd64 architecture.
  --no-ssh-forward        Disable TCP port 2222 forwarding for SSH.
  -i, --interactive       Enable interactive mode (QEMU will not power off, output to terminal).
  -h, --help              Display this help message and exit.

Example (Backup with ZIP):
  ./qemu-clonezilla-ci-run.sh \
    --disk ./qemu/source.qcow2 \
    --zip ./zip/clonezilla-live-3.1.2-9-amd64.zip \
    --cmdpath ./dev/ocscmd/lite-bt-dev.sh \
    --image ./partimag

Example (Restore with extracted files and UEFI):
  ./qemu-clonezilla-ci-run.sh \
    --disk ./qemu/restore.qcow2 \
    --live ./isos/clonezilla.qcow2 \
    --kernel ./isos/vmlinuz \
    --initrd ./isos/initrd.img \
    --cmd 'sudo /usr/sbin/ocs-sr -g auto -e1 auto -e2 -c -r -j2 -p poweroff restoredisk my-img-name sda' \
    --image ./partimag \
    --efi \
    --qemu-args "-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd" \
    --qemu-args "-drive if=pflash,format=raw,file=./logs/temp_ovmf_vars_$(date +%s)_$RANDOM.fd"
```

### `clonezilla-zip2qcow.sh`

This utility converts a Clonezilla Live ZIP into a QCOW2 disk image and extracts the necessary kernel and initrd files. If no ZIP file is provided, it automatically downloads the appropriate version using `download-clonezilla.sh`.

**Features:**
- Uses long options for clarity (`--zip`, `--output`, `--size`, `--arch`, `--type`, `--force`).
- Auto-downloads the correct Clonezilla version if `--zip` is omitted.
- Supports specifying architecture and release type for downloads.
- Names output files based on the ZIP's base name for better organization.

**Usage:**
```bash
# Convert a specific zip file, forcing overwrite
./clonezilla-zip2qcow.sh --zip ./zip/clonezilla-live-amd64.zip --output ./zip/ --force

# Auto-download the latest 'testing' version for amd64 and convert it
./clonezilla-zip2qcow.sh --arch amd64 --type testing --output ./zip/

# Display help
./clonezilla-zip2qcow.sh --help
```

### `clonezilla-boot.sh`

This script boots a QEMU VM from Clonezilla media for interactive use. It can boot from a ZIP file or an ISO. If no boot media is provided, it automatically downloads the latest version for the specified architecture and type.

**Features:**
- Boot from ISO (`--iso`) or ZIP (`--zip`).
- **Auto-downloads** the correct Clonezilla version using `download-clonezilla.sh`.
- Supports specifying architecture (`--arch`) and release type (`--type`) for downloads.
- Attaching a user disk with `--disk` is optional.
- Forwards host port 2222 to the VM's port 22 for SSH access.

**Usage:**
```bash
# Boot with auto-downloaded 'stable' amd64 ZIP and attach a disk
./clonezilla-boot.sh --disk ./qemu/my-disk.qcow2

# Boot with auto-downloaded 'testing' arm64 version
./clonezilla-boot.sh --arch arm64 --type testing

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

### `build-ubuntu-zfs-image.sh`

Builds an **Ubuntu 24.04 golden image with root on ZFS** (no official cloud image exists) fully unattended. It downloads the Ubuntu live-server ISO, renders a NoCloud seed from the subiquity autoinstall templates in `dev/cloudinit/autoinstall-zfs/`, boots the installer kernel directly in QEMU (`autoinstall ---`), and waits for the install to power off. There is no interactive input.

**Layout** (official Ubuntu ZFS layout, matching desktop/server installs):
- UEFI variant: `p1` ESP 600M (fat32, `/boot/efi`) → `p2` **bpool** 2G (GRUB-compatible feature flags, `bpool/BOOT/ubuntu` → `/boot` on ZFS) → `p3` swap 2G → `p4` **rpool** (lz4, autoexpand; `rpool/ROOT/ubuntu` → `/`, `rpool/var/log`).
- BIOS variant: same, with a 1M `bios_grub` partition instead of the ESP (grub-pc reads `/boot` from bpool directly).
- This deliberately exercises the harder case: GRUB boots straight from ZFS, two `zfs_member` partitions (bpool with GRUB-compatible flags vs rpool with full features) plus a real swap partition.
- Hard-codes the cloud-init workarounds the [cmtops.dev guide](https://cmtops.dev/posts/ubuntu-cloud-template-zfs/) recommends: disabled upstream `growpart`/`resize_rootfs` + per-boot ZFS growth fix for every pool (works together with `restoredisk -k1` growing the disk to 80G in tests), `cachefile=none` + per-instance pool-cache restore, serial console on `ttyS0`.

**Output naming contract**: `qemu/cloudimages/ubuntu-zfs-<release>-<firmware>-<arch>.qcow2`, matching the `ubuntu-zfs` stanzas in `qemu/cloudimages/cloud_images.conf` used by `jobs/test_os_ubuntu_zfs.sh`. Default login after boot is `ubuntu / ubuntu` (test-only image).

**Usage:**
```bash
# Build both variants (UEFI + BIOS), amd64 (ISO auto-downloads to isos/)
./build-ubuntu-zfs-image.sh

# Build only the UEFI variant
./build-ubuntu-zfs-image.sh --firmware uefi

# Use an existing ISO, custom output dir, keep temp files for debugging
./build-ubuntu-zfs-image.sh --firmware bios --iso isos/ubuntu-24.04.5-live-server-amd64.iso \
    --output qemu/cloudimages --keep-workdir

# Rebuild from scratch
./build-ubuntu-zfs-image.sh --force
```

**Options:** `--firmware <uefi|bios|both>` (default: both), `--arch` (amd64 only), `--release` (24.04 only), `--iso <path>`, `--output <dir>`, `--name <name>` (single firmware only), `--disk-size <size>` (default `10G`), `-m/--mem`, `--smp`, `--timeout-min` (default 90; raise under TCG), `--skip-smoke-test`, `--keep-workdir`, `--force`, `-h/--help`.

**Notes:**
- Requires KVM for reasonable runtime (`--timeout-min 180+` suggested under TCG).
- The UEFI variant needs the `ovmf` package (already in the Dockerfile).
- Each built image is boot-validated with `validate.sh` (`--efi` for UEFI) unless `--skip-smoke-test` is given.

### `scripts/notify-telegram.sh`

Sends Clonezilla CI notifications to a Telegram group via the Bot API. It is called automatically by the child pipeline (`check_version` job and the `notify:telegram` job) and is designed to **never fail the pipeline**: without `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` it only logs a warning and exits 0.

**Notification filter** (the group stays quiet on no-op scheduled runs):

| Pipeline source | Condition | Message |
|---|---|---|
| Scheduled | `VERSION_STATUS=new_version` | "New version detected" at the start + summary at the end |
| Scheduled | `no_change` / `in_progress` / `mirror_empty` | none |
| Manual (push / web / api / trigger) | tests finished | summary (success or failure) |

**Modes:**
- `started` — new-version notice; used by the `check_version` job.
- `finished` — aggregates `results/*.yml` into a pass/fail summary (missing artifacts of expected jobs count as failures, mirroring `publish_reports.sh`) and appends Pipeline / report links; used by the `notify:telegram` job.

**Required CI/CD variables** (Project → Settings → CI/CD → Variables, masked):
- `TELEGRAM_BOT_TOKEN` — bot token from `@BotFather`; the bot must be a member of the target group.
- `TELEGRAM_CHAT_ID` — group chat id (usually a negative number).

**Usage:**
```bash
# Print the "finished" message without sending (no tokens needed)
./scripts/notify-telegram.sh finished --dry-run

# Send the "new version detected" notice (requires tokens in the environment)
VERSION_STATUS=new_version ./scripts/notify-telegram.sh started
```

**Optional environment:**
- `PAGES_BASE_URL` — overrides the report site base URL (default `https://clonezilla-ci-036aa1.gitlab.io`).

### `jobs/test_dev_to_dev_lvm_thin.sh`

Automates end-to-end testing for **local disk LVM to LVM cloning** (`ocs-onthefly`) where **thin provisioning** is included in the source device.

> **Minimum Clonezilla Live version: `3.3.4-23` (stable/testing) or `20261108-*` (alternative-testing).**
> LVM thin pool support was added in those releases. With an older zip the test
> is **SKIPPED** — it logs `--- Test Job SKIPPED: LVM thin dev-to-dev clone test ... ---`
> and exits 0 (implemented by `skip_unless_clonezilla_version_or_newer` in
> `jobs/common.sh`). Unrecognized zip name formats fall back to running the test
> with a `[WARN]`.

**Test Workflow:**
1. **Source Disk Preparation (`/dev/vda`)**:
   - Creates a standard partition (`vda1`, ext4) and an LVM PV partition (`vda2`).
   - Creates Volume Group (`vg_ci`) on `vda2`.
   - Creates a regular linear Logical Volume (`reg_vol`, ext4) with test data and MD5 checksums.
   - Creates an LVM Thin Pool (`thin_pool`, 8GB) within `vg_ci`.
   - Creates multiple Thin Logical Volumes (`thin_vol1`, `thin_vol2`, 2GB virtual sizes, ext4) within `thin_pool`, populates test data, and calculates MD5 checksums.
   - Deactivates LVM cleanly.
2. **Target Disk Preparation (`/dev/vdb`)**:
   - Prepares a fresh blank target disk.
3. **Local Disk-to-Disk Cloning (`ocs-onthefly`)**:
   - Executes `/usr/sbin/ocs-onthefly -b -g auto -e1 auto -e2 -j2 -r -sfsck -k0 -p true -f vda -d vdb`.
4. **Target Isolation & Verification**:
   - Zeroes the front of source disk `/dev/vda` (50MB) to ensure target disk independence and prevent duplicate VG/UUID conflicts.
   - Probes `/dev/vdb`, checks the boot partition checksum.
   - Rescans and activates LVM on `/dev/vdb`.
   - Validates that the Thin Pool (`thin_pool`, segtype `thin-pool`), Thin Volumes (`thin_vol1`, `thin_vol2`, segtype `thin`), and Regular Volume (`reg_vol`, segtype `linear`) are correctly reconstructed.
   - Mounts each volume and verifies file data integrity against pre-computed MD5 checksums.

**Usage:**
```bash
# Run locally from jobs/ directory
cd jobs && ./test_dev_to_dev_lvm_thin.sh --zip /path/to/clonezilla.zip --arch amd64

# Run with Docker
docker run --rm -it \
  --device /dev/kvm \
  -w /app/jobs \
  -v $(pwd)/zip:/app/zip \
  -v $(pwd)/logs:/app/logs \
  clonezilla-ci ./test_dev_to_dev_lvm_thin.sh --zip /app/zip/clonezilla-live-3.3.4-23-amd64.zip
```

### `jobs/test_lvm_thin_save_restore.sh`

Automates end-to-end testing for **saving an LVM disk (including thin provisioning) as an image**, **cleaning the destination disk**, and **restoring the image back to the destination disk**.

> **Minimum Clonezilla Live version: `3.3.4-23` (stable/testing) or `20261108-*` (alternative-testing).**
> LVM thin pool support was added in those releases. With an older zip the test
> is **SKIPPED** — it logs `--- Test Job SKIPPED: LVM thin save/restore test ... ---`
> and exits 0 (implemented by `skip_unless_clonezilla_version_or_newer` in
> `jobs/common.sh`). Unrecognized zip name formats fall back to running the test
> with a `[WARN]`.

**Test Workflow:**
1. **Source Disk Preparation (`/dev/vda`)**:
   - Creates a boot partition (`vda1`, ext4) and LVM PV partition (`vda2`).
   - Creates Volume Group (`vg_ci`) on `vda2`.
   - Creates regular linear Logical Volume (`reg_vol`, ext4) with test files and MD5 checksums.
   - Creates LVM Thin Pool (`thin_pool`, 8GB) and Thin Logical Volumes (`thin_vol1`, `thin_vol2`, 2GB virtual sizes, ext4) with test files and MD5 checksums.
   - Stores expected MD5 checksums into `/home/partimag` shared repository.
   - Deactivates LVM cleanly.
2. **Image Backup (`savedisk`)**:
   - Executes `/usr/sbin/ocs-sr -b -senc -sfsck -j2 -q2 -z1 -p true savedisk lvm-thin-backup vda` to create the image in `/home/partimag/lvm-thin-backup`.
3. **Destination Disk Cleaning**:
   - Deactivates any active Volume Groups.
   - Completely wipes partition tables, filesystem, and LVM signatures using `wipefs -a -f` and `sgdisk -Z`.
   - Overwrites the first 100MB of the disk with zeros (`dd if=/dev/zero ...`).
   - Verifies that no volume groups or partitions remain on the destination disk.
4. **Image Restoration (`restoredisk`)**:
   - Executes `/usr/sbin/ocs-sr -b -k0 -j2 -sfsck -p true restoredisk lvm-thin-backup vda` to reconstruct the partition table, LVM structures, and thin pool/LVs.
5. **Verification**:
   - Activates LVM on the restored disk.
   - Verifies that `thin_pool` has segtype `thin-pool`, `thin_vol1` / `thin_vol2` have segtype `thin` and pool `thin_pool`, and `reg_vol` has segtype `linear`.
   - Mounts each restored filesystem (`/dev/vda1`, `/dev/vg_ci/reg_vol`, `/dev/vg_ci/thin_vol1`, `/dev/vg_ci/thin_vol2`) and verifies MD5 checksums against the original data.

**Usage:**
```bash
# Run locally from jobs/ directory
cd jobs && ./test_lvm_thin_save_restore.sh --zip /path/to/clonezilla.zip --arch amd64

# Run with Docker
docker run --rm -it \
  --device /dev/kvm \
  -w /app/jobs \
  -v $(pwd)/zip:/app/zip \
  -v $(pwd)/partimag:/app/partimag \
  -v $(pwd)/logs:/app/logs \
  clonezilla-ci ./test_lvm_thin_save_restore.sh --zip /app/zip/clonezilla-live-3.3.4-23-amd64.zip
```

### `jobs/test_os_ubuntu_zfs.sh`

End-to-end **Ubuntu ZFS-on-root** clone/restore test exercising `partclone.zfs`. Discovers `ubuntu-zfs` images from `qemu/cloudimages/cloud_images.conf` (e.g. `ubuntu-zfs-24.04-uefi-amd64.qcow2`, `ubuntu-zfs-24.04-bios-amd64.qcow2`), then runs the standard `os-clone-restore.sh` cycle: savedisk → restoredisk to an 80G disk (`-k1`, partition growth) → cloud-init boot validation. UEFI-named images boot with `--efi` automatically.

> **Minimum Clonezilla Live version: `3.3.4-20` (stable/testing) or `20261030-*` (daily).**
> ZFS support (`partclone.zfs`) first shipped with those releases. With an older zip the
> test exits 0 as SKIPPED (`skip_unless_clonezilla_version_or_newer`), so pipelines and
> local `start.sh` runs never fail on unsupported versions.

**Usage:**
```bash
# Build the golden images first (once)
./build-ubuntu-zfs-image.sh

# Run the test (from jobs/)
cd jobs && ./test_os_ubuntu_zfs.sh --zip /path/to/clonezilla-live-3.3.4-20-amd64.zip --arch amd64
```

Missing images are skipped with a hint to run the build script — they never fail the job.

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
