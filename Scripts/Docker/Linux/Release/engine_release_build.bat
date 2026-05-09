@echo off
setlocal
echo [BUILD] Linux ServerEngine Release (Docker)
call "%~dp0..\..\build.bat" Linux Release engine
if errorlevel 1 ( pause & exit /b 1 )
echo [SUCCESS] Linux ServerEngine Release complete.
pause
endlocal
