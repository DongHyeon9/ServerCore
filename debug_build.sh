#!/bin/bash
set -e

echo "[BUILD] Type: Debug"

cmake -B "build/Debug" -S . \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++

cmake --build "build/Debug" --config Debug

echo "[SUCCESS] Debug build completed."
