#include "Util.h"
#include <cstdarg>
#include <cstdio>

namespace string_util
{
	static std::string vformat(const char* Fmt, va_list Args)
	{
		va_list args_copy;
		va_copy(args_copy, Args);
		const int len = std::vsnprintf(nullptr, 0, Fmt, args_copy);
		va_end(args_copy);

		if (len <= 0)
			return {};

		std::string result(static_cast<size_t>(len), '\0');
		std::vsnprintf(result.data(), static_cast<size_t>(len) + 1, Fmt, Args);
		return result;
	}

	std::string format(const char* Fmt, ...)
	{
		va_list args;
		va_start(args, Fmt);
		std::string result = vformat(Fmt, args);
		va_end(args);
		return result;
	}

	std::string format(std::string Str, ...)
	{
		va_list args;
		va_start(args, Str);
		std::string result = vformat(Str.c_str(), args);
		va_end(args);
		return result;
	}
}
