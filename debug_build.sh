#!/bin/bash
set -e

echo "[BUILD] Linux Debug"

# GLFW가 요구하는 X11 헤더 전부 확인
MISSING=()
[ ! -f /usr/include/X11/Xlib.h ]         && MISSING+=("libx11-dev")
[ ! -f /usr/include/X11/extensions/Xrandr.h ]  && MISSING+=("libxrandr-dev")
[ ! -f /usr/include/X11/extensions/Xinerama.h ] && MISSING+=("libxinerama-dev")
[ ! -f /usr/include/X11/Xcursor/Xcursor.h ]     && MISSING+=("libxcursor-dev")
[ ! -f /usr/include/X11/extensions/XInput2.h ]  && MISSING+=("libxi-dev")
[ ! -f /usr/include/X11/extensions/shape.h ]    && MISSING+=("libxext-dev")
[ ! -f /usr/include/GL/gl.h ]                   && MISSING+=("libgl-dev")

if [ ${#MISSING[@]} -ne 0 ]; then
    echo ""
    echo "[ERROR] 다음 패키지가 없습니다: ${MISSING[*]}"
    echo "  Ubuntu/Debian:"
    echo "    sudo apt install ${MISSING[*]}"
    echo ""
    exit 1
fi

cmake -B "build/Debug" -S . \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++

cmake --build "build/Debug" --config Debug -j$(nproc)

echo "[SUCCESS] Linux Debug build completed. Output: bin/*/debug/"
