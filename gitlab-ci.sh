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
    echo "  failed-logs [hours]         List and download logs for failed jobs (optionally within the last [hours])"
    echo "  failed-summary [prompt]     Analyze and aggregate AI analysis of failed job logs with an optional prompt"
    echo ""
    echo "Examples:"
    echo "  $0 pipelines 5"
    echo "  $0 failed-logs 24"
    echo "  $0 failed-summary \"以繁體中文回應，字數少於100字\""
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

# Download logs for failed jobs
download_failed_logs() {
    local hours_ago=$1
    local api_endpoint="jobs?scope=failed&per_page=100"
    local cutoff_ts=0

    if [ -n "$hours_ago" ] && [ "$hours_ago" != "0" ]; then
        if ! [[ "$hours_ago" =~ ^[0-9]+$ ]]; then
            echo "Error: Hours must be a positive integer."
            exit 1
        fi
        # Calculate cutoff timestamp in seconds
        cutoff_ts=$(date -d "$hours_ago hours ago" +%s)
        local cutoff_date_iso=$(date -d "@$cutoff_ts" -u +"%Y-%m-%dT%H:%M:%SZ")
        api_endpoint="${api_endpoint}&updated_after=${cutoff_date_iso}"
        echo "Fetching failed jobs since $cutoff_date_iso ($hours_ago hours ago)..."
    else
        echo "Fetching all failed jobs (limit: 100)..."
    fi

    local failed_jobs_json=$(api_get "$api_endpoint")
    local count=$(echo "$failed_jobs_json" | jq '. | length' 2>/dev/null)

    if [ -z "$count" ] || [ "$count" -eq 0 ]; then
        echo "No failed jobs found."
        return
    fi

    mkdir -p failed_logs

    # Table Header
    printf "%-12s | %-12s | %-15s | %-25s | %-30s | %-s\n" \
           "Job ID" "Pipeline ID" "Trigger Name" "Test Name" "Clonezilla Version" "Log Folder"
    echo "------------------------------------------------------------------------------------------------------------------------------------------------"

    local processed_count=0
    for row in $(echo "$failed_jobs_json" | jq -r '.[] | @base64'); do
        _jq() {
            echo "${row}" | base64 --decode | jq -r "${1}"
        }
        
        local job_id=$(_jq '.id')
        local finished_at=$(_jq '.finished_at // .created_at')
        
        # Manual time filter check
        if [ "$cutoff_ts" -gt 0 ]; then
            local job_ts=$(date -d "$finished_at" +%s 2>/dev/null)
            if [ -n "$job_ts" ] && [ "$job_ts" -lt "$cutoff_ts" ]; then
                continue
            fi
        fi

        processed_count=$((processed_count + 1))
        local pipeline_id=$(_jq '.pipeline.id')
        local pipeline_source=$(_jq '.pipeline.source')
        local job_name=$(_jq '.name')
        local target_dir="failed_logs/job_${job_id}"
        mkdir -p "$target_dir"

        echo -n "Processing Job $job_id ($finished_at)... "

        # Download log
        local log_path="${target_dir}/job.log"
        curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "${GITLAB_API_URL}/projects/${PROJECT_ID}/jobs/${job_id}/trace" -o "$log_path"
        
        # Download artifacts if any
        local artifacts_dir="${target_dir}/artifacts"
        local zip_file="${target_dir}/artifacts.zip"
        local http_code=$(curl -sL -o "$zip_file" -w "%{http_code}" \
             --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
             "${GITLAB_API_URL}/projects/${PROJECT_ID}/jobs/${job_id}/artifacts")
        
        if [ "$http_code" -eq 200 ]; then
            mkdir -p "$artifacts_dir"
            unzip -qo "$zip_file" -d "$artifacts_dir" 2>/dev/null
            rm -f "$zip_file"
            # Remove unwanted version-* files
            rm -f "$artifacts_dir"/version-*
            echo -n "Log & Artifacts downloaded. "
        else
            rm -f "$zip_file"
            echo -n "Log downloaded. No artifacts found. "
        fi

        # Find Clonezilla version from log
        local clonezilla_version="N/A"
        if [ -f "$log_path" ]; then
             clonezilla_version=$(grep "CLONEZILLA VERSION DETECTED:" "$log_path" | head -n 1 | sed 's/.*VERSION DETECTED: //')
             if [ -z "$clonezilla_version" ]; then
                 clonezilla_version="Unknown"
             fi
        fi

        local trigger_name="N/A"
        if [ "$pipeline_source" = "parent_pipeline" ]; then
            trigger_name="Child"
        fi

        echo "Done."
        # Print Info to table
        printf "%-12s | %-12s | %-15s | %-25s | %-30s | %-s\n" \
               "$job_id" "$pipeline_id" "$trigger_name" "$job_name" "$clonezilla_version" "$target_dir"

    done

    if [ "$processed_count" -eq 0 ]; then
        echo "No failed jobs matched the time filter."
    else
        echo "Processed $processed_count failed jobs. Logs stored in failed_logs/"
    fi
}

