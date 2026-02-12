# AGENTS.md – Guidelines for Automated Agents

---

## Table of Contents
1. [Purpose](#purpose)
2. [Operational Guidelines](#operational-guidelines)
3. [Build Commands](#build-commands)
4. [Test Commands](#test-commands)
5. [Lint / Static Analysis](#lint--static-analysis)
6. [Code‑Style Guidelines](#code‑style-guidelines)
   - [General Bash Practices](#general-bash-practices)
   - [Naming Conventions](#naming-conventions)
   - [Import / Sourcing Rules](#import--sourcing-rules)
   - [Error Handling & Exit Codes](#error-handling--exit-codes)
   - [Logging & Output Consistency](#logging--output-consistency)
   - [Dependency Management](#dependency-management)
   - [Testing Conventions](#testing-conventions)
   - [Documentation Headers](#documentation-headers)
7. [Cursor / Copilot Rules](#cursor--copilot-rules)
8. [Frequently Used Helper Scripts](#frequently-used-helper-scripts)
9. [Version‑Control Practices (Git)](#version‑control-practices-git)
10. [Running Inside Docker](#running-inside-docker)
11. [Continuous‑Integration Tips](#continuous‑integration-tips)
1. [Purpose](#purpose)
2. [Build Commands](#build-commands)
3. [Test Commands](#test-commands)
4. [Lint / Static Analysis](#lint--static-analysis)
5. [Code‑Style Guidelines](#code‑style-guidelines)
   - [General Bash Practices](#general-bash-practices)
   - [Naming Conventions](#naming-conventions)
   - [Import / Sourcing Rules](#import--sourcing-rules)
   - [Error Handling & Exit Codes](#error-handling--exit-codes)
   - [Logging & Output Consistency](#logging--output-consistency)
   - [Dependency Management](#dependency-management)
   - [Testing Conventions](#testing-conventions)
   - [Documentation Headers](#documentation-headers)
6. [Cursor / Copilot Rules](#cursor--copilot-rules)
7. [Frequently Used Helper Scripts](#frequently-used-helper-scripts)
8. [Version‑Control Practices (Git)](#version‑control-practices-git)
9. [Running Inside Docker](#running-inside-docker)
10. [Continuous‑Integration Tips](#continuous‑integration-tips)

---

## Purpose

## Operational Guidelines
- Prefer using Traditional Chinese (繁體中文) for documentation, comments, and user‑facing messages unless the user explicitly requests another language.
- **Always keep `todo.md` up‑to‑date** – add new tasks, mark completed ones, and adjust priorities as the project evolves.
- When a **new script or command‑line parameter** is introduced, **immediately update `usage.md`** so the usage guide stays current.
- **Major functionality additions** must be reflected in the top‑level `README.md` (feature description, usage examples, screenshots, etc.).
- Code should be written to **support parallel execution** where possible; avoid shared mutable state, and handle termination (`kill`) gracefully by tracking PIDs and cleaning up resources.

## Build Commands
This file provides a single source of truth for any **agentic coding assistants** (e.g., OpenAI‑based agents, GitHub Copilot, Cursor) that operate on the `clonezilla-ci` repository.  It defines:
- How to **build** the project.
- How to **run** the full test suite **or** a single test.
- **Linting** and **static analysis** expectations.
- A comprehensive **Bash style guide** covering imports, formatting, naming, error handling, and more.
- Any existing **Cursor** or **Copilot** instruction files.

Agents should read this file before making any code changes, committing, or creating pull requests.

---

## Build Commands
| Target | Command | Description |
|--------|---------|-------------|
| Docker image (recommended) | `docker build -t clonezilla-ci .` | Builds a reproducible Docker image containing all runtime dependencies (QEMU, guestfs, etc.). |
| Local shell environment | `./bootstrap.sh` *(not provided – create if needed)* | Placeholder for a future script that would install system packages on a Debian‑based host. |
| Verify Docker build | `docker run --rm clonezilla-ci echo "Docker image ready"` | Quick sanity check that the image runs.

**Tip for agents:** Prefer the Docker build path.  It isolates the CI environment and guarantees repeatable results.

---

## Test Commands
### 1. Run the **full** test suite
```bash
# From the repository root
./start.sh            # runs every test_*.sh script in jobs/
```
The script logs to `./logs/` and prints a summary at the end.

### 2. Run a **single** test script
```bash
# Example: Ubuntu OS clone‑restore test
cd jobs && ./test_os_ubuntu.sh --arch amd64 --zip path/to/clonezilla.zip
```
All test scripts accept the same CLI flags (`--zip`, `--arch`, `--type`, `--no-ssh-forward`, `-h/--help`).  Agents should pass only the arguments required for the test they are exercising.

### 3. Run a test **inside Docker**
```bash
docker run --rm -it \
  -v "$(pwd)":/app \
  -v "$(pwd)/dev/testData":/app/dev/testData \
  -v "$(pwd)/qemu/cloudimages":/app/qemu/cloudimages \
  -v "$(pwd)/isos":/app/isos \
  -v "$(pwd)/zip":/app/zip \
  -v "$(pwd)/partimag":/app/partimag \
  -v "$(pwd)/logs":/app/logs \
  clonezilla-ci ./start.sh --arch arm64 --zip /app/zip/clonezilla-live-stable-arm64.zip
```
The Docker command mirrors the example in `README.md`.

---

## Lint / Static Analysis
| Tool | Command | What it checks |
|------|---------|----------------|
| **shellcheck** (recommended) | `shellcheck **/*.sh` | Detects common Bash bugs, quoting issues, and style violations. |
| **shfmt** (optional) | `shfmt -d -i 4 **/*.sh` | Enforces consistent indentation (4 spaces) and line‑break style. |
| **bashate** (alternative) | `bashate -i E006 **/*.sh` | Checks for excessive line length and use of `[[` vs `[`. |
| **hadolint** (Dockerfile) | `hadolint Dockerfile` | Lints the Dockerfile for best practices. |

Agents should run the relevant linter **before** committing.  If a linter reports a failure, the agent must fix the issue or open a ticket for manual review.

---

## Code‑Style Guidelines
### General Bash Practices
1. **Shebang** – Every executable script starts with `#!/usr/bin/env bash` (or `#!/bin/bash` if portability is not a concern).
2. **Strict mode** – At the top of each script add:
   ```bash
   set -euo pipefail   # abort on error, undefined variables, and pipe failures
   IFS=$'\n\t'        # sane word splitting
   ```
3. **Indentation** – Four spaces per level; **no tabs**.  Use `shfmt -i 4` to verify.
4. **Quote everything** – Variable expansions, command substitutions, and glob patterns must be quoted unless deliberately unquoted.
5. **Avoid `eval`** – Use arrays or proper parameter expansion instead.
6. **Prefer `[[ … ]]`** – For test expressions; it avoids many quoting pitfalls.
7. **Use `local`** – Inside functions to keep variable scope limited.
8. **Exit codes** – Return `0` on success; non‑zero values must be documented in a comment block above the function.

### Naming Conventions
| Element | Recommended pattern |
|---------|----------------------|
| Variables | `snake_case_all_lower` (e.g., `log_dir`, `clonezilla_zip`). |
| Constants | `UPPER_SNAKE_CASE` (e.g., `DEFAULT_ARCH`). |
| Functions | `verb_noun` (e.g., `run_os_clone_restore`). |
| Test functions (shunit2) | `test_<description>` (already used). |
| Scripts | `verb_target.sh` (e.g., `download-clonezilla.sh`). |

### Import / Sourcing Rules
- All reusable logic lives in `jobs/common.sh` or `dev/…`.  Scripts must source **only** what they need using an absolute path derived from `$(dirname "$0")`.
- Never source a file that mutates global state without a clear comment explaining the side‑effects.
- Do **not** use `source /etc/profile` or similar system files.

### Error Handling & Exit Codes
1. **Return early on error** – Use `|| return` or `|| exit 1` after critical commands.
2. **Custom error messages** – Prefer `echo "[ERROR] <msg>" >&2`.
3. **Cleanup** – Register `trap` handlers for temporary files or network interfaces:
   ```bash
   cleanup() { rm -f "$tmp_file"; }
   trap cleanup EXIT
   ```
4. **Consistent exit codes** – Define symbolic constants when needed:
   ```bash
   readonly ERR_MISSING_IMAGE=2
   if [[ ! -f "$image_path" ]]; then
       echo "[ERROR] Image not found" >&2
       exit $ERR_MISSING_IMAGE
   fi
   ```

### Logging & Output Consistency
- Prefix all informational messages with `---` or `[INFO]` and send to **stdout**.
- Prefix warnings with `[WARN]` and errors with `[ERROR]` and send to **stderr**.
- Use the `LOG_DIR` variable defined in `start.sh` for per‑script logs; write to `$LOG_DIR/<script_name>.log` via `exec &> >(tee -a "$log_file")`.
- When a script finishes successfully, print a **single line** `--- Test Job PASSED: <script>` – this pattern is parsed by CI dashboards.

### Dependency Management
- All external binaries must be documented at the top of the script in a `REQUIRES=` array, e.g.:
  ```bash
  REQUIRES=(qemu-system-x86_64 guestfish shunit2)
  for cmd in "${REQUIRES[@]}"; do command -v "$cmd" >/dev/null || { echo "[ERROR] $cmd missing" >&2; exit 127; }; done
  ```
- For Docker builds, the `Dockerfile` must install the same set of packages listed here.  Agents should keep the two definitions in sync.

### Testing Conventions
- Use **shunit2** – every `test_*.sh` file must end with:
  ```bash
  . shunit2
  ```
- Each test function must start with `test_` and contain **exactly one** logical assertion (e.g., `assertEquals`, `assertTrue`).
- Tests should be **idempotent** – they may be run repeatedly without side effects.
- When a test creates temporary files, always clean them up in a `tearDown` function.

### Documentation Headers
Every script should start with a standardized header block:
```bash
#!/usr/bin/env bash
#
# <script-name>.sh – One‑sentence description.
#
# Usage:   ./<script-name>.sh [options]
#
# Options:
#   --zip <path>   Path to Clonezilla Live ZIP.
#   --arch <arch>  Target architecture (amd64, arm64, ...).
#   -h|--help      Show this help.
#
# Environment:
#   LOG_DIR – Directory for log files (default: ./logs).
#
# Dependencies: qemu-system-x86_64, guestfish, shunit2
#
# Author: Thomas (maintainer)
# SPDX‑License-Identifier: GPL-2.0-or-later
#
```
Keep the header **exactly** as shown; agents must not modify the licensing line.

---

## Cursor / Copilot Rules
The repository does **not** contain a `.cursor/` directory or a `.github/copilot-instructions.md` file at present.  If such files are added in the future, agents should merge their contents into the relevant sections above.

---

## Frequently Used Helper Scripts
| Script | Description |
|--------|-------------|
| `qemu-clonezilla-ci-run.sh` | Low‑level wrapper that starts a QEMU VM with the Clonezilla ISO and executes arbitrary Clonezilla commands. |
| `clonezilla-zip2qcow.sh` | Converts a Clonezilla Live ZIP into QCOW2 + kernel + initrd needed by the VM runner. |
| `os-clone-restore.sh` | Orchestrates a full OS backup → restore → boot validation cycle. |
| `data-clone-restore.sh` | Similar to above but focuses on filesystem data integrity. |
| `validate.sh` | Verifies that a restored disk boots and runs cloud‑init. |
| `download-clonezilla.sh` | Downloads the latest Clonezilla Live ZIP if not present. |

Agents may call these utilities directly; they already respect the strict Bash conventions described earlier.

---

## Version‑Control Practices (Git)
1. **Never commit generated files** – e.g., logs, `.qcow2` images, or downloaded ISOs.
2. **Commit messages** – Follow the conventional format:
   ```text
   <type>(<scope>): <short summary>

   <body> (optional)
   ```
   *type* = `feat`, `fix`, `docs`, `test`, `refactor`, `chore`.
3. **Branch naming** – `feature/<short-name>` or `bugfix/<issue-id>`.
4. **Pre‑commit hook** – Runs `shellcheck` and `shfmt -d`.  Agents must ensure the hook passes before opening a PR.
5. **Pull‑request template** – Include sections for **Test Plan**, **Affected Scripts**, and **Documentation Updates**.

---

## Running Inside Docker
When an agent executes a command inside Docker, it must:
- Mount the repository root at `/app`.
- Mount the `logs/` directory to persist output.
- Pass any required environment variables (e.g., `ARCH`, `CLONEZILLA_ZIP`).
- Use `--rm -it` so the container is removed after execution.

Example (single test):
```bash
docker run --rm -it \
  -v "$(pwd)":/app \
  -v "$(pwd)/logs":/app/logs \
  clonezilla-ci /app/jobs/test_os_ubuntu.sh --arch amd64
```

---

## Continuous‑Integration Tips
- The `.gitlab-ci.yml` (or analogous CI config) runs `./start.sh` inside the Docker image.
- Agents should **never** modify the CI configuration without a clear `changelog` entry.
- When adding a new test script, update `jobs/README.md` (if it exists) and ensure the script is executable (`chmod +x`).
- Keep the CI runtime under **30 minutes**; if a new test exceeds this, consider splitting it into smaller jobs.

---

## Skills

- `clonezilla` skill provides domain‑specific guidance for Clonezilla usage within this repository. Located at `skills/clonezilla.md`. Agents should load it with `skill(name="clonezilla")` when relevant.

*This document is intentionally verbose (~150 lines) to give agents a comprehensive reference.  Keep it up‑to‑date as the repository evolves.*
