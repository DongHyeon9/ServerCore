project(ServerEngine)

file(GLOB_RECURSE SOURCES "src/*.cpp")

add_library(ServerEngine STATIC ${SOURCES} "include/ServerDialog.h"  "include/Core/Struct.h" "include/Core/Header.h" "include/Core/Type.h" "include/ServerDlgUtil.h" "src/ServerDlgUtil.cpp" "include/ServerDialogPreset.h" "src/ServerDialogPreset.cpp" "include/Core/Util.h" "src/Util.cpp" "include/Core/Preprocess.h")

target_include_directories(ServerEngine PUBLIC include)

target_link_libraries(ServerEngine PUBLIC
    BoostAsio
    protobuf::libprotobuf
    ImGui
)
if(WIN32)
    # Boost.Asio가 사용하는 WinSock2 라이브러리
    target_link_libraries(ServerEngine PUBLIC ws2_32 mswsock)
endif()

if(MSVC)
    target_compile_options(ServerEngine PRIVATE
        $<$<CONFIG:Debug>:/Zi /Od /RTC1>
        $<$<CONFIG:Release>:/O2>
    )
else()
    target_compile_options(ServerEngine PRIVATE
        $<$<CONFIG:Debug>:-g -O0>
        $<$<CONFIG:Release>:-O2 -DNDEBUG>
    )
endif()

if(WIN32)
    set(_BIN_PREFIX "${CMAKE_SOURCE_DIR}/bin/windows")
else()
    set(_BIN_PREFIX "${CMAKE_SOURCE_DIR}/bin/linux")
endif()

set_target_properties(ServerEngine PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY_DEBUG   "${_BIN_PREFIX}/debug"
    ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${_BIN_PREFIX}/release"
    LIBRARY_OUTPUT_DIRECTORY_DEBUG   "${_BIN_PREFIX}/debug"
    LIBRARY_OUTPUT_DIRECTORY_RELEASE "${_BIN_PREFIX}/release"
)
