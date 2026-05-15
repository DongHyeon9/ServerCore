# P1 — 설계 / 아키텍처 이슈

빌드는 되지만 추후 확장·유지보수를 어렵게 하는 구조적 문제들.

---

## 1. `server_dialog_base::run()` 에 TestServer 전용 UI 가 박혀 있음 🟠

### 위치
`ServerEngine/include/ServerDialog.h:96-175`

base 템플릿의 main loop 안에 다음 UI 가 직접 들어 있다:
- `"Server Control"` 패널 (Port InputText, Start/Stop 버튼, 상태 텍스트)
- `"Statistics"` 패널 (Connections / Packets / Bytes)
- `"Log"` 패널 (`LogBuffer log` 멤버까지 base 에 존재)
- 상태 변수(`serverRunning`, `portBuf[8]`, `activeConnections`, `packetsPerSec` ...)도 base 멤버

### 문제
1. **단일 책임 원칙 위반**: `server_dialog_base` 는 GLFW/ImGui 라이프사이클 관리자이면서 TestServer UI 디자이너이기도 함.
2. **재사용 불가**: `dummy_client_dialog`, `admin_console_dialog` 등 다른 다이얼로그가 동일 base 를 상속하면, **원하지 않는 "Server Control" 패널이 자동으로 그려짐**.
3. **`dialog::*` 컴포넌트 시스템과 중복**: 사용자가 어렵게 만든 `dialog::pannel`, `dialog::main_menu` 시스템이 있는데 base 가 이를 우회해 직접 ImGui 호출.

### 수정 방향
- base 는 윈도/렌더 루프만 책임. UI 는 `_items` 안의 `component_base` 들로만 표현.
- TestServer 가 `init_impl()` 안에서 `Server Control` / `Statistics` / `Log` 를 `dialog::pannel` 로 조립해 `_items` 에 등록.
- `LogBuffer` 는 base 가 아니라 별도 `dialog::log_panel` 컴포넌트로 분리.

이 작업은 별도 플랜으로 분리하는 것이 좋음 (`ClaudeMD/dialog_base_refactor_plan.md`).
# 테스트 코드 - 이상없음
---

## 2. `Header.h` 가 사실상 `precompiled.h` 처럼 모든 표준 헤더를 끌어옴 🟠

### 위치
`ServerEngine/include/Core/Header.h`

```cpp
#include <iostream> <fstream> <filesystem> <chrono>
#include <memory> <functional> <algorithm> <concepts>
#include <array> <vector> <list> <map> <set> <unordered_map> <unordered_set>
#include <queue> <stack> <string>
#include <thread> <mutex> <condition_variable> <future> <cassert>
#include "boost/asio.hpp"      // ← 매우 무거움
#include <imgui.h> ...
```

그리고 `Type.h → Struct.h → Util.h` 가 줄줄이 이 헤더를 끌어옴. **`ServerEngine.h` 가 결국 모든 .cpp 에 포함됨** → 사실상의 글로벌 PCH.

