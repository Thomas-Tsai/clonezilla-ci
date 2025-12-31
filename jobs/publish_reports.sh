#!/bin/bash
set -e
# FINAL ATTEMPT. Rewritten from scratch to ensure no hidden characters.

# Step 1: Git and Branch Setup
echo "--- 1. Setting up Git and Branch ---"
REPORTS_BRANCH="test-reports"
git config --global user.name "GitLab CI Bot"
git config --global user.email "gitlab-ci-bot@${CI_PROJECT_NAMESPACE}.gitlab.io"
GIT_REMOTE_URL="https://gitlab-ci-token:${CI_JOB_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git"

# Step 2: Clone reports branch
echo "--- 2. Cloning reports branch ---"
if ! git clone --branch "${REPORTS_BRANCH}" "${GIT_REMOTE_URL}" reports_repo 2>/dev/null; then
  echo "INFO: Branch '${REPORTS_BRANCH}' not found or clone failed. Creating it from scratch."
  rm -rf reports_repo
  mkdir reports_repo
  cd reports_repo
  git init
  git remote add origin "${GIT_REMOTE_URL}"
  git checkout -b "${REPORTS_BRANCH}"
  cd ..
fi

# Step 3: Prepare report data
echo "--- 3. Preparing report data ---"
FIRST_RESULT_FILE=$(find results -name "*.yml" -print -quit)
if [ -z "$FIRST_RESULT_FILE" ]; then
  echo "ERROR: No result files found." >&2
  exit 1
fi
ZIP_FILENAME=$(grep "zip:" "$FIRST_RESULT_FILE" | cut -d' ' -f2-)
ZIP_BASENAME=$(basename "$ZIP_FILENAME" .zip)
REPORT_DIR="reports_repo/${ZIP_BASENAME}/${CI_PIPELINE_IID}"
echo "INFO: Generating report in directory: ${REPORT_DIR}"
mkdir -p "${REPORT_DIR}"
if [ -d "logs" ] && [ -n "$(ls -A logs)" ]; then
    echo "INFO: Copying logs to report directory..."
    cp -r logs/* "${REPORT_DIR}/logs/";
fi
if [ -d "results" ] && [ -n "$(ls -A results)" ]; then
    echo "INFO: Copying results to report directory..."
    mkdir -p "${REPORT_DIR}/results"
    cp -r results/*.yml "${REPORT_DIR}/results/";
fi

# Step 3a: Generate per-run report header
pipeline_started_ts=$(date -d "$CI_PIPELINE_CREATED_AT" +%s)
report_job_started_ts=$(date -d "$CI_JOB_STARTED_AT" +%s)
pipeline_duration=$((report_job_started_ts - pipeline_started_ts))
pipeline_duration_formatted=$(date -u -d "@${pipeline_duration}" +'%H:%M:%S')
ARCH_FROM_FILE=$(grep "arch:" "$FIRST_RESULT_FILE" | cut -d' ' -f2)

# Using a single heredoc for simplicity
cat > "${REPORT_DIR}/index.html" <<-EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Test Report: ${ZIP_BASENAME}</title>
    <style>
        body { font-family: sans-serif; margin: 2em; background-color: #f4f4f9; color: #333; }
        h1, h2 { color: #444; border-bottom: 2px solid #ddd; padding-bottom: 5px; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; box-shadow: 0 2px 3px rgba(0,0,0,0.1); }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #e8e8f5; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .summary { background-color: white; padding: 15px; border-radius: 5px; box-shadow: 0 2px 3px rgba(0,0,0,0.1); }
        .summary p { margin: 5px 0; }
    </style>
</head>
<body>
    <h1>Test Report: ${ZIP_BASENAME}</h1>
    <h2><a href="../">Back to Report Index</a></h2>
    <h2>Pipeline Summary</h2>
    <div class="summary">
        <p><strong>Pipeline ID:</strong> <a href="${CI_PIPELINE_URL}">${CI_PIPELINE_IID} (${CI_PIPELINE_ID})</a></p>
        <p><strong>Commit:</strong> <a href="${CI_PROJECT_URL}/-/commit/${CI_COMMIT_SHA}">${CI_COMMIT_SHORT_SHA}</a></p>
        <p><strong>Branch:</strong> <a href="${CI_PROJECT_URL}/-/tree/${CI_COMMIT_REF_NAME}">${CI_COMMIT_REF_NAME}</a></p>
        <p><strong>Triggered by:</strong> ${GITLAB_USER_NAME}</p>
        <p><strong>Pipeline Started:</strong> ${CI_PIPELINE_CREATED_AT}</p>
        <p><strong>Total Duration:</strong> ${pipeline_duration_formatted} (until report generation)</p>
    </div>
    <h2>Test Environment</h2>
    <div class="summary">
      <p><strong>Architecture (ARCH):</strong> ${ARCH_FROM_FILE}</p>
      <p><strong>Clonezilla ZIP:</strong> ${ZIP_FILENAME}</p>
    </div>
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

# Step 3b: Loop through results and append rows
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
    
    job_id=$(grep "job_id:" "$file" | cut -d' ' -f2 || echo "")
    if [ -n "$job_id" ]; then
        log_link="<a href=\"${CI_PROJECT_URL}/-/jobs/${job_id}\" target=\"_blank\">Log</a>"
    else
        log_link="<a href='./logs/${job_name}.log'>Log</a>"
    fi

    echo "        <tr>" >> "${REPORT_DIR}/index.html"
    echo "            <td>${job_name}</td>" >> "${REPORT_DIR}/index.html"
    echo "            <td>${status_icon} ${job_status}</td>" >> "${REPORT_DIR}/index.html"
    echo "            <td>${job_duration}</td>" >> "${REPORT_DIR}/index.html"
    echo "            <td>${runner_desc}</td>" >> "${REPORT_DIR}/index.html"
    echo "            <td>${fs}</td>" >> "${REPORT_DIR}/index.html"
    echo "            <td>${job_started_formatted}</td>" >> "${REPORT_DIR}/index.html"
    echo "            <td>${log_link}</td>" >> "${REPORT_DIR}/index.html"
    echo "        </tr>" >> "${REPORT_DIR}/index.html"
  fi
done

# Step 3c: Generate per-run report footer
cat >> "${REPORT_DIR}/index.html" <<-EOF
      </tbody>
  </table>
</body>
</html>
EOF

# Step 4: Generate history pages
echo "--- 4. Generating history pages ---"
chmod +x jobs/generate_report.sh
jobs/generate_report.sh "$ZIP_BASENAME"

# Step 5: Commit and Push
echo "--- 5. Committing and pushing reports ---"
cd reports_repo
echo "INFO: Committing and pushing changes to '${REPORTS_BRANCH}' branch..."
git add .
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