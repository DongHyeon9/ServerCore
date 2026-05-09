@echo off
setlocal
echo [BUILD] Windows ServerEngine Release (Docker)
call "%~dp0..\..\build.bat" Windows Release engine
if errorlevel 1 ( pause & exit /b 1 )
echo [SUCCESS] Windows ServerEngine Release complete.
pause
endlocal
