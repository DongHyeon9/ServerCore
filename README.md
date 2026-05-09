# ServerCore

C++ 게임 서버 (정적 라이브러리 `ServerEngine` + 실행파일 `TestServer`/`DummyClient`/`ServerMonitor`).
**Linux 네이티브 빌드와 Windows 크로스컴파일을 모두 단일 Docker 이미지(`ubuntu:24.04` + clang/lld/cmake)에서 처리**한다.

> **Docker만 설치되어 있으면 빌드된다.** WSL · Ubuntu · clang · cmake · lld · X11 dev 패키지 · VS2022 모두 **호스트 PC에 설치 불필요** — 이미지 안에 모두 포함된다.
> Windows SDK는 리포지토리에 pre-committed (`Scripts/Tools/Windows/sdk/`) → 컨테이너에 마운트로 노출.

---

## 빌드 (Docker 단일 경로)

### 1. 사전 준비

#### Windows 호스트

**옵션 A — 자동 셋업 스크립트 (권장)**

```
Scripts\Setup\setup_docker_windows.bat
```

WSL2 활성화 → Docker Desktop 설치(`winget` 우선, 수동 다운로드 fallback) → daemon 준비 → `hello-world` 검증까지 한 번에 처리. 멱등성 보장 (이미 셋업된 PC에서 재실행 시 ~30초). 단계별 종료 코드(2/3/10/11/20)로 BIOS 가상화·재부팅·라이선스 동의 등이 필요한 시점을 명시.

