@echo off
setlocal EnableDelayedExpansion
echo [BUILD] Linux ServerEngine Debug via WSL2

where wsl >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] WSL not found.
    echo         Install WSL2: open PowerShell as admin and run: wsl --install
    pause & exit /b 1
)

for %%I in ("%~dp0..\..\..") do set "ROOT=%%~fI"
for /f "delims=" %%P in ('wsl wslpath -a "%ROOT%"') do set "WSL_ROOT=%%P"
if "%WSL_ROOT%"=="" (
    echo [ERROR] Failed to convert Windows path to WSL path.
    pause & exit /b 1
)

wsl bash -c "sed -i 's/\r$//' '%WSL_ROOT%/Scripts/Linux/_wsl_build.sh'"
wsl bash "%WSL_ROOT%/Scripts/Linux/_wsl_build.sh" Debug "%WSL_ROOT%" ServerEngine
if %ERRORLEVEL% neq 0 ( echo [ERROR] Linux ServerEngine Debug build failed. & pause & exit /b %ERRORLEVEL% )

echo [SUCCESS] Linux ServerEngine Debug binaries: build\linux\Debug\
pause
endlocal