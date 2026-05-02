cmake_minimum_required(VERSION 3.20)
project(ServerCore)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug)
endif()

add_subdirectory(ServerEngine)
add_subdirectory(TestServer)
add_subdirectory(DummyClient)
