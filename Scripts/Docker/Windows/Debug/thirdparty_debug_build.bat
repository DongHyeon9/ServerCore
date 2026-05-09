@echo off
setlocal
echo [BUILD] Windows ThirdParty Debug (Docker)
call "%~dp0..\..\build.bat" Windows Debug thirdparty
if errorlevel 1 ( pause & exit /b 1 )
echo [SUCCESS] Windows ThirdParty Debug complete.
pause
endlocal
