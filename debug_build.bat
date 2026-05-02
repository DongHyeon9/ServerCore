@echo off
setlocal EnableDelayedExpansion

echo [BUILD] Windows Debug

set "VS=C:\Program Files\Microsoft Visual Studio\2022\Community"
set "CMAKE=%VS%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
set "PATH=%VS%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;%VS%\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\bin;%PATH%"

if not exist "%CMAKE%" (
    echo [ERROR] Visual Studio 2022 cmake not found.
    pause & exit /b 1
)

call "%VS%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1

"%CMAKE%" -B "build\windows\Debug" -S . ^
    -G "Ninja" ^
    -DCMAKE_BUILD_TYPE=Debug

if %ERRORLEVEL% neq 0 (
    echo [ERROR] CMake configuration failed.
    pause & exit /b %ERRORLEVEL%
)

"%CMAKE%" --build "build\windows\Debug"

if %ERRORLEVEL% neq 0 (
    echo [ERROR] Build failed.
    pause & exit /b %ERRORLEVEL%
)

echo [SUCCESS] Windows Debug build completed. Output: bin\*\debug\
pause
endlocal
