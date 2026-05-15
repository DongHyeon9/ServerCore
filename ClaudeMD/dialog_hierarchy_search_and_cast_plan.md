# dialog::interface::hierarchy 탐색 기능 / 안전한 dialog 캐스트 설계 추천

## 0. 배경

현재 `ServerEngine/include/ServerDlgUtil.h` 의 `dialog::interface::hierarchy<T>` 는 단순히 `std::vector<std::shared_ptr<T>>` 만 보유하고 `add_item / get_items / set_items` 만 제공한다. `component_base` 계열은 가상 소멸자와 `draw()` 만 가지며 RTTI 정보를 노출하지 않는다.

TODO.txt 에서 요구하는 사항은 두 가지다.

1. `dialog::interface::hierarchy` 의 **탐색 기능**.
2. `pannel_item` 등 컴포넌트를 다운캐스트할 때 `static_cast` 기반이되 **잘못된 대상이면 `nullptr` 반환**.

본 문서는 두 요구를 충족하는 후보 설계들을 비교 정리한다.

---

## 1. 탐색 기능 (search in `hierarchy<T>`)

### 1.1 요구 정리

- 트리 형태(예: `main_menu` → `menu_bar` → `menu_item`, `pannel` → `pannel_item::base` → `pannel_item::mutiple_item` → ...) 에서 **특정 컴포넌트를 식별·획득**해야 함.
- 식별 키 후보: `_label` 문자열 / 사용자 지정 ID / 타입 / 경로(`"main/file/save"`).
- 호출 빈도가 낮으면 선형 탐색으로 충분하지만, 매 프레임 호출되면 인덱싱이 필요.

### 1.2 후보 A — 라벨 기반 선형 탐색 (가장 단순, 권장 1차)

`hierarchy<T>` 에 멤버 추가:

```cpp
std::shared_ptr<T> find_by_label(std::string_view label) const
{
    for (auto& item : _items)
        if (item && item->get_label() == label)
            return item;
    return nullptr;
}

template<class Pred>
std::shared_ptr<T> find_if(Pred&& pred) const
{
    for (auto& item : _items)
        if (item && pred(*item))
            return item;
    return nullptr;
}
```

장점
- `component_base` 가 이미 `_label` 을 가지므로 추가 상태 0.
- API 일관 (단일 레벨 검색).

단점
- 트리 깊이가 깊을 때 호출자가 직접 재귀해야 함.
- 동일 라벨 중복 시 첫 항목만 반환.

### 1.3 후보 B — 재귀(트리) 탐색

`hierarchy<T>` 의 자식 자체가 다시 `hierarchy<U>` 가 될 수 있으므로(예: `menu_bar : hierarchy<menu_item>`, `pannel_item::mutiple_item : hierarchy<base>`) 다형적 재귀가 필요하다. 이를 위해선 **부모 측에서 자식이 또 다른 `hierarchy` 인지** 알아야 한다.

해법 1: `component_base` 에 가상 함수 `for_each_child(visitor)` 를 두고 hierarchy 파생 클래스가 override.

```cpp
class component_base
{
public:
    virtual void for_each_child(
        const std::function<void(component_base&)>& fn) {}
    /* ... */
};

template<class T> requires std::is_base_of_v<component_base, T>
class hierarchy
{
protected:
    void for_each_child_impl(
        const std::function<void(component_base&)>& fn)
    {
        for (auto& it : _items) if (it) fn(*it);
    }
};

// 다중 상속이라 직접 override 가능
void pannel_item::mutiple_item::for_each_child(
    const std::function<void(component_base&)>& fn) override
{
    for (auto& it : _items) if (it) fn(*it);
}
```

그 위에 자유 함수 `find_recursive`:

```cpp
namespace dialog::util
{
    component_base* find_recursive(
        component_base& root, std::string_view label)
    {
        if (root.get_label() == label) return &root;
        component_base* hit = nullptr;
        root.for_each_child([&](component_base& c){
            if (hit) return;
            if (auto* r = find_recursive(c, label)) hit = r;
        });
        return hit;
    }
}
```

장점
- 임의 깊이 트리에 일관된 API.
- 라벨/술어/타입 어느 기준으로든 일반화 가능 (`find_recursive_if`).

단점
- 모든 hierarchy 파생에 `for_each_child` override 강제 → 보일러플레이트.
- `std::function` 호출 오버헤드 (드물게 호출되면 무시 가능).

### 1.4 후보 C — 경로(path) 기반 조회

라벨 단위 트리 탐색을 `"MainMenu/File/Save"` 같은 경로 문자열로 노출.

```cpp
component_base* find_by_path(component_base& root, std::string_view path);
// 내부: '/' 분할 후 단계별로 find_by_label 수행
```

