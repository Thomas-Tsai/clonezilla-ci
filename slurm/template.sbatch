#!/bin/bash
#SBATCH --job-name=clonezilla_ci
#SBATCH --partition=dev
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --output=slurm/logs/%j_%x.out
#SBATCH --error=slurm/logs/%j_%x.err

# --- Environment Setup ---
# Default to amd64 if ARCH is not set
ARCH=${ARCH:-amd64}

# Singularity image naming convention
SIF_IMAGE="slurm/clonezilla-ci.sif"

# The test script to run (provided by environment variable or script arg)
# Example: export TEST_SCRIPT=jobs/test_fs_ext4.sh
TARGET_TEST_SCRIPT=${TEST_SCRIPT:-$1}

if [[ -z "$TARGET_TEST_SCRIPT" ]]; then
    echo "ERROR: No test script specified. Set TEST_SCRIPT or pass it as an argument." >&2
    exit 1
fi

if [[ ! -f "$TARGET_TEST_SCRIPT" ]]; then
    echo "ERROR: Test script not found: $TARGET_TEST_SCRIPT" >&2
    exit 1
fi

echo "--- Submitting Clonezilla CI Test Job ---"
echo "Job Name: $SLURM_JOB_NAME"
echo "Job ID:   $SLURM_JOB_ID"
echo "Test File: $TARGET_TEST_SCRIPT"
echo "Arch:      $ARCH"
echo "----------------------------------------"

# Run the test script inside the Singularity container.
# We mount the current directory and use --nv if GPUs were needed (not here).
# -e ensures variables are passed through, but singularity by default passes envvars.
# We assume the user has built the .sif image as slurm/clonezilla-ci.sif.

# We need to change directory to 'jobs' to run the tests correctly because of common.sh check.
# The common.sh script enforces being in 'jobs' directory.

singularity exec --bind .:/app \
    ${SIF_IMAGE} \
    bash -c "cd jobs && ./${TARGET_TEST_SCRIPT#jobs/}"

echo "----------------------------------------"
echo "Job completed at $(date)"
