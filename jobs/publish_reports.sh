#!/bin/bash

set -e
set -x

# This script contains all the logic for the GitLab Pages deploy job.

# Step 1: Git and Branch Setup
echo "--- 1. Setting up Git and Branch ---"
REPORTS_BRANCH="test-reports"
git config --global user.name "GitLab CI Bot"
git config --global user.email "gitlab-ci-bot@${CI_PROJECT_NAMESPACE}.gitlab.io"
GIT_REMOTE_URL="https://gitlab-ci-token:${CI_JOB_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git"

# Step 2: Clone reports branch
echo "--- 2. Cloning reports branch ---"
echo "INFO: Cloning branch '${REPORTS_BRANCH}' into 'reports_repo'..."
if ! git clone --branch "${REPORTS_BRANCH}" "${GIT_REMOTE_URL}" reports_repo 2>/dev/null; then
  echo "INFO: Branch '${REPORTS_BRANCH}' not found or clone failed. Creating it from scratch.";
  rm -rf reports_repo
  mkdir reports_repo
  cd reports_repo
  git init
  git remote add origin "${GIT_REMOTE_URL}"
  git checkout -b "${REPORTS_BRANCH}"
  cd ..
fi

# Step 3: Prepare report data and generate per-run report
echo "--- 3. Preparing report data ---"
FIRST_RESULT_FILE=$(find results -name "*.yml" -print -quit)
if [ -z "$FIRST_RESULT_FILE" ]; then
  echo "ERROR: No result files found. Cannot generate report." >&2
  echo "<h1>Error: Test results not found.</h1>" > reports_repo/index.html
  cd reports_repo
  git add index.html
  git commit -m "Fail: No test results found in pipeline ${CI_PIPELINE_IID}"
  git push origin "${REPORTS_BRANCH}"
  cd ..
  mkdir -p public
  mv reports_repo/* public/
  exit 1
fi
ZIP_FILENAME=$(grep "zip:" "$FIRST_RESULT_FILE" | cut -d' ' -f2-)
ZIP_BASENAME=$(basename "$ZIP_FILENAME" .zip)

REPORT_DIR="reports_repo/${ZIP_BASENAME}"
echo "INFO: Generating report in directory: ${REPORT_DIR}"
mkdir -p "${REPORT_DIR}/logs"
if [ -d "logs" ] && [ -n "$(ls -A logs)" ]; then cp -r logs/* "${REPORT_DIR}/logs/"; fi

pipeline_started_ts=$(date -d "$CI_PIPELINE_CREATED_AT" +%s)
report_job_started_ts=$(date -d "$CI_JOB_STARTED_AT" +%s)
pipeline_duration=$((report_job_started_ts - pipeline_started_ts))
pipeline_duration_formatted=$(date -u -d "@${pipeline_duration}" +'%H:%M:%S')

cat > "${REPORT_DIR}/index.html" <<-EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Test Report: $(printf '%s' "${ZIP_BASENAME}")</title>
    <style>
        body { font-family: sans-serif; margin: 2em; background-color: #f4f4f9; color: #333; }
        h1, h2 { color: #444; border-bottom: 2px solid #ddd; padding-bottom: 5px; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; box-shadow: 0 2px 3px rgba(0,0,0,0.1); }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #e8e8f5; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        tr:hover { background-color: #f1f1f1; }
        a { color: #007bff; text-decoration: none; }
        a:hover { text-decoration: underline; }
        .summary { background-color: white; padding: 15px; border-radius: 5px; box-shadow: 0 2px 3px rgba(0,0,0,0.1); }
        .summary p { margin: 5px 0; }
    </style>
</head>
<body>
    <h1>Test Report: $(printf '%s' "${ZIP_BASENAME}")</h1>
    <h2><a href="../">Back to Report Index</a></h2>
    <h2>Pipeline Summary</h2>
    <div class="summary">
        <p><strong>Pipeline ID:</strong> <a href="$(printf '%s' "${CI_PIPELINE_URL}")">$(printf '%s' "${CI_PIPELINE_ID}")</a></p>
        <p><strong>Commit:</strong> <a href="$(printf '%s' "${CI_PROJECT_URL}")/-/commit/$(printf '%s' "${CI_COMMIT_SHA}")">$(printf '%s' "${CI_COMMIT_SHORT_SHA}")</a></p>
        <p><strong>Branch:</strong> <a href="$(printf '%s' "${CI_PROJECT_URL}")/-/tree/$(printf '%s' "${CI_COMMIT_REF_NAME}")">$(printf '%s' "${CI_COMMIT_REF_NAME}")</a></p>
        <p><strong>Triggered by:</strong> $(printf '%s' "${GITLAB_USER_NAME}")</p>
        <p><strong>Pipeline Started:</strong> $(printf '%s' "${CI_PIPELINE_CREATED_AT}")</p>
        <p><strong>Total Duration:</strong> $(printf '%s' "${pipeline_duration_formatted}") (until report generation)</p>
    </div>
EOF
ARCH_FROM_FILE=$(grep "arch:" "$FIRST_RESULT_FILE" | cut -d' ' -f2)
cat >> "${REPORT_DIR}/index.html" <<-EOF
  <h2>Test Environment</h2>
  <div class="summary">
      <p><strong>Architecture (ARCH):</strong> $(printf '%s' "${ARCH_FROM_FILE}")</p>
      <p><strong>Clonezilla ZIP:</strong> $(printf '%s' "${ZIP_FILENAME}")</p>
  </div>
EOF
cat >> "${REPORT_DIR}/index.html" <<-EOF
<h2>Test Results</h2>
<table>
    <thead>
        <tr>
            <th>Test Job</th>
            <th>Status</th>
            <th>Duration</th>
            <th>Runner</th>
            <th>Filesystem</th>
            <th>Start Time (UTC)</th>
            <th>Log</th>
        </tr>
    </thead>
    <tbody>
EOF
for file in results/*.yml; do
  if [ -f "$file" ]; then
    job_name=$(grep "job_name:" "$file" | cut -d' ' -f2)
    job_status=$(grep "job_status:" "$file" | cut -d' ' -f2)
    job_duration=$(grep "job_duration:" "$file" | cut -d' ' -f2 || echo "N/A")
    job_started=$(grep "job_started_at:" "$file" | cut -d' ' -f2- || echo "N/A")
    runner_desc=$(grep "runner_description:" "$file" | cut -d':' -f2- | xargs || echo "N/A")
    fs=$(grep "fs:" "$file" | cut -d' ' -f2 || echo "N/A")
    
    if [ "$job_status" = "success" ]; then status_icon="✅"; elif [ "$job_status" = "failed" ]; then status_icon="❌"; else status_icon="❓"; fi
    job_started_formatted=$(date -d "$job_started" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$job_started")
    log_link="<a href='./logs/${job_name}.log'>Log</a>"

    cat >> "${REPORT_DIR}/index.html" <<-EOF
        <tr>
            <td>$(printf '%s' "${job_name}")</td>
            <td>$(printf '%s' "${status_icon}") $(printf '%s' "${job_status}")</td>
            <td>$(printf '%s' "${job_duration}")</td>
            <td>$(printf '%s' "${runner_desc}")</td>
            <td>$(printf '%s' "${fs}")</td>
            <td>$(printf '%s' "${job_started_formatted}")</td>
            <td>$(printf '%s' "${log_link}")</td>
        </tr>
    EOF
  fi
done
cat >> "${REPORT_DIR}/index.html" <<-EOF
      </tbody>
  </table>
  <br>
  <p><em>For detailed logs, click on the link in the 'Log' column or <a href="./logs/">browse the raw logs directory</a>.</em></p>
</body>
</html>
EOF

# Step 4: Generate history and archive pages
echo "--- 4. Generating history pages ---"
chmod +x jobs/generate_report.sh
jobs/generate_report.sh "$ZIP_BASENAME"

# Step 5: Commit and Push
echo "--- 5. Committing and pushing reports ---"
cd reports_repo
echo "INFO: Committing and pushing changes to '${REPORTS_BRANCH}' branch..."
git add .
# Check for changes
if git diff --staged --quiet; then
  echo "INFO: No changes detected in reports. Nothing to commit."
else
  git commit -m "Update test reports for pipeline ${CI_PIPELINE_IID}" -m "Clonezilla version: ${ZIP_BASENAME}"
  git push origin "${REPORTS_BRANCH}"
fi
cd ..

# Step 6: Prepare GitLab Pages artifact
echo "--- 6. Preparing public directory ---"
mkdir -p public
mv reports_repo/* public/

echo "INFO: All report steps completed successfully."
