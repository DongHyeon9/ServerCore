#pragma once
#include <system_error>
#include <string>
#include <type_traits>

namespace boost {
namespace system {

using error_category  = std::error_category;
using error_condition = std::error_condition;

inline const std::error_category& system_category()  noexcept { return std::system_category(); }
inline const std::error_category& generic_category() noexcept { return std::generic_category(); }

template<typename T>
struct is_error_code_enum : std::false_type {};

class error_code {
    int _val = 0;
    const std::error_category* _cat = &std::system_category();
public:
    error_code() noexcept = default;
    error_code(int val, const std::error_category& cat) noexcept : _val(val), _cat(&cat) {}

    template<typename E,
             typename std::enable_if<is_error_code_enum<E>::value, int>::type = 0>
    error_code(E e) noexcept {
        *this = make_error_code(e);
    }

    template<typename E,
             typename std::enable_if<is_error_code_enum<E>::value, int>::type = 0>
    error_code& operator=(E e) noexcept {
        *this = make_error_code(e);
        return *this;
    }

    void assign(int val, const std::error_category& cat) noexcept { _val = val; _cat = &cat; }
    void clear() noexcept { _val = 0; _cat = &std::system_category(); }

    int value() const noexcept { return _val; }
    const std::error_category& category() const noexcept { return *_cat; }
    std::string message() const { return _cat->message(_val); }

    explicit operator bool() const noexcept { return _val != 0; }

    bool operator==(const error_code& rhs) const noexcept {
        return _val == rhs._val && _cat == rhs._cat;
    }
    bool operator!=(const error_code& rhs) const noexcept { return !(*this == rhs); }
    bool operator<(const error_code& rhs) const noexcept {
        return _cat < rhs._cat || (_cat == rhs._cat && _val < rhs._val);
    }

    template<typename E,
             typename std::enable_if<is_error_code_enum<E>::value, int>::type = 0>
    bool operator==(E e) const noexcept { return *this == make_error_code(e); }

    template<typename E,
             typename std::enable_if<is_error_code_enum<E>::value, int>::type = 0>
    bool operator!=(E e) const noexcept { return !(*this == e); }

    operator std::error_code() const noexcept { return std::error_code(_val, *_cat); }
};

template<typename E,
         typename std::enable_if<is_error_code_enum<E>::value, int>::type = 0>
bool operator==(E e, const error_code& ec) noexcept { return ec == e; }

template<typename E,
         typename std::enable_if<is_error_code_enum<E>::value, int>::type = 0>
bool operator!=(E e, const error_code& ec) noexcept { return ec != e; }

} // namespace system
} // namespace boost
