@echo off
setlocal
echo [BUILD] Windows ThirdParty Release (Docker)
call "%~dp0..\..\build.bat" Windows Release thirdparty
if errorlevel 1 ( pause & exit /b 1 )
echo [SUCCESS] Windows ThirdParty Release complete.
pause
endlocal
