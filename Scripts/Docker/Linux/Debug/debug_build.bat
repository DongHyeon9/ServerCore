@echo off
setlocal
echo [BUILD] Linux Full Debug (Docker)
call "%~dp0..\..\build.bat" Linux Debug all
if errorlevel 1 ( pause & exit /b 1 )
echo [SUCCESS] Linux Full Debug complete.
pause
endlocal
