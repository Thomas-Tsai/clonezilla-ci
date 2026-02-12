---
applyTo: '**'
---
# Clonezilla Skill

## Architecture Overview (from https://clonezilla.nchc.org.tw/clonezilla-live/doc/fine-print.php?path=00_clonezilla_intro/01-clonezilla-arch.doc)
- Clonezilla Live, Lite Server, and SE (Server Edition) are built on Debian/Ubuntu base.
- Three editions:
  1. **Clonezilla Live** – bootable CD/USB for single‑machine backup & restore (includes Lite Server for network boot).
  2. **Clonezilla Lite Server** – uses Clonezilla Live to perform massive deployments via unicast, multicast, or BitTorrent.
  3. **Clonezilla SE** – integrated with DRBL for large‑scale cloning; requires a DRBL server and PXE boot.
- Supports a wide range of filesystems (ext*, xfs, btrfs, ntfs, vfat, hfs+, apfs, UFS, etc.) and both MBR/GPT, BIOS/UEFI.
- Image storage format is compatible across Live and SE; images reside in a directory under `/home/partimag` with metadata files (`Info-*.txt`, `blkdev.list`, etc.).

## Boot Parameters (from https://clonezilla.nchc.org.tw/clonezilla-live/doc/fine-print.php?path=99_Misc/00_live-boot-parameters.doc)
- Parameters are passed via the kernel command line (`/proc/cmdline`).
- **ocs_live_run** – program to execute after boot (e.g., `ocs-live-general`, `ocs-live-restore`). Can include `sudo` if needed.
- **ocs_live_extra_param** – extra parameters fed to `ocs-sr` when `ocs_live_run=ocs-live-restore`.
- **ocs_repository** – URI of the image repository (supports `dev`, `nfs`, `smb`, `ssh`, `http`, `https`). Example: `ocs_repository="nfs://192.168.100.254/home/partimag/"`.
- **ocs_preload** – download & extract files (tarball, zip, script) into `/opt/` on boot. Supports multiple numbered variants (`ocs_preload`, `ocs_preload1`, ...).
- **ocs_preload** can also be a mount command for CIFS/NFS.
- **ocs_preload** files can overwrite boot parameters via `overwrite-all-boot-param` and `overwrite-part-boot-param` placed in `/opt/`.
- **ocs_prerun** – commands executed before the main Clonezilla program (e.g., network setup via `dhclient`).
- **ocs_postrun** – commands executed after the main program.
- Additional parameters: `ocs_debug`, `ocs_daemonon/off`, `ocs_numlk`, `ocs_capslk`, `ocs_fontface`, `ocs_fontsize`, `ip=`, `live-netdev=`, `nicif=`, `ocs_netlink_timeout=`.
- To customise keyboard/layout: `keyboard-layouts=us`, `locales=zh_TW.UTF-8`.

## ocs-sr Command Options (from https://clonezilla.org/fine-print-live-doc.php?path=./clonezilla-live/doc/98_ocs_related_command_manpages/01-ocs-sr.doc)
- **Basic syntax**: `ocs-sr [OPTIONS] {savedisk|saveparts|restoredisk|restoreparts} IMAGE DEVICE`
- **Image** is a directory name under `/home/partimag`.
- **Device** can be `/dev/sda`, `sda`, PTUUID, SERIALNO, UUID, etc.
- **Saving options** (selected):
  - `-z0` … `-z9p` – compression level & algorithm (gzip, bzip2, lzop, lzma, xz, lz4, zstd, etc.).
  - `-gm` / `-gs` – generate MD5 / SHA1 checksum for the image.
  - `-enc` / `-senc` – enable/skip image encryption (passphrase via `-pe`).
  - `-sfsck` / `-fsck` – skip / run fsck on source before saving.
  - `-j2` – clone hidden data between MBR and first partition.
  - `-ntfs-ok` – assume NTFS integrity.
  - `-q`, `-q1`, `-q2` – choose backend (ntfsclone, dd, partclone).
- **Restoring options** (selected):
  - `-g` – install GRUB after restore (auto or specific partition).
  - `-r` – resize partition after restore.
  - `-k0`, `-k1`, `-k2` – partition table handling.
  - `-t` / `-t1` / `-t2` – control MBR/EBR restoration.
  - `-cm`, `-cs` – check MD5 / SHA1 checksum.
  - `-scr` – skip restore‑ability check.
  - `-iefi` – ignore EFI NVRAM update.
  - `-f` – restore a specific partition.
