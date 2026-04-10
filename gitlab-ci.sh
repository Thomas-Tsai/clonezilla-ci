#!/bin/bash

# GitLab CI CLI tool for Clonezilla-CI
# This script interacts with the GitLab API to list pipelines, jobs, and fetch logs.

if [ -f .env ]; then
    source .env
fi

# Defaults
GITLAB_API_URL="${GITLAB_API_URL:-https://gitlab.com/api/v4}"
# PROJECT_ID should be provided by the user or set in .env
# Example: PROJECT_ID="freelabstw%2Fclonezilla-ci"

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install it first."
    exit 1
fi

if [ -z "$GITLAB_TOKEN" ]; then
    echo "Error: GITLAB_TOKEN is not set. Please set it in .env or as an environment variable."
    exit 1
fi

if [ -z "$PROJECT_ID" ]; then
    echo "Error: PROJECT_ID is not set. Please set it in .env or as an environment variable."
    echo "Hint: PROJECT_ID can be the numeric ID or the URL-encoded path (e.g., namespace%2Fproject)."
    exit 1
fi

usage() {
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  pipelines [limit] [status]  List pipelines (default limit: 10, default status: all)"
    echo "  running                     List currently running pipelines"
    echo "  child [pipeline_id]         List child pipelines (bridges) for a given pipeline"
    echo "  jobs [pipeline_id]          List jobs and their status for a given pipeline"
    echo "  job [job_id]                Show detailed information about a job"
    echo "  log [job_id]                Fetch and display the log for a given job"
    echo "  artifacts [job_id]          Download and unzip job artifacts into job_<id> directory"
    echo "  debug [jobs|child|job] [id] Show raw JSON for debugging"
    echo "  failed-logs                 Download logs for all failed jobs and analyze with AI"
    echo "  failed-summary              Aggregate AI analysis of failed job logs into a summary file"
    echo ""
    echo "Examples:"
    echo "  $0 pipelines 5"
    echo "  $0 job 13788739616"
    echo "  $0 artifacts 13788739616"
    exit 1
}

api_get() {
    local endpoint="$1"
    curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "${GITLAB_API_URL}/projects/${PROJECT_ID}/${endpoint}"
}

list_pipelines() {
    local limit="${1:-10}"
    local status="$2"
    local query="?per_page=${limit}"
    if [ -n "$status" ]; then
        query="${query}&status=${status}"
    fi

    echo "Listing $limit pipelines (status: ${status:-any})..."
    api_get "pipelines${query}" | jq -r '.[] | "[\(.id)] \(.status) - \(.ref) - \(.created_at) - \(.web_url)"'
}

list_running_pipelines() {
    list_pipelines 20 "running"
}

list_child_pipelines() {
    local pipeline_id="$1"
    if [ -z "$pipeline_id" ]; then
        echo "Error: pipeline_id is required."
        exit 1
    fi

    echo "Listing child pipelines for pipeline $pipeline_id..."
    local bridges=$(api_get "pipelines/${pipeline_id}/bridges")
    local count=$(echo "$bridges" | jq '. | length' 2>/dev/null)
    if [ "$count" -eq 0 ]; then
        echo "No child pipelines found for pipeline $pipeline_id."
    else
        echo "$bridges" | jq -r '.[] | "Bridge Job: \(.name) [ID: \(.id)] -> Downstream Pipeline ID: \(.downstream_pipeline.id // "N/A") status: \(.downstream_pipeline.status // "N/A")"'
    fi
}

list_jobs() {
    local pipeline_id="$1"
    if [ -z "$pipeline_id" ]; then
        echo "Error: pipeline_id is required."
        exit 1
    fi

    echo "Listing jobs for pipeline $pipeline_id (up to 100 jobs)..."
    local response=$(api_get "pipelines/${pipeline_id}/jobs?per_page=100")
    
    local error_msg=$(echo "$response" | jq -r '.message' 2>/dev/null)
    if [ "$error_msg" != "null" ] && [ -n "$error_msg" ]; then
        echo "Error from GitLab: $error_msg"
        return
    fi

    local count=$(echo "$response" | jq '. | length' 2>/dev/null)
    if [ -z "$count" ] || [ "$count" -eq 0 ]; then
        echo "No jobs found for pipeline $pipeline_id."
    else
        echo "$response" | jq -r '.[] | "[\(.id)] \(.status) - \(.name) (\(.stage))"'
    fi
}

