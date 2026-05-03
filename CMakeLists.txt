cmake_minimum_required(VERSION 3.20)
project(ServerCore)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug)
endif()

# clang + MSVC ABI 조합 전용 전역 설정
if(WIN32 AND CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    # offsetof 가 __builtin_offsetof 로 확장되도록 강제
    # (MSVC 헤더의 기본 offsetof 는 non-constexpr 이라 abseil static_assert 가 실패함)
    add_compile_definitions(_CRT_USE_BUILTIN_OFFSETOF)
    # SSE2 명시 활성화 — clang 이 _mm_set_ss 등 SSE intrinsic 을 인라인으로 처리하게 함
    # (x86_64 는 SSE2 가 기본 제공이지만 clang MSVC 모드에서는 명시 필요)
    add_compile_options(-msse2)
endif()

# ── Boost.Asio (header-only) ──────────────────────────────────────────────────
add_library(BoostAsio INTERFACE)
target_include_directories(BoostAsio INTERFACE
    ${CMAKE_SOURCE_DIR}/ThirdParty/boost_asio/include
)
target_compile_definitions(BoostAsio INTERFACE
    BOOST_ASIO_STANDALONE
    BOOST_ASIO_NO_DEPRECATED
)
if(WIN32)
    # Boost.Asio가 WinSock2를 올바르게 포함하려면 필요
    target_compile_definitions(BoostAsio INTERFACE
        _WIN32_WINNT=0x0A00
        WIN32_LEAN_AND_MEAN
    )
endif()

# ── Abseil-cpp (Protobuf dependency) ─────────────────────────────────────────
set(ABSL_PROPAGATE_CXX_STD ON CACHE BOOL "" FORCE)
set(ABSL_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory(ThirdParty/abseil-cpp EXCLUDE_FROM_ALL)

# ── Protobuf ──────────────────────────────────────────────────────────────────
set(protobuf_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(protobuf_BUILD_CONFORMANCE OFF CACHE BOOL "" FORCE)
set(protobuf_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(protobuf_INSTALL OFF CACHE BOOL "" FORCE)
set(protobuf_MSVC_STATIC_RUNTIME OFF CACHE BOOL "" FORCE)
set(protobuf_WITH_ZLIB OFF CACHE BOOL "" FORCE)
add_subdirectory(ThirdParty/protobuf)

# ── GLFW (windowing for server monitor) ──────────────────────────────────────
set(GLFW_BUILD_DOCS     OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_TESTS    OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(GLFW_INSTALL        OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_WAYLAND  OFF CACHE BOOL "" FORCE)
if(WIN32)
    set(GLFW_BUILD_X11   OFF CACHE BOOL "" FORCE)
    set(GLFW_BUILD_WIN32 ON  CACHE BOOL "" FORCE)
else()
    set(GLFW_BUILD_X11   ON  CACHE BOOL "" FORCE)
endif()
add_subdirectory(ThirdParty/glfw)

# ── ImGui ────────────────────────────────────────────────────────────────────
add_subdirectory(ThirdParty/imgui)

# ── Project targets ───────────────────────────────────────────────────────────
add_subdirectory(ServerEngine)
add_subdirectory(Server/TestServer)
add_subdirectory(Server/DummyClient)
add_subdirectory(Server/ServerMonitor)
