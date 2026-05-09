# Windows x64 Clang 툴체인 (MSVC ABI)
# 사용 환경:
#   - Docker 컨테이너 (권장): Linux clang이 x86_64-pc-windows-msvc 타겟으로 크로스컴파일
#     → 컨테이너의 windows-clang-toolchain-docker.cmake가 이 파일을 include하여 사용
#   - 호스트 직접 사용 시: $ENV{LLVM_PATH}/bin 또는 시스템 PATH의 clang 사용
# SDK: Scripts\Tools\Windows\sdk\ (리포지토리에 pre-committed)

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# ── 컴파일러 탐색 (CMAKE_C_COMPILER가 외부에서 설정되지 않은 경우만) ──────────
if(NOT CMAKE_C_COMPILER)
    set(_LLVM_HINTS
        "$ENV{LLVM_PATH}/bin"
        "/usr/bin"
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
endif()

# Windows x64 MSVC ABI 타겟
set(CMAKE_C_COMPILER_TARGET   x86_64-pc-windows-msvc)
set(CMAKE_CXX_COMPILER_TARGET x86_64-pc-windows-msvc)

# LLD 링커 사용
set(CMAKE_EXE_LINKER_FLAGS_INIT    "-fuse-ld=lld")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-fuse-ld=lld")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "-fuse-ld=lld")

# ── Pre-committed SDK 경로 설정 (VS2022 없이도 빌드 가능) ─────────────────────
# CMAKE_CURRENT_LIST_DIR = Scripts/Tools/Compiler/
# SDK 위치    = Scripts/Tools/Windows/sdk/
get_filename_component(_SDK_ROOT "${CMAKE_CURRENT_LIST_DIR}/../Windows/sdk" ABSOLUTE)

if(EXISTS "${_SDK_ROOT}/include/msvc")
    # MSVC 버전 명시 (sdk_versions.txt 의 MSVC_VERSION 14.44.35207 → 19.44)
    string(APPEND CMAKE_C_FLAGS_INIT   " -fms-compatibility-version=19.44")
    string(APPEND CMAKE_CXX_FLAGS_INIT " -fms-compatibility-version=19.44")

    # 시스템 헤더로 취급 (-imsvc = MSVC-compatible system include)
    foreach(_inc msvc ucrt shared um)
        string(APPEND CMAKE_C_FLAGS_INIT   " -imsvc${_SDK_ROOT}/include/${_inc}")
        string(APPEND CMAKE_CXX_FLAGS_INIT " -imsvc${_SDK_ROOT}/include/${_inc}")
    endforeach()

    # 링커 라이브러리 검색 경로
    foreach(_lib ucrt/x64 um/x64 msvc/x64)
        string(APPEND CMAKE_EXE_LINKER_FLAGS_INIT    " /LIBPATH:${_SDK_ROOT}/lib/${_lib}")
        string(APPEND CMAKE_SHARED_LINKER_FLAGS_INIT " /LIBPATH:${_SDK_ROOT}/lib/${_lib}")
        string(APPEND CMAKE_MODULE_LINKER_FLAGS_INIT " /LIBPATH:${_SDK_ROOT}/lib/${_lib}")
    endforeach()
endif()
