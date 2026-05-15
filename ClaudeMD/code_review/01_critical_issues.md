# P0 — 빌드 차단 / UB 수준 이슈

빌드를 다시 그린 상태로 만들려면 아래 항목을 먼저 처리해야 한다.

---

## 1. `ServerDlgUtil.cpp` ↔ `ServerDlgUtil.h` 심볼 불일치 🔴

### 증상
헤더(`ServerEngine/include/ServerDlgUtil.h`)는 최근 리팩터링으로 다음 이름을 사용:
- `namespace panel_item` (한 개의 'n')
- `class multiple_item` (`multiple`)
- `class pannel` (그대로 'pannel' — 한국식 표기인 듯)

반면 구현 파일(`ServerEngine/src/ServerDlgUtil.cpp`)은 이전 이름을 그대로 정의:
```cpp
namespace pannel_item                 // ← 헤더와 다름 ('nn')
{
    void mutiple_item::draw() { ... } // ← 헤더와 다름 ('multiple' → 'mutiple')
    void button::draw()    { ... }
    void text::draw()      { ... }
    ...
}
void pannel::draw() { ... }           // 헤더와 일치 (둘 다 'pannel')
```

### 결과
- `mutiple_item` 은 헤더에 정의되지 않음 → 정의할 클래스가 없으므로 컴파일러 오류(`'mutiple_item' is not a member of 'dialog::pannel_item'`).
- `pannel_item::button`, `text`, `editable_text`, `rich_text` 도 동일 — 네임스페이스 불일치로 모두 미정의.
- 따라서 `ServerEngine` 정적 라이브러리 자체가 빌드 실패.

### 수정 방향
헤더 쪽 이름이 의도된 새 이름인 듯하므로, `.cpp` 의 네임스페이스/클래스명을 헤더에 맞춰 수정:
- `pannel_item::mutiple_item` → `panel_item::multiple_item`
- (단 `pannel` 클래스는 양쪽 다 `pannel` 이므로 유지 — 의도된 표기라면 그대로 두고, 영어 'panel' 로 통일하려면 헤더·소스 동시 변경)

### 검증
`Scripts/Docker/Linux/Debug/engine_debug_build.bat` 한 번 돌려서 그린이면 OK.

# 수정완료

---

## 2. `ServerDlgUtil.h` 의 소스 인코딩이 UTF-8 이 아님 🔴

### 증상
```
$ file ServerEngine/include/ServerDlgUtil.h
ServerDlgUtil.h: C++ source, ISO-8859 text, with CRLF line terminators
```

다른 신규/수정 파일은 UTF-8(with BOM)으로 저장됨:
```
ServerEngine/include/Core/Util.h:           C++ source, ASCII text
Server/TestServer/src/TestServerDialog.cpp: ... UTF-8 (with BOM) ...
Scripts/Docker/build.bat:                   ... UTF-8 (with BOM) ...
```

`git diff` 출력에서 한국어 주석이 `�� ���� �ʿ� ������� ������` 같이 깨져서 표시되는 것이 증거.

