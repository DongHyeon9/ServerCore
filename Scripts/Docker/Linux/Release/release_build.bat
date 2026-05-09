@echo off
setlocal
echo [BUILD] Linux Full Release (Docker)
call "%~dp0..\..\build.bat" Linux Release all
if errorlevel 1 ( pause & exit /b 1 )
echo [SUCCESS] Linux Full Release complete.
pause
endlocal
