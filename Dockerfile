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
    qemu-efi-aarch64 && \
    # Ensure xfsprogs is included in the libguestfs appliance
    find /usr/lib -name supermin.d -type d -exec sh -c 'echo xfsprogs >> {}/packages' \; && \
    # Clean up APT cache (after main install)
    rm -rf /var/lib/apt/lists/*

# Install kernel package required by libguestfs to build its appliance for the TARGETARCH
# This prevents 'supermin exited with error status 1' by providing kernel modules.
RUN apt-get update && \
    case ${TARGETARCH} in \
        "amd64") apt-get install -y --no-install-recommends linux-image-amd64 ;; \
        "arm64") apt-get install -y --no-install-recommends linux-image-arm64 ;; \
        "riscv64") \
            apt-get install -y --no-install-recommends linux-image-riscv64 ;; \
        *) echo "No specific linux-image package for TARGETARCH: ${TARGETARCH}. Skipping specific kernel image installation." && true ;; \
    esac && \
    rm -rf /var/lib/apt/lists/*

# Copy kernel and modules to /opt/kernel/ so they remain accessible when running
# inside Singularity containers (which may overlay host's /boot over container's /boot).
# Debian trixie may place modules in /usr/lib/modules/ instead of /lib/modules/.
RUN mkdir -p /opt/kernel && \
    VMLINUZ=$(find /boot /usr/lib -name 'vmlinuz-*' -type f 2>/dev/null | head -1) && \
    MODDIR=$(find /lib/modules /usr/lib/modules -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1) && \
    echo "Found kernel: ${VMLINUZ}" && \
    echo "Found modules: ${MODDIR}" && \
    if [ -n "$VMLINUZ" ]; then cp "$VMLINUZ" /opt/kernel/vmlinuz; fi && \
    if [ -n "$MODDIR" ]; then cp -a "$MODDIR" /opt/kernel/modules; fi && \
    ls -la /opt/kernel/

ENV SUPERMIN_KERNEL=/opt/kernel/vmlinuz
ENV SUPERMIN_MODULES=/opt/kernel/modules


# Set the working directory
WORKDIR /app

# Copy all the project files into the container
# .dockerignore will prevent logs, images, and other large files from being copied
COPY . .

# Set a default command to run the test suite
CMD ["./start.sh"]
