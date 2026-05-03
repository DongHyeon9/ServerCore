@echo off
setlocal EnableDelayedExpansion
echo [SETUP] Copying Windows build tools from VS2022 to Scripts\Tools\Windows\
echo         Run this once per machine before building.
echo.

for %%I in ("%~dp0..") do set "ROOT=%%~fI"

REM Find VS2022 (Community -> Professional -> Enterprise -> BuildTools)
set "VS_BASE="
for %%E in (Community Professional Enterprise) do (
    if not defined VS_BASE (
        if exist "C:\Program Files\Microsoft Visual Studio\2022\%%E\VC\Auxiliary\Build\vcvars64.bat" (
            set "VS_BASE=C:\Program Files\Microsoft Visual Studio\2022\%%E"
        )
    )
)
if not defined VS_BASE (
    if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" (
        set "VS_BASE=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
    )
)
if not defined VS_BASE (
    echo [ERROR] Visual Studio 2022 or Build Tools not found.
    echo         Install from https://visualstudio.microsoft.com/downloads/
    echo         Select the "Desktop development with C++" workload.
    pause ^& exit /b 1
)
echo [INFO] VS2022: %VS_BASE%

set "SRC_CMAKE_DIR=%VS_BASE%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake"
set "SRC_NINJA=%VS_BASE%\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja"
set "SRC_LLVM=%VS_BASE%\VC\Tools\Llvm\x64\bin"

if not exist "%SRC_CMAKE_DIR%\bin\cmake.exe" ( echo [ERROR] cmake.exe not found: %SRC_CMAKE_DIR%\bin ^& pause ^& exit /b 1 )
if not exist "%SRC_NINJA%\ninja.exe"          ( echo [ERROR] ninja.exe not found: %SRC_NINJA%       ^& pause ^& exit /b 1 )
if not exist "%SRC_LLVM%\clang.exe"           ( echo [ERROR] clang.exe not found: %SRC_LLVM%        ^& pause ^& exit /b 1 )

set "DEST_BIN=%ROOT%\Scripts\Tools\Windows\bin"
mkdir "%DEST_BIN%" 2>nul

echo [COPY] ninja.exe
copy /Y "%SRC_NINJA%\ninja.exe" "%DEST_BIN%\" >nul

echo [COPY] cmake.exe  cmcldeps.exe
copy /Y "%SRC_CMAKE_DIR%\bin\cmake.exe"    "%DEST_BIN%\" >nul
copy /Y "%SRC_CMAKE_DIR%\bin\cmcldeps.exe" "%DEST_BIN%\" >nul

echo [COPY] cmake share (modules)
xcopy /E /Y /I /Q "%SRC_CMAKE_DIR%\share" "%ROOT%\Scripts\Tools\Windows\share\" >nul

echo [COPY] clang.exe  clang++.exe  lld-link.exe  llvm-ar.exe  llvm-ranlib.exe
for %%F in (clang.exe clang++.exe lld-link.exe llvm-ar.exe llvm-ranlib.exe) do (
    copy /Y "%SRC_LLVM%\%%F" "%DEST_BIN%\" >nul
    if !ERRORLEVEL! neq 0 ( echo [ERROR] Failed to copy %%F ^& pause ^& exit /b 1 )
)

REM clang built-in headers (xmmintrin.h etc.) -- located at ../lib/clang/N/ relative to clang.exe
echo [COPY] clang intrinsic headers (lib\clang)
for /f "delims=" %%D in ('dir /b "%VS_BASE%\VC\Tools\Llvm\x64\lib\clang"') do set "CLANG_VER=%%D"
xcopy /E /Y /I /Q "%VS_BASE%\VC\Tools\Llvm\x64\lib\clang\%CLANG_VER%" "%ROOT%\Scripts\Tools\Windows\lib\clang\%CLANG_VER%\" >nul

echo.
echo [SUCCESS] Tools copied to: %ROOT%\Scripts\Tools\Windows\
echo           You can now run Scripts\Debug\debug_build.bat or
echo                         Scripts\Release\release_build.bat
pause
endlocal
