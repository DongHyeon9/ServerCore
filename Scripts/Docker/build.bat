@echo off
REM Docker 빌드 디스패처 (Windows 호스트)
REM 사용법: build.bat <Linux^|Windows> <Debug^|Release> [target_group]
REM   target_group: all (기본) | thirdparty | engine | server | engine_server
setlocal EnableDelayedExpansion

set "TARGET_OS=%~1"
set "MODE=%~2"
set "TARGET_GROUP=%~3"
if "%TARGET_OS%"=="" set "TARGET_OS=Linux"
if "%MODE%"=="" set "MODE=Debug"
if "%TARGET_GROUP%"=="" set "TARGET_GROUP=all"

REM 인자 정규화 (entrypoint.sh는 소문자 OS 기대)
if /I "%TARGET_OS%"=="Linux" (
    set "TARGET_OS_LOWER=linux"
) else if /I "%TARGET_OS%"=="Windows" (
    set "TARGET_OS_LOWER=windows"
) else (
    echo [ERROR] TARGET_OS must be 'Linux' or 'Windows' ^(got: %TARGET_OS%^)
    exit /b 2
)
if /I not "%MODE%"=="Debug" if /I not "%MODE%"=="Release" (
    echo [ERROR] MODE must be 'Debug' or 'Release' ^(got: %MODE%^)
    exit /b 2
)

REM Docker 설치 확인
where docker >nul 2>&1
if errorlevel 1 (
    echo [ERROR] docker not found. Install Docker Desktop: https://www.docker.com/products/docker-desktop
    exit /b 1
)

REM 리포 루트 (Scripts\Docker\ 의 두 단계 위)
for %%I in ("%~dp0..\..") do set "ROOT=%%~fI"

set "IMAGE=servercore-builder:latest"
set "VOLUME=servercore-build-cache"

REM 이미지 부재 시 빌드
docker image inspect "%IMAGE%" >nul 2>&1
if errorlevel 1 (
    echo [BUILD] Building image %IMAGE% ^(first run, ~3-5 min^) ...
    docker build -t "%IMAGE%" "%ROOT%"
    if errorlevel 1 (
        echo [ERROR] docker build failed.
        exit /b 1
    )
)

REM 캐시 볼륨 보장
docker volume inspect "%VOLUME%" >nul 2>&1
if errorlevel 1 (
    docker volume create "%VOLUME%" >nul
)

echo [RUN] %TARGET_OS_LOWER% %MODE% %TARGET_GROUP%
docker run --rm ^
    -v "%ROOT%:/work" ^
    -v "%VOLUME%:/build_src" ^
    "%IMAGE%" "%TARGET_OS_LOWER%" "%MODE%" "%TARGET_GROUP%"
if errorlevel 1 (
    echo [ERROR] Build failed.
    exit /b 1
)

echo [DONE] Output: bin\%TARGET_OS_LOWER%\
endlocal