### 문제
- **빌드 시간 폭증**: boost.asio + imgui + filesystem 을 매 TU 가 파싱. ServerEngine 본체 + Server/* 각 .cpp 마다 발생.
- **결합도**: 다이얼로그용 코드(imgui, glfw)가 네트워크 유틸이나 메모리 풀에도 강제로 노출됨. 콘솔 전용 서버 빌드가 불가.
- **순환 의존**: 아직 안 나타났지만 추후 헤더가 늘어나면 매우 위험.

### 수정 방향
- `Header.h` 를 폐기하거나 명확한 PCH (`target_precompile_headers`) 로 분리.
- 각 헤더는 자기 자신이 필요한 표준 헤더만 include.
- ImGui/GLFW 의존은 **dialog 관련 헤더 안으로만 제한** (예: `ServerDialog.h`, `ServerDlgUtil.h`).
- `BoostAsio` 는 `ServerEngine` 의 `PUBLIC` 이므로 어차피 노출되지만, `network/` 하위 헤더에서만 include 하도록 격리.
# target_precompile_headers로 분리
---

## 3. `singleton<T>` 패턴이 절반만 강제됨 🟠

### 위치
`ServerEngine/include/Core/Struct.h:4-22`

```cpp
template<class T>
class singleton
{
public:
    static T& get_instance() { static T inst; return inst; }
    virtual bool init() = 0;
    virtual void terminate() = 0;
protected:
    singleton() = default;
    virtual ~singleton() = default;
    singleton(const singleton&) = delete;
    singleton& operator=(const singleton&) = delete;
};
```

### 문제
1. **`T` 의 public 생성자가 막혀있지 않음** — `T` 가 일반 클래스라면 `T x;` 로 인스턴스를 또 만들 수 있어 싱글톤 의미 깨짐.
2. **`init()` / `terminate()` 가 자동 호출되지 않음** — `main()` 에서 명시적으로 호출해야 함. 실수로 빠뜨리면 무한정 다이얼로그 미초기화 상태로 사용됨.
3. **소멸 순서가 불명확** — static local 의 소멸은 `main` 종료 후 reverse 순. `glfwTerminate()` 가 그 시점에 호출되면 GL 컨텍스트가 이미 다른 라이브러리에 의해 정리됐을 수 있음.
4. **이동/복사 금지가 derived 에 자동 적용 안 됨** — `singleton` 의 `delete` 는 base 의 복사만 막음. derived 의 컴파일러 생성 복사 생성자가 별도로 활성화됨 (현재는 component_base 정도지만 추후 위험).

### 수정 방향
- derived 의 생성자도 `friend class singleton<T>` 로 보호:
  ```cpp
  template<class T>
  class singleton {
      friend T;  // T 의 private 생성자에 접근 가능
      static T& get_instance() { static T inst; return inst; }
      ...
  };

  class test_server_dialog : public server_dialog_base<test_server_dialog> {
  private:
      test_server_dialog() = default;
      friend class singleton<test_server_dialog>;
      ...
  };
  ```
- `init`/`terminate` 자동화: RAII 형 `ScopedInit` 또는 `get_instance()` 안에서 `call_once` 로 init 보장.
# 이상없음
---

## 4. `dialog::hierarchy<T>` 가 다층 트리 탐색을 제공하지 않음 🟠

### 위치
`ServerEngine/include/ServerDlgUtil.h:73-241`

### 문제
- `find_item(label)` 은 **현재 레벨**만 찾음. `main_menu → menu_bar → menu_item` 같은 트리에서 `find_item("Exit")` 호출 시 즉시 false.
- TODO.txt 에서 사용자가 "dialog::interface::hierarchy 탐색 기능 구현 고려" 라고 적은 것과 일치.
- 이미 `ClaudeMD/dialog_hierarchy_search_and_cast_plan.md` 가 후보 설계를 정리해 둠 → 그 플랜의 후보 A(라벨 기반 선형 + 재귀 visitor) 또는 후보 B(트리 walker) 채택 필요.

### 수정 방향
플랜대로 진행. `for_each_child(visitor)` 를 `component_base` 가상 함수로 추가 + `hierarchy<T>` 가 override. 이미 플랜 문서가 있으므로 별도 설계 작업 불필요.
# 고려중
---

## 5. `dialog::component_base` 의 RTTI 우회가 불완전 🟠

### 위치
`ServerEngine/include/ServerDlgUtil.h:382-391`

```cpp
template<class DERIVED, class BASE>
DERIVED* Cast(BASE* Ptr) noexcept
{
    return (Ptr && Ptr->type_id() == DERIVED::_s_type_id) ? static_cast<DERIVED*>(Ptr) : nullptr;
}
```

### 문제
1. **다이아몬드 상속의 경우 잘못된 캐스트**: 예컨대 `multiple_item : public base, public hierarchy<base>`. `_s_type_id` 가 정확히 일치할 때만 캐스트하므로 derived-of-derived 는 캐스트 실패 (예: `editable_text` → `text` 캐스트 불가, 둘 다 `text` 의 자식이 아니라 enum 값이 다름).
2. **enum 추가/순서 변경 시 ABI 변경**: enum 값을 보존하지 않으면 모든 사용 코드의 의미가 바뀜.
3. **`dynamic_cast` 가 있는데 굳이 enum 기반으로 한 이유 불명** — 코드에 RTTI 비활성화 옵션 없음(`-fno-rtti` 미사용).

### 수정 방향
- 단순 `dynamic_cast<DERIVED*>(Ptr)` 로 충분. 성능이 정말 문제일 때만 enum + static_cast 고려.
- enum 기반을 유지한다면, 각 클래스가 "내 type_id 와 내 모든 ancestor 의 type_id 를 알고 있다" 는 구조로 확장 (boost 의 type_id_with_cvr 또는 abseil 의 type_traits 참고).
# 이상없음
---

## 6. `delegate<>` / `multicast_delegate<>` 는 단일 스레드 가정 🟠

### 위치
`ServerEngine/include/Core/Struct.h:40-164`

### 문제
- `add` / `remove` / `broadcast` 어느 것에도 mutex 없음.
- `multicast_delegate::broadcast` 가 vector copy 를 통해 "broadcast 중에도 add/remove 가능" 을 보장한다고 주석에 있으나, **다른 스레드의 add/remove 까지는 보호하지 못함**.
- `_next_id` 가 단순 `++` → 두 스레드가 동시에 add 하면 handle 충돌 가능.

### 수정 방향
서버 코어가 멀티스레드라면 `std::mutex` 또는 `std::shared_mutex` 추가. 가벼운 fast-path 가 필요하면 generation counter + per-thread queue 패턴 검토.
# 고려중
---

## 7. `pannel` 명명이 typo (panel) 🟢

### 문제
영문 표기는 `panel` 이 맞고, 같은 코드 안에서 `panel_item::*` namespace 는 한 'n' 으로 정확히 쓰임. 클래스만 `pannel` 로 유지되어 일관성 깨짐.

### 수정 방향
`pannel` → `panel` 로 일괄 변경. 헤더 + cpp + TestServer 코드 동시 수정. (검색 치환 안전: `pannel` 만 매칭하면 됨)
# 수정됨
---

## 8. `editable_text::set_text = delete` 가 사용성을 막음 🟢

### 위치
`ServerEngine/include/ServerDlgUtil.h:313-326`

### 문제
`editable_text` 는 `_text.resize(Buffer)` 로 고정 크기 버퍼를 잡고, `set_text` 를 `delete` 해서 초기값 설정 자체를 금지함. 이러면:
- 기본값 표시 불가 (예: "Enter server name" placeholder)
- 다른 곳에서 받아온 값을 보여줄 수 없음

### 수정 방향
```cpp
void set_text(std::string T) override {
    if (T.size() >= _text.size())
        T.resize(_text.size() - 1);  // null terminator 자리
    std::ranges::copy(T, _text.begin());
    _text[T.size()] = '\0';
}
```
또는 `_text` 를 `std::string` 이 아닌 `std::vector<char>` 로 두고 명시적으로 capacity vs size 구분.
# 이상없음
