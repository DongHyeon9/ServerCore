# ServerCore 코드리뷰 — 개요

리뷰 일자: 2026-05-15
리뷰 범위: `ServerEngine/`, `Server/`, `Scripts/Docker/`, 루트 `CMakeLists.txt`

---

## 한 줄 요약

빌드 인프라(Docker 단일 경로)는 견고하게 정리되어 있으나, **`ServerEngine` 본체 코드는 다이얼로그 프로토타입 단계**에 머물러 있으며 **빌드를 깨뜨리는 헤더/구현 불일치**와 **Linux 컴파일러가 거부할 수 있는 소스 인코딩 문제**가 동시에 존재한다. 게임 서버 코어로서 핵심 기능(네트워크, 세션, 패킷, 메모리 풀)은 아직 부재.

---

## 분류별 문서

| # | 파일 | 내용 | 시급도 |
|---|------|------|--------|
| 1 | [01_critical_issues.md](01_critical_issues.md) | 빌드 차단/UB 수준의 즉시 수정 항목 | 🔴 P0 |
| 2 | [02_design_issues.md](02_design_issues.md) | 아키텍처·책임 분리·확장성 문제 | 🟠 P1 |
| 3 | [03_safety_issues.md](03_safety_issues.md) | 스레드 안전성, 수명 관리, 포맷 인젝션 | 🟠 P1 |
| 4 | [04_build_system.md](04_build_system.md) | CMake·Docker·인코딩·.gitattributes | 🟡 P2 |
| 5 | [05_code_quality.md](05_code_quality.md) | 네이밍·중복·미사용 코드·스타일 | 🟢 P3 |
| 6 | [06_recommendations.md](06_recommendations.md) | 우선순위 부여된 액션 아이템 | — |

---

## 가장 시급한 3가지 (P0)

1. **`ServerDlgUtil.cpp` 와 `ServerDlgUtil.h` 의 심볼 불일치** — `.cpp` 가 헤더의 옛 이름(`pannel_item::mutiple_item`, `pannel::draw`)을 그대로 정의하지만, 헤더는 `panel_item::multiple_item`, `pannel` 로 갱신됨. **현재 상태에서 ServerEngine 링크 실패 또는 정의되지 않은 멤버 오류 발생 가능.**
2. **`ServerDlgUtil.h` 가 ISO-8859/CP949 인코딩으로 저장됨** (다른 신규 파일은 UTF-8 with BOM). Linux clang 의 기본 입력 인코딩은 UTF-8 이므로, 한국어 주석에 의해 `error: source file is not valid UTF-8` 또는 mojibake 경고가 발생할 수 있다.
3. **`string_util::format(std::string, ...)` 는 정의되지 않은 동작(UB)** — `va_start` 의 첫 인자는 자명한(trivial) 타입이어야 한다는 C++ 표준 위반.

---

## 가장 시급한 3가지 (P1)

1. **`server_dialog_base::run()` 에 TestServer 전용 UI(Server Control / Statistics / Log) 하드코딩** — base/derived 책임 경계가 무너져 다른 다이얼로그 파생이 불가능.
2. **`ImGui::Text(_text.c_str())` 의 포맷 문자열 인젝션** — 사용자 입력에 `%` 가 들어가면 즉시 크래시/UB.
3. **`hierarchy<T>::add_item` 의 람다가 `this` 를 raw capture** — `weak_ptr<T>` 로 아이템 수명은 보호하지만, `hierarchy` 자신이 먼저 파괴되면 dangling. 현재 코드는 hierarchy 소멸자에서 `clear_label_callbacks()` 를 호출해 안전 경로를 만들었지만, **이동(move)된 `hierarchy` 사본이 존재하면 등록 시점의 this 가 그대로 유지되어 위험.** 또한 `_label_change_handles` 가 `T*` 키이므로 같은 주소가 재사용될 때 충돌 가능.

---

## 시스템 전반의 인상

| 영역 | 평가 |
|------|------|
| 빌드 인프라 (Docker, CMake 디스패처) | 잘 정리됨. 캐시 명명 볼륨 + 마운트 분리, 케이스 보정 등 실전적 |
| 서버 코어 기능 | **거의 미구현** (`ServerEngine.cpp` 가 사실상 빈 파일) |
| 다이얼로그 추상화 (`dialog::*`) | 의도는 좋으나 헤더/소스 동기화 누락, 책임 분리 미흡 |
| 위임/싱글톤/델리게이트 유틸 | 단일 스레드 가정. 멀티스레드 서버 코어에는 부적합 |
| ThirdParty 통합 (boost.asio, protobuf, glfw, imgui) | CMake 옵션은 정확히 설정됨 |
| 테스트 | **0건** — 단위 테스트, 통합 테스트 모두 없음 |

---

## 다음 단계 권장

1. **P0 3건을 먼저 처리하여 빌드를 그린 상태로 복구** (1일 이내)
2. P1 의 설계 문제는 별도 `ClaudeMD/<topic>_plan.md` 로 플랜화 후 진행
3. 다이얼로그 작업이 안정화되면 본래 목표인 네트워크/세션/패킷 코어 구현으로 전환 (TODO.txt 참조)
