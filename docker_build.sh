#!/bin/bash
# Convenience wrapper: build the Docker image (once) and run build.sh inside it.
#
# Usage:
#   ./docker_build.sh <arch>          # arch in {arm64, arm, x64}
#   ./docker_build.sh package         # assemble AAR + jniLibs from staging/
#
# All build output (depot_tools, angle/, angle-<arch>/, *.tar.gz) lands in
# this directory, mounted into /work in the container.

set -euo pipefail
cd "$(dirname "$0")"

export PATH="$HOME/.orbstack/bin:$PATH"

IMAGE="angle-android-builder:latest"
PLATFORM_ARG="--platform=linux/amd64"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "==> Building Docker image $IMAGE"
  docker build $PLATFORM_ARG \
    --build-arg UID=$(id -u) \
    --build-arg GID=$(id -g) \
    -t "$IMAGE" .
fi

CMD="${1:?usage: docker_build.sh <arch|package>}"
shift || true

case "$CMD" in
  arm64|arm|x64)
    docker run --rm -t $PLATFORM_ARG \
      -v "$PWD":/work \
      -w /work \
      "$IMAGE" \
      bash -lc "./build.sh Android $CMD"
    ;;
  package)
    mkdir -p staging dist
    for arch in arm64 arm x64; do
      f="angle-$arch.tar.gz"
      [ -f "$f" ] || { echo "Missing $f — build that ABI first"; exit 1; }
      tar -xzf "$f" -C staging
    done
    docker run --rm -t $PLATFORM_ARG \
      -v "$PWD":/work \
      -w /work \
      "$IMAGE" \
      bash -lc "./package_aar.sh /work/staging /work/dist"
    echo "==> Outputs in dist/:"
    ls -lh dist
    ;;
  *)
    echo "Unknown command: $CMD"
    exit 1
    ;;
esac
