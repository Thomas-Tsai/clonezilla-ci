# Issue: `ocs-install-grub` fails to restore GRUB for RHEL‑family guests (separate `/boot` + `/grub2`) – writes `/grub` without `grub.cfg`

## Environment
- Clonezilla Live: 3.3.4‑23 (later versions likely affected)
- Distribution: Fedora 43, AlmaLinux 10, Rocky 10 (both have `/grub2` layout)
- Boot mode: BIOS (i386‑pc)

## Steps to Reproduce
1. Run the Clonezilla restore of one of the above systems with `-g auto` (which triggers `ocs-install-grub`).
2. After restore completes, boot the VM under QEMU (BIOS).

## Observed Behaviour
- During restore we see:
  ```
  Trying to use the grub2 from the running OS ...
  Running: grub-install --force --recheck --root-directory=/tmp/hd_img.XXXX /dev/vda
  Installation finished. No error reported.
  ```
- After restore, the VM boots into a bare `grub>` prompt.
- Filesystem inspection shows:
  - `/grub2` contains the original Fedora `grub.cfg` (correct).
  - `/grub` is newly created with typical Debian‑style files (`fonts/`, `i386-pc/`, etc.) **but no `grub.cfg`**.
  - The `bios_grub` partition (vda1) has been overwritten by the live `grub-install`, with its prefix set to `(hd0,gpt3)/grub`. Because `/grub/grub.cfg` does not exist, GRUB falls back to the prompt.

## A/B Test
- **With `-g auto`** – results above (failure).
- **Without `-g auto`** (other parameters unchanged) – the restored image boots normally; the original `core.img` is retained and the system loads `/grub2/grub.cfg` correctly.

## Root Cause
`ocs-install-grub`’s fallback path installs the *live* GRUB using a Debian‑style layout (`/grub`) and assumes that the restored OS will provide a `grub.cfg` in that location. In RHEL‑family systems, the correct location is `/grub2` (and the original `core.img` references it). Because the fallback does not account for this difference, it writes the wrong directory and does not generate a `grub.cfg`, causing the BIOS boot to fail.

## Proposed Fix
Enhance `ocs-install-grub` to:
1. Detect when the target system has a separate `/boot` **and** uses `/grub2` instead of `/grub`.
2. In such cases, either:
   - Mount the target’s `/boot` partition before attempting `grub-install`, or
   - Use the *fallback* branch but write to `/grub2` (not `/grub`) and generate a minimal `grub.cfg` that sources the real config from `/grub2/grub.cfg`.

## Reference
- Full logs and test artifacts are available in the CI workspace. The failing jobs are currently marked **RED** to surface the bug for downstream consumers.
