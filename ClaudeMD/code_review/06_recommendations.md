# 우선순위 부여된 액션 아이템

리뷰 전반의 결론을 실행 단위로 정리. 각 항목은 독립적으로 처리 가능.

---

## 🔴 P0 — 즉시 (이번 작업 세션)

### A0-1. ServerDlgUtil 헤더/소스 동기화 - 수정완료
- 변경: `ServerEngine/src/ServerDlgUtil.cpp`
- 작업: `pannel_item::mutiple_item` → `panel_item::multiple_item`
- 검증: `Scripts/Docker/Linux/Debug/engine_debug_build.bat` 그린
- 참조: [01_critical_issues.md#1](01_critical_issues.md)

### A0-2. ServerDlgUtil.h 인코딩 UTF-8 BOM 으로 통일 - 수정완료
- 변경: `ServerEngine/include/ServerDlgUtil.h`
- 작업: CP949/ISO-8859 → UTF-8 with BOM 재저장
- 도구: VS Code "Save with Encoding" 또는 PowerShell `[System.IO.File]::WriteAllText` + `UTF8Encoding($true)`
- 검증: `file ServerDlgUtil.h` 가 "UTF-8 (with BOM) text" 출력
- 참조: [01_critical_issues.md#2](01_critical_issues.md)

### A0-3. `string_util::format(std::string, ...)` 오버로드 제거 - 수정완료
- 변경: `ServerEngine/src/Util.cpp`, `ServerEngine/include/Core/Util.h`
- 작업: 두 번째 오버로드 삭제. 호출자가 있다면 `.c_str()` 추가
- 검증: 빌드 그린 + grep 으로 `format(some_string_var,` 호출 없음 확인
- 참조: [01_critical_issues.md#3](01_critical_issues.md)

### A0-4. `Core/` 디렉토리 git add - 수정완료
- 변경: 추적되지 않은 `ServerEngine/include/Core/Header.h`, `Type.h` 등을 git add
- 작업: `git add ServerEngine/include/Core/`
- 참조: [01_critical_issues.md#5](01_critical_issues.md), [05_code_quality.md#12](05_code_quality.md)

### A0-5. `LogBuffer::add` 의 `localtime` 을 thread-safe 변형으로 - 예정
- 변경: `ServerEngine/include/ServerDialog.h`
- 작업: `localtime_r` (POSIX) / `localtime_s` (Windows) 또는 `std::chrono::zoned_time`
- 검증: 빌드 그린, ImGui 로그 패널에 시간 정상 표시
- 참조: [01_critical_issues.md#4](01_critical_issues.md)

### A0-6. `ImGui::Text(_text.c_str())` → `TextUnformatted` - 수정완료
- 변경: `ServerEngine/src/ServerDlgUtil.cpp` (`text::draw`, `rich_text::draw`)
- 작업: 포맷 인젝션 방지
- 참조: [01_critical_issues.md#6](01_critical_issues.md)

**예상 작업량**: 2~3시간. 빌드 그린 + 다이얼로그 정상 동작 확인까지.

---

## 🟠 P1 — 다음 스프린트 (각 항목 별도 플랜으로)

### A1-1. `server_dialog_base::run()` 의 TestServer UI 분리 - 테스트코드
- **별도 플랜 문서 필요**: `ClaudeMD/dialog_base_refactor_plan.md`
- 핵심: base 는 윈도/렌더 루프만, UI 는 모두 `dialog::*` 컴포넌트로
- 참조: [02_design_issues.md#1](02_design_issues.md)

### A1-2. `dialog::hierarchy<T>` 트리 탐색 구현 - 고려중
- 이미 플랜 있음: `ClaudeMD/dialog_hierarchy_search_and_cast_plan.md`
- 그 플랜의 후보 A 또는 B 채택 후 구현
- 참조: [02_design_issues.md#4](02_design_issues.md), TODO.txt 1번 항목

### A1-3. `hierarchy<T>` 의 `this` raw capture 안전화 - 의도된 사양
- 핸들 키를 `T*` → `delegate_handle` 로 변경
- 이동 생성자 명시적 `= delete` 또는 안전한 재등록
- 참조: [03_safety_issues.md#1](03_safety_issues.md)

### A1-4. `delegate` / `multicast_delegate` 스레드 안전성 - 고려중
- mutex 추가 또는 lock-free 자료구조 도입
- 참조: [02_design_issues.md#6](02_design_issues.md), [03_safety_issues.md#2](03_safety_issues.md)

### A1-5. `Header.h` PCH 화 + 의존성 슬림화 - target_precompile_headers화 필요
- `target_precompile_headers` 또는 명시 include 정리
- ImGui/GLFW 의존을 dialog 헤더로만 격리
- 참조: [02_design_issues.md#2](02_design_issues.md)

### A1-6. 단위 테스트 인프라 - 고려중
- GoogleTest 또는 abseil gtest 통합
- `tests/test_delegate.cpp`, `tests/test_hierarchy.cpp` 최소 셋
- 참조: [04_build_system.md#10](04_build_system.md)

**예상 작업량**: 각 1~2일.

---

## 🟡 P2 — 빌드 시스템 정리

### A2-1. CMake 중복 제거 (helper function 도입)
- `servercore_setup_target(tgt)` 헬퍼
- RUNTIME_OUTPUT_DIRECTORY 글로벌 변수화
- 참조: [04_build_system.md#2-3](04_build_system.md)

### A2-2. `GLOB_RECURSE` → 명시적 파일 목록
- ServerEngine 외 다른 CMakeLists 도 동일하게
- 참조: [04_build_system.md#1](04_build_system.md)

### A2-3. `.editorconfig` 추가 + `.gitattributes` 보강
- 모든 .h/.cpp 가 UTF-8 BOM + CRLF 로 유지되도록
- 참조: [04_build_system.md#4](04_build_system.md)

### A2-4. ThirdParty `EXCLUDE_FROM_ALL` 통일
- protobuf/glfw/imgui 도 `EXCLUDE_FROM_ALL`
- 참조: [04_build_system.md#8](04_build_system.md)

### A2-5. `clean.bat --all` 옵션
- 빌드 캐시 + bin/ 동시 청소
- 참조: [04_build_system.md#9](04_build_system.md)

**예상 작업량**: 합쳐서 반나절.

---

## 🟢 P3 — 코드 품질 (시간 날 때)

### A3-1. `.clang-format` 도입 + 일괄 포매팅
- snake_case 통일
- 참조: [05_code_quality.md#1](05_code_quality.md)

### A3-2. 빈 .cpp 파일 / placeholder 정리
- `ServerEngine.cpp`, `ServerDialogPreset.cpp` 등
- 참조: [05_code_quality.md#3](05_code_quality.md)

### A3-3. ServerMonitor 를 `server_dialog_base` 기반으로 리팩터링
- 참조: [05_code_quality.md#5](05_code_quality.md)

### A3-4. `pannel` → `panel` 일괄 변경
- 참조: [02_design_issues.md#7](02_design_issues.md)

### A3-5. `TODO.txt` → `ROADMAP.md` 또는 GitHub Issues 로 이관
- 참조: [05_code_quality.md#9](05_code_quality.md)

---

## 본 게임 (TODO.txt 의 핵심 항목)

다이얼로그 인프라가 안정화되면, TODO.txt 의 핵심 백엔드 작업으로 전환:

1. **Asio 기반 네트워크 레이어** — `acceptor`, `session`, `connection_manager`
2. **메모리 풀** — 패킷/세션용 객체 풀
3. **Producer-Consumer 큐** — 패킷 처리 파이프라인
4. **Protobuf 패킷 정의** — `.proto` 스키마 + `protoc` 통합 (CMake 에서 자동 생성)
5. **DB 연동** — Redis (세션) / RDS (영구) / DynamoDB (운영)
6. **AWS 배포** — EC2 + Lambda + S3 로그 적재
7. **Unreal 플러그인** — 모바일/PC 클라이언트 SDK
8. **CI/CD** — Jenkins or GitHub Actions, k8s 매니페스트

이 항목들은 본 리뷰 범위 밖.

---

## 권장 진행 순서

```
[현재 시점]
   │
   ▼
P0 6건 처리 (반나절)
   │
   ▼
P1 단위 테스트 인프라 먼저 (A1-6)
   │   - 이후 모든 P1 작업이 테스트 보호 받음
   ▼
P1 나머지 (다이얼로그 리팩터, 스레드 안전성)
   │
   ▼
P2 빌드 정리 (한 PR 로 묶어서)
   │
   ▼
P3 는 새 기능 작업 사이에 분산 처리
   │
   ▼
[본 게임: Asio + 패킷 + DB]
```

---

## 부록 — 본 리뷰가 다루지 않은 영역

- ThirdParty 자체 코드 (abseil-cpp, protobuf, glfw, imgui) — upstream 책임
- Windows SDK 의 케이스 보정 로직 — 이미 별도 플랜에서 검토됨
- CI/CD, 배포 — 아직 도입 전
- 성능 프로파일링 — 코어 기능 부재로 의미 없음
- 보안 감사 — 네트워크 코드 부재로 보류
