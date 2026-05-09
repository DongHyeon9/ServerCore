@echo off
setlocal
echo [BUILD] Windows ServerEngine+Projects Release (Docker)
call "%~dp0..\..\build.bat" Windows Release engine_server
if errorlevel 1 ( pause & exit /b 1 )
echo [SUCCESS] Windows ServerEngine+Projects Release complete.
pause
endlocal
