@echo off
setlocal
echo [BUILD] Linux ThirdParty Debug (Docker)
call "%~dp0..\..\build.bat" Linux Debug thirdparty
if errorlevel 1 ( pause & exit /b 1 )
echo [SUCCESS] Linux ThirdParty Debug complete.
pause
endlocal
