@echo off
setlocal
echo [BUILD] Windows Server Projects Release (Docker)
call "%~dp0..\..\build.bat" Windows Release server
if errorlevel 1 ( pause & exit /b 1 )
echo [SUCCESS] Windows Server Projects Release complete.
pause
endlocal
