@echo off
setlocal EnableDelayedExpansion
echo [CLEAN] Removing WSL build cache...

where wsl >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] WSL not found.
    pause & exit /b 1
)

wsl bash -c "rm -rf ~/build/ServerCore && echo '[CLEAN] Done: ~/build/ServerCore removed.'"
if %ERRORLEVEL% neq 0 ( echo [ERROR] Failed to clean WSL cache. & pause & exit /b 1 )

pause
endlocal