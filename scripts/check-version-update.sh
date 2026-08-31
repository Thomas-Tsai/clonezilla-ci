#!/usr/bin/env bash
# ============================================================================
# scripts/check-version-update.sh
#
# Compares the latest Clonezilla Live zip on the NCHC mirror against the most
# recently tested version recorded in reports.json on the test-reports branch.
#
# This reuses the existing reporting infrastructure: publish_reports.sh already
# pushes test results + reports.json to the test-reports branch using
# CI_JOB_TOKEN, so no additional state file or token is needed.
#
# Output contract (stdout, machine-parseable, one KEY=VALUE per line):
#   VERSION_STATUS=new_version | no_change | init
#   LATEST_URL=<full URL of the latest zip on the mirror>
#   LATEST_VERSION=<zip basename without .zip>
#   PREVIOUS_VERSION=<version recorded in reports.json, empty if first run>
#   STATE_KEY=<arch>_<type> key used for logging
#
# Exit codes:
#   0  comparison succeeded (regardless of new/no-change)
#   1  failed to fetch the latest version from NCHC
#   2  failed to fetch reports.json from test-reports branch
#
# Usage:
#   ./scripts/check-version-update.sh --arch amd64 --type stable
#   CI_PIPELINE_ID=12345 ./scripts/check-version-update.sh --arch amd64 --type stable
#   ./scripts/check-version-update.sh --arch amd64 --type stable --dry-run
#
# Environment (CI):
#   CI_JOB_TOKEN           GitLab CI job token (used to fetch reports.json).
#   CI_API_V4_URL          GitLab API v4 base URL.
#   CI_PROJECT_ID          GitLab project ID.
#   CI_SERVER_HOST         GitLab server host (e.g. gitlab.com).
#   CI_PROJECT_PATH        Namespace/project path.
#   If these are unset, the script falls back to anonymous GitLab API access
#   (works for public projects like freelabstw/clonezilla-ci).
# ============================================================================

set -euo pipefail
IFS=$'\n\t'

# --- Defaults ---------------------------------------------------------------
ARCH=""
TYPE="stable"
DRY_RUN=false

# Resolve repo root from script location so it works from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOWNLOAD_SCRIPT="${REPO_ROOT}/download-clonezilla.sh"

# CI environment (with safe fallbacks for public-project anonymous access).
GITLAB_API_URL="${CI_API_V4_URL:-https://gitlab.com/api/v4}"
PROJECT_ID="${CI_PROJECT_ID:-freelabstw%2Fclonezilla-ci}"
REPORTS_BRANCH="test-reports"

# --- Argument parsing -------------------------------------------------------
print_usage() {
    cat >&2 <<EOF
Usage: $0 --arch <ARCH> --type <TYPE> [--dry-run]

Required:
  --arch <ARCH>   amd64 | arm64 | riscv64
  --type <TYPE>   stable | testing | alternative-stable | alternative-testing | experimental
                  (ignored for arm64/riscv64, which are always 'experimental')

Options:
  --dry-run       Do not commit anything; just report.
  -h, --help      Show this help.

Environment (set automatically by GitLab CI):
  CI_JOB_TOKEN, CI_API_V4_URL, CI_PROJECT_ID
EOF
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        --type) TYPE="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) print_usage ;;
        *) echo "Error: Unknown option: $1" >&2; print_usage ;;
    esac
done

if [[ -z "$ARCH" ]]; then
    echo "Error: --arch is required." >&2
    print_usage
fi

# Normalize: arm64/riscv64 are always "experimental" in the NCHC layout.
if [[ "$ARCH" == "arm64" || "$ARCH" == "riscv64" ]]; then
    TYPE="experimental"
fi

STATE_KEY="${ARCH}_${TYPE}"

# --- Dependency checks ------------------------------------------------------
if [[ ! -x "$DOWNLOAD_SCRIPT" ]]; then
    chmod +x "$DOWNLOAD_SCRIPT" 2>/dev/null || true
fi
if [[ ! -x "$DOWNLOAD_SCRIPT" ]]; then
    echo "Error: download-clonezilla.sh not found or not executable at ${DOWNLOAD_SCRIPT}" >&2
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed." >&2
    exit 2
fi

# --- Functions --------------------------------------------------------------

# Echo the latest download URL for ARCH/TYPE by calling the repo's existing
# download script in --dry-run mode.
fetch_latest_url() {
    "$DOWNLOAD_SCRIPT" --arch "$ARCH" --type "$TYPE" --dry-run 2>/dev/null | tail -n1
}

