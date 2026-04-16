#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="lldpos-builder"

cd "$SCRIPT_DIR"

echo "=== Building Docker image ==="
docker build -t "$IMAGE_NAME" .

echo "=== Running build in container ==="
docker run --rm \
    --privileged \
    --hostname lldpos \
    -e HOST_UID=$(id -u) \
    -e HOST_GID=$(id -g) \
    -v "$SCRIPT_DIR":/build \
    -w /build \
    "$IMAGE_NAME" \
    ./build.sh

echo "=== Done ==="
ls -lh "$SCRIPT_DIR"/lldpOS-v*.iso 2>/dev/null || true
