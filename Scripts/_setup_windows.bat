@echo off
REM Windows common build environment setup
REM Call with: call "%~dp0_setup_windows.bat" || exit /b 1

REM Resolve project root: directory containing the Scripts\ folder
REM %~dp0 = Scripts\ directory (with trailing backslash)
REM %%~fI resolves ".." so ROOT is a clean absolute path
for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "TOOLS=%ROOT%\Scripts\Tools\Windows\bin"

if not exist "%TOOLS%\cmake.exe" (
    echo [ERROR] Build tools not found.
    echo         Run Scripts\setup_tools_windows.bat first.
    exit /b 1
)
if not exist "%TOOLS%\clang.exe" (
    echo [ERROR] clang.exe not found.
    echo         Run Scripts\setup_tools_windows.bat first.
    exit /b 1
)

set "CMAKE=%TOOLS%\cmake.exe"
set "PATH=%TOOLS%;%PATH%"

REM Find VS2022 -- only needed for vcvars64.bat (Windows SDK headers/libs)
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
    echo         Required for Windows SDK headers and libraries.
    echo         https://visualstudio.microsoft.com/downloads/
    exit /b 1
)

REM Initialize Windows SDK environment for clang
call "%VS_BASE%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
