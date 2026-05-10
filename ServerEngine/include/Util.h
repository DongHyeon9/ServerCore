#pragma once
#include "Struct.h"

namespace string_util
{
	std::string format(const char* Fmt, ...);
	std::string format(std::string Str, ...);
}