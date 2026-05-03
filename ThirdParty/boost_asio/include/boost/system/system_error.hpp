#pragma once
#include <system_error>
#include "error_code.hpp"

namespace boost {
namespace system {

class system_error : public std::exception {
    error_code _ec;
    std::string _what;
public:
    system_error(error_code ec) : _ec(ec), _what(ec.message()) {}
    system_error(error_code ec, const std::string& what_arg)
        : _ec(ec), _what(what_arg + ": " + ec.message()) {}
    system_error(error_code ec, const char* what_arg)
        : _ec(ec), _what(std::string(what_arg) + ": " + ec.message()) {}

    const error_code& code() const noexcept { return _ec; }
    const char* what() const noexcept override { return _what.c_str(); }
};

} // namespace system
} // namespace boost
