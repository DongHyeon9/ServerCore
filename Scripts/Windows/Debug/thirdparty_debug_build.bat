@echo off
setlocal EnableDelayedExpansion
echo [BUILD] Windows Clang - ThirdParty Debug

call "%~dp0..\..\_setup_windows.bat"
if %ERRORLEVEL% neq 0 ( pause & exit /b 1 )

for %%I in ("%~dp0..\..\..") do set "ROOT=%%~fI"
set "BD=%ROOT%\build\windows-clang\Debug"

if not exist "%BD%\CMakeCache.txt" (
    "%CMAKE%" -B "%BD%" -S "%ROOT%" ^
        -G "Ninja" ^
        -DCMAKE_BUILD_TYPE=Debug ^
        -DCMAKE_TOOLCHAIN_FILE="%ROOT%\Scripts\Tools\Compiler\windows-clang-toolchain.cmake"
    if %ERRORLEVEL% neq 0 ( echo [ERROR] CMake configure failed. & pause & exit /b %ERRORLEVEL% )
)

"%CMAKE%" --build "%BD%" --parallel --target libprotobuf glfw ImGui
if %ERRORLEVEL% neq 0 ( echo [ERROR] Build failed. & pause & exit /b %ERRORLEVEL% )

echo [SUCCESS] ThirdParty Debug complete.
pause
endlocal