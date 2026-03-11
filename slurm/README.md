# Slurm/HPC Support for Clonezilla CI

This directory contains scripts and configuration to run the Clonezilla CI test suite on an HPC environment using the Slurm workload manager and Singularity containers.

## Prerequisites

1.  **Slurm**: The HPC cluster should use Slurm for job scheduling.
2.  **Singularity/Apptainer**: Singularity must be installed to run the tests in a consistent containerized environment.
3.  **QEMU with KVM (Optional but recommended)**: For optimal performance, the HPC nodes should support KVM.

## Setup Instructions

### 1. Build the Singularity Image

Instead of managing a separate Singularity definition file, we build the Singularity image directly from the project's `Dockerfile` to ensure the environments are identical.

First, build the Docker image from the project root:
```bash
docker build -t clonezilla-ci:latest .
```

Then, export the image to a tar archive and build the Singularity image from it (this avoids issues with Apptainer docker-daemon API incompatibilities):
```bash
docker save clonezilla-ci:latest -o /tmp/clonezilla-ci.tar
cd slurm
sudo singularity build clonezilla-ci.sif docker-archive:///tmp/clonezilla-ci.tar
```

*Note: You may need `sudo` to run `singularity build` locally depending on your Apptainer/Singularity setup.*

### 2. Prepare Your Environment

Ensure that any required disk images or Clonezilla ZIP files are available in the project's `qemu/cloudimages/` and `zip/` directories, respectively.

## Running Tests

### Submit a Single Test

You can submit a specific test script using `sbatch`:

```bash
sbatch --export=ALL,TEST_SCRIPT=jobs/test_fs_ext4.sh template.sbatch
```

### Submit All Tests

To run the entire test suite in parallel, use the `submit_all.sh` script:

```bash
./submit_all.sh
```

This will iterate through all `jobs/test*.sh` scripts and submit each as a separate Slurm job.

## Monitoring and Logs

*   **Slurm Queue**: Use `squeue -u $USER` to monitor your jobs.
*   **Job Output**: Standard output and error for each job are stored in `slurm/logs/`.
*   **Test Logs**: Detailed test logs are still generated in the project's root `logs/` directory.

## Customization

You can modify `template.sbatch` to adjust Slurm parameters such as partition, account, memory, or time limits to fit your HPC environment.
