#!/usr/bin/env bash
#
# notify-telegram.sh - Send Clonezilla CI notifications to a Telegram group.
#
# Two modes:
#   started   - New-version notice, called from the check_version job.
#   finished  - Test-suite summary, called from the notify:telegram job.
#
# Notification filter (this is what keeps the group quiet):
#   - scheduled pipeline + VERSION_STATUS=new_version            -> send
#   - scheduled pipeline + no_change / in_progress / mirror_empty -> skip
#   - manual pipeline (push / web / api / trigger)                -> always send
#
# The script NEVER fails the calling job: errors are logged as warnings
# and the exit code is always 0.
#
# Usage:   ./scripts/notify-telegram.sh <started|finished> [--dry-run]
#
# Options:
#   --dry-run   Print the message instead of sending (no tokens required).
#   -h|--help   Show this help.
#
# Environment:
#   TELEGRAM_BOT_TOKEN   Telegram bot token from @BotFather (masked CI/CD variable).
#   TELEGRAM_CHAT_ID     Target group chat id, usually negative (masked CI/CD variable).
#   PAGES_BASE_URL       Pages site base URL
#                        (default: https://clonezilla-ci-036aa1.gitlab.io).
#   Regular GitLab CI variables are used when present:
#     PARENT_PIPELINE_SOURCE, VERSION_STATUS, ZIP_FILE_FROM_BUILD, LATEST_VERSION,
#     ARCH, TYPE, GITLAB_USER_NAME, CI_PIPELINE_URL, CI_PIPELINE_IID,
#     CI_COMMIT_BRANCH, CI_DEFAULT_BRANCH
#
# Dependencies: curl
#
# Author: Thomas (maintainer)
# SPDX-License-Identifier: GPL-2.0-or-later
#
set -euo pipefail
IFS=$'\n\t'

MODE=""
DRY_RUN=false
PAGES_BASE_URL="${PAGES_BASE_URL:-https://clonezilla-ci-036aa1.gitlab.io}"

log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*" >&2; }

print_usage() {
    cat >&2 <<EOF
Usage: $0 <started|finished> [--dry-run]

Modes:
  started    New-version notice (called from the check_version job).
  finished   Test-suite summary (called from the notify:telegram job).

Options:
  --dry-run  Print the message instead of sending; no tokens required.
  -h|--help  Show this help.
EOF
    exit 1
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            started | finished)
                if [[ -n "$MODE" ]]; then
                    echo "Error: multiple modes given." >&2
                    print_usage
                fi
                MODE="$1"
                shift
                ;;
            --dry-run) DRY_RUN=true; shift ;;
            -h | --help) print_usage ;;
            *)
                echo "Error: unknown argument: $1" >&2
                print_usage
                ;;
        esac
    done
    [[ -n "$MODE" ]] || print_usage
}

# Escape &, <, > for Telegram HTML parse mode.
html_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    printf '%s' "$s"
}

# The notification filter. Returns 0 when a message should be sent.
passes_filter() {
    case "$MODE" in
        started)
            [[ "${VERSION_STATUS:-}" == "new_version" ]]
            ;;
        finished)
            if [[ "${PARENT_PIPELINE_SOURCE:-}" == "schedule" ]]; then
                [[ "${VERSION_STATUS:-}" == "new_version" ]]
            else
                return 0
            fi
            ;;
    esac
}

send_telegram_message() {
    local text="$1"
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[dry-run] Would send:"
        echo "----------------------------------------"
        echo "$text"
        echo "----------------------------------------"
        return 0
    fi
    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        log_warn "TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set; notification skipped."
        log_warn "Message would have been:"
        echo "$text" >&2
        return 0
    fi
    local response
    if response=$(curl -fsSL --max-time 30 \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${text}" \
        --data-urlencode "parse_mode=HTML" \
        --data-urlencode "disable_web_page_preview=true" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" 2>&1); then
        log_info "Telegram notification sent (mode=${MODE})."
    else
        log_warn "Telegram API call failed: ${response}"
    fi
    return 0
}

build_started_message() {
    local version="${LATEST_VERSION:-${ZIP_FILE_FROM_BUILD:-unknown}}"
    version="${version%.zip}"
    cat <<EOF
🆕 <b>Clonezilla 新版本偵測</b>
版本: <code>$(html_escape "${version}")</code>
架構/類型: $(html_escape "${ARCH:-unknown}") / $(html_escape "${TYPE:-unknown}")
⏳ 開始測試 · <a href="${CI_PIPELINE_URL:-}">Pipeline #${CI_PIPELINE_IID:-?}</a>
EOF
}

