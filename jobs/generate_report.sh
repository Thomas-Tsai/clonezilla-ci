#!/bin/bash
set -e

# This script is executed by the 'pages' job in .gitlab-ci.yml
# It generates the main index, history index, and monthly archive pages.

REPORTS_JSON_PATH="reports_repo/reports.json"
ZIP_BASENAME=$1

if [ -z "$ZIP_BASENAME" ]; then
    echo "ERROR: ZIP_BASENAME argument not provided." >&2
    exit 1
fi

# --- 4a. Update reports.json (logic from yml) ---
echo "INFO: Updating historical report index..."
if [ ! -f "${REPORTS_JSON_PATH}" ]; then
  echo "INFO: No previous reports.json found. Starting a new one."
  echo "[]" > "${REPORTS_JSON_PATH}"
fi

OVERALL_STATUS="success"
if grep -q "job_status: failed" results/*.yml; then OVERALL_STATUS="failed"; fi

CURRENT_REPORT_JSON=$(jq -n \
  --arg zip_basename "$ZIP_BASENAME" \
  --arg pipeline_iid "$CI_PIPELINE_IID" \
  --arg pipeline_id "${CI_PIPELINE_ID:-$CI_PIPELINE_IID}" \
  --arg pipeline_url "$CI_PIPELINE_URL" \
  --arg commit_sha "$CI_COMMIT_SHORT_SHA" \
  --arg commit_url "${CI_PROJECT_URL}/-/commit/${CI_COMMIT_SHA}" \
  --arg commit_ref "$CI_COMMIT_REF_NAME" \
  --arg status "$OVERALL_STATUS" \
  --arg date "$(date -u -Iseconds)" \
  '{zip_name: $zip_basename, pipeline: {iid: $pipeline_iid, id: $pipeline_id, url: $pipeline_url}, commit: {sha: $commit_sha, ref: $commit_ref, url: $commit_url}, status: $status, date: $date, report_url: ($zip_basename + "/" + $pipeline_iid + "/")}')

UPDATED_REPORTS_JSON=$(jq --argjson new_report "${CURRENT_REPORT_JSON}" \
  '. | map(select(.pipeline.iid != $new_report.pipeline.iid)) | [$new_report] + .' \
  "${REPORTS_JSON_PATH}")
echo "${UPDATED_REPORTS_JSON}" > "${REPORTS_JSON_PATH}"


# --- 4b. Generate index.html (latest 50) ---
echo "INFO: Generating index.html with latest 50 reports..."
cat > reports_repo/index.html <<- 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Clonezilla CI Test Reports</title>
    <style>
        body { font-family: sans-serif; margin: 2em; background-color: #f4f4f9; color: #333; }
        h1 { color: #444; border-bottom: 2px solid #ddd; padding-bottom: 5px; }
        h2 { font-size: 1.2em; color: #555; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; box-shadow: 0 2px 3px rgba(0,0,0,0.1); }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #e8e8f5; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        tr:hover { background-color: #f1f1f1; }
        a { color: #007bff; text-decoration: none; }
        a:hover { text-decoration: underline; }
        .status-success { color: green; font-weight: bold; }
        .status-failed { color: red; font-weight: bold; }
    </style>
</head>
<body>
    <h1>Clonezilla CI Test Reports (Latest 50)</h1>
    <h2><a href="history.html">View Full History</a></h2>
    <table>
        <thead>
            <tr>
                <th>Clonezilla Version</th>
                <th>Date</th>
                <th>Status</th>
                <th>Pipeline</th>
                <th>Commit</th>
                <th>Report</th>
            </tr>
        </thead>
        <tbody>
EOF
jq -r '
  .[0:50] | .[] |
  "<tr>
      <td>" + .zip_name + "</td>
      <td>" + .date + "</td>
      <td><span class=\"status-" + .status + "\">" + .status + "</span></td>
      <td><a href=\"" + .pipeline.url + "\" target=\"_blank\">" + .pipeline.iid + " (" + .pipeline.id + ")</a></td>
      <td><a href=\"" + .commit.url + "\" target=\"_blank\">" + .commit.sha + " (" + .commit.ref + ")</a></td>
      <td><a href=\"" + .report_url + "\">View Report</a></td>
   </tr>"
' "${REPORTS_JSON_PATH}" >> reports_repo/index.html
cat >> reports_repo/index.html <<- 'EOF'
        </tbody>
    </table>
</body>
</html>
EOF

# --- 4c. Generate history pages ---
echo "INFO: Generating monthly archives..."
cat > reports_repo/history.html <<- 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Test Report History</title>
    <style>
        body { font-family: sans-serif; margin: 2em; background-color: #f4f4f9; color: #333; }
        h1 { color: #444; border-bottom: 2px solid #ddd; padding-bottom: 5px; }
        h2 { font-size: 1.2em; color: #555; }
        ul { list-style-type: none; padding: 0; }
        li { background-color: white; margin: 5px 0; padding: 10px; border-radius: 3px; box-shadow: 0 1px 2px rgba(0,0,0,0.1); }
        a { color: #007bff; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <h1>Test Report History</h1>
    <h2><a href="index.html">Back to Latest Reports</a></h2>
    <ul>
EOF

UNIQUE_MONTHS=$(jq -r '.[].date[0:7]' "${REPORTS_JSON_PATH}" | sort -r | uniq)
for month in $UNIQUE_MONTHS; do
    ARCHIVE_FILENAME="history-${month}.html"
    echo "INFO: Generating archive for ${month} -> ${ARCHIVE_FILENAME}"
    echo "<li><a href=\" ${ARCHIVE_FILENAME}\">Test reports from ${month}</a></li>" >> reports_repo/history.html
    cat > "reports_repo/${ARCHIVE_FILENAME}" <<- EOF
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <title>Test Reports for ${month}</title>
        <style>
            body { font-family: sans-serif; margin: 2em; background-color: #f4f4f9; color: #333; }
            h1 { color: #444; border-bottom: 2px solid #ddd; padding-bottom: 5px; }
            table { border-collapse: collapse; width: 100%; margin-top: 20px; box-shadow: 0 2px 3px rgba(0,0,0,0.1); }
            th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
            th { background-color: #e8e8f5; }
            tr:nth-child(even) { background-color: #f9f9f9; }
            a { color: #007bff; text-decoration: none; }
            .status-success { color: green; font-weight: bold; }
            .status-failed { color: red; font-weight: bold; }
        </style>
    </head>
    <body>
        <h1>Test Reports for ${month}</h1>
        <h2><a href="history.html">Back to History Index</a></h2>
        <table>
            <thead>
                <tr>
                    <th>Clonezilla Version</th>
                    <th>Date</th>
                    <th>Status</th>
                    <th>Pipeline</th>
                    <th>Commit</th>
                    <th>Report</th>
                </tr>
            </thead>
            <tbody>
EOF
    jq -r --arg month "$month" '.
      .[] | select(.date | startswith($month)) |
      "<tr>
          <td>" + .zip_name + "</td>
          <td>" + .date + "</td>
          <td><span class=\"status-" + .status + "\">" + .status + "</span></td>
          <td><a href=\"" + .pipeline.url + "\" target=\"_blank\">" + .pipeline.iid + " (" + .pipeline.id + ")</a></td>
          <td><a href=\"" + .commit.url + "\" target=\"_blank\">" + .commit.sha + " (" + .commit.ref + ")</a></td>
          <td><a href=\"" + .report_url + "\">View Report</a></td>
       </tr>"
    ' "${REPORTS_JSON_PATH}" >> "reports_repo/${ARCHIVE_FILENAME}"
    cat >> "reports_repo/${ARCHIVE_FILENAME}" <<- 'EOF'
          </tbody>
      </table>
    </body>
    </html>
EOF
done
cat >> reports_repo/history.html <<- 'EOF'
    </ul>
</body>
</html>
EOF

echo "INFO: Report generation complete."
