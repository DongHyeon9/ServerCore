@echo off
setlocal
echo [BUILD] Linux ServerEngine+Projects Release (Docker)
call "%~dp0..\..\build.bat" Linux Release engine_server
if errorlevel 1 ( pause & exit /b 1 )
echo [SUCCESS] Linux ServerEngine+Projects Release complete.
pause
endlocal
