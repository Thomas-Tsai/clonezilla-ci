#!/usr/bin/env bash
# =============================================================================
# scripts/cron-report.sh
#
# Checks recent Clonezilla CI pipelines for new version detections and test
# results. Outputs a report to stdout. If no new version was detected, outputs
# nothing (empty stdout) so the cron monitor gate suppresses the message.
#
# Usage:
#   ./scripts/cron-report.sh [--hours N]
#
# Default: look back 4 hours (covers the gap between 3-hour cron intervals).
#
# Output contract:
#   - Empty stdout  → no new version detected, nothing to report
#   - Non-empty     → report text (markdown), send to user
#
# Environment:
#   GITLAB_TOKEN    GitLab API token (read from .env)
#   PROJECT_ID      GitLab project ID (read from .env)
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load .env
if [[ -f "${REPO_ROOT}/.env" ]]; then
    set -a
    source "${REPO_ROOT}/.env"
    set +a
fi

GITLAB_API_URL="${CI_API_V4_URL:-https://gitlab.com/api/v4}"
HOURS="${1:-4}"
# Allow --hours N flag
if [[ "$1" == "--hours" ]]; then
    HOURS="$2"
fi

# All 6 schedule IDs mapped to arch/type for display
declare -A SCHEDULE_NAMES
SCHEDULE_NAMES[4088594]="amd64/stable"
SCHEDULE_NAMES[4088595]="amd64/testing"
SCHEDULE_NAMES[4088596]="amd64/alt-stable"
SCHEDULE_NAMES[4088597]="amd64/alt-testing"
SCHEDULE_NAMES[4088598]="arm64/experimental"
SCHEDULE_NAMES[4088599]="riscv64/experimental"

echo "Fetching pipelines from last ${HOURS}h..." >&2

# Fetch recent pipelines (get more than needed, filter in Python)
# Use per_page=50 to cover hourly schedules * 6 archs * 4 hours = up to ~24
PIPELINES_JSON=$(curl -fsSL \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_API_URL}/projects/${PROJECT_ID}/pipelines?per_page=50&sort=desc" 2>/dev/null)

# Process in Python for reliability
export PIPELINES_JSON
python3 - "$HOURS" <<'PYEOF'
import json
import sys
import os
from datetime import datetime, timezone, timedelta

hours = int(sys.argv[1])
now = datetime.now(timezone.utc)
cutoff = now - timedelta(hours=hours)

# Read pipelines JSON from environment variable
pipelines = json.loads(os.environ.get("PIPELINES_JSON", "[]"))

# Filter: only pipelines since cutoff
recent = []
for p in pipelines:
    created = p.get("created_at", "")
    if not created:
        continue
    try:
        dt = datetime.fromisoformat(created.replace("Z", "+00:00"))
    except:
        continue
    if dt >= cutoff:
        recent.append(p)

if not recent:
    sys.exit(0)

# For each recent pipeline that is a parent (has source=schedule),
# check its child pipeline for VERSION_STATUS
# We need to fetch bridges for each parent pipeline
import urllib.request

GITLAB_TOKEN = __import__("os").environ.get("GITLAB_TOKEN", "")
PROJECT_ID = __import__("os").environ.get("PROJECT_ID", "freelabstw%2Fclonezilla-ci")
API = "https://gitlab.com/api/v4"

schedule_names = {
    "4088594": "amd64/stable",
    "4088595": "amd64/testing",
    "4088596": "amd64/alt-stable",
    "4088597": "amd64/alt-testing",
    "4088598": "arm64/experimental",
    "4088599": "riscv64/experimental",
}

