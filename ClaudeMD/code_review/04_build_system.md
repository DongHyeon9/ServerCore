# P2 — 빌드 시스템 / CMake / 인코딩

빌드는 동작하지만 향후 유지보수·이식성을 깎아먹는 항목들.

---

## 1. `file(GLOB_RECURSE)` + 명시적 파일 목록 혼용 🟠

### 위치
`ServerEngine/CMakeLists.txt:3-5`

```cmake
file(GLOB_RECURSE SOURCES "src/*.cpp")
add_library(ServerEngine STATIC ${SOURCES}
    "include/ServerDialog.h"  "include/Core/Struct.h"
    "include/ServerDlgUtil.h" "src/ServerDlgUtil.cpp"
    "include/ServerDialogPreset.h" "src/ServerDialogPreset.cpp"
    "include/Core/Util.h" "src/Util.cpp"
    "include/Core/Preprocess.h")
```

### 문제
1. **`GLOB_RECURSE` 가 이미 `src/*.cpp` 를 다 잡는데**, 그 뒤에 `src/ServerDlgUtil.cpp`, `src/ServerDialogPreset.cpp`, `src/Util.cpp` 를 또 명시 → **중복 소스 등록**.
   - CMake 가 보통 중복을 허용하지만, 어떤 generator(특히 일부 IDE 통합)는 같은 .cpp 를 두 번 컴파일 시도하다 오류.
2. **`GLOB` 사용 자체가 CMake 공식 권장 X** — 빌드 트리는 새 파일 추가를 감지하지 못하고 stale 됨. 매번 `cmake reconfigure` 필요.
3. **헤더 명시 목록이 일관성 없음** — `Core/Struct.h`, `Core/Util.h`, `Core/Preprocess.h` 는 있지만 `Core/Header.h`, `Core/Type.h` 는 누락. IDE 색인에서 일부 헤더가 안 보임.

### 수정 방향
```cmake
set(SOURCES
    src/ServerEngine.cpp
    src/ServerDlgUtil.cpp
    src/ServerDialogPreset.cpp
    src/Util.cpp
)
set(HEADERS
    include/ServerEngine.h
    include/ServerDialog.h
    include/ServerDialogPreset.h
    include/ServerDlgUtil.h
    include/Core/Header.h
    include/Core/Type.h
    include/Core/Struct.h
    include/Core/Util.h
    include/Core/Preprocess.h
)
add_library(ServerEngine STATIC ${SOURCES} ${HEADERS})
```

---

## 2. 컴파일러 옵션 중복 정의 🟢

### 위치
- `ServerEngine/CMakeLists.txt:19-29`
- `Server/TestServer/CMakeLists.txt:14-24`
- `Server/DummyClient/CMakeLists.txt:9-19`
- `Server/ServerMonitor/CMakeLists.txt:12-22`

```cmake
if(MSVC)
    target_compile_options(... PRIVATE
        $<$<CONFIG:Debug>:/Zi /Od /RTC1>
        $<$<CONFIG:Release>:/O2>
    )
else()
    target_compile_options(... PRIVATE
        $<$<CONFIG:Debug>:-g -O0>
        $<$<CONFIG:Release>:-O2 -DNDEBUG>
    )
endif()
```

### 문제
- 동일 블록이 4개 CMakeLists 에 반복. 새 타겟 추가 시 또 복붙.
- `/Zi /Od /RTC1` 은 CMake 기본 Debug 플래그 (`CMAKE_CXX_FLAGS_DEBUG`) 와 중복 — 명시할 필요 없음.
- `-DNDEBUG` 는 `CMAKE_CXX_FLAGS_RELEASE` 가 이미 추가함.