### 결과
- Linux clang 의 기본 입력 인코딩은 UTF-8.
- ISO-8859 / CP949 로 저장된 멀티바이트 한국어 주석은 컴파일러가 이를 잘못 디코딩 하면서 다음 중 하나 발생:
  - `warning: illegal character encoding in comment [-Winvalid-source-encoding]`
  - 아주 드물게 주석 내 바이트가 `\` 로 끝나 다음 줄을 주석으로 이어 붙여 **코드 한 줄을 통째로 삼킴**
  - `-Werror` 가 켜져 있다면 빌드 실패

### 수정 방향
파일을 UTF-8(with BOM 또는 without BOM) 로 재저장. 옵션 두 가지:
1. VS Code 에서 "Save with Encoding → UTF-8" 또는 "UTF-8 with BOM" (다른 .cpp 파일과 일치시키려면 BOM 포함)
2. Python 한 줄:
   ```bash
   python3 -c "import pathlib; p=pathlib.Path('ServerEngine/include/ServerDlgUtil.h'); p.write_text(p.read_text(encoding='cp949'), encoding='utf-8-sig')"
   ```

### 예방
`.gitattributes` 에 `*.h *.cpp text working-tree-encoding=UTF-8` 추가, `.editorconfig` 에 `charset = utf-8-bom` 명시.

# 수정완료
---

## 3. `string_util::format(std::string, ...)` 는 UB 🔴

### 위치
`ServerEngine/src/Util.cpp:31-38`

```cpp
std::string format(std::string Str, ...)
{
    va_list args;
    va_start(args, Str);          // ← UB
    std::string result = vformat(Str.c_str(), args);
    va_end(args);
    return result;
}
```

### 원인
C++ 표준 [cstdarg.syn] / N4950 17.13.1: `va_start` 의 두 번째 인자는 **반드시 trivially copyable 한 타입**이어야 하며, **참조/비 trivial 타입을 전달하면 UB**.
`std::string` 은 non-trivial → 즉시 UB. 실제 동작은 ABI 마다 다르지만, clang 은 `-Wvarargs` 경고 후 잘못된 va_list 를 생성한다.

또한 가변 인자에 `std::string` 자체를 전달하면 컴파일러는 그것을 어떻게 캐스팅할지 모르므로 호출자가 `format(std::string(...), 42)` 같이 쓰면 두 번째 UB 가 발생.

### 수정 방향
- 이 오버로드 자체를 **삭제**하거나
- 시그니처를 `const char*` 로 통일:
  ```cpp
  std::string format(const char* Fmt, ...);   // 유일 시그니처
  ```
- 호출자는 `format(str.c_str(), ...)` 또는 `format("%s", str.c_str())` 사용.

권장: C++20 `std::format` 으로 전환. `printf` 식 가변 인자 대신 타입 안전한 포매팅 사용 가능.
# 수정완료
---

## 4. `LogBuffer::add` 의 `localtime` 사용 🔴 (스레드 안전성)

### 위치
`ServerEngine/include/ServerDialog.h:11-26`

```cpp
time_t t = time(nullptr);
char timebuf[16];
strftime(timebuf, sizeof(timebuf), "%H:%M:%S", localtime(&t));
```

### 원인
- `localtime` 은 **정적 내부 버퍼**를 사용 → 멀티스레드에서 호출 시 race condition.
- 서버 코어가 결국 멀티스레드로 동작하면 (현재 boost.asio io_context 가 곧 들어올 예정) 로그가 깨지거나 크래시.

### 수정 방향
POSIX: `localtime_r(&t, &tm_buf)`
Windows: `localtime_s(&tm_buf, &t)`
또는 C++20 `std::chrono::zoned_time` / `std::format("{:%T}", ...)`.

또한 `LogBuffer::add` 자체에 mutex 가 없어서 `lines.push_back` 도 race 가 발생.

---

## 5. `Header.h` 가 두 군데에 존재 🟠

### 증상
`git status`:
```
D ServerEngine/include/Header.h          ← 삭제됨
?? ServerEngine/include/Core/Header.h    ← 추가됨 (아직 미커밋)
```

`ServerEngine/CMakeLists.txt` 는 `include/Core/Struct.h`, `include/Core/Util.h`, `include/Core/Preprocess.h` 만 명시하고 `Core/Header.h`, `Core/Type.h` 는 명시하지 않음. `GLOB_RECURSE` 가 `src/*.cpp` 만 잡으므로 헤더 누락은 컴파일은 가능하지만 IDE 색인/패키징에서 빠짐.

### 수정 방향
- 미커밋 파일들을 `git add` 하여 추적하기 시작 (또는 의도적으로 누락이면 `git rm` 으로 정리).
- CMakeLists 에 `Core/Header.h`, `Core/Type.h` 도 명시.
# 수정완료
---

## 6. `ImGui::Text(_text.c_str())` 포맷 인젝션 🔴

### 위치
`ServerEngine/src/ServerDlgUtil.cpp:58-60, 68-70`

```cpp
void text::draw()      { ImGui::Text(_text.c_str()); }
void rich_text::draw() { ImGui::TextColored(_color, _text.c_str()); }
```

### 원인
`ImGui::Text` 는 `printf` 식 가변 인자 함수. `_text` 가 `"%s"` 또는 `"100%"` 같은 문자열이면 스택을 잘못 읽어 크래시/정보 누설.

### 수정 방향
`ImGui::TextUnformatted(_text.c_str())` 사용. 색상이 필요한 경우:
```cpp
ImGui::PushStyleColor(ImGuiCol_Text, _color);
ImGui::TextUnformatted(_text.c_str());
ImGui::PopStyleColor();
```
# 수정완료
---

## 7. `pannel::add_spacing` / `add_separator` 가 hierarchy 불변식 위반 🟠

### 위치
`ServerEngine/include/ServerDlgUtil.h:363-364`

```cpp
void add_spacing() { _items.emplace_back(std::make_shared<panel_item::spacing>()); }
void add_separator() { _items.emplace_back(std::make_shared<panel_item::separator>()); }
```

### 원인
`hierarchy<T>::add_item` 은 `_item_map`, `_label_change_handles` 동기화까지 보장하지만, 이 두 함수는 `_items` 에만 직접 push. 결과적으로:
- `find_item` 으로 찾을 수 없음 (의도적일 수 있으나)
- `clear()` / `remove_item` 후 `_label_change_handles` 의 raw pointer 가 다른 객체에 재할당되면 콜백 등록이 어긋날 수 있음

### 수정 방향
- 라벨이 없는 컴포넌트라면 `_item_map` 동기화는 자동으로 스킵됨 → 그냥 `add_item(make_shared<...>())` 호출하면 됨.
- 일관성을 위해 두 함수도 `add_item` 경유로 변경.

# 수정완료
