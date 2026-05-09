# ServerCore Docker 빌드 환경 이관 계획서

작성일: 2026-05-05
대상 프로젝트: `C:\Users\user\Desktop\linux_shared_folder\ServerCore`

---

## 1. 목표

> **"Docker만 설치된 빈 PC"에서 `git clone` 후 단일 명령으로 Linux/Windows 빌드 산출물을 모두 얻는 것**

- WSL, Ubuntu, clang, cmake, lld, rsync, X11 dev 패키지, VS2022 등을 **사용자 PC에 설치하지 않음**
- 빌드에 필요한 모든 도구·라이브러리·헤더를 **Docker 이미지 안에 고정** (Windows SDK는 리포에 pre-committed)
- 빌드 출력은 호스트 PC에 그대로 남음
  - Linux: `bin/linux/debug/`, `bin/linux/release/`
  - Windows: `bin/windows/debug/`, `bin/windows/release/` (Windows 호스트에서 더블클릭 실행/디버거 attach 가능)
- **기존 빌드 시스템(WSL .bat, 네이티브 Windows .bat)은 전부 제거**. Docker가 유일한 빌드 진입점이 된다 — 9장 삭제 리스트 참조

---

## 2. 현재 빌드 의존성 분석 (Docker 이미지에 옮겨야 할 항목 도출용)

### 2.1 Linux 빌드 의존성 (WSL 시스템 → Docker 이미지로 옮김)

기존 `Scripts/Linux/setup_wsl_ubuntu.bat` 및 `_wsl_build.sh`에서 발췌:

| 카테고리 | 패키지 / 도구 | 사용 위치 |
|---------|---------------|----------|
| 빌드 시스템 | `cmake` (≥ 3.20) | 모든 CMakeLists.txt |
| 컴파일러 | `clang`, `clang++` | `linux-clang-toolchain.cmake` |
| 링커 | `lld` (`ld.lld`, `lld-link`) | `linux-clang-toolchain.cmake`, Windows 크로스컴파일 |
| 아카이버 | `llvm-ar`, `llvm-ranlib` | 양 toolchain |
| 동기화 | `rsync` | bind mount 우회 (선택) |
| GLFW(X11) | `libx11-dev`, `libxrandr-dev`, `libxinerama-dev`, `libxcursor-dev`, `libxi-dev`, `libxext-dev`, `libgl-dev` | `ThirdParty/glfw` (Linux X11 백엔드) |
| 셸 | `bash`, `coreutils`, `sed`, `tr`, `nproc` | `entrypoint.sh` |

### 2.2 Windows 빌드 의존성 (네이티브 → Docker 안 클로스컴파일로 옮김)

기존 `Scripts/_setup_windows.bat` 및 `windows-clang-toolchain.cmake`에서 발췌:

| 카테고리 | 자산 | 위치 | Docker 이관 후 |
|---------|------|------|---------------|
| 컴파일러 | `clang`/`clang++` (MSVC ABI 지원) | (구) `Scripts/Tools/Windows/bin/clang.exe` | 컨테이너 내장 Linux clang으로 교체 (`/usr/bin/clang`) |
| 링커 | `lld-link` (PE 모드) | (구) `Scripts/Tools/Windows/bin/lld-link.exe` | 컨테이너 내장 `lld-link` (Ubuntu `lld` 패키지 제공) |
| 아카이버 | `llvm-ar`, `llvm-ranlib` | (구) `Scripts/Tools/Windows/bin/` | 컨테이너 내장 `llvm-ar`/`llvm-ranlib` |
| Windows SDK | UCRT, UM, MSVC, Shared 헤더/라이브러리 | `Scripts/Tools/Windows/sdk/` (pre-committed, **유지**) | 마운트된 `/work` 통해 그대로 사용 |
| 타겟 트리플 | `x86_64-pc-windows-msvc` | `windows-clang-toolchain.cmake` | 동일 |
| MS 호환 버전 | `-fms-compatibility-version=19.44` | 동상 | 동일 |
| `cmake.exe`, `ninja.exe` | Windows 네이티브 빌드 | (구) `Scripts/Tools/Windows/bin/` | **불필요** — 컨테이너 안 cmake가 Ninja generator로 PE 산출 |

