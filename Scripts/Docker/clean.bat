@echo off
REM Docker 빌드 캐시 볼륨 삭제 (다음 빌드 시 자동 재생성)
setlocal
set "VOLUME=servercore-build-cache"

docker volume inspect "%VOLUME%" >nul 2>&1
if errorlevel 1 (
    echo [INFO] Cache volume '%VOLUME%' does not exist. Nothing to clean.
    exit /b 0
)

echo [CLEAN] Removing volume %VOLUME% ...
docker volume rm "%VOLUME%"
if errorlevel 1 (
    echo [ERROR] Failed to remove volume. Make sure no containers are using it.
    exit /b 1
)
echo [DONE] Cache cleared.
endlocal