get_job_info() {
    local job_id="$1"
    if [ -z "$job_id" ]; then echo "Error: job_id required"; exit 1; fi
    
    local job=$(api_get "jobs/${job_id}")
    local error_msg=$(echo "$job" | jq -r '.message' 2>/dev/null)
    if [ "$error_msg" != "null" ] && [ -n "$error_msg" ]; then
        echo "Error: $error_msg"
        return
    fi

    echo "--- Job $job_id Information ---"
    echo "Name:      $(echo "$job" | jq -r '.name')"
    echo "Stage:     $(echo "$job" | jq -r '.stage')"
    echo "Status:    $(echo "$job" | jq -r '.status')"
    echo "Created:   $(echo "$job" | jq -r '.created_at')"
    echo "Finished:  $(echo "$job" | jq -r '.finished_at')"
    
    local artifacts_file=$(echo "$job" | jq -r '.artifacts_file.filename')
    if [ "$artifacts_file" != "null" ]; then
        echo "Artifacts: $artifacts_file ($(echo "$job" | jq -r '.artifacts_file.size') bytes)"
        echo "Expires:   $(echo "$job" | jq -r '.artifacts_expire_at')"
    else
        echo "Artifacts: NONE (or already expired/deleted)"
    fi
    echo "Web URL:   $(echo "$job" | jq -r '.web_url')"
}

get_log() {
    local job_id="$1"
    if [ -z "$job_id" ]; then
        echo "Error: job_id is required."
        exit 1
    fi

    curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "${GITLAB_API_URL}/projects/${PROJECT_ID}/jobs/${job_id}/trace"
}

# Download logs for all failed jobs and analyze with Fabric AI
download_failed_logs() {
    echo "Fetching failed jobs..."
    local failed_jobs_json=$(api_get "jobs?scope[]=failed")
    local job_ids=$(echo "$failed_jobs_json" | jq -r '.[].id')
    mkdir -p failed_logs
    for job_id in $job_ids; do
        echo "Downloading log for job $job_id..."
        local log_path="failed_logs/job_${job_id}.log"
        curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "${GITLAB_API_URL}/projects/${PROJECT_ID}/jobs/${job_id}/trace" -o "$log_path"
        if [ -s "$log_path" ]; then
            # Capture AI analysis output and store it alongside the log
            local analysis_output=$(analyze_failure_with_ai "$log_path")
            echo "$analysis_output" > "${log_path}.analysis"
        else
            echo "Log for job $job_id is empty or failed to download."
        fi
    done
    echo "All failed logs processed."
}

