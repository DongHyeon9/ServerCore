@echo off
setlocal
echo [BUILD] Linux Server Projects Release (Docker)
call "%~dp0..\..\build.bat" Linux Release server
if errorlevel 1 ( pause & exit /b 1 )
echo [SUCCESS] Linux Server Projects Release complete.
pause
endlocal
