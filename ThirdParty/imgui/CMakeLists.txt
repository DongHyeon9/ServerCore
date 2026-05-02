project(ImGui)

find_package(OpenGL REQUIRED)

add_library(ImGui STATIC
    imgui.cpp
    imgui_draw.cpp
    imgui_tables.cpp
    imgui_widgets.cpp
    imgui_demo.cpp
    backends/imgui_impl_glfw.cpp
    backends/imgui_impl_opengl3.cpp
)

target_include_directories(ImGui PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/backends
)

# glfw 타겟은 루트 CMakeLists.txt에서 ThirdParty/glfw로 이미 추가됨
target_link_libraries(ImGui PUBLIC
    glfw
    OpenGL::GL
)

target_compile_features(ImGui PUBLIC cxx_std_17)
