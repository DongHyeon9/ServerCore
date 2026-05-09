@echo off
setlocal
echo [BUILD] Windows Full Debug (Docker)
call "%~dp0..\..\build.bat" Windows Debug all
if errorlevel 1 ( pause & exit /b 1 )
echo [SUCCESS] Windows Full Debug complete.
pause
endlocal