# Aggregate AI analysis results from all failed logs into a single summary file
aggregate_failed_analysis() {
    local summary_file="failed_logs/summary.txt"
    echo "AI Failure Analysis Summary" > "$summary_file"
    echo "Generated on $(date)" >> "$summary_file"
    echo "----------------------------------------" >> "$summary_file"
    for analysis in failed_logs/*.analysis; do
        [ -e "$analysis" ] || continue
        echo "--- $(basename "$analysis" .analysis) ---" >> "$summary_file"
        cat "$analysis" >> "$summary_file"
        echo -e "\n" >> "$summary_file"
    done
    echo "Summary written to $summary_file"
}


# Analyze a log file using Fabric AI
analyze_failure_with_ai() {
    local log_file="$1"
    # Internal GenAI API configuration
    local baseurl="${INTERNAL_API_BASEURL:-https://inner-medusa.genai.nchc.org.tw/v1/}"
    if [ -z "$INTERNAL_API_KEY" ]; then
        echo "INTERNAL_API_KEY not set; skipping AI analysis."
        return 1
    fi
    echo "Analyzing $log_file with internal GenAI API..."
    # Extract last 200 lines to limit size
    tail -n 200 "$log_file" > "${log_file}.snippet"
    local snippet=$(cat "${log_file}.snippet")
    # Build payload compatible with internal GenAI API (expects messages array)
    # Default model can be overridden via INTERNAL_API_MODEL env var.
    # Choose a model that the team is permitted to use, e.g., "llama-3.1-8B-m1-raft-v1.1.4-ep5".
    local model="${INTERNAL_API_MODEL:-llama-3.1-8B-m1-raft-v1.1.4-ep5}"
    local payload=$(jq -n --arg ctx "$snippet" --arg mdl "$model" '{"model":$mdl,"messages":[{"role":"user","content":$ctx}],"temperature":0.2}')
    # Primary endpoint – assume chat completions
    local endpoint="${INTERNAL_API_ENDPOINT:-${baseurl%/}/chat/completions}"
    local response=$(curl -s -X POST "$endpoint" \
        -H "Authorization: Bearer ${INTERNAL_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$payload")
    # If response contains an error, attempt fallback to /v1/analyze if provided
    if echo "$response" | grep -q "detail"; then
        local fallback="${INTERNAL_API_FALLBACK_ENDPOINT:-${baseurl%/}/analyze}"
        response=$(curl -s -X POST "$fallback" \
            -H "Authorization: Bearer ${INTERNAL_API_KEY}" \
            -H "Content-Type: application/json" \
            -d "$payload")
    fi
    if echo "$response" | grep -q "detail"; then
        echo "AI analysis failed: $(echo "$response" | jq -r '.detail // .')"
        rm -f "${log_file}.snippet"
        return 1
    else
        # Extract content from typical OpenAI‑style response
        local analysis=$(echo "$response" | jq -r '.choices[0].message.content // .analysis // .')
        echo "AI analysis result:"
        echo "$analysis"
        rm -f "${log_file}.snippet"
    fi
    echo "Analyzing $log_file with internal GenAI API..."
    # Extract last 200 lines to limit size
    tail -n 200 "$log_file" > "${log_file}.snippet"
    local snippet=$(cat "${log_file}.snippet")
    # Build JSON payload (you can adjust model/prompt as needed)
    # Build payload compatible with internal GenAI API (expects messages array)
    # Default model can be overridden via INTERNAL_API_MODEL env var.
    # Choose a model that the team is permitted to use, e.g., "llama-3.1-8B-m1-raft-v1.1.4-ep5".
    local model="${INTERNAL_API_MODEL:-llama-3.1-8B-m1-raft-v1.1.4-ep5}"
    local payload=$(jq -n --arg ctx "$snippet" --arg mdl "$model" '{"model":$mdl,"messages":[{"role":"user","content":$ctx}],"temperature":0.2}')
    local endpoint="${baseurl}analyze"
    local response=$(curl -s -X POST "$endpoint" \
        -H "Authorization: Bearer ${INTERNAL_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$payload")
    if echo "$response" | grep -q "detail"; then
        echo "AI analysis failed: $(echo "$response" | jq -r '.detail // .')"
        rm -f "${log_file}.snippet"
        return 1
    else
        echo "AI analysis result:"
        echo "$response" | jq -r '.analysis // .'
        rm -f "${log_file}.snippet"
    fi
}

download_artifacts() {
    local job_id="$1"
    if [ -z "$job_id" ]; then
        echo "Error: job_id is required."
        exit 1
    fi

    if ! command -v unzip &> /dev/null; then
        echo "Error: unzip is not installed. Please install it first."
        exit 1
    fi

    local target_dir="job_${job_id}"
    local zip_file="artifacts_${job_id}.zip"

    echo "Downloading artifacts for job $job_id..."
    # Using -f to fail on HTTP errors (like 404)
    local http_code=$(curl -sL -o "$zip_file" -w "%{http_code}" \
         --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
         "${GITLAB_API_URL}/projects/${PROJECT_ID}/jobs/${job_id}/artifacts")

    if [ "$http_code" -ne 200 ]; then
        echo "Error: Failed to download artifacts. HTTP Status: $http_code"
        if [ "$http_code" -eq 404 ]; then
            echo "Possible reasons: Job has no artifacts, artifacts expired, or wrong Project ID."
            echo "Try: ./gitlab-ci.sh job $job_id  to see job details."
        fi
        rm -f "$zip_file"
        exit 1
    fi

    if ! unzip -t "$zip_file" &>/dev/null; then
        echo "Error: Downloaded file is not a valid ZIP."
        rm -f "$zip_file"
        exit 1
    fi

    echo "Extracting artifacts into $target_dir..."
    mkdir -p "$target_dir"
    unzip -o "$zip_file" -d "$target_dir"
    rm "$zip_file"
    echo "Done. Artifacts are in $target_dir"
}

debug_api() {
    local cmd="$2"
    local id="$3"
    case "$cmd" in
        jobs) api_get "pipelines/${id}/jobs" | jq . ;;
        job) api_get "jobs/${id}" | jq . ;;
        child) api_get "pipelines/${id}/bridges" | jq . ;;
        *) echo "Usage: $0 debug [jobs|job|child] [id]" ;;
    esac
}

case "$1" in
  pipelines) list_pipelines "$2" "$3" ;;
  running)   list_running_pipelines ;;
  child)     list_child_pipelines "$2" ;;
  jobs)      list_jobs "$2" ;;
  job)       get_job_info "$2" ;;
  log|trace) get_log "$2" ;;
  artifacts|download) download_artifacts "$2" ;;
  debug)     debug_api "$@" ;;
  failed-logs) download_failed_logs ;;
  failed-summary) aggregate_failed_analysis ;;
  *)         usage ;;
 esac