장점
- 호출자가 사람이 읽기 좋은 키로 컴포넌트를 지정 → 디버깅 GUI/스크립트 친화적.

단점
- 라벨에 `/` 사용 불가 제약.
- 경로 파싱 비용 (한 번 캐시하면 해소).

### 1.5 후보 D — 인덱싱(맵) 캐시

`hierarchy<T>` 안에 `std::unordered_map<std::string, std::weak_ptr<T>>` 같은 보조 인덱스를 두고 `add_item` 시 등록.

장점
- O(1) 라벨 조회. 매 프레임 검색이 필요한 경우 적합.

단점
- 라벨 변경(`set_label`) 시 인덱스 무효화 처리가 필요 → `component_base::set_label` 에 알림 콜백을 걸어야 함.
- 메모리·복잡도 증가.

### 1.6 후보 E — 방문자(Visitor) 패턴

`component_base` 에 `accept(visitor&)` 추가. 탐색은 `visitor` 가 책임지며 캐스트와도 자연스럽게 결합 (다음 절 참조).

장점
- 타입별 분기와 트리 순회를 한 자리에 모음.
- "특정 타입의 모든 인스턴스 수집" 같은 질의가 깔끔.

단점
- visitor 인터페이스 변경 시 모든 컴포넌트 영향.

### 1.7 추천

- **1차 도입**: 1.2(라벨/술어 단일 레벨) + 1.3(`for_each_child` 기반 재귀 자유 함수). 추가 상태 없이 기존 클래스 위에 얹을 수 있다.
- **GUI 디버깅 도구가 본격화되면**: 1.4 인덱스 캐시를 root dialog 레벨(예: `server_dialog_base::_items` 옆)에 추가.
- **경로 문자열 표기**(1.5)는 외부 스크립팅/콘솔이 생길 때 도입.

---

## 2. 잘못된 대상이면 nullptr 을 반환하는 static_cast (커스텀 RTTI)

`dynamic_cast` 가 가장 단순한 정답이지만, TODO 의 명시("static_cast 로 RTTI 구현") 와 RTTI off 옵션(`-fno-rtti`) 호환성을 고려한 대안들을 정리한다.

### 2.1 후보 A — 타입 ID enum + 가상 함수 (가장 가볍고 빠름)

```cpp
// ServerDlgUtil.h
namespace dialog
{
    enum class component_type : uint16
    {
        unknown,
        menu_item, menu_bar, main_menu,
        pannel, pannel_item_base,
        pannel_item_multiple, pannel_item_button,
        pannel_item_text, pannel_item_editable_text,
        pannel_item_rich_text, pannel_item_spacing,
        pannel_item_separator,
    };

    class component_base
    {
    public:
        virtual component_type type_id() const noexcept
            { return component_type::unknown; }
        /* 기존 멤버 ... */
    };
}

#define DIALOG_DECLARE_TYPE(EnumValue)                       \
    static constexpr ::dialog::component_type kTypeId        \
        = ::dialog::component_type::EnumValue;               \
    ::dialog::component_type type_id() const noexcept override \
        { return kTypeId; }

class menu_item : public component_base, public interface::event
{
    DIALOG_DECLARE_TYPE(menu_item)
public:
    void draw() override;
};
```

캐스트 헬퍼:

```cpp
namespace dialog::util
{
    template<class Derived>
    Derived* checked_cast(component_base* p) noexcept
    {
        static_assert(std::is_base_of_v<component_base, Derived>);
        return (p && p->type_id() == Derived::kTypeId)
            ? static_cast<Derived*>(p)
            : nullptr;
    }

    template<class Derived>
    std::shared_ptr<Derived> checked_cast(
        const std::shared_ptr<component_base>& p) noexcept
    {
        return (p && p->type_id() == Derived::kTypeId)
            ? std::static_pointer_cast<Derived>(p)
            : nullptr;
    }
}
```

장점
- `dynamic_cast` 대비 매우 빠름(가상 호출 1회 + 정수 비교).
- `-fno-rtti` 와 호환.
- 디버깅용 enum 출력이 그대로 사용 가능.

단점
- **상속 관계를 표현하지 못함**: `pannel_item::editable_text` 를 `pannel_item::text*` 로 받고 싶을 때 단순 enum 비교는 실패.
- 새 타입 추가 시 enum 갱신 필요.

### 2.2 후보 B — 비트 마스크 / 카테고리 ID (얕은 상속 표현)

타입 ID 를 비트 플래그로 두거나, "카테고리 + 세부" 2단 ID 로 두면 상속을 부분 표현 가능.

```cpp
struct type_id_t { uint32 category; uint32 leaf; };
// is-a 체크: target.category 비트가 ours 에 포함되는가
```

