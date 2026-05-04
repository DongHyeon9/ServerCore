@echo off
REM Windows common build environment setup
REM Call with: call "%~dp0_setup_windows.bat" || exit /b 1

REM Resolve project root: directory containing the Scripts\ folder
REM %~dp0 = Scripts\ directory (with trailing backslash)
REM %%~fI resolves ".." so ROOT is a clean absolute path
for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "TOOLS=%ROOT%\Scripts\Tools\Windows\bin"
set "SDK=%ROOT%\Scripts\Tools\Windows\sdk"

if not exist "%TOOLS%\cmake.exe" (
    echo [ERROR] cmake.exe not found in Scripts\Tools\Windows\bin\
    echo         This file should be pre-committed in the repository.
    echo         Try: git checkout -- Scripts/Tools/Windows/
    exit /b 1
)
if not exist "%TOOLS%\clang.exe" (
    echo [ERROR] clang.exe not found in Scripts\Tools\Windows\bin\
    echo         This file should be pre-committed in the repository.
    echo         Try: git checkout -- Scripts/Tools/Windows/
    exit /b 1
)

set "CMAKE=%TOOLS%\cmake.exe"
set "PATH=%TOOLS%;%PATH%"

REM ── SDK 헤더/라이브러리 경로 설정 ─────────────────────────────────────────
REM 우선순위 1: 리포지토리에 미리 커밋된 SDK (VS2022 불필요)
if exist "%SDK%\include\msvc" (
    echo [INFO] Using pre-committed SDK (VS2022 not required)
    set "INCLUDE=%SDK%\include\msvc;%SDK%\include\ucrt;%SDK%\include\shared;%SDK%\include\um"
    set "LIB=%SDK%\lib\ucrt\x64;%SDK%\lib\um\x64;%SDK%\lib\msvc\x64"
    goto :setup_done
)

REM 우선순위 2: 설치된 VS2022 (pre-committed SDK가 없을 경우 fallback)
echo [INFO] Pre-committed SDK not found. Looking for VS2022...
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
    echo [ERROR] Neither pre-committed SDK nor Visual Studio 2022 found.
    echo         The repository should include Scripts\Tools\Windows\sdk\
    echo         Try: git checkout -- Scripts/Tools/Windows/sdk/
    exit /b 1
)
call "%VS_BASE%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1

:setup_done
