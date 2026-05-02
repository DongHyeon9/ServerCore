project(ServerEngine)

file(GLOB_RECURSE SOURCES "src/*.cpp")

add_library(ServerEngine STATIC ${SOURCES})

target_include_directories(ServerEngine PUBLIC include)

target_compile_options(ServerEngine PRIVATE
    $<$<CONFIG:Debug>:-g -O0>
    $<$<CONFIG:Release>:-O2 -DNDEBUG>
)

set_target_properties(ServerEngine PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY_DEBUG   "${CMAKE_SOURCE_DIR}/bin/ServerEngine/debug"
    ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${CMAKE_SOURCE_DIR}/bin/ServerEngine/release"
    LIBRARY_OUTPUT_DIRECTORY_DEBUG   "${CMAKE_SOURCE_DIR}/bin/ServerEngine/debug"
    LIBRARY_OUTPUT_DIRECTORY_RELEASE "${CMAKE_SOURCE_DIR}/bin/ServerEngine/release"
)
