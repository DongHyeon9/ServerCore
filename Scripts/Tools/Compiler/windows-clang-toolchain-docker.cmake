# Docker 컨테이너 전용 Windows 크로스컴파일 toolchain (자가완결).
#
# 디자인 메모:
#   - Linux clang-cl 드라이버를 사용 → MSVC ABI(x86_64-pc-windows-msvc) 타겟.
#   - SDK 헤더/라이브러리 경로는 `-imsvc`/`/LIBPATH:` 플래그 대신
#     **INCLUDE / LIB 환경변수**로 전달한다. (clang-cl이 native로 인식)
#     → entrypoint.sh가 cmake configure 직전에 export 한다.
#     → Linux에서 `/LIBPATH:/abs/path` 가 절대 경로 파일로 오인되는 문제 회피.
#   - 호스트(Windows native) 빌드는 `windows-clang-toolchain.cmake` 사용.

set(CMAKE_SYSTEM_NAME      Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# clang-cl: clang의 CL 드라이버 모드. MSVC ABI 타겟용.
# llvm-lib (lib.exe 호환). llvm-ar은 GNU/BSD ar 인자만 받으므로 clang-cl이
# `/nologo /machine:x64 /out:...` 스타일로 호출하면 unknown option 에러.
set(CMAKE_C_COMPILER   /usr/bin/clang-cl)
set(CMAKE_CXX_COMPILER /usr/bin/clang-cl)
set(CMAKE_AR           /usr/bin/llvm-lib)
set(CMAKE_RANLIB       /usr/bin/llvm-ranlib)

# 타겟 트리플 (clang-cl이 Linux 호스트에서 PE/COFF를 생성하도록)
set(CMAKE_C_COMPILER_TARGET   x86_64-pc-windows-msvc)
set(CMAKE_CXX_COMPILER_TARGET x86_64-pc-windows-msvc)

# MSVC 호환 버전 (sdk_versions.txt 의 MSVC 14.44.35207 → 19.44)
add_compile_options(-fms-compatibility-version=19.44)

# MSVC 14.44 STL은 Clang 19+ 만 인정한다 (yvals_core.h STL1000 정적 어서션).
# 우리는 Ubuntu 24.04 의 Clang 18을 쓰므로 escape hatch 매크로로 우회.
add_compile_definitions(_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH)

# CMake가 link.exe 대신 lld-link를 사용하도록 (PE 출력에 필요)
set(CMAKE_LINKER /usr/bin/lld-link)
# clang-cl 드라이버 안에서 lld-link 사용 강제
add_link_options(/MANIFEST:NO)
set(CMAKE_C_USING_LINKER_LLD   "-fuse-ld=lld-link")
set(CMAKE_CXX_USING_LINKER_LLD "-fuse-ld=lld-link")

# CMake가 호스트 시스템 라이브러리(/usr/lib 등)를 검색하지 않도록
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