- **General options**:
  - `-b` / `-batch` – run in batch mode (no prompts).
  - `-c` – ask for confirmation.
  - `-d` – debug mode (interactive before operation).
  - `-l` – set language (or use `locales`).
  - `-v` – verbose.
  - `-x` – interactive mode (shows UI dialogs).
  - `-p` – post‑action after save/restore (`choose|poweroff|reboot|command`).
  - `-o0` / `-o1` – run scripts in `/usr/share/drbl/postrun/ocs/` before/after cloning.

## ocs-onthefly (brief, similar to ocs-sr but for network cloning)
- Syntax: `ocs-onthefly [OPTIONS] {savedisk|saveparts|restoredisk|restoreparts} IMAGE TARGET_IP`
- Uses `--use-netcat` or default `nuttcp` for data transfer.
- Supports same compression, encryption, and checksum options as `ocs-sr`.
- Useful for device‑to‑device over network or multicast/Bittorrent deployments.

## Lite Server (ocs-live-feed-img)

### ocs-live-get-img (Client side for multicast/BT)

`ocs-live-get-img` is the client‑side helper used to **retrieve** an image from a multicast or BitTorrent server before restoring it. It works in conjunction with `ocs-live-feed-img` which streams the image data.

#### Usage
```
ocs-live-get-img [OPTION] [SERVER]
```
- **SERVER** – IP address or FQDN of the multicast/BT server (e.g., `192.168.25.111`). If omitted, a menu will prompt for selection.
- **OPTIONS**:
  - `-b, --batch-mode` – Run in batch mode (no interactive prompts).
  - `-icol, --ignore-check-ocs-live` – Skip the check that ensures the environment is Clonezilla Live.
  - `-d, --dest-dev DEV` – Specify the destination device for restore; if omitted, the device assigned by the server is used.
  - `-v, --verbose` – Enable verbose output.

The typical workflow is:
1. **Server**: start the Lite Server with `ocs-live-feed-img` (including `-bt-iface` or `-mcast-iface`).
2. **Client**: boot Clonezilla Live and set kernel parameters:
   ```
   ocs_live_run=ocs-live-get-img
   ocs_live_extra_param="-b -d /dev/sda"
   ocs_repository="nfs://<SERVER_IP>/home/partimag"
   ```
   This tells the live system to run `ocs-live-get-img` in batch mode, download the image from the specified server, and then automatically invoke `ocs-live-restore` to write the image to the destination device.

#### Integration with CI
- Add the server start command to a CI job (e.g., `jobs/start_liteserver_bt.sh`).
- For the client side, include the above kernel parameters in the PXE/DHCP configuration or invoke `ocs-live-get-img` directly inside a CI container:
  ```bash
  export ocs_repository="nfs://$(hostname)/home/partimag"
  ocs-live-get-img -b -d /dev/sda
  ```
- After the image is retrieved, `ocs-live-get-img` will automatically call `ocs-live-restore` with any extra parameters passed via `ocs_live_extra_param`.

#### Reference
- Source: Clonezilla documentation and `ocs-live-get-img` man page.


The **ocs-live-feed-img** script implements Clonezilla Lite Server functionality, enabling mass deployment via multicast or BitTorrent. It is used to **feed** image data to client machines.

### Core Concepts
- **Mode**: `start` or `stop` – start or stop the Lite Server service.
- **Image Repository**: Must be mounted beforehand (`ocs_repository`). Supports local, NFS, SMB, HTTP, etc.
- **Network Configuration**: Handles NIC selection, optional DHCP server (`-dm/--dhcpd-mode`), and can operate in a closed LAN (`ipadd_closed_lan`, `netmask_closed_lan`).
- **Client Boot Mode** (`-cbm`): `netboot`, `local-boot-media`, or `both` – determines how clients boot.
- **Lite Server Client Mode** (`-lscm`): `massive-deployment` or `interactive-client`.
- **Massive Deploy Source Type** (`-mdst`): `from-image` (server serves an image) or `from-device` (server streams a live disk).
- **Massive Deploy Source Image** (`-mdst-img`): Name of the source image directory when `-mdst from-image`.
- **Cast Device Type** (`-cdt` / `-bdt`): `disk-2-mdisks` or `part-2-mparts` – indicates whether a whole disk or partitions are being streamed.
- **Network Interfaces**: `-mcast-iface` for multicast seed interface, `-bt-iface` for BitTorrent seed interface.
- **Full‑Duplex** (`-x`): Use full‑duplex UDP cast for faster multicast (requires a switch, not a hub).
- **DHCP Options** (`-dm`): `use-existing-dhcpd`, `start-new-dhcpd`, `auto-detect`, `no-dhcpd`.
- **Other Useful Options**:
  - `-b/--batch` – run without interactive prompts.
  - `-c/--confirm` – ask for confirmation before actions.
  - `-v/--verbose` – increase output verbosity.
  - `-g` – install GRUB after restore.
  - `-r` – resize partition after restore.
  - `-t`/`-t1`/`-t2` – control MBR/EBR restoration.
  - Checksum options: `-cm`/`-cs`/`-cb2`/`-cb3`.
  - Encryption: `-enc`/`-senc`.
  - Compression: `-z0` … `-z9p` (same as `ocs-sr`).

