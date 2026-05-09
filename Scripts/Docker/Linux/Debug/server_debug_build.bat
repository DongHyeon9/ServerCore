@echo off
setlocal
echo [BUILD] Linux Server Projects Debug (Docker)
call "%~dp0..\..\build.bat" Linux Debug server
if errorlevel 1 ( pause & exit /b 1 )
echo [SUCCESS] Linux Server Projects Debug complete.
pause
endlocal
