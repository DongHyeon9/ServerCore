#!/bin/bash
# Runs inside WSL2 -- called by wsl_*_build.bat scripts
set -e

MODE="${1:-Debug}"
SRC="$2"    # Project root as WSL path  (e.g. /mnt/c/Users/user/Desktop/.../ServerCore)
shift 2
TARGETS=("$@")   # optional: cmake --target args (empty = build all)

NATIVE="$HOME/ServerCore"
BD="$HOME/build/ServerCore/$MODE"

if ! command -v rsync &>/dev/null; then
    echo "[ERROR] rsync not found. Run: Scripts/Linux/setup_wsl_ubuntu.bat"
    exit 1
fi

echo "[WSL] Syncing source to native filesystem: $NATIVE"
mkdir -p "$NATIVE"
rsync -a --delete "$SRC/" "$NATIVE/" \
    --exclude='.vs/' \
    --exclude='build/' \
    --exclude='Scripts/Tools/Windows/'

# Fix case-sensitivity: glfw CMakeLists.txt references CMake/ but dir is cmake/ on disk (Windows is case-insensitive)
if [ -d "$NATIVE/ThirdParty/glfw/cmake" ] && [ ! -e "$NATIVE/ThirdParty/glfw/CMake" ]; then
    ln -sf cmake "$NATIVE/ThirdParty/glfw/CMake"
fi

echo "[WSL] Configuring $MODE..."
mkdir -p "$BD"
if ! cmake -B "$BD" -S "$NATIVE" \
    -DCMAKE_BUILD_TYPE="$MODE" \
    -DCMAKE_TOOLCHAIN_FILE="$NATIVE/Scripts/Tools/Compiler/linux-clang-toolchain.cmake"; then
    rm -rf "$BD"
    echo "[ERROR] CMake configure failed. Build directory cleaned for next retry."
    exit 1
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
    echo "[WSL] Building $MODE (all targets) with $(nproc) threads..."
    cmake --build "$BD" -j$(nproc)
else
    echo "[WSL] Building $MODE targets: ${TARGETS[*]} with $(nproc) threads..."
    cmake --build "$BD" -j$(nproc) --target "${TARGETS[@]}"
fi

echo "[WSL] Copying binaries to shared folder..."
MODE_LOWER=$(echo "$MODE" | tr '[:upper:]' '[:lower:]')
SRC_BIN="$NATIVE/bin/linux/$MODE_LOWER"
OUT="$SRC/bin/linux/$MODE_LOWER"
mkdir -p "$OUT"
for TARGET in TestServer DummyClient ServerMonitor; do
    BIN="$SRC_BIN/$TARGET"
    if [ -f "$BIN" ]; then
        cp -f "$BIN" "$OUT/"
        echo "  -> $TARGET"
    fi
done

echo "[SUCCESS] Linux $MODE build complete. Output: bin/linux/$MODE_LOWER/"