> **핵심 통찰**: Linux의 `clang`은 `-target x86_64-pc-windows-msvc` + `lld-link` + `-imsvc`(시스템 헤더로 SDK 헤더 추가) + `/LIBPATH:`(SDK 라이브러리) 조합으로 Windows PE/COFF 바이너리를 **그대로 만들어낸다**. 별도 mingw, wine, Windows 컨테이너 모두 불필요.

### 2.3 빌드 산출물 흐름 (이관 후)

```
호스트 ServerCore/  ──(bind mount, ro)──►  /work
                                              │
                                              ▼
                                  /build_src (named volume, rsync target)
                                              │
                              ┌───────────────┼───────────────┐
                              ▼                               ▼
                /build_src/linux/<mode>/             /build_src/windows/<mode>/
                              │                               │
                              ▼ (cp)                          ▼ (cp)
              호스트 ServerCore/bin/linux/<mode>/   호스트 ServerCore/bin/windows/<mode>/
```

### 2.4 코드/CMake 측 함정 (Dockerfile/entrypoint에서 처리)

- `glfw` CMakeLists가 `CMake/`(대문자) 디렉터리를 참조하지만 실제는 `cmake/`(소문자) → entrypoint에서 `ln -s cmake CMake` 처리
- `*.sh` CRLF 문제 → `.gitattributes`로 LF 강제 + entrypoint 안에서 `dos2unix` 안전망
- CMake `RUNTIME_OUTPUT_DIRECTORY`가 `CMAKE_SOURCE_DIR` 기준 → 컨테이너 안 빌드 결과를 호스트 `bin/...`으로 명시적 복사
- `windows-clang-toolchain.cmake`의 `_LLVM_HINTS` 첫 번째 항목(`Scripts/Tools/Windows/bin`)이 **삭제됨** → 컨테이너에서 환경변수 `LLVM_PATH=/usr` 또는 별도 wrapper toolchain 사용 (3.4 참조)

---

## 3. Docker 이미지 명세

### 3.1 베이스 이미지 — `ubuntu:24.04`

- 기존 `setup_wsl_ubuntu.bat`이 Ubuntu 기준으로 검증됨 → 패키지명·동작 호환성 보장
- LTS, glibc 2.39, clang 18 → `x86_64-pc-windows-msvc` 타겟 안정 지원
- `lld-link` 심볼릭 링크가 `lld` 패키지에 포함

