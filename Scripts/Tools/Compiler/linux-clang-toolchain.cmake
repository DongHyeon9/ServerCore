# Linux x64 Clang 툴체인
# 사전 조건: clang, clang++, lld 가 PATH에 있어야 합니다
# Ubuntu/Debian: sudo apt install clang lld

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

find_program(CMAKE_C_COMPILER
    NAMES clang
    DOC "Clang C compiler"
    REQUIRED
)
find_program(CMAKE_CXX_COMPILER
    NAMES clang++
    DOC "Clang C++ compiler"
    REQUIRED
)
# llvm-ar/llvm-ranlib: 버전 suffix 형태(llvm-ar-17 등)도 탐색
find_program(CMAKE_AR
    NAMES llvm-ar llvm-ar-20 llvm-ar-19 llvm-ar-18 llvm-ar-17 llvm-ar-16 llvm-ar-15 llvm-ar-14
    DOC "LLVM archiver"
)
find_program(CMAKE_RANLIB
    NAMES llvm-ranlib llvm-ranlib-20 llvm-ranlib-19 llvm-ranlib-18 llvm-ranlib-17 llvm-ranlib-16 llvm-ranlib-15 llvm-ranlib-14
    DOC "LLVM ranlib"
)

# LLD가 설치된 경우 사용 (빌드 속도 향상)
find_program(_LLD NAMES ld.lld lld)
if(_LLD)
    set(CMAKE_EXE_LINKER_FLAGS_INIT    "-fuse-ld=lld")
    set(CMAKE_SHARED_LINKER_FLAGS_INIT "-fuse-ld=lld")
    set(CMAKE_MODULE_LINKER_FLAGS_INIT "-fuse-ld=lld")
endif()
