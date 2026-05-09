@echo off
setlocal
echo [BUILD] Windows Server Projects Debug (Docker)
call "%~dp0..\..\build.bat" Windows Debug server
if errorlevel 1 ( pause & exit /b 1 )
echo [SUCCESS] Windows Server Projects Debug complete.
pause
endlocal