### 수정 방향
```cmake
# 최상위 CMakeLists.txt 에
function(servercore_setup_target tgt)
    if(MSVC)
        target_compile_options(${tgt} PRIVATE
            $<$<CONFIG:Debug>:/RTC1>)
    else()
        target_compile_options(${tgt} PRIVATE
            $<$<CONFIG:Debug>:-fno-omit-frame-pointer>)
    endif()
    target_compile_options(${tgt} PRIVATE
        $<$<CXX_COMPILER_ID:Clang,GNU>:-Wall -Wextra -Wpedantic>
        $<$<CXX_COMPILER_ID:MSVC>:/W4>)
endfunction()
```
각 하위 CMakeLists 는 `servercore_setup_target(MyTarget)` 한 줄만 호출.

---

## 3. RUNTIME/ARCHIVE/LIBRARY 출력 디렉토리 설정 중복 🟢

### 위치
4개 모든 CMakeLists.txt 의 끝부분에 동일 패턴:

```cmake
if(WIN32)
    set(_BIN_PREFIX "${CMAKE_SOURCE_DIR}/bin/windows")
else()
    set(_BIN_PREFIX "${CMAKE_SOURCE_DIR}/bin/linux")
endif()
set_target_properties(... PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY_DEBUG ...
    ...)
```

### 수정 방향
최상위 CMakeLists.txt 에서 글로벌 변수로 설정하면 모든 타겟이 자동 적용:
```cmake
if(WIN32)
    set(_BIN_PREFIX "${CMAKE_SOURCE_DIR}/bin/windows")
else()
    set(_BIN_PREFIX "${CMAKE_SOURCE_DIR}/bin/linux")
endif()
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_DEBUG   "${_BIN_PREFIX}/debug")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_RELEASE "${_BIN_PREFIX}/release")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY_DEBUG   "${_BIN_PREFIX}/debug")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${_BIN_PREFIX}/release")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY_DEBUG   "${_BIN_PREFIX}/debug")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY_RELEASE "${_BIN_PREFIX}/release")
```

---

## 4. 소스 인코딩 일관성 부재 🔴

### 현황
| 파일 | 인코딩 |
|------|--------|
| `ServerDlgUtil.h` | ISO-8859 / CP949 |
| `Core/Util.h`, `Core/Struct.h`, `Core/Header.h`, `Core/Type.h`, `Core/Preprocess.h` | ASCII (BOM 없음) |
| `Util.cpp`, `ServerDialogPreset.cpp` | ASCII (BOM 없음) |
| `TestServerDialog.cpp` | UTF-8 with BOM |
| `Scripts/Docker/build.bat`, `clean.bat` | UTF-8 with BOM |
| `Scripts/Docker/entrypoint.sh` | UTF-8 (BOM 없음, LF) — `.gitattributes` 로 강제 |

### 문제
- ISO-8859 파일 1개 (P0 항목 2 참조) — Linux clang 빌드 차단 가능.
- BOM 있고 없음 혼재 — 일부 도구가 BOM 을 BOM 그대로 코드로 인식.

### 수정 방향
`.editorconfig` 추가:
```ini
root = true

[*]
charset = utf-8-bom
end_of_line = crlf
insert_final_newline = true
trim_trailing_whitespace = true

[*.sh]
end_of_line = lf
charset = utf-8

[*.{cmake,txt}]
charset = utf-8
```

`.gitattributes` 에 보강:
```
*.h     text working-tree-encoding=UTF-8
*.hpp   text working-tree-encoding=UTF-8
*.cpp   text working-tree-encoding=UTF-8
*.cmake text working-tree-encoding=UTF-8
```

---

## 5. `Dockerfile` 의 `clang-cl` 심링크가 버전 의존 🟢

### 위치
`Dockerfile:30`

```dockerfile
&& ln -sf clang-cl-18 /usr/bin/clang-cl
```

### 문제
- Ubuntu 24.04 패키지 `clang-tools` 버전이 19, 20 으로 올라가면 `clang-cl-18` 가 더 이상 존재하지 않음. 매번 Dockerfile 수정 필요.

