#!/bin/bash
#
# start.sh - Run the clonezilla ci test suite.
#
# This script runs all test jobs located in the jobs/ directory.
#

# --- Configurable variables ---
LOG_DIR="./logs"
MAIN_LOG_FILE="${LOG_DIR}/start_sh_main_$(date +%Y%m%d_%H%M%S).log"
START_TIME=$(date +%s)
JOBS_DIR="jobs"

# --- Setup Logging ---
mkdir -p "$LOG_DIR"
exec &> >(tee -a "$MAIN_LOG_FILE")

echo "--- Starting Clonezilla CI Test Suite ---"
echo "Arguments: $@"
echo "-----------------------------------------"

# Find and run all test scripts in the jobs directory
for test_script in "${JOBS_DIR}"/test_*.sh; do
    if [ -f "$test_script" ]; then
        echo ""
        echo "=================================================================="
        echo "--- Running Test Job: $(basename "$test_script")"
        echo "=================================================================="
        
        # Execute the test script, passing along all arguments from start.sh
        (cd "${JOBS_DIR}" && ./"$(basename "$test_script")" "$@")
        
        RESULT=$?
        if [ "$RESULT" -ne 0 ]; then
            echo "--- Test Job FAILED: $(basename "$test_script") (Exit Code: $RESULT) ---"
        else
            echo "--- Test Job PASSED: $(basename "$test_script") ---"
        fi
        echo "=================================================================="
    fi
done


# --- Final Summary ---
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo "------------------------------------------------------------------"
echo "All test jobs completed."
echo "Total execution time: ${DURATION} seconds"
echo "Main log file: $MAIN_LOG_FILE"
echo "------------------------------------------------------------------"

