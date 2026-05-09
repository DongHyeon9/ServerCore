@echo off
REM ============================================================
REM  ServerCore - Windows Docker Desktop setup launcher
REM
REM  This launcher is intentionally ASCII-only.
REM  All real logic lives in setup_docker_windows.ps1.
REM
REM  Why a PowerShell rewrite:
REM    cmd.exe has a long-standing parser bug with chcp 65001 +
REM    multibyte (Korean) text inside if/for blocks. That bug was
REM    causing flow control to misbehave (and elevation to spawn
REM    new windows in a loop).
REM ============================================================

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_docker_windows.ps1" %*
exit /b %ERRORLEVEL%
