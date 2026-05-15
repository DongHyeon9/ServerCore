# P3 — 코드 품질 / 네이밍 / 미사용 코드

기능에 영향은 없으나 가독성·유지보수성을 떨어뜨리는 항목들.

---

## 1. 네이밍 컨벤션 혼재 🟢

### 현황
| 종류 | 컨벤션 | 예 |
|------|--------|----|
| 클래스 | `snake_case` | `component_base`, `menu_item`, `server_dialog_base` |
| 클래스 | `PascalCase` (LogBuffer 만) | `LogBuffer` |
| 함수 | `snake_case` | `add_item`, `set_label` |
| 함수 | `camelCase` (LogBuffer 만) | `scrollToBottom`, `activeConnections` |
| 매크로/Cast | `PascalCase` | `Cast`, `DIALOG_DECLARE_TYPE` |
| 함수 인자 | `PascalCase` | `Label`, `Item`, `Before`, `After` |
| 멤버 변수 | `_snake_case` | `_label`, `_items` |
| 멤버 변수 | `camelCase` (LogBuffer/server_dialog_base 만) | `portBuf`, `serverRunning` |
| Enum | `SCREAMING_SNAKE` | `E_COMPONENT_TYPE::MENU_ITEM` |

→ **3가지 컨벤션이 혼재**. 특히 `server_dialog_base` 안의 멤버(`serverRunning`, `portBuf`) 와 다른 멤버(`_label`) 가 같은 클래스 안에서 다른 스타일.

### 수정 방향
프로젝트 전체에서 한 가지 컨벤션 채택. `.clang-format` 으로 강제.

권장: `snake_case` 통일 (현재 ServerEngine 의 다수 코드 스타일과 일치). C++ STL 컨벤션과도 일치하고 abseil 도 동일.

---

## 2. 깨진 한글 주석 다수 🟢

### 위치
- `ServerEngine/include/ServerDlgUtil.h` — 모든 한글 주석이 mojibake
- `ServerEngine/include/Core/Struct.h:92, 106, 114, 121, 132, 149, 152` — `// ��Ƽĳ��Ʈ ��������Ʈ` 등

### 원인
P0 항목 2 와 동일 — 파일 인코딩 문제. P0 수정 시 함께 해결됨.

---

## 3. 미사용 / 의미 없는 파일 🟢

| 파일 | 상태 |
|------|------|
| `ServerEngine/src/ServerEngine.cpp` | `#include "ServerEngine.h"` 한 줄 |
| `ServerEngine/src/ServerDialogPreset.cpp` | `#include` 한 줄 |
| `ServerEngine/include/ServerDialogPreset.h` | `#include "ServerDlgUtil.h"` 한 줄 |

→ 사실상 빈 컴파일 단위. 정적 라이브러리에 .obj 파일만 추가됨.

### 수정 방향
- 헤더 only 라면 .cpp 삭제 후 CMakeLists 에서 빼기.
- `ServerDialogPreset.h` 가 단순 alias 라면 그냥 헤더 통합.

---

## 4. `DummyClient` 가 사실상 비어있음 🟢

### 위치
`Server/DummyClient/src/main.cpp`

```cpp
int main() {
    std::cout << "DummyClient started\n";
    return 0;
}
```

### 문제
TODO.txt 에 부하 테스트 클라이언트로 표기되어 있지만, 현재 코드는 placeholder. 빌드는 되지만 의미 없음.

### 수정 방향
- 일단 그대로 두되 TODO 에 명시 (이미 됨).
- 본격 구현 시 boost.asio TCP 클라이언트 + 패킷 송수신 루프.

---

## 5. `ServerMonitor` 와 `server_dialog_base` 가 코드 중복 🟢

### 위치
- `Server/ServerMonitor/src/main.cpp` — GLFW + ImGui main loop 를 손으로 작성
- `ServerEngine/include/ServerDialog.h::server_dialog_base` — 같은 로직을 템플릿화

