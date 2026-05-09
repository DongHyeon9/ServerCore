@echo off
setlocal
echo [BUILD] Windows ServerEngine+Projects Debug (Docker)
call "%~dp0..\..\build.bat" Windows Debug engine_server
if errorlevel 1 ( pause & exit /b 1 )
echo [SUCCESS] Windows ServerEngine+Projects Debug complete.
pause
endlocal
