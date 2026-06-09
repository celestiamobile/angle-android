# Build environment for ANGLE Android — mirrors ubuntu-24.04 CI runner.
# Must be linux/amd64: chromium ships only x86_64 NDK toolchains for Linux.
FROM --platform=linux/amd64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential pkg-config python3 python3-setuptools \
        curl git lsb-release ca-certificates file xz-utils zip unzip \
        libglib2.0-dev libnss3-dev libdrm-dev libgbm-dev \
        libxkbcommon-dev libxshmfence-dev \
        openjdk-17-jdk-headless \
        sudo procps \
    && rm -rf /var/lib/apt/lists/*

ARG UID=1000
ARG GID=1000
RUN (getent group ${GID} || groupadd -g ${GID} builder) \
    && (id -u builder >/dev/null 2>&1 || useradd -m -u ${UID} -g ${GID} -s /bin/bash builder) \
    && echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER builder
WORKDIR /work
CMD ["/bin/bash"]
