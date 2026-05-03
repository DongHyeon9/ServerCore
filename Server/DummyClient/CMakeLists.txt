project(DummyClient)

file(GLOB_RECURSE SOURCES "src/*.cpp")

add_executable(DummyClient ${SOURCES})

target_link_libraries(DummyClient PRIVATE ServerEngine)

if(MSVC)
    target_compile_options(DummyClient PRIVATE
        $<$<CONFIG:Debug>:/Zi /Od /RTC1>
        $<$<CONFIG:Release>:/O2>
    )
else()
    target_compile_options(DummyClient PRIVATE
        $<$<CONFIG:Debug>:-g -O0>
        $<$<CONFIG:Release>:-O2 -DNDEBUG>
    )
endif()

if(WIN32)
    set(_BIN_PREFIX "${CMAKE_SOURCE_DIR}/bin/windows")
else()
    set(_BIN_PREFIX "${CMAKE_SOURCE_DIR}/bin/linux")
endif()

set_target_properties(DummyClient PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY_DEBUG   "${_BIN_PREFIX}/debug"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${_BIN_PREFIX}/release"
)