장점
- A 의 속도를 거의 유지하면서 부모 캐스트도 허용.

단점
- 다중 상속 처리(`button : base, event`) 가 까다로움. event 처럼 mix-in 성격 인터페이스가 있을 때 비트 충돌 관리 비용.

### 2.3 후보 C — CRTP + 정적 ID 자동 부여

`component_base` 직속 파생을 CRTP 로 감싸면 enum 을 수기로 관리하지 않아도 됨.

```cpp
template<class Self, class Base = component_base>
class typed : public Base
{
public:
    static const void* static_type_id() noexcept
    {
        static const char tag = 0;
        return &tag;          // 타입별 유일 주소
    }
    const void* type_id() const noexcept override
        { return static_type_id(); }
};

class component_base
{
public:
    virtual const void* type_id() const noexcept { return nullptr; }
    /* ... */
};

class menu_item : public typed<menu_item>, public interface::event { /* ... */ };
```

캐스트:

```cpp
template<class Derived>
Derived* checked_cast(component_base* p) noexcept
{
    return (p && p->type_id() == Derived::static_type_id())
        ? static_cast<Derived*>(p) : nullptr;
}
```

장점
- enum 중앙 관리 불필요, 새 타입 추가가 헤더 한 줄로 끝남.
- `static const char` 주소를 ID 로 쓰므로 ABI/링크 비용 없음.

단점
- 여전히 평면 비교 → 상속 사슬에서 부모로의 캐스트는 실패.
- CRTP 가 다중 상속 트리(`pannel_item::editable_text : text`) 에 끼면 약간 어색.

### 2.4 후보 D — 사슬 체크(parent chain) 로 상속까지 안전

각 파생 타입이 자기 타입 + 부모들 ID 사슬을 노출.

```cpp
class component_base
{
public:
    virtual bool is_kind_of(component_type t) const noexcept
        { return t == component_type::unknown; }
};

class pannel_item_text : public component_base
{
public:
    bool is_kind_of(component_type t) const noexcept override
        { return t == component_type::pannel_item_text
              || component_base::is_kind_of(t); }
};

class pannel_item_editable_text : public pannel_item_text
{
public:
    bool is_kind_of(component_type t) const noexcept override
        { return t == component_type::pannel_item_editable_text
              || pannel_item_text::is_kind_of(t); }
};

template<class D>
D* checked_cast(component_base* p) noexcept
{
    return (p && p->is_kind_of(D::kTypeId))
        ? static_cast<D*>(p) : nullptr;
}
```

장점
- 단일 상속 사슬에 대해 `dynamic_cast` 와 사실상 동일한 의미.
- enum 비교 N 번 (사슬 깊이만큼) → 여전히 매우 빠름.

단점
- 다중 상속 사용 중(`menu_item : component_base, interface::event`). `event` 같은 mix-in 측 캐스트는 별도 메커니즘 필요(아래 2.6).
- 모든 클래스에 `is_kind_of` override 작성.

### 2.5 후보 E — `std::type_index` 기반 (RTTI 사용, 간결)

```cpp
class component_base { public: virtual ~component_base() = default; };

template<class D>
D* checked_cast(component_base* p) noexcept
{
    return (p && typeid(*p) == typeid(D))
        ? static_cast<D*>(p) : nullptr;
}
```

장점
- 코드 변경 거의 없음.
- 새 타입 추가 시 추가 작업 0.

단점
- `-fno-rtti` 와 비호환.
- 그러나 어차피 `dynamic_cast` 를 안 쓸 거면 굳이 이 방법보다 A/C 가 더 빠르고 가벼움.

### 2.6 mix-in 인터페이스(`interface::event` 등) 캐스트

`menu_item` 은 `component_base` 와 `interface::event` 를 동시에 상속한다. enum/주소 ID 방식은 단일 사슬을 가정하므로 mix-in 으로의 캐스트가 곤란하다. 대응 패턴:

- 옵션 1: `component_base` 에 `void* query_interface(component_type)` 같은 가상 함수를 두고, 각 파생이 자기가 구현하는 인터페이스를 반환. COM 의 `QueryInterface` 와 동일한 발상.
- 옵션 2: 인터페이스 자체에 자기 식별 함수를 둠. `interface::event::as_event()` 가 자기 자신을 반환하고, `component_base` 의 기본 구현은 `nullptr` 반환.

```cpp
class component_base
{
public:
    virtual interface::event* as_event() noexcept { return nullptr; }
};

class menu_item : public component_base, public interface::event
{
public:
    interface::event* as_event() noexcept override { return this; }
};
```

호출 측은 `if (auto* e = comp->as_event()) e->set_event(...)` 로 안전하게 사용.

### 2.7 추천