# jobs that publish_reports.sh also treats as expected; kept in sync so the
# Telegram summary matches the published report (missing artifact = failed).
expected_test_jobs() {
    local jobs="test:os:ubuntu test:os:debian test:fs:exfat test:fs:ntfs test:fs:vfat test:fs:ext4 test:fs:xfs test:fs:btrfs test:slurm:sample test:lite_bt_from_device test:lite_bt_from_image test:lite_multicast_from_image test:lite_multicast_from_device test:lite_raw_data test:disk_512en_4kn_ext4_data test:dev_to_dev"
    if [[ "${ARCH:-}" == "amd64" ]]; then
        jobs="${jobs} test:os:windows11"
    fi
    printf '%s' "$jobs"
}

build_finished_message() {
    shopt -s nullglob
    local files=(results/*.yml)
    local total=0 ok=0 fail=0 other=0
    local failed_names=()
    local zip_version="${ZIP_FILE_FROM_BUILD:-${LATEST_VERSION:-}}"
    local job_name job_status f j

    if [[ -z "$zip_version" && ${#files[@]} -gt 0 ]]; then
        zip_version=$(grep -m1 'zip:' "${files[0]}" 2>/dev/null | cut -d' ' -f2-) || true
    fi
    zip_version="${zip_version%.zip}"
    [[ -n "$zip_version" ]] || zip_version="unknown"

    # --- Aggregate results/*.yml (same layout the test jobs produce) ---
    for f in "${files[@]}"; do
        job_name=$(grep -m1 'job_name:' "$f" 2>/dev/null | cut -d' ' -f2) || true
        job_status=$(grep -m1 'job_status:' "$f" 2>/dev/null | cut -d' ' -f2) || true
        total=$((total + 1))
        case "$job_status" in
            success) ok=$((ok + 1)) ;;
            failed)
                fail=$((fail + 1))
                failed_names+=("${job_name:-${f#results/}}")
                ;;
            *) other=$((other + 1)) ;;
        esac
    done

    # --- Missing artifacts count as failed (runner died mid-job etc.) ---
    # Only synthesize when at least one result file exists; with zero result
    # files the tests never reported anything at all (download failure, total
    # artifact loss, ...) and marking every job failed would be misleading.
    if (( total > 0 )); then
        local IFS=' '
        for j in $(expected_test_jobs); do
            if [[ ! -f "results/${j}.yml" ]]; then
                total=$((total + 1))
                fail=$((fail + 1))
                failed_names+=("$j")
            fi
        done
    fi

    # --- Trigger description ---
    local trigger_text
    if [[ "${PARENT_PIPELINE_SOURCE:-}" == "schedule" ]]; then
        trigger_text="新版本排程"
    else
        trigger_text="手動 ($(html_escape "${GITLAB_USER_NAME:-unknown}"))"
    fi

    # --- Status icon + result line ---
    local status_icon result_line failed_line=""
    if (( total == 0 )); then
        status_icon="❓"
        result_line="結果: 無測試結果（測試未執行或 artifacts 全部遺失）"
    else
        if (( fail > 0 )); then status_icon="❌"; else status_icon="✅"; fi
        result_line="結果: ${ok}/$((total - other)) ✅"
        if (( fail > 0 )); then
            local escaped=() n joined
            for n in "${failed_names[@]}"; do
                escaped+=("<code>$(html_escape "$n")</code>")
            done
            joined=$(IFS=,; printf '%s' "${escaped[*]}")
            failed_line="失敗項目: ${joined}"$'\n'
            result_line="${result_line} · ❌ ${fail}"
        fi
    fi

    # --- Report link: only when publish_reports will actually deploy ---
    local report_link=""
    if [[ -n "${CI_COMMIT_BRANCH:-}" ]] \
        && [[ "${CI_COMMIT_BRANCH}" == "${CI_DEFAULT_BRANCH:-}" || "${CI_COMMIT_BRANCH}" == "test-reports" ]]; then
        report_link=" | <a href=\"${PAGES_BASE_URL}/${zip_version}/${CI_PIPELINE_IID:-}/\">測試報告</a>"
    fi

    cat <<EOF
${status_icon} <b>Clonezilla CI 測試完成</b>
版本: <code>$(html_escape "${zip_version}")</code>
架構/類型: $(html_escape "${ARCH:-unknown}") / $(html_escape "${TYPE:-unknown}")
觸發: ${trigger_text}
${result_line}
${failed_line}🔗 <a href="${CI_PIPELINE_URL:-}">Pipeline #${CI_PIPELINE_IID:-?}</a>${report_link}
EOF
}

main() {
    parse_args "$@"
    if ! passes_filter; then
        log_info "Filter: no notification needed (mode=${MODE}, PARENT_PIPELINE_SOURCE=${PARENT_PIPELINE_SOURCE:-unset}, VERSION_STATUS=${VERSION_STATUS:-unset})."
        return 0
    fi
    local message
    case "$MODE" in
        started) message=$(build_started_message) ;;
        finished) message=$(build_finished_message) ;;
    esac
    send_telegram_message "$message"
}

rc=0
main "$@" || rc=$?
if [[ "$rc" -ne 0 ]]; then
    log_warn "notify-telegram.sh error (rc=${rc}); continuing without failing the job."
fi
exit 0