def api_get(path):
    url = f"{API}/projects/{PROJECT_ID}/{path}"
    req = urllib.request.Request(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        print(f"API error: {e}", file=sys.stderr)
        return None

def get_child_pipeline_id(parent_id):
    """Get the child pipeline ID from the trigger:scheduled bridge."""
    bridges = api_get(f"pipelines/{parent_id}/bridges?per_page=100")
    if not bridges:
        return None
    for b in bridges:
        if b.get("name") == "trigger:scheduled":
            dp = b.get("downstream_pipeline") or {}
            return dp.get("id")
    return None

def get_child_jobs(child_id):
    """Get all jobs from child pipeline."""
    return api_get(f"pipelines/{child_id}/jobs?per_page=100") or []

def get_check_version_status(jobs):
    """Extract VERSION_STATUS from check_version job's log."""
    cv_jobs = [j for j in jobs if j["name"] == "check_version"]
    if not cv_jobs:
        return None  # manual trigger, no check_version
    job_id = cv_jobs[0]["id"]
    # Fetch trace
    url = f"{API}/projects/{PROJECT_ID}/jobs/{job_id}/trace"
    req = urllib.request.Request(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            trace = resp.read().decode(errors="replace")
        # Look for VERSION_STATUS= line
        for line in trace.split("\n"):
            if "VERSION_STATUS=" in line:
                # Extract the value
                for part in line.split():
                    if part.startswith("VERSION_STATUS="):
                        return part.split("=", 1)[1].strip()
    except:
        pass
    return "unknown"

def get_job_summary(jobs):
    """Summarize job statuses."""
    summary = {}
    for j in jobs:
        s = j["status"]
        summary[s] = summary.get(s, 0) + 1
    return summary

# Collect new-version findings
new_version_pipelines = []
no_change_count = 0
manual_count = 0

for p in recent:
    pid = p["id"]
    source = p.get("source", "")
    status = p.get("status", "")

    if source == "schedule":
        child_id = get_child_pipeline_id(pid)
        if not child_id:
            continue
        jobs = get_child_jobs(child_id)
        version_status = get_check_version_status(jobs)

        if version_status == "new_version":
            job_summary = get_job_summary(jobs)
            child_status = None
            child_pipe = api_get(f"pipelines/{child_id}")
            if child_pipe:
                child_status = child_pipe.get("status")

            # Get arch/type from schedule description if possible
            # We don't have schedule_id directly, infer from created_at time
            # Instead, just report what we have
            new_version_pipelines.append({
                "parent_id": pid,
                "child_id": child_id,
                "status": child_status or status,
                "jobs": job_summary,
                "jobs_list": jobs,
                "created_at": p.get("created_at"),
                "web_url": p.get("web_url"),
            })
        elif version_status in ("no_change", "in_progress", "mirror_empty"):
            no_change_count += 1
        elif version_status is None:
            # No check_version job — could be a push-triggered parent
            manual_count += 1
    elif source in ("push", "web", "api", "trigger"):
        manual_count += 1

# Only output if there are new versions
if not new_version_pipelines:
    print(f"No new Clonezilla versions detected in last {hours}h "
          f"({no_change_count} schedule runs, {manual_count} manual).", file=sys.stderr)
    sys.exit(0)

# Build report
tz = timezone(timedelta(hours=8))
now_taipei = datetime.now(tz)
report_lines = []
report_lines.append(f"## 🔄 Clonezilla CI — 新版本偵測報告")
report_lines.append(f"**{now_taipei.strftime('%Y-%m-%d %H:%M')} (Taipei)** | 過去 {hours} 小時")
report_lines.append("")

for nv in new_version_pipelines:
    created_dt = datetime.fromisoformat(
        nv["created_at"].replace("Z", "+00:00")
    ).astimezone(tz)
    report_lines.append(f"### 📦 新版本 — {created_dt.strftime('%H:%M')}")
    report_lines.append(f"- Pipeline: [#{nv['child_id']}]({nv['web_url']})")

    # Pipeline status
    status_emoji = {
        "success": "✅",
        "failed": "❌",
        "running": "🔄",
        "pending": "⏳",
        "created": "⏳",
    }.get(nv["status"], "❓")
    report_lines.append(f"- 狀態: {status_emoji} `{nv['status']}`")

    # Job summary
    js = nv["jobs"]
    parts = []
    for s in ["success", "failed", "running", "pending", "created", "skipped"]:
        if s in js:
            emoji = {
                "success": "✅", "failed": "❌", "running": "🔄",
                "pending": "⏳", "created": "⏳", "skipped": "⏭️"
            }.get(s, "❓")
            parts.append(f"{emoji} {s}: {js[s]}")
    if parts:
        report_lines.append(f"- Jobs: {' | '.join(parts)} (共 {sum(js.values())})")

    # List failed jobs if any
    failed_jobs = [j for j in nv["jobs_list"] if j["status"] == "failed"]
    if failed_jobs:
        report_lines.append(f"- **失敗的測試:**")
        for fj in failed_jobs:
            report_lines.append(f"  - ❌ `{fj['name']}`")

    # Find the version from check_version job
    cv_jobs = [j for j in nv["jobs_list"] if j["name"] == "check_version"]
    if cv_jobs:
        # Try to get version from trace
        job_id = cv_jobs[0]["id"]
        url = f"{API}/projects/{PROJECT_ID}/jobs/{job_id}/trace"
        req = urllib.request.Request(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                trace = resp.read().decode(errors="replace")
            for line in trace.split("\n"):
                if "LATEST_VERSION=" in line:
                    for part in line.split():
                        if part.startswith("LATEST_VERSION="):
                            ver = part.split("=", 1)[1].strip()
                            report_lines.append(f"- 版本: `{ver}`")
                            break
                    break
        except:
            pass

    report_lines.append("")

if no_change_count > 0 or manual_count > 0:
    report_lines.append("---")
    report_lines.append(f"ℹ️ 同期另有 {no_change_count} 個排程無新版、{manual_count} 個手動觸發。")

print("\n".join(report_lines))
PYEOF
