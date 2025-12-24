# Use a slim Debian image as the base for multi-arch support
FROM debian:trixie

# Docker provides this build-time argument automatically
ARG TARGETARCH

# Set a non-interactive frontend for package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # Core utilities
    curl \
    wget \
    unzip \
    shunit2 \
    uuid-runtime \
    genisoimage \
    # Filesystem and guest tools
    guestfs-tools \
    guestfish \
    guestmount \
    # QEMU common utilities
    qemu-utils \
    # All QEMU system emulators
    qemu-system-x86 \
    qemu-system-arm \
    qemu-system-riscv \
    qemu-efi-aarch64 && \
    # Clean up APT cache (after main install)
    rm -rf /var/lib/apt/lists/*;

# Install kernel package required by libguestfs to build its appliance for the TARGETARCH
# This prevents 'supermin exited with error status 1' by providing kernel modules.
RUN apt-get update && \
    case ${TARGETARCH} in \
        "amd64") apt-get install -y --no-install-recommends linux-image-amd64 ;; \
        "arm64") apt-get install -y --no-install-recommends linux-image-arm64 ;; \
        "riscv64") \
            # Debian 'bookworm' might not have a direct 'linux-image-riscv64' or it's named differently.
            # We'll install a generic kernel-image if available, or skip if not.
            # For Debian bookworm, 'linux-image-riscv64' should exist for that architecture.
            apt-get install -y --no-install-recommends linux-image-riscv64 ;; \
        *) echo "No specific linux-image package for TARGETARCH: ${TARGETARCH}. Skipping specific kernel image installation." && true ;; \
    esac && \
    rm -rf /var/lib/apt/lists/*


# Set the working directory
WORKDIR /app

# Copy all the project files into the container
# .dockerignore will prevent logs, images, and other large files from being copied
COPY . .

# Set a default command to run the test suite
CMD ["./start.sh"]
