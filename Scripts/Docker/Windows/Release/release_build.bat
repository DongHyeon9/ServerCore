@echo off
setlocal
echo [BUILD] Windows Full Release (Docker)
call "%~dp0..\..\build.bat" Windows Release all
if errorlevel 1 ( pause & exit /b 1 )
echo [SUCCESS] Windows Full Release complete.
pause
endlocal