# Aggregate AI analysis results from all failed logs into a single summary file
analyze_and_summarize_failed() {
    local user_prompt="$1"
    local summary_file="failed_logs/summary.txt"
    echo "AI Failure Analysis Summary" > "$summary_file"
    echo "Generated on $(date)" >> "$summary_file"
    if [ -n "$user_prompt" ]; then
        echo "Custom Prompt: $user_prompt" >> "$summary_file"
    fi
    echo "----------------------------------------" >> "$summary_file"
    
    # Iterate through all job folders in failed_logs
    for job_dir in failed_logs/job_*; do
        [ -d "$job_dir" ] || continue
        local job_id=$(basename "$job_dir" | sed 's/job_//')
        local analysis_file="${job_dir}/job.log.analysis"

        # If user provides a custom prompt, we always re-analyze to respect it
        if [ ! -s "$analysis_file" ] || [ -n "$user_prompt" ]; then
            echo "Analyzing Job $job_id (combining all logs)..."
            analyze_failure_with_ai_combined "$job_dir" "$user_prompt" > "$analysis_file"
        fi
        
        if [ -s "$analysis_file" ]; then
            echo "--- Job $job_id ---" >> "$summary_file"
            cat "$analysis_file" >> "$summary_file"
            echo -e "\n" >> "$summary_file"
        else
            echo "--- Job $job_id (Analysis Failed) ---" >> "$summary_file"
            echo -e "\n" >> "$summary_file"
        fi
    done
    echo "Summary written to $summary_file"
}

# New function to analyze combined logs from a job directory
analyze_failure_with_ai_combined() {
    local job_dir="$1"
    local user_prompt="$2"
    local combined_snippet="${job_dir}/combined_logs.snippet"
    rm -f "$combined_snippet"

    # Add job.log
    if [ -f "${job_dir}/job.log" ]; then
        echo "=== Main GitLab Job Log ===" >> "$combined_snippet"
        tail -n 150 "${job_dir}/job.log" >> "$combined_snippet"
        echo -e "\n" >> "$combined_snippet"
    fi

    # Add artifact logs
    local artifact_logs=$(find "${job_dir}/artifacts/logs" -name "*.log" 2>/dev/null)
    for log in $artifact_logs; do
        echo "=== Artifact Log: $(basename "$log") ===" >> "$combined_snippet"
        tail -n 150 "$log" >> "$combined_snippet"
        echo -e "\n" >> "$combined_snippet"
    done

    if [ ! -s "$combined_snippet" ]; then
        echo "No log content found for analysis." >&2
        rm -f "$combined_snippet"
        return 1
    fi

    # AI analysis
    local result=$(call_ai_api "$combined_snippet" "$user_prompt")
    echo "$result"
    rm -f "$combined_snippet"
}

# Generic AI API call function
call_ai_api() {
    local input_file="$1"
    local user_prompt="$2"
    local baseurl="${INTERNAL_API_BASEURL:-https://inner-medusa.genai.nchc.org.tw/v1/}"
    if [ -z "$INTERNAL_API_KEY" ]; then
        echo "INTERNAL_API_KEY not set." >&2
        return 1
    fi

    local snippet=$(cat "$input_file")
    local final_content="$snippet"
    
    # If custom prompt is provided, prepend it
    if [ -n "$user_prompt" ]; then
        final_content="Instruction: ${user_prompt}\n\nLogs:\n${snippet}"
    fi

    # Default to gemma-4-31B-it
    local model="${INTERNAL_API_MODEL:-gemma-4-31B-it}"
    local payload=$(jq -n --arg ctx "$final_content" --arg mdl "$model" '{"model":$mdl,"messages":[{"role":"user","content":$ctx}],"temperature":0.1}')
    
    local endpoint="${INTERNAL_API_ENDPOINT:-${baseurl%/}/chat/completions}"
    local response=$(curl -s -X POST "$endpoint" \
        -H "Authorization: Bearer ${INTERNAL_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$payload")

    # Error checking
    if echo "$response" | grep -q "\"detail\""; then
        echo "AI API Error: $(echo "$response" | jq -r '.detail // .')" >&2
        return 1
    fi

    local analysis=$(echo "$response" | jq -r '.choices[0].message.content // .analysis // empty')
    if [ -z "$analysis" ]; then
        # Fallback for different API response structures
        analysis=$(echo "$response" | jq -r '.content // .analysis // empty')
    fi

    if [ -n "$analysis" ]; then
        echo "$analysis"
    else
        echo "AI returned empty result. Raw response: $response" >&2
        return 1
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
    # Remove unwanted version-* files
    rm -f "$target_dir"/version-*
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
  failed-logs) download_failed_logs "$2" ;;
  failed-summary) analyze_and_summarize_failed "$2" ;;
  *)         usage ;;
 esac
