# P1 — 안전성 / 수명 / 동시성 이슈

크래시·메모리 손상·정보 누설로 이어질 수 있는 항목들.

---

## 1. `hierarchy<T>` 의 `this` raw capture + `T*` 키 문제 🟠

### 위치
`ServerEngine/include/ServerDlgUtil.h:90-117`

```cpp
delegate_handle handle = Item->_on_label_change.add(
    [this, weak_item](const std::string& Before, const std::string& After)
    {
        auto sp = weak_item.lock();
        if (!sp) return;
        // _item_map 동기화 ... this-> 접근
    });
_label_change_handles[Item.get()] = handle;
```

### 문제
1. **`this` 가 raw 캡처** — `hierarchy` 인스턴스의 수명이 콜백 호출 시점까지 유지되어야 함. 소멸자에서 `clear_label_callbacks()` 를 호출해 등록 해제하므로 정상 경로는 안전. 그러나:
   - **이동 생성된 hierarchy 가 있다면** 콜백은 원본 주소를 가리킨 채 살아있고, 원본은 소멸한 상태 → use-after-free.
   - `hierarchy` 는 `protected` 생성자라 직접 인스턴스화는 불가하지만, `menu_bar`, `pannel` 등이 상속받아 다중 인스턴스 + 컨테이너에 저장될 때 동일 위험.
2. **`_label_change_handles[Item.get()]` 의 raw pointer 키** — 같은 주소에 다른 `T` 객체가 새로 들어오면 `_label_change_handles` 가 잘못된 객체의 핸들을 가리킴 (주소 재사용 ABA 문제). `shared_ptr` 가 소멸 → 다른 `make_shared` 가 같은 주소를 반환할 가능성 존재.

### 수정 방향
- 캡처를 `weak_ptr<hierarchy>` 로 만들기 어렵다면, **콜백 등록 측이 아닌 컨테이너 측에서 폴링** (라벨 변경 시 외부에서 명시적 sync 호출) 으로 단순화.
- `_label_change_handles` 의 키를 `delegate_handle` 값(unique uint64)으로 변경하고, hierarchy 가 보유한 모든 핸들을 set 으로 관리.

---

## 2. `multicast_delegate::broadcast` 의 스냅샷 비용 🟢

### 위치
`ServerEngine/include/Core/Struct.h:150-159`

```cpp
void broadcast(ARGS... Args) const
{
    auto snapshot = _delegates;   // ← 매 broadcast 마다 vector copy
    for (const auto& entry : snapshot)
        if (entry._func) entry._func(Args...);
}
```

### 문제
- `_delegates` 는 `std::vector<delegate_entry>` (각 entry 가 `std::function`). `std::function` 복사는 small object optimization 안 들어가면 힙 할당 → broadcast 마다 N 번의 malloc.
- 고빈도 broadcast (예: 매 프레임 label 변경 후처리) 가 들어오면 성능 저하.

### 수정 방향
- generation counter 패턴: broadcast 시작 시 generation 캡처, 콜백에서 add/remove 한 항목은 다음 broadcast 부터 반영.
- 또는 broadcast 도중 remove 는 "사망 마킹" 으로 처리하고 다음 cleanup pass 에서 실제 제거.

---

## 3. `delegate::bind_raw` / `add_raw` 의 수명 보호 부재 🟠

### 위치
`ServerEngine/include/Core/Struct.h:51-57, 115-119`

```cpp
template<typename T>
void bind_raw(T* Obj, void(T::* Method)(ARGS...))
{
    _func = [Obj, Method](ARGS... Args) { (Obj->*Method)(...); };
}
```

### 문제
- `Obj` 가 람다에 raw pointer 로 들어가므로, `Obj` 소멸 후 콜백 호출 시 use-after-free.
- 짝꿍 `bind_sp` / `add_sp` 는 `weak_ptr` 로 안전하게 처리되어 있는데, raw 버전은 위험.

### 수정 방향
- 이름을 `bind_unsafe` / `add_unsafe` 로 바꾸거나 docstring 에 "호출자가 수명을 보장해야 한다" 명시.
- 가능하면 raw 변형을 삭제. 거의 모든 사용처는 shared_ptr 변형으로 대체 가능.

---

## 4. `LogBuffer::add` 의 다중 문제 🟠

### 위치
`ServerEngine/include/ServerDialog.h:10-26`

```cpp
void add(const char* fmt, ...) {
    char buf[512];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    ...
    lines.push_back(...);
    if (lines.size() > 256)
        lines.erase(lines.begin());   // O(N) — 매번 256 이동
    scrollToBottom = true;
}
```

문제:
1. **`localtime` 비-스레드안전** (이미 P0 에서 언급).
2. **`lines.erase(begin)` 가 O(N)** — `std::deque` 로 변경하거나 ring buffer 사용.
3. **512 바이트 잘림** — 긴 로그가 truncate 됨. truncated 표시도 없음.
4. **lock 부재** — 멀티스레드에서 호출 시 vector race.