### 3.2 시스템 패키지 (apt-get)

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake clang lld llvm \
    rsync git ninja-build pkg-config ca-certificates dos2unix \
    libx11-dev libxrandr-dev libxinerama-dev libxcursor-dev \
    libxi-dev libxext-dev libgl-dev \
 && rm -rf /var/lib/apt/lists/*
```

| 패키지 | 용도 |
|--------|------|
| `cmake` | 빌드 구성 (Ubuntu 24.04 기본 ≥ 3.28) |
| `clang` | C/C++ 컴파일러 (Linux 네이티브 + Windows 크로스컴파일 양쪽) |
| `lld` | `ld.lld`(Linux) + `lld-link`(Windows PE) 모두 포함 |
| `llvm` | `llvm-ar`, `llvm-ranlib`, `llvm-rc`(Windows 리소스) |
| `rsync` | 호스트→컨테이너 소스 동기화 |
| `git` | 서브모듈/CI 활용 가능성 |
| `ninja-build` | Windows 빌드는 Ninja generator 사용 (기존 동작과 동일) |
| `pkg-config` | GLFW의 X11 detect |
| `ca-certificates` | apt/HTTPS |
| `libx*-dev`, `libgl-dev` | GLFW X11 백엔드 (Linux 빌드 전용) |
| `dos2unix` | CRLF 안전망 |

> **Windows 크로스컴파일에 별도 패키지 추가 없음** — 위의 `clang`/`lld`/`llvm`이 모두 PE 타겟을 지원.

### 3.3 환경 / 사용자

| 항목 | 값 |
|------|-----|
| `WORKDIR` | `/work` (호스트 소스 마운트 지점) |
| 빌드 작업 디렉터리 | `/build_src` (named volume `servercore-build-cache`) |
| 사용자 | `builder` (UID/GID는 `--user $(id -u):$(id -g)` 매핑) |
| `LANG` | `C.UTF-8` |
| `LLVM_PATH` | `/usr` (Windows toolchain의 `_LLVM_HINTS`가 시스템 clang을 찾도록) |

### 3.4 Windows toolchain wrapper (신규 파일)

**`Scripts/Tools/Compiler/windows-clang-toolchain-docker.cmake`**

기존 `windows-clang-toolchain.cmake`은 `Scripts/Tools/Windows/bin`(이제 삭제됨)을 첫 번째 hint로 가지므로, 컨테이너 안에서는 시스템 clang을 강제하는 wrapper를 사용:

```cmake
# Docker 컨테이너 전용: 시스템 clang을 강제하고 SDK 처리는 원본 toolchain에 위임
set(CMAKE_C_COMPILER   /usr/bin/clang)
set(CMAKE_CXX_COMPILER /usr/bin/clang++)
set(CMAKE_AR           /usr/bin/llvm-ar)
set(CMAKE_RANLIB       /usr/bin/llvm-ranlib)
set(CMAKE_LINKER       /usr/bin/lld-link)

# 원본 toolchain의 SDK 처리(-imsvc, /LIBPATH, MSVC compat) 재사용
include(${CMAKE_CURRENT_LIST_DIR}/windows-clang-toolchain.cmake)
```

원본 `windows-clang-toolchain.cmake`은 그대로 유지하되, Windows 호스트 hint(`Scripts/Tools/Windows/bin`)는 제거 — 그 디렉터리가 더 이상 존재하지 않음. (또는 `if(EXISTS ...)` 가드만 추가하고 hint 자체는 남겨도 무방)

### 3.5 컨테이너 진입점 — `Scripts/Docker/entrypoint.sh`

호출 형식: `entrypoint.sh <TARGET_OS> <MODE> [TARGETS...]`
- `TARGET_OS`: `linux` | `windows`
- `MODE`: `Debug` | `Release`
- `TARGETS`: `all`(기본) | `ThirdParty` | `Engine` | `Server` | `EngineServer`

수행 순서:
1. CRLF 정리 (`dos2unix Scripts/Docker/*.sh ThirdParty/glfw/CMake* 2>/dev/null || true`)
2. `glfw/CMake` ↔ `glfw/cmake` 케이스 심볼릭 링크 보정
3. `/work` → `/build_src` rsync (Windows 호스트의 9P/SMB I/O 우회)
4. CMake configure:
   - Linux: `-DCMAKE_TOOLCHAIN_FILE=/build_src/Scripts/Tools/Compiler/linux-clang-toolchain.cmake`
   - Windows: `-DCMAKE_TOOLCHAIN_FILE=/build_src/Scripts/Tools/Compiler/windows-clang-toolchain-docker.cmake -GNinja`
5. `cmake --build /build_src/<os>/<mode> -j$(nproc) --target <target>`
6. 산출물 복사:
   - Linux: `/build_src/<os>/<mode>/bin/linux/<mode>/*` → `/work/bin/linux/<mode>/`
   - Windows: `/build_src/<os>/<mode>/bin/windows/<mode>/*.{exe,dll,lib,pdb}` → `/work/bin/windows/<mode>/`

### 3.6 호스트 디스패처

- **`Scripts/Docker/build.bat`** (Windows 호스트) — `<TARGET_OS> <MODE> [target]` 인자 받아 `docker run` 호출
- **`Scripts/Docker/build.sh`** (Linux/macOS 호스트) — 동일 기능

각 디스패처는:
1. 이미지 부재 시 `docker build -t servercore-builder:latest .`
2. `docker volume create servercore-build-cache` (없으면)
3. `docker run --rm -v <repo>:/work -v servercore-build-cache:/build_src --user <uid>:<gid> servercore-builder:latest <args>`
4. exit code 전파

### 3.7 .dockerignore

| 패턴 | 이유 |
|------|------|
| `.git/` | 빌드 무관 |
| `bin/`, `build/`, `out/` | 호스트 빌드 결과 |
| `.vs/`, `.svn/`, `.claude/` | IDE/자동화 메타 |
| `ClaudeMD/` | 문서 |
| `Scripts/Tools/Windows/sdk/` | **이미지 컨텍스트에 포함시키지 않음** — 마운트로 접근 (이미지 빌드 시 컨텍스트 절약) |

> 기존 계획과 달리 `Scripts/Tools/Windows/bin/`/`share/`/`lib/`은 **삭제되어 더 이상 존재하지 않음**.

---

## 4. 빌드 매트릭스 (5 타겟 × 2 OS × 2 모드 = 20개 진입 스크립트)

### 4.1 매트릭스

| 타겟 | CMake target | Linux Debug | Linux Release | Windows Debug | Windows Release |
|------|-------------|-------------|---------------|---------------|-----------------|
| 풀빌드 | (전체) | `Scripts/Docker/Linux/Debug/debug_build.bat` | `Scripts/Docker/Linux/Release/release_build.bat` | `Scripts/Docker/Windows/Debug/debug_build.bat` | `Scripts/Docker/Windows/Release/release_build.bat` |
| ThirdParty | `ThirdParty` | `..../thirdparty_debug_build.bat` | `..../thirdparty_release_build.bat` | `..../thirdparty_debug_build.bat` | `..../thirdparty_release_build.bat` |
| Engine | `Engine` | `..../engine_debug_build.bat` | `..../engine_release_build.bat` | `..../engine_debug_build.bat` | `..../engine_release_build.bat` |
| Server | `Server` (또는 `TestServer`) | `..../server_debug_build.bat` | `..../server_release_build.bat` | `..../server_debug_build.bat` | `..../server_release_build.bat` |
| Engine+Server | `Engine;Server` (다중 target) | `..../engine_server_debug_build.bat` | `..../engine_server_release_build.bat` | `..../engine_server_debug_build.bat` | `..../engine_server_release_build.bat` |

각 .bat 한 줄 예시:
```bat
@echo off
call "%~dp0..\..\build.bat" Linux Debug Server
```

### 4.2 디렉터리 구조 (신규)

```
Scripts/Docker/
├── build.bat                       # 호스트 디스패처 (Windows)
├── build.sh                        # 호스트 디스패처 (Linux/macOS)
├── clean.bat                       # 캐시 볼륨 정리 (Windows)
├── clean.sh                        # 캐시 볼륨 정리 (Linux/macOS)
├── entrypoint.sh                   # 컨테이너 안 빌드 로직
├── Linux/
│   ├── Debug/
│   │   ├── debug_build.bat                  # 풀빌드
│   │   ├── thirdparty_debug_build.bat
│   │   ├── engine_debug_build.bat
│   │   ├── server_debug_build.bat
│   │   └── engine_server_debug_build.bat
│   └── Release/
│       ├── release_build.bat
│       ├── thirdparty_release_build.bat
│       ├── engine_release_build.bat
│       ├── server_release_build.bat
│       └── engine_server_release_build.bat
└── Windows/
    ├── Debug/  (위와 동일한 5종)
    └── Release/  (위와 동일한 5종)
```

> 기존 `Scripts/Linux/Debug/wsl_*_build.bat` (10종), `Scripts/Windows/Debug/*_build.bat` (10종)와 **1:1 미러** — 사용자 학습 곡선 0.

### 4.3 신규 / 변경 파일 요약

| 파일 | 역할 |
|------|------|
| `Dockerfile` (저장소 루트) | 베이스 이미지 + apt 패키지 + 사용자 + ENTRYPOINT |
| `.dockerignore` (저장소 루트) | 컨텍스트 슬림화 |
| `Scripts/Docker/entrypoint.sh` | 컨테이너 안 빌드 로직 (linux/windows 분기) |
| `Scripts/Docker/build.bat` / `build.sh` | 호스트 디스패처 |
| `Scripts/Docker/clean.bat` / `clean.sh` | 캐시 볼륨 정리 |
| `Scripts/Docker/{Linux,Windows}/{Debug,Release}/*_build.bat` | 20개 진입 스크립트 |
| `Scripts/Tools/Compiler/windows-clang-toolchain-docker.cmake` | 컨테이너용 Windows toolchain wrapper |
| `Scripts/Tools/Compiler/windows-clang-toolchain.cmake` | (수정) `_LLVM_HINTS`에서 삭제된 hint 제거 또는 `if(EXISTS)` 가드 |
| `.gitattributes` | `Scripts/Docker/*.sh text eol=lf` 추가 |
| `README.md` | "Docker로 빌드하기" 섹션 (유일한 빌드 경로) |

---

## 5. 사용자 시나리오

### 5.1 신규 PC에서 처음 빌드 (Linux + Windows 모두)

```
1. Docker Desktop 설치 (Windows/Mac) 또는 docker engine 설치 (Linux)
2. git clone <repo>
3. Scripts\Docker\Linux\Debug\debug_build.bat        → bin/linux/debug/*
4. Scripts\Docker\Windows\Debug\debug_build.bat      → bin/windows/debug/*.exe
```

내부 동작:
- 첫 실행: `docker build` ~3–5분 (apt 패키지)
- 이후: 이미지 캐시 → 즉시 컨테이너 실행 → cmake configure + 컴파일
- Windows .exe는 호스트가 Windows일 경우 그대로 더블클릭 실행 / 디버거 attach 가능

### 5.2 이미지 재빌드 트리거

| 상황 | 재빌드 필요? |
|------|------------|
| 소스 코드 수정 | ❌ (마운트로 반영) |
| `Dockerfile` 수정 | ✅ |
| 새 시스템 패키지 필요 | ✅ |
| ThirdParty 추가 | ❌ (소스 마운트) |
| Windows SDK 변경 | ❌ (마운트, 단 sdk/ 디렉터리 갱신 필요) |

### 5.3 캐시 정리

`Scripts/Docker/clean.bat` → `docker volume rm servercore-build-cache` (재빌드 시 자동 재생성)

---

## 6. 빌드 캐시 / 성능

### 6.1 빌드 디렉터리 — **명명 볼륨 `servercore-build-cache`**

| 방식 | 속도 | 영속성 | 권장도 |
|------|-----|-------|-------|
| 마운트된 `/work` 직접 빌드 | 느림 (Windows bind mount I/O) | 호스트에 남음 | ❌ |
| 익명 볼륨 | 빠름 | 컨테이너 삭제 시 사라짐 | △ |
| **명명 볼륨** `servercore-build-cache` | 빠름 | 영속, incremental build 정상 | ✅ |

Linux/Windows 빌드를 같은 볼륨에 두되 `/build_src/linux/<mode>/`, `/build_src/windows/<mode>/`로 디렉터리 분리 — toolchain이 다르므로 캐시 충돌 없음.

### 6.2 (선택) ccache

`ccache` apt 추가 + `/ccache` 명명 볼륨 → ThirdParty(abseil/protobuf) 첫 빌드 외 모든 incremental 빌드 가속. PHASE 3에서 도입.

---

## 7. 실패 모드 / 사전 점검

| 위험 | 완화책 |
|------|-------|
| Windows 호스트 CRLF로 `entrypoint.sh` 깨짐 | `.gitattributes` LF 강제 + `dos2unix` 안전망 |
| GLFW `CMake`/`cmake` 케이스 충돌 | entrypoint에서 심볼릭 링크 |
| 출력 파일이 root 소유로 호스트에 남음 | `--user $(id -u):$(id -g)` |
| 첫 이미지 빌드 시 apt 다운로드 시간 | 이미지 태그 버전 고정 후 팀 레지스트리 push (선택) |
| `bin/<os>/<mode>/`에 기존 파일 잔존 | `mkdir -p` 후 덮어쓰기 (`cp -f`) |
| Windows 크로스컴파일 시 일부 MSVC 전용 헤더 동작 차이 | 첫 빌드에서 모든 타겟 컴파일·링크 검증, 차이 발견 시 `#pragma`/조건부 처리 |
| `lld-link` PE 모드에서 `/LIBPATH:` 처리 | Ubuntu 24.04의 `lld-link`가 MSVC 호환 인자 지원 — 첫 빌드에서 검증 |
| Windows PDB 디버깅 정보 | `-gcodeview` 플래그로 PDB 호환 정보 생성 (`windows-clang-toolchain.cmake`에 이미 적용 검토) |
| 케이스 인센서티브 `#include <Windows.h>` | SDK가 케이스-올바른 이름 제공, 소스 일관성만 유지 |

---

## 8. 단계별 도입 로드맵

### PHASE 0 — 정리 (이번 작업의 첫 단계)

1. **9장 삭제 리스트의 모든 파일 `git rm`**
2. `windows-clang-toolchain.cmake`의 `_LLVM_HINTS`에서 삭제된 경로 항목 제거 또는 가드
3. `.gitignore` 정리 (삭제된 디렉터리 패턴 제거)
4. README의 기존 빌드 안내 모두 제거 (Docker 안내 들어오기 전 임시 placeholder)

### PHASE 1 — Docker 빌드 인프라 (Linux + Windows 동시)

1. `Dockerfile` (ubuntu:24.04 + 3.2 패키지 일체)
2. `.dockerignore`
3. `Scripts/Docker/entrypoint.sh` (linux + windows 분기 모두 구현)
4. `Scripts/Tools/Compiler/windows-clang-toolchain-docker.cmake`
5. `Scripts/Docker/build.bat` + `build.sh` (디스패처)
6. **20개 진입 스크립트** (4.2 디렉터리 구조)
7. README.md "Docker로 빌드하기" 섹션 (유일한 빌드 경로)
8. `.gitattributes` LF 강제

**검증 기준 (PHASE 1 완료 조건)**:
- Docker만 설치된 깨끗한 Windows PC에서 `git clone` 후
  - `Scripts\Docker\Linux\Debug\debug_build.bat` → `bin/linux/debug/TestServer` 생성
  - `Scripts\Docker\Windows\Debug\debug_build.bat` → `bin/windows/debug/TestServer.exe` 생성
  - 생성된 `.exe`가 Windows에서 정상 실행 (TestServer 핸드셰이크)
- 5개 타겟 × 2 OS × 2 모드 = **20개 빌드 모두 녹색**

### ✅ PHASE 1 완료 (2026-05-07)

**검증 매트릭스** — 5 타겟 × 2 OS × 2 모드 = **20/20 PASS**

| 타겟 | Linux Debug | Linux Release | Windows Debug | Windows Release |
|------|:-:|:-:|:-:|:-:|
| all           | ✅ | ✅ | ✅ | ✅ |
| thirdparty    | ✅ | ✅ | ✅ | ✅ |
| engine        | ✅ | ✅ | ✅ | ✅ |
| server        | ✅ | ✅ | ✅ | ✅ |
| engine_server | ✅ | ✅ | ✅ | ✅ |

`bin/windows/debug/TestServer.exe` Windows 직접 실행 확인 (정상 RUNNING).

**검증 중 발견·수정한 이슈 4건** (모두 entrypoint.sh + windows-clang-toolchain-docker.cmake에 반영됨):

| # | 위치 | 증상 | 원인 | 수정 |
|---|------|------|------|------|
| 1 | `windows-clang-toolchain-docker.cmake` | `llvm-ar: error: unknown option /` (lib.exe 인자 거부) | `llvm-ar`은 GNU/BSD ar 인자만 처리. clang-cl이 `/nologo /machine:x64 /out:` 형식으로 호출 | `CMAKE_AR /usr/bin/llvm-ar` → `/usr/bin/llvm-lib` (lib.exe 호환 도구) |
| 2 | `entrypoint.sh` SDK 심링크 1단계 | `'dbghelp.h' file not found` — 1단계 심링크 일부 누락 | `set -euo pipefail` + `find ... \| while ...` 파이프에서 `pipefail`이 SIGPIPE로 find를 종료시켜 일부 파일 미처리 | 1a단계를 서브셸 + `set +e`로 분리 + 명시적 count 출력 (0개→959개로 회복) |
| 3 | `entrypoint.sh` SDK 심링크 1단계 | `'GL/gl.h' file not found` — 디렉터리 케이스 미처리 | 1단계가 파일만 처리. SDK는 `gl/`(소문자) 디렉터리, 코드는 `<GL/gl.h>` 요청 | 1b단계 추가: include 디렉터리에 양방향(`${b,,}` + `${b^^}`) 케이스 심링크 (34개 생성) |
| 4 | `entrypoint.sh` 산출물 복사 | `cp: preserving permissions ... Operation not permitted` (exit 1) | Windows bind mount(9P/SMB)는 mtime/mode 변경을 EPERM으로 거부. `cp -af`/`--preserve=mode` 모두 마지막에 실패 | `cp -rf --no-preserve=all` (모든 metadata 보존 시도 비활성화. 호스트 마운트 기본 권한 자동 적용) |

**3.4의 계획 vs 실제 차이**

원래 계획은 `windows-clang-toolchain-docker.cmake`이 `windows-clang-toolchain.cmake`을 `include()`해서 `-imsvc`/`/LIBPATH:` 플래그를 재사용하는 것이었으나, 실제 구현은 **clang-cl 드라이버 + INCLUDE/LIB 환경변수**(MSVC native 방식)로 변경:

- `clang-cl`은 INCLUDE/LIB 환경변수를 native로 인식 (MSVC link.exe와 동일 규칙)
- Linux 호스트에서 `/LIBPATH:/abs/path` 가 절대경로로 오인되는 문제 회피
- entrypoint가 cmake configure 직전에 `export INCLUDE=...; export LIB=...` (`;` 구분자, MSVC 형식)
- 결과: docker용 toolchain은 self-contained, 호스트 native 빌드용 `windows-clang-toolchain.cmake`과 완전 분리

### PHASE 2 — 사용성 개선

1. `Scripts/Docker/clean.bat` / `clean.sh` (캐시 볼륨 삭제)
2. 빌드 캐시 명명 볼륨 자동 생성/마운트
3. 진입 스크립트에서 컬러 출력, 에러 메시지 한글화

### PHASE 3 — 최적화

1. `ccache` 통합 (Linux/Windows 양쪽)
2. GitHub Container Registry에 이미지 push → `docker pull`만으로 시작
3. CI(GitHub Actions)에서 동일 Dockerfile로 20개 빌드 매트릭스 실행

---

## 9. 삭제 대상 파일 리스트 (PHASE 0)

> **목적**: 프로젝트 워킹 트리 사이즈 ~322MB 절감 + 유지보수 표면 단순화 (단일 빌드 경로)
> **방식**: `git rm`. 히스토리는 git에 남음.
> **유지**: `Scripts/Tools/Windows/sdk/` (Docker 크로스컴파일이 의존 — 절대 지우지 말 것)
> **유지**: `Scripts/Tools/Compiler/{linux,windows}-clang-toolchain.cmake` (Docker가 사용)

### 9.1 빌드 스크립트 (전체 삭제)

| 경로 | 사이즈 | 사유 |
|------|-------|------|
| `Scripts/Linux/_wsl_build.sh` | 작음 | WSL 진입점 — Docker entrypoint로 대체 |
| `Scripts/Linux/setup_wsl_ubuntu.bat` | 작음 | WSL 셋업 — Docker가 모든 도구 제공 |
| `Scripts/Linux/wsl_clean_cache.bat` | 작음 | WSL 캐시 — `Scripts/Docker/clean.bat`로 대체 |
| `Scripts/Linux/Debug/wsl_debug_build.bat` | 작음 | → `Scripts/Docker/Linux/Debug/debug_build.bat`로 대체 |
| `Scripts/Linux/Debug/wsl_thirdparty_debug_build.bat` | 작음 | 동상 |
| `Scripts/Linux/Debug/wsl_engine_debug_build.bat` | 작음 | 동상 |
| `Scripts/Linux/Debug/wsl_server_debug_build.bat` | 작음 | 동상 |
| `Scripts/Linux/Debug/wsl_engine_server_debug_build.bat` | 작음 | 동상 |
| `Scripts/Linux/Release/wsl_release_build.bat` | 작음 | 동상 |
| `Scripts/Linux/Release/wsl_thirdparty_release_build.bat` | 작음 | 동상 |
| `Scripts/Linux/Release/wsl_engine_release_build.bat` | 작음 | 동상 |
| `Scripts/Linux/Release/wsl_server_release_build.bat` | 작음 | 동상 |
| `Scripts/Linux/Release/wsl_engine_server_release_build.bat` | 작음 | 동상 |
| `Scripts/Windows/Debug/debug_build.bat` | 작음 | → `Scripts/Docker/Windows/Debug/debug_build.bat`로 대체 |
| `Scripts/Windows/Debug/thirdparty_debug_build.bat` | 작음 | 동상 |
| `Scripts/Windows/Debug/engine_debug_build.bat` | 작음 | 동상 |
| `Scripts/Windows/Debug/server_debug_build.bat` | 작음 | 동상 |
| `Scripts/Windows/Debug/engine_server_debug_build.bat` | 작음 | 동상 |
| `Scripts/Windows/Release/release_build.bat` | 작음 | 동상 |
| `Scripts/Windows/Release/thirdparty_release_build.bat` | 작음 | 동상 |
| `Scripts/Windows/Release/engine_release_build.bat` | 작음 | 동상 |
| `Scripts/Windows/Release/server_release_build.bat` | 작음 | 동상 |
| `Scripts/Windows/Release/engine_server_release_build.bat` | 작음 | 동상 |
| `Scripts/_setup_windows.bat` | 작음 | 네이티브 Windows 빌드 환경 셋업 — Docker 불필요 |
| `Scripts/setup_tools_windows.bat` | 작음 | VS2022에서 도구 복사 — Docker 불필요 |

→ 총 빈 디렉터리(`Scripts/Linux/`, `Scripts/Windows/`)도 삭제

### 9.2 Pre-committed Windows 도구 (선택적 부분 삭제 — 큰 용량)

| 경로 | 사이즈 | 사유 |
|------|-------|------|
| `Scripts/Tools/Windows/bin/` | **258MB** | Windows .exe 도구 (cmake.exe, clang.exe, lld-link.exe, llvm-ar.exe, ninja.exe 등) — Docker는 컨테이너 안 Linux clang 사용 |
| `Scripts/Tools/Windows/share/` | **17MB** | cmake 3.31 문서/모듈 — 컨테이너 안 cmake가 자체 share 보유 |
| `Scripts/Tools/Windows/lib/` | **47MB** | clang built-in intrinsic 헤더 (Windows 호스트 clang 전용) — Linux clang은 자체 intrinsic 보유 |

→ **소계: ~322MB 절감**

### 9.3 절대 삭제하지 말 것

| 경로 | 사이즈 | 사유 |
|------|-------|------|
| `Scripts/Tools/Windows/sdk/` | 429MB | **Docker Windows 크로스컴파일이 의존**. 컨테이너가 마운트된 `/work/Scripts/Tools/Windows/sdk/`에서 헤더(`-imsvc`)와 라이브러리(`/LIBPATH:`)를 읽음 |
| `Scripts/Tools/Compiler/linux-clang-toolchain.cmake` | 작음 | Docker Linux 빌드가 사용 |
| `Scripts/Tools/Compiler/windows-clang-toolchain.cmake` | 작음 | Docker Windows wrapper가 `include()` |

### 9.4 삭제 후 검증

1. `git status`에서 의도한 것만 삭제됨 확인
2. `ls Scripts/Tools/Windows/` → `sdk/`만 남아야 함
3. `Scripts/` 트리 → `Tools/`, `Docker/`(추후 추가)만 남아야 함
4. (PHASE 1 완료 후) Docker 빌드 20종 모두 성공

---

## 10. 한 줄 요약

`Dockerfile` + `.dockerignore` + `Scripts/Docker/entrypoint.sh` + 20개 진입 스크립트로,
**ubuntu:24.04 + clang/lld/cmake/X11-dev를 묶은 빌드 이미지**가 **Linux 네이티브 빌드와 Windows 크로스컴파일을 한 컨테이너에서 모두** 처리하고,
**소스는 마운트, 빌드 디렉터리는 명명 볼륨, 산출물은 호스트의 `bin/{linux,windows}/<mode>/`로 복사**한다.
**기존 WSL/네이티브 Windows 빌드 시스템(약 322MB pre-committed Windows 도구 포함)은 PHASE 0에서 전부 삭제**하여 단일 빌드 경로로 통합한다.
