project(DummyClient)

file(GLOB_RECURSE SOURCES "src/*.cpp")

add_executable(DummyClient ${SOURCES})

target_link_libraries(DummyClient PRIVATE ServerEngine)

target_compile_options(DummyClient PRIVATE
    $<$<CONFIG:Debug>:-g -O0>
    $<$<CONFIG:Release>:-O2 -DNDEBUG>
)

set_target_properties(DummyClient PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY_DEBUG   "${CMAKE_SOURCE_DIR}/bin/DummyClient/debug"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_SOURCE_DIR}/bin/DummyClient/release"
)