### 수정 방향
```cpp
class LogBuffer {
    std::deque<std::string> lines;
    std::mutex mtx;
    static constexpr size_t kMax = 256;
public:
    void add(std::string msg) {
        std::lock_guard lk(mtx);
        lines.push_back(std::move(msg));
        if (lines.size() > kMax) lines.pop_front();
    }
    // draw() 도 lock 필요
};
```
포매팅은 호출자가 `std::format` 또는 `string_util::format` 으로 미리 해결 후 string 전달.

---

## 5. `ImGui::InputText("##port", portBuf, sizeof(portBuf), ...)` 의 buffer 크기 부족 🟢

### 위치
`ServerEngine/include/ServerDialog.h:117, 259`

```cpp
char portBuf[8] = "7777";
```

### 문제
- 8 바이트는 5-digit 포트("65535\0") 와 IPv6 zone-id 등을 고려하면 빠듯. 사용자가 길게 입력하면 즉시 잘림.
- 더 큰 문제: 포트 외의 IP/Host 같은 필드를 같은 패턴으로 만들 때 8 바이트로는 부족.

### 수정 방향
- 최소 16~32 바이트, 가능하면 `std::array<char, 64>`.
- 또는 `dialog::editable_text` 로 통일.

---

## 6. `string_util::vformat` 의 길이 계산 후 재포매팅 두 번 호출 🟢

### 위치
`ServerEngine/src/Util.cpp:7-20`

```cpp
const int len = std::vsnprintf(nullptr, 0, Fmt, args_copy);
...
std::vsnprintf(result.data(), len + 1, Fmt, Args);  // 원본 args 그대로 재사용
```

### 문제
- `vsnprintf` 가 va_list 를 소비 (UB 아님, 그러나 일부 ABI 에서 두 번째 호출이 잘못된 결과). `va_copy` 로 안전하게 만든 것은 첫 번째 호출이라서 OK. 두 번째 호출은 원본 `Args` 를 그대로 사용 → 정의된 동작이긴 하지만 fragile.
- `len <= 0` 만 검사. `vsnprintf` 는 인코딩 오류 시 -1 반환. `len < 0` 만 명시적 처리하고 `len == 0` (빈 문자열) 은 OK 로 처리해야 함.

### 수정 방향
- 두 번째 `vsnprintf` 에도 `va_copy` 적용.
- 길이 검사 `if (len < 0) return {};` 로 명확히.
- 더 안전한 대안: `std::format` 도입.

---

## 7. `dialog::editable_text` 의 `_text.data()` 직접 수정 🟠

### 위치
`ServerEngine/src/ServerDlgUtil.cpp:64-66`

```cpp
void editable_text::draw() {
    ImGui::InputText(_label.c_str(), _text.data(), _text.size(), _flags);
}
```

### 문제
- C++17 이후 `std::string::data()` 가 mutable pointer 를 반환하지만, `_text.size()` 는 capacity 가 아닌 size. 즉 `InputText` 가 size 만큼만 사용한다고 가정하지만 ImGui 는 끝에 null terminator 를 보장.
- `_text.resize(Buffer)` 로 미리 잡은 경우 size 와 capacity 가 일치하지만, 사용자가 짧게 입력하면 `_text` 안에 중간에 `\0` 이 박힌 채 size 는 여전히 Buffer.
- 결과: `_text == "abc\0\0\0..."` 인 상태로 다른 곳에서 사용 시 의도와 다름.

### 수정 방향
```cpp
void editable_text::draw() {
    if (ImGui::InputText(_label.c_str(), _text.data(), _text.size(), _flags))
        _text.resize(std::strlen(_text.c_str()));  // 실제 길이로 잘라냄
}
```
또는 별도 `_buffer: std::vector<char>` 와 `_value: std::string` 분리.

---

## 8. `glfwInit` / `glfwTerminate` 가 main 외부에서 호출됨 🟢

### 위치
`server_dialog_base::init/terminate` — Meyers singleton 으로 호출되므로 사실상 `main()` 안에서 호출되긴 하지만, 만약 `main` 의 `return` 이후에도 어떤 path 로 `glfwTerminate` 가 호출되면 위험. 현재는 OK 이지만, atexit-style 자동 호출로 바꾸지 말 것.

---

## 9. `main()` 의 init/run/terminate 가 실패 처리 없음 🟢

### 위치
`Server/TestServer/src/main.cpp:5-9`

```cpp
test_server_dialog::get_instance().init();
test_server_dialog::get_instance().run();
test_server_dialog::get_instance().terminate();
```

### 문제
- `init()` 반환값 `bool` 무시. 실패해도 `run()` 진입.
- `terminate()` 가 실패해도 무시.
- 예외 발생 시 (현재는 안 던지지만 추후 가능) `terminate` 가 호출되지 않음 → GL 컨텍스트 누수.

### 수정 방향
```cpp
auto& dlg = test_server_dialog::get_instance();
if (!dlg.init()) {
    std::fprintf(stderr, "init failed\n");
    return 1;
}
const int rc = dlg.run();
dlg.terminate();
return rc;
```
RAII 로 `terminate` 자동화하면 더 좋음.
