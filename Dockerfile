# Use a slim Debian image as the base for multi-arch support
FROM debian:bookworm-slim

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
    qemu-utils && \
    # Install all QEMU architecture-specific packages unconditionally
    qemu-system-x86 \
    qemu-system-arm \
    qemu-efi-aarch64 && \
    # Clean up APT cache
    rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /app

# Copy all the project files into the container
# .dockerignore will prevent logs, images, and other large files from being copied
COPY . .

# Set a default command to run the test suite
CMD ["./start.sh"]
