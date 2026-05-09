@echo off
setlocal
echo [BUILD] Linux ThirdParty Release (Docker)
call "%~dp0..\..\build.bat" Linux Release thirdparty
if errorlevel 1 ( pause & exit /b 1 )
echo [SUCCESS] Linux ThirdParty Release complete.
pause
endlocal
