cmake_minimum_required(VERSION 3.20)
project(ServerCore)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug)
endif()

# ── Boost.Asio (header-only) ──────────────────────────────────────────────────
add_library(BoostAsio INTERFACE)
target_include_directories(BoostAsio INTERFACE
    ${CMAKE_SOURCE_DIR}/ThirdParty/boost_asio/include
)
target_compile_definitions(BoostAsio INTERFACE
    BOOST_ASIO_NO_DEPRECATED
)

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
set(GLFW_BUILD_DOCS OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(GLFW_INSTALL OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_WAYLAND OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_X11 ON CACHE BOOL "" FORCE)
add_subdirectory(ThirdParty/glfw)

# ── ImGui ────────────────────────────────────────────────────────────────────
add_subdirectory(ThirdParty/imgui)

# ── Project targets ───────────────────────────────────────────────────────────
add_subdirectory(ServerEngine)
add_subdirectory(TestServer)
add_subdirectory(DummyClient)
add_subdirectory(ServerMonitor)
