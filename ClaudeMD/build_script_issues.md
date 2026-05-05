# ServerCore 빌드 스크립트 문제점 분석

분석일: 2026-05-05  
분석 대상: `C:\Users\user\Desktop\linux_shared_folder\ServerCore`

---

## 요약

| 빌드 방식 | 현재 상태 | 핵심 원인 |
|-----------|-----------|-----------|
| Linux (WSL) | **동작** | - |
| Windows Clang | **실패** | `rc.exe` 미포함 + `-imsvc` 플래그 미지원 |

---

## [Windows 빌드] 문제 1 — `rc.exe` (리소스 컴파일러) 없음

### 증상
```
CMake Error at .../Platform/Windows-Clang.cmake:136 (enable_language):
  No CMAKE_RC_COMPILER could be found.
```

### 원인
- CMake가 Windows 타겟을 위한 프로젝트를 구성할 때 리소스 컴파일러(`rc.exe`)를 필수로 요구함
- `rc.exe`는 Windows SDK의 **바이너리 도구** 디렉터리(`bin/x64/`)에 있는 실행 파일임
- 현재 리포지토리에는 SDK의 `include/`와 `lib/`만 커밋되어 있고, `bin/`(rc.exe 포함)은 없음

```
Scripts/Tools/Windows/sdk/
  include/  ← 커밋됨
  lib/      ← 커밋됨
  (bin/)    ← 없음, rc.exe가 여기 있어야 함
```

- `_setup_windows.bat`에서 `INCLUDE`, `LIB` 환경변수는 설정되지만 `PATH`에 `rc.exe` 경로는 추가되지 않음
- VS2022가 설치되어 있는 경우에는 VS vcvars64.bat이 `rc.exe` 경로를 PATH에 추가해주지만, 그 경우에도 아래의 문제 2가 발생함

### 발생 조건
- VS2022가 설치되어 있지 않은 환경 (clean 설치 상태)
- `_setup_windows.bat`의 pre-committed SDK 경로를 사용하는 경우

---

## [Windows 빌드] 문제 2 — `clang.exe`가 `-imsvc` 플래그를 지원하지 않음

### 증상
```
clang: error: unknown argument: '-imsvcC:/Users/.../sdk/include/msvc'
clang: error: unknown argument: '-imsvcC:/Users/.../sdk/include/ucrt'
clang: error: unknown argument: '-imsvcC:/Users/.../sdk/include/shared'
clang: error: unknown argument: '-imsvcC:/Users/.../sdk/include/um'
```

### 원인
`Scripts/Tools/Compiler/windows-clang-toolchain.cmake`가 MSVC SDK 헤더 경로를 `-imsvc` 플래그로 전달하도록 설계되어 있음:

```cmake
foreach(_inc msvc ucrt shared um)
    string(APPEND CMAKE_C_FLAGS_INIT " -imsvc${_SDK_ROOT}/include/${_inc}")
endforeach()
```

그런데 커밋된 `clang.exe`(버전 19.1.5)는 **`-imsvc` 플래그를 드라이버 모드에서 지원하지 않음**.

```
$ clang.exe --target=x86_64-pc-windows-msvc -imsvc C:\test ...
clang: error: unknown argument: '-imsvc'
```

`-imsvc`는 `clang-cl.exe` 전용 플래그임. 현재 툴체인은 `clang.exe`를 사용하도록 설정되어 있음.

```cmake
find_program(CMAKE_C_COMPILER NAMES clang ...)   ← clang.exe 사용
find_program(CMAKE_CXX_COMPILER NAMES clang++ ...) ← clang++.exe 사용
```

`clang-cl.exe`는 리포지토리에 커밋되어 있지 않음:

```
Scripts/Tools/Windows/bin/
  clang.exe      ← 있음
  clang++.exe    ← 있음
  clang-cl.exe   ← 없음  ← 여기서 문제 발생
```

### VS2022 설치 환경에서도 실패하는 이유
VS2022 + vcvars64.bat을 통해 빌드해도 동일하게 실패함. vcvars64.bat은 `INCLUDE`/`LIB` 환경변수를 설정해주지만, cmake toolchain이 별도로 `-imsvc` 플래그를 생성하고, `clang.exe`가 이를 거부하기 때문.

---

## [Windows 빌드] 문제 3 — 헤더/라이브러리 경로 중복 추가

### 증상
컴파일 명령에 동일한 경로가 두 번 포함됨:
```
-fms-compatibility-version=19.44 -imsvc.../msvc -imsvc.../ucrt ...
-fms-compatibility-version=19.44 -imsvc.../msvc -imsvc.../ucrt ...  ← 중복
```

### 원인
`_setup_windows.bat`이 `INCLUDE` 환경변수를 설정하고, cmake toolchain도 동일 경로를 `-imsvc` 플래그로 추가하기 때문.

1. `_setup_windows.bat` → `INCLUDE=...sdk/include/msvc;...sdk/include/ucrt;...` 환경변수 설정
2. cmake가 INCLUDE 환경변수를 읽어 include 경로로 추가
3. toolchain cmake가 동일 경로를 `-imsvc` 플래그로 다시 추가

---

## [Windows 빌드] 문제 4 — CMakeCache.txt 경로 고착 문제

### 증상
프로젝트 폴더를 이동하거나 다른 경로에 새로 받으면 빌드가 실패하거나 잘못된 경로로 빌드됨.

### 원인
`debug_build.bat` (및 release, engine, server, thirdparty 계열 전부)이 다음 로직을 사용함:

```bat
if not exist "%BD%\CMakeCache.txt" (
    ... cmake configure ...
)
"%CMAKE%" --build "%BD%" ...
```

`CMakeCache.txt`가 있으면 cmake configure를 건너뜀. 그런데 `CMakeCache.txt` 내부에는 이전 경로가 절대 경로로 박혀 있음:

```
# For build in directory: C:/OLD/PATH/ServerCore/build/...
CMAKE_SOURCE_DIR = C:/OLD/PATH/ServerCore
```

- 프로젝트를 새 경로로 복사/이동한 경우
- 이전 빌드 결과가 남아 있는 경우

에는 cmake가 configure를 재실행하지 않아서 잘못된 경로로 빌드가 진행됨.

현재 Windows 빌드 스크립트에는 cache 초기화 방법이 없음 (Linux에는 `wsl_clean_cache.bat`이 있음).

---

## [공통] 문제 5 — 리포지토리 크기 과다

### 현황
커밋된 Windows 빌드 도구 용량:

| 디렉터리 | 내용 | 용량 |
|---------|------|------|
| `Scripts/Tools/Windows/bin/` | clang.exe, cmake.exe, ninja.exe 등 | ~257 MB |
| `Scripts/Tools/Windows/lib/` | clang 내장 헤더 (xmmintrin.h 등) | ~45 MB |
| `Scripts/Tools/Windows/share/` | cmake 모듈 파일 | ~8 MB |
| `Scripts/Tools/Windows/sdk/` | MSVC + WinSDK 헤더/라이브러리 | ~420 MB |
| **합계** | | **~730 MB** |

### 문제점
- GitHub 권장 리포지토리 크기: 1 GB 미만 (경고), 5 GB 초과 시 push 차단
- 현재 리포지토리 로컬 git 객체 크기: ~105 MB (pack 압축 후 82 MB)
- 팀원이 `git clone` 시 730 MB 이상 다운로드 필요
- 바이너리 파일(`.exe`, `.lib`)은 git 압축이 거의 되지 않아 히스토리마다 전체 용량 누적
- 앞으로 clang/SDK 버전 업데이트 시마다 수백 MB가 추가됨

---

## [Linux 빌드] 문제 6 — WSL 빌드 출력 복사 대상이 하드코딩됨

### 위치
`Scripts/Linux/_wsl_build.sh` 48~59번째 줄:

```bash
for TARGET in TestServer DummyClient ServerMonitor; do
    BIN="$SRC_BIN/$TARGET"
    if [ -f "$BIN" ]; then
        cp -f "$BIN" "$OUT/"
    fi
done
```

### 문제
새로운 실행 파일 타겟이 CMakeLists.txt에 추가되더라도 이 목록에 수동으로 추가하지 않으면 Windows 폴더(`bin/linux/debug/`)로 복사되지 않음.

빌드는 성공해도 출력 파일이 공유 폴더에 나타나지 않아 빌드가 실패한 것처럼 보일 수 있음.

---

## [Linux 빌드] 문제 7 — WSL 빌드 경로 충돌 가능성

### 위치
`Scripts/Linux/_wsl_build.sh` 10~11번째 줄:

```bash
NATIVE="$HOME/ServerCore"
BD="$HOME/build/ServerCore/$MODE"
```

### 문제
WSL 인스턴스의 홈 디렉터리(`$HOME`)를 기준으로 고정 경로를 사용함.

- 같은 WSL 인스턴스에서 여러 ServerCore 프로젝트를 동시에 작업할 경우 소스가 덮어씌워짐
- 다른 Windows 경로에서 동시에 빌드 스크립트를 실행하면 rsync가 소스를 덮어씀

---

## [Linux 빌드] 문제 8 — `shift 2`의 인자 수 미검사

### 위치
`Scripts/Linux/_wsl_build.sh` 7번째 줄:

```bash
shift 2
TARGETS=("$@")
```

### 문제
인자가 2개 미만으로 전달되면 `shift 2`가 실패하고 `set -e`에 의해 스크립트가 즉시 종료됨.  
(정상적인 bat 파일에서는 항상 2개 이상 전달되므로 현재는 문제없음. 하지만 직접 실행하거나 인자를 빠뜨리면 디버그하기 어려운 실패가 발생함.)

---

## 문제 우선순위 정리

| 우선순위 | 문제 | 영향 |
|---------|------|------|
| 🔴 긴급 | 문제 1: `rc.exe` 없음 | Windows 빌드 전면 불가 |
| 🔴 긴급 | 문제 2: `-imsvc` 미지원 | Windows 빌드 전면 불가 |
| 🟠 높음 | 문제 5: 리포지토리 크기 | clone 속도 저하, GitHub 한계 근접 |
| 🟡 중간 | 문제 4: CMakeCache 경로 고착 | 경로 변경 시 빌드 실패 |
| 🟡 중간 | 문제 3: 경로 중복 추가 | 컴파일 경고, 비효율 |
| 🟢 낮음 | 문제 6: 복사 대상 하드코딩 | 신규 타겟 추가 시 누락 |
| 🟢 낮음 | 문제 7: WSL 경로 충돌 | 동시 작업 환경에서만 발생 |
| 🟢 낮음 | 문제 8: shift 미검사 | 직접 실행 시에만 발생 |

---

## 참고: 현재 동작하는 것

- **Linux (WSL) 빌드**: 정상 동작. `Scripts/Linux/Debug/wsl_debug_build.bat` 실행 시 cmake configure → clang 빌드 → `bin/linux/debug/`로 바이너리 복사까지 완료됨
- **상대 경로**: 모든 스크립트가 `%~dp0`와 `%%~fI`를 사용해 프로젝트 루트를 동적으로 계산하므로 절대 경로 의존성 없음
- **CRLF 자동 수정**: `wsl_*.bat` 파일들이 bash 실행 전 `sed -i 's/\r$//'`로 줄끝을 자동 수정함
- **ThirdParty 라이브러리**: abseil-cpp, protobuf, glfw, imgui 모두 소스 포함됨
