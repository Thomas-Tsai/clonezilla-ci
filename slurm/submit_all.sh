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
    echo "Make sure to build Docker image first: docker build -t clonezilla-ci:latest ."
    echo "Then export it: docker save clonezilla-ci:latest -o /tmp/clonezilla-ci.tar"
    echo "Then build Singularity image: sudo singularity build $SIF_IMAGE docker-archive:///tmp/clonezilla-ci.tar"
    echo "If you continue, the Slurm jobs may fail."
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Parse command line arguments
ZIP_FILE=""
ARCH=""
TYPE=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --zip)
            ZIP_FILE="$2"
            shift 2
            ;;
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --type)
            TYPE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--zip <path>] [--arch <arch>] [--type <type>]"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: $0 [--zip <path>] [--arch <arch>] [--type <type>]"
            exit 1
            ;;
    esac
done

ARCH=${ARCH:-amd64}
TYPE=${TYPE:-stable}

if [[ -z "$ZIP_FILE" ]]; then
    echo "--- Ensuring Clonezilla ZIP is downloaded for $ARCH ($TYPE) ---"
    "$PROJECT_ROOT/download-clonezilla.sh" --arch "$ARCH" --type "$TYPE" -o "$PROJECT_ROOT/zip"
    if [ $? -ne 0 ]; then
        echo "WARNING: Failed to auto-download zip on login node. Compute nodes may fail if they cannot access the internet."
    fi
else
    echo "--- Using specific Clonezilla ZIP: $ZIP_FILE ---"
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
    # Using --export to pass the test script and arguments into the sbatch environment
    export_args="ALL,TEST_SCRIPT=$test_file,ARCH=$ARCH"
    if [[ -n "$ZIP_FILE" ]]; then
        export_args="$export_args,ZIP_FILE=$ZIP_FILE"
    fi

    sbatch --job-name="ci_$test_name" \
           --partition="$SLURM_PARTITION" \
           --account="$SLURM_ACCOUNT" \
           --export="$export_args" \
           "$SBATCH_TEMPLATE"
done

echo "--- All jobs submitted. Use 'squeue -u \$USER' to monitor progress. ---"
