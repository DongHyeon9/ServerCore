#!/usr/bin/env bash
# Docker 빌드 캐시 볼륨 삭제 (다음 빌드 시 자동 재생성)
set -euo pipefail
VOLUME="servercore-build-cache"

if ! docker volume inspect "$VOLUME" >/dev/null 2>&1; then
    echo "[INFO] Cache volume '$VOLUME' does not exist. Nothing to clean."
    exit 0
fi

echo "[CLEAN] Removing volume $VOLUME ..."
docker volume rm "$VOLUME"
echo "[DONE] Cache cleared."
