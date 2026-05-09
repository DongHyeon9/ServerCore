@echo off
setlocal
echo [BUILD] Linux ServerEngine+Projects Debug (Docker)
call "%~dp0..\..\build.bat" Linux Debug engine_server
if errorlevel 1 ( pause & exit /b 1 )
echo [SUCCESS] Linux ServerEngine+Projects Debug complete.
pause
endlocal