### 수정 방향
```dockerfile
RUN apt-get install ... \
    && CC_VER=$(clang --version | head -1 | grep -oE 'version [0-9]+' | awk '{print $2}') \
    && ln -sf "clang-cl-${CC_VER}" /usr/bin/clang-cl
```
또는 단순히 alternatives 사용:
```dockerfile
&& update-alternatives --install /usr/bin/clang-cl clang-cl /usr/bin/clang-cl-18 100
```

---

## 6. `.dockerignore` / rsync exclude 동기화 🟢

### 위치
`Scripts/Docker/entrypoint.sh:46-58`

```bash
rsync -a --delete \
    --exclude='.git/' \
    --exclude='.vs/' \
    --exclude='.vscode/' \
    ...
```

### 문제
- 동일한 패턴이 `.dockerignore` 에도 있어야 일관성. 실수로 한쪽만 갱신되면 큰 디렉터리가 마운트되거나 컨텍스트로 들어감.

### 수정 방향
- `.dockerignore` 확인 후 동기화 (또는 둘 다 같은 generated list 에서 빌드).
- `--exclude-from=$SRC/.dockerignore` 사용해 단일 진실 원천화.

---

## 7. `cmake_minimum_required` 가 ServerEngine 등 하위에 없음 🟢

### 위치
하위 CMakeLists.txt 들에 `cmake_minimum_required` 가 없고 `project()` 만 있음.

### 문제
- 하위 디렉터리는 부모 `cmake_minimum_required` 를 상속하므로 보통 무관하지만, CMake 3.x 신규 정책(`CMP0XXX`)이 활성화될 때 의도와 다른 동작이 나올 수 있음.

### 수정 방향
- 하위 CMakeLists 에 `cmake_minimum_required(VERSION 3.20)` 명시하거나, 최상위에서 `cmake_policy(VERSION 3.20)` 로 정책 묶기.

---

## 8. ThirdParty 통합이 `EXCLUDE_FROM_ALL` 불일치 🟢

### 위치
`CMakeLists.txt:42`

```cmake
add_subdirectory(ThirdParty/abseil-cpp EXCLUDE_FROM_ALL)
add_subdirectory(ThirdParty/protobuf)            # ← 그대로 'all' 에 포함
add_subdirectory(ThirdParty/glfw)
add_subdirectory(ThirdParty/imgui)
```

### 문제
- abseil 만 `EXCLUDE_FROM_ALL`. 결과: `cmake --build .` (no target) 시 abseil 의 타겟은 빌드되지 않지만, protobuf, glfw, imgui 의 모든 타겟(테스트, 예제 등)이 의도치 않게 빌드될 가능성.
- protobuf 는 `protobuf_BUILD_TESTS OFF` 등으로 가지치기 했으나 glfw 의 `EXCLUDE_FROM_ALL` 누락.

### 수정 방향
- 모든 ThirdParty 를 `EXCLUDE_FROM_ALL` 로 통일. 필요한 타겟만 명시적 `target_link_libraries` 로 끌어옴.

---

## 9. `clean.bat` 가 빌드 산출물(`bin/`) 은 안 지움 🟢

### 위치
`Scripts/Docker/clean.bat`

### 문제
- 명명 볼륨만 삭제. 호스트의 `bin/linux`, `bin/windows` 는 그대로 남음.
- 사용자가 "clean" 했다고 생각하지만 stale binary 가 남아서 디버깅 시 헷갈림.

### 수정 방향
`clean.bat` 에 옵션 추가:
```bat
clean.bat            # 캐시 볼륨만
clean.bat --all      # 캐시 + bin/ 까지
```

---

## 10. 단위 테스트 인프라 부재 🟠

### 현황
- ServerEngine 에 테스트 디렉토리·CMake 옵션 없음.
- ThirdParty/abseil-cpp 와 protobuf 가 GTest 를 들고 옴에도 ServerCore 자체는 활용 안 함.

### 수정 방향
- `ThirdParty/googletest` 추가 또는 abseil 의 gtest 활용.
- `tests/` 디렉토리 + CTest 통합. `delegate`, `multicast_delegate`, `hierarchy<T>` 처럼 순수 로직은 즉시 테스트 가능.