### Typical Workflow
1. **Prepare Image Repository** – Ensure the image directory is available and mounted (e.g., NFS).
2. **Start Lite Server**:
   ```bash
   sudo ocs-live-feed-img start my-image sda \
       -md massive-deployment \
       -cbm netboot \
       -lscm massive-deployment \
       -mdst from-image \
       -cdt disk-2-mdisks \
       -mcast-iface eth0 \
       -b
   ```
   This starts feeding `my-image` to disk `sda` on clients using multicast.
3. **Stop Server** when deployment is finished:
   ```bash
   sudo ocs-live-feed-img stop my-image sda
   ```
4. **Client Boot** – Clients boot via network (PXE) and receive the image according to the parameters set.

### CI Integration Tips
- Run the script inside the CI container with appropriate `--batch` flag to avoid prompts.
- Pass `-dm start-new-dhcpd` or `-dm use-existing-dhcpd` depending on whether the container provides a DHCP service.
- Use `-mcast-iface` to bind to the container’s network interface (e.g., `eth0`).
- Ensure the image repository is mounted inside the container at the same path expected by the script (`/home/partimag`).
- Clean up temporary files (`/opt/overwrite-*.txt`, `/opt/*.sh`) with a trap or after the job finishes.

## Deep Repository Knowledge (from the `clonezilla/` source tree)

The Clonezilla project includes a full source tree under the `clonezilla/` directory. Below is a concise extraction of the most relevant parts for agents working in the CI environment.

