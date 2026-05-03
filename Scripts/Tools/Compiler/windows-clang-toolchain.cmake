# Windows x64 Clang 툴체인 (MSVC ABI)
# 사전 조건:
#   1. Scripts\setup_tools_windows.bat 실행 (최초 1회) — 컴파일러를 Scripts\Tools\Windows\bin\ 로 복사
#   2. Visual Studio 2022 빌드 도구 설치 — Windows SDK 헤더/라이브러리 제공 (vcvars64.bat)

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# 탐색 순서: 프로젝트 로컬 → LLVM_PATH 환경변수 → 독립 LLVM 설치
set(_LLVM_HINTS
    "${CMAKE_SOURCE_DIR}/Scripts/Tools/Windows/bin"
    "$ENV{LLVM_PATH}/bin"
    "C:/Program Files/LLVM/bin"
    "C:/Program Files (x86)/LLVM/bin"
)

find_program(CMAKE_C_COMPILER
    NAMES clang
    HINTS ${_LLVM_HINTS}
    DOC "Clang C compiler"
    REQUIRED
)
find_program(CMAKE_CXX_COMPILER
    NAMES clang++
    HINTS ${_LLVM_HINTS}
    DOC "Clang C++ compiler"
    REQUIRED
)
find_program(CMAKE_AR
    NAMES llvm-ar
    HINTS ${_LLVM_HINTS}
    DOC "LLVM archiver"
)
find_program(CMAKE_RANLIB
    NAMES llvm-ranlib
    HINTS ${_LLVM_HINTS}
    DOC "LLVM ranlib"
)

# Windows x64 MSVC ABI 타겟
set(CMAKE_C_COMPILER_TARGET   x86_64-pc-windows-msvc)
set(CMAKE_CXX_COMPILER_TARGET x86_64-pc-windows-msvc)

# LLD 링커 사용
set(CMAKE_EXE_LINKER_FLAGS_INIT    "-fuse-ld=lld")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-fuse-ld=lld")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "-fuse-ld=lld")
