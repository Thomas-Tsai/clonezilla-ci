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
    bc \
    # Filesystem and guest tools
    guestfs-tools \
    guestfish \
    guestmount \
    xfsprogs \
    # QEMU common utilities
    qemu-utils \
    # All QEMU system emulators
    qemu-system-x86 \
    qemu-system-arm \
    qemu-system-riscv \
    qemu-efi-aarch64 \
    u-boot-qemu && \
    # Ensure xfsprogs is included in the libguestfs appliance
    find /usr/lib -name supermin.d -type d -exec sh -c 'echo xfsprogs >> {}/packages' \; && \
    # Clean up APT cache (after main install)
    rm -rf /var/lib/apt/lists/*

# Install kernel package required by libguestfs to build its appliance.
# This prevents 'supermin exited with error status 1' by providing kernel modules.
# Note: TARGETARCH may not be set in Docker legacy builder; use dpkg as fallback.
RUN apt-get update && \
    REAL_ARCH="${TARGETARCH:-$(dpkg --print-architecture)}" && \
    echo "Detected architecture: ${REAL_ARCH}" && \
    case ${REAL_ARCH} in \
        "amd64") apt-get install -y --no-install-recommends linux-image-amd64 ;; \
        "arm64") apt-get install -y --no-install-recommends linux-image-arm64 ;; \
        "riscv64") apt-get install -y --no-install-recommends linux-image-riscv64 ;; \
        *) echo "No specific linux-image package for arch: ${REAL_ARCH}." && true ;; \
    esac && \
    rm -rf /var/lib/apt/lists/* && \
    echo "Kernel files in /boot:" && ls -la /boot/vmlinuz-* 2>/dev/null || echo "(none)" && \
    echo "Modules dirs:" && ls -d /lib/modules/*/ /usr/lib/modules/*/ 2>/dev/null || echo "(none)"

# Copy kernel and modules to /opt/kernel/ so they remain accessible when running
# inside Singularity containers (which may overlay host's /boot over container's /boot).
# IMPORTANT: supermin requires the kernel filename to contain the version string.
RUN mkdir -p /opt/kernel/boot /opt/kernel/lib/modules && \
    VMLINUZ=$(find /boot -name 'vmlinuz-*' -type f 2>/dev/null | head -1) && \
    MODDIR=$(find /lib/modules /usr/lib/modules -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1) && \
    echo "Found kernel: [${VMLINUZ}]" && \
    echo "Found modules: [${MODDIR}]" && \
    if [ -z "$VMLINUZ" ]; then echo "ERROR: No kernel found!" && exit 1; fi && \
    if [ -z "$MODDIR" ]; then echo "ERROR: No modules found!" && exit 1; fi && \
    cp "$VMLINUZ" /opt/kernel/boot/ && \
    cp -a "$MODDIR" /opt/kernel/lib/modules/ && \
    KNAME=$(basename "$VMLINUZ") && \
    MNAME=$(basename "$MODDIR") && \
    echo "SUPERMIN_KERNEL=/opt/kernel/boot/${KNAME}" > /opt/kernel/env && \
    echo "SUPERMIN_MODULES=/opt/kernel/lib/modules/${MNAME}" >> /opt/kernel/env && \
    echo "--- /opt/kernel/env ---" && cat /opt/kernel/env


# Set the working directory
WORKDIR /app

# Copy all the project files into the container
# .dockerignore will prevent logs, images, and other large files from being copied
COPY . .

# Set a default command to run the test suite
CMD ["./start.sh"]
