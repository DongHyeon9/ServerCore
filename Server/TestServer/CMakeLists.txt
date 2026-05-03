project(TestServer)

file(GLOB_RECURSE SOURCES "src/*.cpp")

add_executable(TestServer ${SOURCES} "include/TestServerDialog.h" "src/TestServerDialog.cpp")

target_include_directories(TestServer PRIVATE include)

target_link_libraries(TestServer PRIVATE
    ServerEngine
    ImGui
)

if(MSVC)
    target_compile_options(TestServer PRIVATE
        $<$<CONFIG:Debug>:/Zi /Od /RTC1>
        $<$<CONFIG:Release>:/O2>
    )
else()
    target_compile_options(TestServer PRIVATE
        $<$<CONFIG:Debug>:-g -O0>
        $<$<CONFIG:Release>:-O2 -DNDEBUG>
    )
endif()

if(WIN32)
    set(_BIN_PREFIX "${CMAKE_SOURCE_DIR}/bin/windows")
else()
    set(_BIN_PREFIX "${CMAKE_SOURCE_DIR}/bin/linux")
endif()

set_target_properties(TestServer PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY_DEBUG   "${_BIN_PREFIX}/debug"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${_BIN_PREFIX}/release"
)