### Directory Overview
- **conf/** – Global configuration files (e.g., `drbl-ocs.conf`) that define default paths, network settings, and repository locations.
- **doc/** – Documentation such as `AUTHORS`, `COPYING`, `ChangeLog.txt`.
- **postrun/ocs/** & **prerun/ocs/** – Scripts executed *after* or *before* a Clonezilla operation. Useful for custom cleanup or preparation (e.g., `00-readme.txt`).
- **samples/** – Example scripts and utilities (e.g., image checksum generation, custom OCS commands, network configuration generators). These can be copied into CI jobs for quick prototyping.
- **scripts/sbin/** – Core operational binaries used by Clonezilla Live and the Lite Server:
  - `ocs-functions` – Common helper functions for both server and client side (parsing options, logging, error handling).
  - `ocs-chnthn-functions` – Functions specific to Chinese language handling and localization.
  - `set-netboot-1st-efi-nvram` – Helper to set the first boot entry in UEFI NVRAM for network boot.
- **setup/files/** – Files shipped inside the live environment (e.g., gparted configuration, UI themes, systemd units).
- **setup/ocs/** – Live‑hook scripts that run during the early boot phase of Clonezilla Live (`start-ocs-live`, `stop-ocs-live`). These scripts source the functions above and apply boot‑parameter handling.
- **themes/clonezilla/** – Splash screens and theme assets used by the live UI.
- **toolbox/** – Build helpers (`make-deb.sh`, `make-rpm.sh`, `makeit.sh`) and miscellaneous notes.

### Important Configuration Files
| File | Purpose |
|------|---------|
| `conf/drbl-ocs.conf` | Default DRBL/Clonezilla server configuration (paths, default NIC, repository URI, logging). |
| `setup/ocs/drbl-live.d/S00drbl-start` | Early start script executed by the live system; sets up environment variables and mounts the image repository. |
| `setup/ocs/drbl-live.d/S99drbl-stop` | Cleanup script run on shutdown; unmounts repositories, stops services. |
| `setup/ocs/live-hook/ocs-live-hook.conf` | Controls which hooks are enabled (e.g., `ocs_live_hook_pre`, `ocs_live_hook_post`). |
| `setup/ocs/live-hook/ocs-live-hook-functions` | Library of reusable Bash functions for the live‑hook system (logging, error handling, parsing `ocs_live_*` boot parameters). |

### Core Bash Functions (from `scripts/sbin/ocs-functions`)
- `parse_ocs_cmdline` – Parses kernel command line for all `ocs_*` parameters and populates corresponding variables.
- `add_opt_in_pxelinux_cfg_block` / `add_opt_in_grub_efi_cfg_block` – Helper to inject boot parameters into PXELINUX or GRUB config blocks.
- `ocs_log` – Central logging routine that prefixes messages with timestamps and writes to `${OCS_LOGFILE}`.
- `ocs_error` – Prints an error message and exits with a non‑zero status, ensuring CI jobs can detect failures.
- `check_repo_mounted` – Verifies that `${ocsroot}` is a mount point before any operation; aborts otherwise.

### Sample Workflows Extracted from `samples/`
- **Checksum Generation** (`samples/mdisk‑checksum`):
  ```bash
  # Generate checksum files for all images in /home/partimag
  for img in /home/partimag/*; do
      (cd "$img" && md5sum * > MD5SUMS)
  done
  ```
- **Custom OCS Command** (`samples/ocs‑cmd‑screen‑sample`):
  Shows how to launch a full‑screen `screen` session that runs `ocs‑sr` with user‑defined options. Useful for long‑running multicast deployments.
- **Network Configuration Generator** (`samples/gen‑netcfg`):
  Produces a DHCP/DNSMasq configuration based on the current network, which can be fed to the Lite Server (`-dm start-new-dhcpd`).

### Hook Integration Points
Agents can inject custom behavior by adding scripts to the following directories:
- `prerun/ocs/` – Executed **before** `ocs‑sr` runs. Ideal for mounting additional repositories, setting `ocs_repository`, or preparing temporary files.
- `postrun/ocs/` – Executed **after** `ocs‑sr` finishes. Good for cleaning up temporary data, publishing logs, or sending notifications.

Each hook script receives the same environment variables as the main Clonezilla process (`OCS_OPT`, `OCS_LOGFILE`, `ocsroot`, etc.) and should exit with `0` on success.

### Extending the CI Wrapper (`qemu-clonezilla-ci-run.sh`)
When invoking Clonezilla from CI, the wrapper can:
1. Source `/usr/share/drbl/ocs-functions` to reuse the same parsing logic as the live system.
2. Set `OCS_OPT` based on CI‑provided arguments (e.g., `--batch`, compression flags).
3. Mount the image repository inside the container at `/home/partimag` and export it via `-v`.
4. Use the **Lite Server** hook scripts (`ocs-live-feed-img`) by passing `--cmd "ocs-live-feed-img start …"`.
5. Ensure clean termination by trapping `SIGTERM`/`SIGINT` and calling the `task_stop_feed_img_for_cast` function from `ocs-live-feed-img`.

### Quick Reference Cheat‑Sheet for CI Scripts
| Goal | Command (via `qemu-clonezilla-ci-run.sh --cmd` ) |
|------|---------------------------------------------------|
| Save a disk image (gzip, batch) | `ocs-sr -b -z1 savedisk my-img /dev/sda` |
| Restore a disk image and install GRUB | `ocs-sr -b -g auto restoredisk my-img /dev/sda` |
| Start a multicast Lite Server (image `my-img`) | `ocs-live-feed-img start my-img sda -md massive-deployment -cbm netboot -lscm massive-deployment -mdst from-image -cdt disk-2-mdisks -mcast-iface eth0 -b` |
| Stop the Lite Server | `ocs-live-feed-img stop my-image sda` |
| Run a custom pre‑run hook | Place script in `prerun/ocs/01‑my‑hook.sh` and add `-o0` to `OCS_OPT` (or use `--run-prerun-dir` flag). |
| Run a custom post‑run hook | Place script in `postrun/ocs/01‑my‑hook.sh` and add `-o1` to `OCS_OPT` (or use `--run-postrun-dir` flag). |

---

## CI‑Relevant Highlights
- All CLI options can be passed to `qemu-clonezilla-ci-run.sh` via `--cmd` or `--cmdpath`.
- For unattended CI runs, use `-b`/`--batch` and appropriate `ocs_live_extra_param` to feed `ocs‑sr` arguments.
- To mount a remote repository, set `ocs_repository` to an NFS/SMB/SSH/HTTP URI.
- When using UEFI, add `--efi` to the QEMU wrapper and ensure `ocs_live_run` respects EFI boot.
- Clean up temporary files (`/opt/overwrite-*.txt`, `/opt/*.sh`) via trap handlers.

---

**External References**
- Official website: https://clonezilla.org
- NCHC mirror: https://clonezilla.nchc.org.tw/
- Detailed docs: https://clonezilla.nchc.org.tw/clonezilla-live/doc/
- ocs‑sr man page: https://clonezilla.org/fine-print-live-doc.php?path=./clonezilla-live/doc/98_ocs_related_command_manpages/01-ocs-sr.doc
- Boot parameters: https://clonezilla.nchc.org.tw/clonezilla-live/doc/fine-print.php?path=99_Misc/00_live-boot-parameters.doc
- Lite Server script: https://github.com/stevenshiau/clonezilla/blob/master/sbin/ocs-live-feed-img

**Usage tip for agents**: When adding new scripts or parameters, reference this section to ensure correct Lite Server configuration and option usage.