### 문제
- ServerMonitor 가 `server_dialog_base` 를 상속해서 만들면 코드 중복 사라짐.
- 현재 ServerMonitor 는 ServerEngine 에 링크되어 있지만(`target_link_libraries(ServerMonitor PRIVATE ServerEngine ImGui)`) `server_dialog_base` 를 사용하지 않음.

### 수정 방향
ServerMonitor 를 `server_monitor_dialog : server_dialog_base<...>` 로 리팩터링.

---

## 6. 주석 처리된 코드 잔존 🟢

### 위치
`Server/ServerMonitor/src/main.cpp:7-10, 14`

```cpp
//static void GlfwErrorCallback(int error, const char* description)
//{
//    fprintf(stderr, "GLFW Error %d: %s\n", error, description);
//}
...
    //glfwSetErrorCallback(GlfwErrorCallback);
```

### 수정 방향
- 죽은 코드 제거. 필요하면 git 에서 복구 가능.

---

## 7. `multicast_delegate::add_sp` 의 `sp.get()->*Method` 🟢

### 위치
`ServerEngine/include/Core/Struct.h:126-130`

```cpp
return add([weak, Method](ARGS... Args) {
    if (auto sp = weak.lock())
        (sp.get()->*Method)(std::forward<ARGS>(Args)...);
});
```

### 문제
- `sp.get()->*Method` 보다 `(*sp).*Method` 또는 `(sp.operator->()->*Method)` 가 직관적. 의미는 같음.
- 사소하지만 다른 곳(`bind_sp`)도 같은 패턴이라 일관됨. 굳이 바꿀 필요는 없음.

---

## 8. `#pragma once` 와 include guard 혼재 안함 🟢

모든 헤더가 `#pragma once` 사용 — 일관됨. 다만 clang-tidy 의 `llvm-header-guard` 룰을 적용하려면 guard 추가 권장. 우선순위 매우 낮음.

---

## 9. `TODO.txt` 가 한 줄짜리 항목 나열 🟢

### 위치
프로젝트 루트 `TODO.txt`

### 문제
- 항목별 우선순위·진척도 정보 없음.
- "Asio / 구글 protobuf" 같이 이미 통합된 항목과 미구현 항목이 섞임.

### 수정 방향
- GitHub Issues 또는 별도 `ROADMAP.md` 로 분리.
- 항목별 체크박스 + 우선순위 + 종속성 명시.

---

## 10. `int main()` 의 `argc/argv` 무시 🟢

### 위치
모든 `main.cpp`

### 문제
- 포트, 로그 레벨, 설정 파일 경로 등을 CLI 인자로 받는 경우 거의 0. TestServer 의 포트는 GUI 에서만 입력 가능.

### 수정 방향
- 향후 `--port 7777 --headless` 같은 옵션 지원 시 cxxopts/abseil flags 도입.

---

## 11. `dialog::pannel::description::attribute` 의 멤버 노출 🟢

### 위치
`ServerEngine/include/ServerDlgUtil.h:350-356`

```cpp
struct description {
    struct attribute {
        ImVec2 _point{};
        ImGuiCond_ _cond{};
    } _size, _pos;
};
```

### 문제
- `description` 은 public 인터페이스인데 멤버 이름이 `_` 접두 — 외부에서 직접 접근.
- POD 처럼 쓰일 의도였다면 그냥 `point`, `cond` 가 더 자연스러움.

### 수정 방향
- public 데이터는 `_` 접두 없이, private 멤버만 `_` 접두 사용 등 룰 통일.

---

## 12. `Header.h` 가 두 군데 (`include/`, `include/Core/`) 🟢

### 현황
- git status: `D ServerEngine/include/Header.h` (삭제됨), `?? ServerEngine/include/Core/` (추가 미커밋)
- 의도는 `include/Core/` 로 이전이나 `git add` 미실행.

### 수정 방향
`git add ServerEngine/include/Core/` 후 한 커밋으로 정리.
