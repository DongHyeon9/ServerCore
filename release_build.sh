#!/bin/bash
set -e

echo "[BUILD] Type: Release"

cmake -B "build/Release" -S . \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++

cmake --build "build/Release" --config Release

echo "[SUCCESS] Release build completed."