조합 권장:

- **기본 캐스트**: 2.3(CRTP 자동 ID) 또는 2.4(parent-chain). 새 타입 추가 비용이 낮고 빠르다.
  - 현재 클래스 트리에 `text → editable_text/rich_text` 처럼 의미 있는 상속이 있으므로 **2.4 parent-chain** 을 1차 추천. 단순 평면 비교(2.1/2.3)는 `text` 변수에 `editable_text` 가 들어왔을 때 실패한다.
- **mix-in 인터페이스(`event`) 캐스트**: 2.6 `as_xxx()` 가상 함수. parent-chain 과 직교적으로 공존 가능.
- enum 작성이 부담스러우면 2.3 CRTP 와 parent-chain 을 합쳐 `typed<Self, Parent>` 가 `is_kind_of` 를 자동 생성하도록 만들 수 있다(템플릿으로 `Self::static_type_id() || Parent::is_kind_of(t)` 위임).

최종 캐스트 API 모양(권장):

```cpp
namespace dialog::util
{
    template<class D> D*                       try_cast(component_base*);
    template<class D> const D*                 try_cast(const component_base*);
    template<class D> std::shared_ptr<D>       try_cast(const std::shared_ptr<component_base>&);

    template<class I> I*                       query_interface(component_base*);
}
```

---

## 3. 탐색 + 캐스트가 함께 쓰이는 시나리오 예

```cpp
auto root = main_menu_root;                       // std::shared_ptr<main_menu>
auto bar  = root->find_by_label("File");          // std::shared_ptr<menu_bar>
auto item = bar ? bar->find_by_label("Save") : nullptr; // std::shared_ptr<menu_item>

if (auto* ev = item ? item->as_event() : nullptr)
    ev->set_event([]{ /* save */ });

// 패널 내부에서 텍스트 박스 골라내기
for (auto& c : my_pannel->get_items())
    if (auto et = dialog::util::try_cast<pannel_item::editable_text>(c))
        et->add_input_text_flags(ImGuiInputTextFlags_Password);
```

---

## 4. 구현 로드맵(권장 순서)

1. `component_base` 에 `is_kind_of(component_type) const noexcept` 가상 함수 + `component_type` enum 추가. (디폴트 반환 `unknown`)
2. 매크로 `DIALOG_DECLARE_TYPE(parent, leaf)` 정의 — `kTypeId` 상수 + `is_kind_of` override 자동 생성.
3. 모든 구체 dialog 클래스(`menu_item, menu_bar, main_menu, pannel`, `pannel_item::*`)에 매크로 적용.
4. `dialog::util::try_cast<D>` 템플릿 자유 함수 추가 (포인터/`shared_ptr` 오버로드 2종).
5. `interface::event` 등 mix-in 용 `as_event()` 등 query 함수 추가.
6. `hierarchy<T>` 에 `find_by_label`, `find_if` 멤버 추가.
7. `component_base` 에 `for_each_child` 가상 함수 + hierarchy 파생에서 override. 그 위에 `dialog::util::find_recursive`, `find_recursive_if` 자유 함수 작성.
8. (선택) `find_by_path` 와 라벨 인덱스 캐시는 디버깅 UI 요구가 명확해진 뒤 도입.

---

## 5. 검토 포인트 / 실패 모드

- **라벨 중복**: 동일 라벨이 형제 노드에 둘 이상 → 첫 항목만 반환되는 정책을 문서화하거나 `find_all_by_label` 을 별도 제공.
- **shared_ptr cycle**: hierarchy 가 자식 `shared_ptr` 을 보유하므로, 자식이 부모를 다시 잡으면 누수. 부모 참조가 필요해지면 `weak_ptr` 만 사용.
- **타입 ID 충돌**: enum 방식 채택 시 별도 모듈/플러그인이 추가 타입을 등록할 가능성에 대비해 `user_defined_begin = 0x8000` 같이 예약 구간을 둠. 또는 CRTP 주소-기반(2.3) 으로 가서 충돌 자체를 회피.
- **`-fno-rtti` 빌드**: 위 권장안(2.3/2.4)은 모두 RTTI 비의존. `typeid` 기반(2.5)만 제외하면 안전.
- **다중 상속**: `menu_item : component_base, interface::event` 에서 `static_cast` 는 적절한 오프셋 보정을 알아서 한다. `try_cast<event>(comp_base_ptr)` 직접 호출은 두 베이스가 한 객체에 공존함을 컴파일러가 알아야 가능 — 그래서 2.6 `as_event()` 우회가 필요.
- **성능**: 위 방식은 모두 가상 호출 ≤ 2회 + 정수 비교 수 회 수준. ImGui 프레임당 수천 회 호출도 부담 없음.
