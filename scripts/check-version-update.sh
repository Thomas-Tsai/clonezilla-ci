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
#   VERSION_STATUS=new_version | no_change | in_progress | init
#   LATEST_URL=<full URL of the latest zip on the mirror>
#   LATEST_VERSION=<zip basename without .zip>
#   PREVIOUS_VERSION=<version recorded in reports.json, empty if first run>
#   STATE_KEY=<arch>_<type> key used for logging
#   CLAIMED=true | false  (whether this run recorded an in-progress claim)
#
# Concurrency note:
#   reports.json is only updated by publish_reports at the END of a full test
#   run, which can take hours. Without an early reservation, every schedule
#   that fires while a full run is still in flight would detect the same "new
#   version" and start a duplicate 22-job run, eventually exceeding the
#   GitLab.com per-project active-jobs quota. To prevent this, whenever a new
#   version is detected this script immediately records a claim in
#   `in-progress.json` on the test-reports branch. Later schedules see a fresh
#   claim (younger than CLAIM_TTL_SECONDS, default 12h) and emit
#   VERSION_STATUS=in_progress, which downstream jobs treat like a skip.
#   publish_reports.sh removes the claim when the report is published; the TTL
#   is the fallback for pipelines that get canceled mid-run.
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

# In-progress claim state (see header "Concurrency note").
IN_PROGRESS_FILE="in-progress.json"
CLAIM_TTL_SECONDS="${CLAIM_TTL_SECONDS:-43200}"   # 12 hours

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

# Fetch in-progress.json from the test-reports branch via GitLab API.
# Returns an empty string when the file does not exist yet.
fetch_in_progress_json() {
    local url="${GITLAB_API_URL}/projects/${PROJECT_ID}/repository/files/${IN_PROGRESS_FILE}/raw?ref=${REPORTS_BRANCH}"
    local auth_header=()
    if [[ -n "${CI_JOB_TOKEN:-}" ]]; then
        auth_header=(--header "JOB-TOKEN: ${CI_JOB_TOKEN}")
    fi
    curl -fsSL "${auth_header[@]}" "$url" 2>/dev/null
}

# Print "<version>\t<claimed_at>" for STATE_KEY from the given JSON, or empty.
get_in_progress_entry() {
    local claims_json="$1"
    echo "$claims_json" | jq -r --arg k "$STATE_KEY" \
        '.[$k] // empty | "\(.version)\t\(.claimed_at)"' 2>/dev/null
}

# Return 0 if the given ISO-8601 timestamp is younger than CLAIM_TTL_SECONDS.
# Timestamps up to 10 minutes in the future are still fresh (clock skew
# between runners); undatable/malformed timestamps are treated as stale.
is_claim_fresh() {
    local claimed_at="$1"
    local claimed_ts now_ts delta
    claimed_ts="$(date -u -d "$claimed_at" +%s 2>/dev/null)" || return 1
    [[ -n "$claimed_ts" ]] || return 1
    now_ts="$(date -u +%s)"
    delta=$(( now_ts - claimed_ts ))
    (( delta < CLAIM_TTL_SECONDS && delta > -600 ))
}

