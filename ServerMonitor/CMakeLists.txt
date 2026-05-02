project(ServerMonitor)

file(GLOB_RECURSE SOURCES "src/*.cpp")

add_executable(ServerMonitor ${SOURCES})

target_link_libraries(ServerMonitor PRIVATE
    ServerEngine
    ImGui
)

if(MSVC)
    target_compile_options(ServerMonitor PRIVATE
        $<$<CONFIG:Debug>:/Zi /Od /RTC1>
        $<$<CONFIG:Release>:/O2>
    )
else()
    target_compile_options(ServerMonitor PRIVATE
        $<$<CONFIG:Debug>:-g -O0>
        $<$<CONFIG:Release>:-O2 -DNDEBUG>
    )
endif()

set_target_properties(ServerMonitor PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY_DEBUG   "${CMAKE_SOURCE_DIR}/bin/ServerMonitor/debug"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_SOURCE_DIR}/bin/ServerMonitor/release"
)
