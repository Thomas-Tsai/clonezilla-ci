#!/bin/bash
# submit_all.sh - Submits all Clonezilla CI tests as Slurm jobs.

# Directory of this script
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/..")"
SBATCH_TEMPLATE="$SCRIPT_DIR/template.sbatch"

# Default partition and account
SLURM_PARTITION=${SLURM_PARTITION:-development}
SLURM_ACCOUNT=${SLURM_ACCOUNT:-GOV109092}

# Ensure we're running from the project root
cd "$PROJECT_ROOT"

# Ensure the logs directory for Slurm exists
mkdir -p "$SCRIPT_DIR/logs"

# Verify the Singularity image exists
SIF_IMAGE="$SCRIPT_DIR/clonezilla-ci.sif"
if [[ ! -f "$SIF_IMAGE" ]]; then
    echo "WARNING: Singularity image not found at $SIF_IMAGE"
    echo "Make sure to build it first: singularity build $SIF_IMAGE $SCRIPT_DIR/clonezilla-ci.def"
    echo "If you continue, the Slurm jobs may fail."
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "--- Submitting all tests in parallel ---"

# Find all test files in the jobs directory
TEST_FILES=$(ls jobs/test_*.sh 2>/dev/null)

if [[ -z "$TEST_FILES" ]]; then
    echo "No test scripts found in jobs/ directory."
    exit 1
fi

for test_file in $TEST_FILES; do
    test_name=$(basename "$test_file" .sh)
    echo "Submitting job for: $test_name"
    # Using --export to pass the test script into the sbatch environment
    sbatch --job-name="ci_$test_name" \
           --partition="$SLURM_PARTITION" \
           --account="$SLURM_ACCOUNT" \
           --export=ALL,TEST_SCRIPT="$test_file" \
           "$SBATCH_TEMPLATE"
done

echo "--- All jobs submitted. Use 'squeue -u \$USER' to monitor progress. ---"
