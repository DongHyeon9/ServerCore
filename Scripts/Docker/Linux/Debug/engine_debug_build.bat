@echo off
setlocal
echo [BUILD] Linux ServerEngine Debug (Docker)
call "%~dp0..\..\build.bat" Linux Debug engine
if errorlevel 1 ( pause & exit /b 1 )
echo [SUCCESS] Linux ServerEngine Debug complete.
pause
endlocal
