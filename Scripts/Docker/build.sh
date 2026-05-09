#!/usr/bin/env bash
# Docker 빌드 디스패처 (Linux / macOS 호스트)
# 사용법: build.sh <Linux|Windows> <Debug|Release> [target_group]
#   target_group: all (기본) | thirdparty | engine | server | engine_server
set -euo pipefail

TARGET_OS="${1:-Linux}"
MODE="${2:-Debug}"
TARGET_GROUP="${3:-all}"

case "$(echo "$TARGET_OS" | tr '[:upper:]' '[:lower:]')" in
    linux)   TARGET_OS_LOWER=linux ;;
    windows) TARGET_OS_LOWER=windows ;;
    *) echo "[ERROR] TARGET_OS must be 'Linux' or 'Windows' (got: $TARGET_OS)" >&2; exit 2 ;;
esac
case "$MODE" in
    Debug|Release) ;;
    *) echo "[ERROR] MODE must be 'Debug' or 'Release' (got: $MODE)" >&2; exit 2 ;;
esac

if ! command -v docker >/dev/null 2>&1; then
    echo "[ERROR] docker not found. Install Docker: https://docs.docker.com/get-docker/" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

IMAGE="servercore-builder:latest"
VOLUME="servercore-build-cache"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "[BUILD] Building image $IMAGE (first run, ~3-5 min) ..."
    docker build -t "$IMAGE" "$ROOT"
fi

docker volume inspect "$VOLUME" >/dev/null 2>&1 || docker volume create "$VOLUME" >/dev/null

echo "[RUN] $TARGET_OS_LOWER $MODE $TARGET_GROUP"
docker run --rm \
    -v "$ROOT:/work" \
    -v "$VOLUME:/build_src" \
    --user "$(id -u):$(id -g)" \
    "$IMAGE" "$TARGET_OS_LOWER" "$MODE" "$TARGET_GROUP"

echo "[DONE] Output: bin/$TARGET_OS_LOWER/"