**옵션 B — 수동**
1. [Docker Desktop](https://www.docker.com/products/docker-desktop) 설치 (WSL2 백엔드 권장)
2. Docker Desktop 실행 → 트레이 아이콘이 "running" 상태인지 확인
3. `git clone <repo>` (clone 위치는 한글/공백 없는 경로 권장)

**Docker Desktop이 "Engine starting…"에서 멈출 때**

```
Scripts\Setup\fix_docker_engine.bat
```

프로세스 재시작 → `wsl --update` → `settings.json` reset 순으로 안전한 자동 fix를 시도하고, 실패 시 진단 로그 (`%TEMP%\docker_diag_*.log`)와 다음 시도할 액션(BIOS, AV 예외 등록, factory reset)을 안내. 위험한 단계(WSL distro 재등록 — 컨테이너/이미지 삭제됨)는 `--level 4` 명시 + 사용자 confirm 필요.

#### Linux 호스트
1. Docker Engine 설치 ([공식 가이드](https://docs.docker.com/engine/install/))
2. 현재 사용자를 `docker` 그룹에 추가하고 재로그인 (`sudo usermod -aG docker $USER`)
3. `docker info`로 데몬 응답 확인
4. `git clone <repo>`

#### macOS 호스트
1. [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop) 설치 (Apple Silicon / Intel 모두 지원)
2. Docker Desktop 실행
3. `git clone <repo>`

> **공통**: 첫 빌드 시 `docker build`가 자동 수행됨 (~3–5분, 이후 캐시).

### 2. 빌드 실행

#### Windows 호스트

**옵션 A — 진입 스크립트 더블클릭 (권장)**

`Scripts\Docker\<OS>\<Mode>\<group>_build.bat`을 탐색기에서 더블클릭하면 Docker가 자동 실행되고 결과물은 호스트에 그대로 남는다. 끝나면 `pause`로 결과 확인 가능.

| 자주 쓰는 빌드 | 경로 |
|---|---|
| Linux Debug 풀빌드 | `Scripts\Docker\Linux\Debug\debug_build.bat` |
| Windows Debug 풀빌드 | `Scripts\Docker\Windows\Debug\debug_build.bat` |
| Linux Release 풀빌드 | `Scripts\Docker\Linux\Release\release_build.bat` |
| Windows Release 풀빌드 | `Scripts\Docker\Windows\Release\release_build.bat` |

**옵션 B — cmd / PowerShell에서 디스패처 직접 호출**

```bat
Scripts\Docker\build.bat <Linux|Windows> <Debug|Release> [all|thirdparty|engine|server|engine_server]
```

예:
```bat
Scripts\Docker\build.bat Windows Debug all
Scripts\Docker\build.bat Linux Release server
```

#### Linux / macOS 호스트

진입점은 `Scripts/Docker/build.sh`. 실행 비트가 없다면 `chmod +x Scripts/Docker/build.sh` 한 번.

```bash
./Scripts/Docker/build.sh Linux   Debug   all
./Scripts/Docker/build.sh Linux   Release server
./Scripts/Docker/build.sh Windows Debug   all       # Windows .exe 크로스컴파일
./Scripts/Docker/build.sh Windows Release engine
```

> Linux/macOS 호스트에서도 Windows .exe 크로스컴파일이 정상 동작한다. 단, Windows .exe는 Linux/macOS에서 직접 실행할 수 없다 (파일로만 생성됨).

### 3. 빌드 매트릭스 (5 타겟 × 2 OS × 2 모드 = 20 검증 완료)

| 타겟          | Linux Debug                                                        | Linux Release                                                          | Windows Debug                                                          | Windows Release                                                            |
| ------------- | ------------------------------------------------------------------ | ---------------------------------------------------------------------- | ---------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| 풀빌드        | `Scripts\Docker\Linux\Debug\debug_build.bat`                       | `Scripts\Docker\Linux\Release\release_build.bat`                       | `Scripts\Docker\Windows\Debug\debug_build.bat`                         | `Scripts\Docker\Windows\Release\release_build.bat`                         |
| ThirdParty    | `Scripts\Docker\Linux\Debug\thirdparty_debug_build.bat`            | `Scripts\Docker\Linux\Release\thirdparty_release_build.bat`            | `Scripts\Docker\Windows\Debug\thirdparty_debug_build.bat`              | `Scripts\Docker\Windows\Release\thirdparty_release_build.bat`              |
| Engine        | `Scripts\Docker\Linux\Debug\engine_debug_build.bat`                | `Scripts\Docker\Linux\Release\engine_release_build.bat`                | `Scripts\Docker\Windows\Debug\engine_debug_build.bat`                  | `Scripts\Docker\Windows\Release\engine_release_build.bat`                  |
| Server        | `Scripts\Docker\Linux\Debug\server_debug_build.bat`                | `Scripts\Docker\Linux\Release\server_release_build.bat`                | `Scripts\Docker\Windows\Debug\server_debug_build.bat`                  | `Scripts\Docker\Windows\Release\server_release_build.bat`                  |
| Engine+Server | `Scripts\Docker\Linux\Debug\engine_server_debug_build.bat`         | `Scripts\Docker\Linux\Release\engine_server_release_build.bat`         | `Scripts\Docker\Windows\Debug\engine_server_debug_build.bat`           | `Scripts\Docker\Windows\Release\engine_server_release_build.bat`           |

> Linux/macOS 호스트에서는 `.bat` 대신 `Scripts/Docker/build.sh <OS> <Mode> <group>` 형태로 호출.

### 4. 산출물 위치

```
bin/linux/debug/    — Linux ELF (TestServer, DummyClient, ServerMonitor, libServerEngine.a)
bin/linux/release/
bin/windows/debug/  — Windows PE (TestServer.exe, DummyClient.exe, ServerMonitor.exe, *.pdb, ServerEngine.lib)
bin/windows/release/   (Release 빌드는 .pdb 미생성)
```

Windows 호스트에서는 `.exe`를 더블클릭으로 실행하거나 디버거 attach 가능.

---

## 캐시 / 이미지 관리

### 빌드 캐시 정리

```
Scripts\Docker\clean.bat      (Windows 호스트)
./Scripts/Docker/clean.sh     (Linux / macOS 호스트)
```

→ 빌드 캐시 명명 볼륨 `servercore-build-cache` 삭제. 다음 빌드 시 자동 재생성 (전체 재컴파일).

### 이미지 재빌드가 필요한 경우

| 상황                          | 재빌드 필요 |
| ----------------------------- | ----------- |
| 소스 코드 / ThirdParty 수정     | ❌ (마운트로 자동 반영) |
| Windows SDK 갱신                | ❌ (마운트로 자동 반영) |
| `Dockerfile` 수정              | ✅           |
| `entrypoint.sh` 수정           | ✅ (이미지에 COPY 됨) |
| 새 시스템 패키지 추가          | ✅           |

수동 재빌드:
```
docker build -t servercore-builder:latest .
```

이미지 통째로 삭제:
```
docker image rm servercore-builder:latest
```

---

## 빌드 시스템 구조

| 파일/디렉터리                                                  | 역할                                                                          |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `Dockerfile`                                                   | `ubuntu:24.04` + clang/lld/cmake/X11-dev 빌드 이미지                          |
| `.dockerignore`                                                | 이미지 빌드 컨텍스트 슬림화 (Windows SDK는 마운트로 노출, 이미지에 미포함)    |
| `Scripts/Docker/entrypoint.sh`                                 | 컨테이너 안 빌드 로직 (rsync, glfw 케이스 보정, SDK 케이스 심링크, cmake)     |
| `Scripts/Docker/build.{bat,sh}`                                | 호스트 디스패처 (이미지 보장 + `docker run` 호출)                             |
| `Scripts/Docker/clean.{bat,sh}`                                | 빌드 캐시 명명 볼륨 삭제                                                      |
| `Scripts/Docker/{Linux,Windows}/{Debug,Release}/`              | 20개 진입 스크립트 (한 줄로 디스패처 호출)                                    |
| `Scripts/Tools/Compiler/linux-clang-toolchain.cmake`           | Linux 네이티브 toolchain                                                      |
| `Scripts/Tools/Compiler/windows-clang-toolchain.cmake`         | Windows MSVC ABI toolchain (호스트 직접 빌드용 — 현재 미사용)                 |
| `Scripts/Tools/Compiler/windows-clang-toolchain-docker.cmake`  | 컨테이너 안 `clang-cl` + `INCLUDE`/`LIB` 환경변수 기반 크로스컴파일 toolchain |
| `Scripts/Tools/Windows/sdk/`                                   | pre-committed Windows SDK (UCRT/UM/MSVC 헤더 + lib)                           |

### 빌드 데이터 흐름

```
호스트 ServerCore/  ──(bind mount, ro 의도)──►  /work
                                                  │
                                                  │ rsync --delete (Windows bind I/O 우회)
                                                  ▼
                                  /build_src (named volume: servercore-build-cache)
                                                  │
                              ┌───────────────────┼───────────────────┐
                              ▼                                       ▼
                /build_src/{linux,windows}/{Debug,Release}/   ← cmake + ninja
                              │
                              ▼ (cp --no-preserve=all)
              호스트 ServerCore/bin/{linux,windows}/{debug,release}/
```

---

## 프로젝트 구조

```
ServerEngine/      — 정적 라이브러리 (네트워크/세션/패킷 등 공통 기반)
Server/
    TestServer/    — 실행파일
    DummyClient/   — 실행파일 (부하 테스트 클라이언트)
    ServerMonitor/ — 실행파일 (ImGui 모니터)
ThirdParty/
    abseil-cpp/, protobuf/, glfw/, imgui/, boost_asio/ (header-only)
Scripts/
    Docker/        — 빌드 진입점 (이 README의 핵심)
    Tools/         — Compiler toolchain + pre-committed Windows SDK
```
