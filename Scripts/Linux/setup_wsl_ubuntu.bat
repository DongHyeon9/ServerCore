@echo off
setlocal EnableDelayedExpansion
echo [SETUP] WSL Ubuntu Build Environment
echo.

REM Check WSL is available
where wsl >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] WSL is not available on this system.
    echo         Open PowerShell as Administrator and run: wsl --install
    echo         Restart Windows, then run this script again.
    pause & exit /b 1
)

REM Check if Ubuntu is already installed and ready
wsl -d Ubuntu --exec echo ok >nul 2>&1
if %ERRORLEVEL% equ 0 goto :install_packages

REM Ubuntu not ready -- install it
echo [SETUP] Ubuntu not found in WSL. Installing...
echo         An internet connection is required.
echo.
wsl --install -d Ubuntu
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Ubuntu installation failed.
    echo         Try running this script as Administrator.
    pause & exit /b 1
)

REM Re-check after install
wsl -d Ubuntu --exec echo ok >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo.
    echo [INFO] Ubuntu is installed but needs initial setup.
    echo        1. Run:  wsl -d Ubuntu
    echo        2. Set a username and password when prompted.
    echo        3. Close the Ubuntu window, then run this script again.
    pause & exit /b 0
)

REM Install build tools
:install_packages
echo [SETUP] Installing build tools in Ubuntu...
echo         cmake  clang  lld  rsync
echo.
wsl -d Ubuntu -u root bash -c "apt-get update -y && apt-get install -y cmake clang lld rsync libx11-dev libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev libxext-dev libgl-dev"
if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] Package installation failed.
    echo         Check your internet connection and try again.
    pause & exit /b 1
)

echo.
echo [SUCCESS] WSL Ubuntu is ready for Linux builds.
echo.
echo           Next step:  Scripts\Linux\Debug\wsl_debug_build.bat
pause
endlocal