# Fetch reports.json from the test-reports branch via GitLab API.
# Uses CI_JOB_TOKEN if available; falls back to anonymous for public projects.
fetch_reports_json() {
    local url="${GITLAB_API_URL}/projects/${PROJECT_ID}/repository/files/reports.json/raw?ref=${REPORTS_BRANCH}"
    local auth_header=()
    if [[ -n "${CI_JOB_TOKEN:-}" ]]; then
        auth_header=(--header "JOB-TOKEN: ${CI_JOB_TOKEN}")
    fi
    curl -fsSL "${auth_header[@]}" "$url" 2>/dev/null
}

# Check if a specific zip_name exists in reports.json (i.e. has been tested before).
# Returns the zip_name if found, empty otherwise.
has_been_tested() {
    local reports_json="$1"
    local target_version="$2"
    echo "$reports_json" | jq -r --arg v "$target_version" \
        '[.[] | select(.zip_name == $v)] | if length > 0 then $v else empty end' 2>/dev/null
}

# Find the most recently tested zip_name for the given ARCH from reports.json.
# Used only for informational logging (shows what was last tested for this arch).
get_last_tested_version() {
    local reports_json="$1"
    # reports.json is a JSON array; filter entries whose zip_name ends with
    # "-${ARCH}", sort by date descending, take the first.
    echo "$reports_json" | jq -r --arg arch "$ARCH" \
        '[.[] | select(.zip_name | endswith("-" + $arch))] | sort_by(.date) | reverse | .[0].zip_name // empty' 2>/dev/null
}

# --- Main logic -------------------------------------------------------------

echo "--- check-version-update.sh ---" >&2
echo "ARCH=${ARCH}  TYPE=${TYPE}  STATE_KEY=${STATE_KEY}" >&2
echo "DRY_RUN=${DRY_RUN}" >&2
echo >&2

# 1. Fetch the latest URL from NCHC.
echo "Fetching latest version URL from NCHC..." >&2
LATEST_URL="$(fetch_latest_url)"
if [[ -z "$LATEST_URL" ]]; then
    echo "Error: Could not determine latest zip URL for ${ARCH}/${TYPE}." >&2
    echo "VERSION_STATUS=error"
    exit 1
fi
LATEST_VERSION="$(basename "$LATEST_URL" .zip)"
echo "Latest on mirror: ${LATEST_VERSION}" >&2
echo "  URL: ${LATEST_URL}" >&2
echo >&2

# 2. Fetch reports.json from test-reports branch.
echo "Fetching reports.json from ${REPORTS_BRANCH} branch..." >&2
REPORTS_JSON="$(fetch_reports_json || true)"
if [[ -z "$REPORTS_JSON" ]]; then
    echo "Warning: Could not fetch reports.json (branch may not exist yet). Treating as first run." >&2
    PREVIOUS_VERSION=""
else
    # Check if the exact LATEST_VERSION has ever been tested.
    PREVIOUS_VERSION="$(has_been_tested "$REPORTS_JSON" "$LATEST_VERSION")"
    if [[ -n "$PREVIOUS_VERSION" ]]; then
        echo "Version ${LATEST_VERSION} has already been tested (found in reports.json)." >&2
    else
        # For informational logging, show the last tested version for this arch.
        last_for_arch="$(get_last_tested_version "$REPORTS_JSON")"
        echo "Version ${LATEST_VERSION} has NOT been tested yet." >&2
        if [[ -n "$last_for_arch" ]]; then
            echo "Last tested version for ${ARCH}: ${last_for_arch}" >&2
        fi
    fi
fi
echo >&2

# 3. Compare and decide.
if [[ -z "$PREVIOUS_VERSION" ]]; then
    # Version was never tested before -> run tests.
    STATUS="new_version"
    if [[ -z "$REPORTS_JSON" ]]; then
        echo "First run (no reports.json): treating as new version." >&2
    else
        echo "New version detected: ${LATEST_VERSION} not in reports.json." >&2
    fi
elif [[ "$PREVIOUS_VERSION" == "$LATEST_VERSION" ]]; then
    STATUS="no_change"
    echo "No version change detected: ${LATEST_VERSION} was already tested." >&2
else
    STATUS="new_version"
    echo "!!! NEW VERSION DETECTED !!!" >&2
    echo "  ${PREVIOUS_VERSION} -> ${LATEST_VERSION}" >&2
fi

# 4. Emit machine-readable output for the CI dotenv artifact.
#    No state file update is needed here: when tests run, the pages job will
#    publish results + update reports.json on the test-reports branch, which
#    is exactly what this script reads next time.
echo "VERSION_STATUS=${STATUS}"
echo "LATEST_URL=${LATEST_URL}"
echo "LATEST_VERSION=${LATEST_VERSION}"
echo "PREVIOUS_VERSION=${PREVIOUS_VERSION}"
echo "STATE_KEY=${STATE_KEY}"

exit 0
