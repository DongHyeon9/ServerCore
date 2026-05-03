#pragma once
#include "Type.h"

template<class T>
class singleton
{
public:
	static T& get_instance()
	{
		static T inst;
		return inst;
	}

	virtual bool init() = 0;
	virtual void terminate() = 0;

protected:
	singleton() = default;
	~singleton() = default;
	singleton(const singleton&) = delete;
	singleton& operator=(const singleton&) = delete;
};