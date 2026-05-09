@echo off
setlocal
echo [BUILD] Windows ServerEngine Debug (Docker)
call "%~dp0..\..\build.bat" Windows Debug engine
if errorlevel 1 ( pause & exit /b 1 )
echo [SUCCESS] Windows ServerEngine Debug complete.
pause
endlocal
