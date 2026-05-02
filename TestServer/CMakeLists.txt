project(TestServer)

file(GLOB_RECURSE SOURCES "src/*.cpp")

add_executable(TestServer ${SOURCES})

target_link_libraries(TestServer PRIVATE ServerEngine)

target_compile_options(TestServer PRIVATE
    $<$<CONFIG:Debug>:-g -O0>
    $<$<CONFIG:Release>:-O2 -DNDEBUG>
)

set_target_properties(TestServer PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY_DEBUG   "${CMAKE_SOURCE_DIR}/bin/TestServer/debug"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_SOURCE_DIR}/bin/TestServer/release"
)