# Record an in-progress claim for STATE_KEY/LATEST_VERSION on the
# test-reports branch, pushing with -o ci.skip so the pages pipeline is not
# triggered. Uses a fresh-shallow-clone + push retry loop to stay race-safe
# against concurrently scheduled check_version jobs.
# Returns: 0 claimed, 2 lost race (a fresh claim for the same version exists),
#          3 skipped (no CI_JOB_TOKEN, e.g. local run), 4 push/write failure.
claim_version() {
    if [[ -z "${CI_JOB_TOKEN:-}" ]]; then
        echo "Warning: CI_JOB_TOKEN not set; cannot write claim (local run?)." >&2
        return 3
    fi

    local server_host="${CI_SERVER_HOST:-gitlab.com}"
    local project_path="${CI_PROJECT_PATH:-freelabstw/clonezilla-ci}"
    local git_url="https://gitlab-ci-token:${CI_JOB_TOKEN}@${server_host}/${project_path}.git"
    local now_iso tmpdir attempt rc
    now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    tmpdir="$(mktemp -d)"

    for attempt in 1 2 3; do
        rm -rf "${tmpdir}/repo"
        if ! git clone --quiet --depth 1 --branch "${REPORTS_BRANCH}" \
                "${git_url}" "${tmpdir}/repo" 2>"${tmpdir}/clone.err"; then
            echo "Warning: clone of branch ${REPORTS_BRANCH} failed (attempt ${attempt}):" >&2
            sed "s#${CI_JOB_TOKEN}#<token>#g" "${tmpdir}/clone.err" >&2 || true
            rm -rf "$tmpdir"
            return 4
        fi

        pushd "${tmpdir}/repo" >/dev/null

        # Re-check the live state: another pipeline may have claimed meanwhile.
        local entry ip_version ip_ts
        entry="$(cat "${IN_PROGRESS_FILE}" 2>/dev/null || echo '{}')"
        entry="$(get_in_progress_entry "$entry" || true)"
        if [[ -n "$entry" ]]; then
            IFS=$'\t' read -r ip_version ip_ts <<< "$entry"
            if [[ "$ip_version" == "$LATEST_VERSION" ]] && is_claim_fresh "$ip_ts"; then
                popd >/dev/null
                rm -rf "$tmpdir"
                return 2
            fi
        fi

        [[ -f "${IN_PROGRESS_FILE}" ]] || echo '{}' > "${IN_PROGRESS_FILE}"
        jq --arg k "$STATE_KEY" --arg ver "$LATEST_VERSION" --arg ts "$now_iso" \
           --arg pid "${CI_PIPELINE_ID:-}" --arg url "${CI_PIPELINE_URL:-}" \
           '.[$k] = {version: $ver, claimed_at: $ts, pipeline_id: $pid, pipeline_url: $url}' \
           "${IN_PROGRESS_FILE}" > "${IN_PROGRESS_FILE}.tmp" \
            && mv "${IN_PROGRESS_FILE}.tmp" "${IN_PROGRESS_FILE}"

        git config user.name "GitLab CI Bot"
        git config user.email "gitlab-ci-bot@${CI_PROJECT_NAMESPACE:-freelabstw}.gitlab.io"
        git add "${IN_PROGRESS_FILE}"
        if git diff --staged --quiet; then
            # Nothing to commit (claim already identical); treat as success.
            popd >/dev/null
            rm -rf "$tmpdir"
            return 0
        fi
        git commit --quiet -m "claim: ${STATE_KEY} testing ${LATEST_VERSION} (pipeline ${CI_PIPELINE_ID:-?})"

        rc=0
        git push --quiet -o ci.skip origin "${REPORTS_BRANCH}" 2>"${tmpdir}/push.err" || rc=$?
        popd >/dev/null

        if [[ "$rc" -eq 0 ]]; then
            rm -rf "$tmpdir"
            return 0
        fi
        echo "Warning: claim push failed (attempt ${attempt}), retrying..." >&2
        sed "s#${CI_JOB_TOKEN}#<token>#g" "${tmpdir}/push.err" >&2 || true
    done

    rm -rf "$tmpdir"
    return 4
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

# 3b. New version -> consult in-progress.json so that only one scheduled
#     pipeline actually runs the full suite for this version (see the
#     "Concurrency note" in the header).
CLAIMED="false"
if [[ "$STATUS" == "new_version" ]]; then
    echo "Checking in-progress claims on ${REPORTS_BRANCH} branch..." >&2
    CLAIMS_JSON="$(fetch_in_progress_json || true)"
    entry="$(get_in_progress_entry "${CLAIMS_JSON:-{\}}" || true)"
    if [[ -n "$entry" ]]; then
        IFS=$'\t' read -r ip_version ip_ts <<< "$entry"
        if [[ "$ip_version" == "$LATEST_VERSION" ]] && is_claim_fresh "$ip_ts"; then
            STATUS="in_progress"
            echo "Version ${LATEST_VERSION} is already being tested (claimed at ${ip_ts}). Skipping." >&2
        fi
    fi

    if [[ "$STATUS" == "new_version" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[dry-run] Would record a claim for ${LATEST_VERSION} (${STATE_KEY}); skipping write." >&2
        else
            rc=0
            claim_version || rc=$?
            case "$rc" in
                0)
                    CLAIMED="true"
                    echo "Claim recorded: ${STATE_KEY} will test ${LATEST_VERSION}." >&2
                    ;;
                2)
                    STATUS="in_progress"
                    echo "Another pipeline claimed ${LATEST_VERSION} first. Skipping." >&2
                    ;;
                *)
                    echo "Warning: failed to record claim (rc=${rc}). Running tests anyway;" >&2
                    echo "         duplicate runs are possible for this version." >&2
                    ;;
            esac
        fi
    fi
fi
echo >&2

# 4. Emit machine-readable output for the CI dotenv artifact.
#    reports.json is updated later by publish_reports.sh (see step 3b above
#    for the early in-progress claim that prevents duplicate concurrent runs).
echo "VERSION_STATUS=${STATUS}"
echo "LATEST_URL=${LATEST_URL}"
echo "LATEST_VERSION=${LATEST_VERSION}"
echo "PREVIOUS_VERSION=${PREVIOUS_VERSION}"
echo "STATE_KEY=${STATE_KEY}"
echo "CLAIMED=${CLAIMED}"

exit 0
