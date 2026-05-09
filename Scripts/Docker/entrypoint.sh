#!/usr/bin/env bash
# Docker 컨테이너 안에서 실행되는 빌드 진입점
# 사용법: entrypoint.sh <TARGET_OS> <MODE> [TARGET_GROUP]
#   TARGET_OS    : linux | windows
#   MODE         : Debug | Release
#   TARGET_GROUP : all (기본) | thirdparty | engine | server | engine_server
set -euo pipefail

TARGET_OS="${1:-linux}"
MODE="${2:-Debug}"
TARGET_GROUP="${3:-all}"

case "$TARGET_OS" in
    linux|windows) ;;
    *) echo "[ERROR] TARGET_OS must be 'linux' or 'windows' (got: $TARGET_OS)"; exit 2 ;;
esac
case "$MODE" in
    Debug|Release) ;;
    *) echo "[ERROR] MODE must be 'Debug' or 'Release' (got: $MODE)"; exit 2 ;;
esac

case "$TARGET_GROUP" in
    all)            CMAKE_TARGETS=() ;;
    thirdparty)     CMAKE_TARGETS=(libprotobuf glfw ImGui) ;;
    engine)         CMAKE_TARGETS=(ServerEngine) ;;
    server)         CMAKE_TARGETS=(TestServer DummyClient ServerMonitor) ;;
    engine_server)  CMAKE_TARGETS=(ServerEngine TestServer DummyClient ServerMonitor) ;;
    *) echo "[ERROR] TARGET_GROUP unknown: $TARGET_GROUP"; exit 2 ;;
esac

MODE_LOWER="$(echo "$MODE" | tr '[:upper:]' '[:lower:]')"
SRC=/work
BUILD_SRC=/build_src
BUILD_DIR="$BUILD_SRC/$TARGET_OS/$MODE"

echo "[DOCKER] OS=$TARGET_OS MODE=$MODE GROUP=$TARGET_GROUP"
echo "[DOCKER] Source=$SRC  BuildDir=$BUILD_DIR"

# ── 1. CRLF 안전망 (Windows 호스트에서 마운트된 셸 스크립트 보호) ─────────────
find "$SRC/Scripts/Docker" -type f -name '*.sh' -exec dos2unix -q {} \; 2>/dev/null || true

# ── 2. 호스트 → 컨테이너 빌드 디렉터리 동기화 ───────────────────────────────
# Windows bind mount의 I/O 오버헤드를 우회하기 위해 ext4(/build_src) 안에서 작업
echo "[DOCKER] Syncing source -> $BUILD_SRC ..."
mkdir -p "$BUILD_SRC"
rsync -a --delete \
    --exclude='.git/' \
    --exclude='.vs/' \
    --exclude='.vscode/' \
    --exclude='.idea/' \
    --exclude='.claude/' \
    --exclude='ClaudeMD/' \
    --exclude='build/' \
    --exclude='out/' \
    --exclude='bin/' \
    --exclude='/linux/' \
    --exclude='/windows/' \
    "$SRC/" "$BUILD_SRC/"

# ── 3. glfw cmake/CMake 케이스 보정 (Windows 호스트 대소문자 무시 회피) ──────
if [ -d "$BUILD_SRC/ThirdParty/glfw/cmake" ] && [ ! -e "$BUILD_SRC/ThirdParty/glfw/CMake" ]; then
    ln -sf cmake "$BUILD_SRC/ThirdParty/glfw/CMake"
fi

# ── 4. CMake configure ────────────────────────────────────────────────────────
if [ "$TARGET_OS" = "linux" ]; then
    TOOLCHAIN="$BUILD_SRC/Scripts/Tools/Compiler/linux-clang-toolchain.cmake"
else
    TOOLCHAIN="$BUILD_SRC/Scripts/Tools/Compiler/windows-clang-toolchain-docker.cmake"
    # clang-cl은 INCLUDE / LIB 환경변수를 native로 인식한다 (MSVC link.exe 동일 규칙).
    # Linux에서 `/LIBPATH:/abs/path`가 절대 경로 파일로 오인되는 문제를 우회.
    SDK="$BUILD_SRC/Scripts/Tools/Windows/sdk"
    export INCLUDE="$SDK/include/msvc;$SDK/include/ucrt;$SDK/include/shared;$SDK/include/um"
    export LIB="$SDK/lib/ucrt/x64;$SDK/lib/um/x64;$SDK/lib/msvc/x64"

    # SDK는 Windows의 대소문자 무시 파일시스템을 가정하므로 (예: kernel32.Lib 파일 +
    # `#include <windows.h>` 또는 `#include "DriverSpecs.h"` 가 `driverspecs.h` 파일 참조)
    # 양방향 케이스 보정 심링크가 필요하다.
    #
    #  1) lib/ 의 모든 파일에 대한 소문자 심링크 (예: User32.Lib -> user32.lib)
    #  2) include/ 안 헤더들의 #include 지시문을 스캔해 실제 파일이 존재하지만
    #     케이스가 다른 경우 요청된 케이스로 심링크 생성
    #
    # rsync --delete가 매번 정리하므로 매 실행마다 다시 만들지만, 합쳐서 ~수 초 수준.
    echo "[DOCKER] Creating case-insensitive symlinks for Windows SDK..."

    # 1a) 파일 케이스 보정: lib/include 안 모든 파일에 소문자 심링크
    #     (예: User32.Lib -> user32.lib, DbgHelp.h -> dbghelp.h)
    #     set +e + 서브셸: pipefail이 SIGPIPE로 find를 죽여 일부 파일이 누락되는
    #     문제 회피. count를 명시적으로 출력해 진행상황 가시화.
    find "$SDK/lib" "$SDK/include" -type f -print0 | (
        set +e
        count=0
        while IFS= read -r -d '' p; do
            b=${p##*/}
            lc=${b,,}
            [ "$b" = "$lc" ] && continue
            d=${p%/*}
            [ -e "$d/$lc" ] && continue
            if ln -s "$b" "$d/$lc" 2>/dev/null; then
                count=$((count+1))
            fi
        done
        echo "[DOCKER]   ... lowercase file symlinks: $count"
    )

    # 1b) 디렉터리 케이스 보정: include 안 모든 디렉터리에 소문자/대문자 심링크
    #     (예: gl/ <-> GL/, 코드가 #include <GL/gl.h> 요청해도 gl/ 디렉터리로 resolved)
    find "$SDK/include" -mindepth 1 -type d -print0 | (
        set +e
        count=0
        while IFS= read -r -d '' p; do
            b=${p##*/}
            d=${p%/*}
            lc=${b,,}
            uc=${b^^}
            if [ "$b" != "$lc" ] && [ ! -e "$d/$lc" ]; then
                ln -s "$b" "$d/$lc" 2>/dev/null && count=$((count+1))
            fi
            if [ "$b" != "$uc" ] && [ ! -e "$d/$uc" ]; then
                ln -s "$b" "$d/$uc" 2>/dev/null && count=$((count+1))
            fi
        done
        echo "[DOCKER]   ... directory case symlinks: $count"
    )

    # 2) include 디렉터리: 헤더의 #include 지시문 기반 케이스 보정
    #    (예: kernelspecs.h가 "DriverSpecs.h" 참조하지만 파일은 driverspecs.h)
    python3 - "$SDK/include" "$BUILD_SRC/ThirdParty" "$BUILD_SRC/ServerEngine" "$BUILD_SRC/Server" <<'PYEOF'
import os, re, sys

include_root = sys.argv[1]
extra_dirs   = sys.argv[2:]

# {(dir, basename_lower): basename_actual} 인덱스
index = {}
for root, _, files in os.walk(include_root):
    for f in files:
        index.setdefault((root, f.lower()), f)

inc_re = re.compile(rb'^\s*#\s*include\s*[<"]([^>"]+)[>"]', re.MULTILINE)
seen = set()
created = 0

# 헤더가 참조하는 파일들을 모두 모은다 (SDK + 프로젝트 소스)
search_dirs = [include_root] + extra_dirs
for d in search_dirs:
    if not os.path.isdir(d):
        continue
    for root, _, files in os.walk(d):
        for f in files:
            if not f.lower().endswith(('.h', '.hpp', '.hxx', '.c', '.cc', '.cpp', '.cxx', '.inl', '.ipp')):
                continue
            path = os.path.join(root, f)
            try:
                with open(path, 'rb') as fp:
                    data = fp.read()
            except Exception:
                continue
            for m in inc_re.finditer(data):
                inc = m.group(1).decode('utf-8', errors='ignore').replace('\\', '/').strip()
                if inc in seen:
                    continue
                seen.add(inc)
                # SDK include 디렉터리 4종(msvc/ucrt/shared/um) 안에서 찾아본다
                inc_parts = inc.split('/')
                for sub in ('msvc', 'ucrt', 'shared', 'um', ''):
                    base_dir = os.path.join(include_root, sub) if sub else include_root
                    if not os.path.isdir(base_dir):
                        continue
                    target = os.path.join(base_dir, *inc_parts)
                    if os.path.exists(target):
                        break
                    target_dir = os.path.dirname(target)
                    if not os.path.isdir(target_dir):
                        continue
                    actual = index.get((target_dir, os.path.basename(target).lower()))
                    if actual and actual != os.path.basename(target):
                        try:
                            os.symlink(actual, target)
                            created += 1
                        except FileExistsError:
                            pass
                        except OSError:
                            pass
                        break

print(f"[DOCKER]   ... include symlinks created: {created}")
PYEOF
fi
# Ninja for both: 이미지에 ninja-build만 포함 (make는 미설치)
GENERATOR="Ninja"

mkdir -p "$BUILD_DIR"
echo "[DOCKER] Configuring CMake ($GENERATOR, $MODE) ..."
if ! cmake -S "$BUILD_SRC" -B "$BUILD_DIR" \
        -G "$GENERATOR" \
        -DCMAKE_BUILD_TYPE="$MODE" \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN"; then
    echo "[ERROR] CMake configure failed. Cleaning $BUILD_DIR for next retry."
    rm -rf "$BUILD_DIR"
    exit 1
fi

# ── 5. 빌드 ───────────────────────────────────────────────────────────────────
JOBS="$(nproc)"
if [ ${#CMAKE_TARGETS[@]} -eq 0 ]; then
    echo "[DOCKER] Building all targets with $JOBS jobs..."
    cmake --build "$BUILD_DIR" -j"$JOBS"
else
    echo "[DOCKER] Building targets [${CMAKE_TARGETS[*]}] with $JOBS jobs..."
    cmake --build "$BUILD_DIR" -j"$JOBS" --target "${CMAKE_TARGETS[@]}"
fi

# ── 6. 산출물 호스트로 복사 ──────────────────────────────────────────────────
SRC_BIN="$BUILD_SRC/bin/$TARGET_OS/$MODE_LOWER"
OUT_BIN="$SRC/bin/$TARGET_OS/$MODE_LOWER"
mkdir -p "$OUT_BIN"

if [ -d "$SRC_BIN" ]; then
    echo "[DOCKER] Copying artifacts: $SRC_BIN -> $OUT_BIN"
    # Windows bind mount는 9P/SMB 위에서 동작하므로 어떤 metadata(mtime, mode,
    # ownership)든 변경 시도가 EPERM. cp가 그 시도를 안 하도록 모두 비활성화.
    # 결과 파일은 호스트 마운트의 기본 권한을 자동으로 따른다.
    cp -rf --no-preserve=all "$SRC_BIN/." "$OUT_BIN/"
else
    echo "[WARN] Build output dir not found: $SRC_BIN (no artifacts to copy)"
fi

echo "[SUCCESS] $TARGET_OS $MODE ($TARGET_GROUP) -> bin/$TARGET_OS/$MODE_LOWER/"
