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
	virtual ~singleton() = default;
	singleton(const singleton&) = delete;
	singleton& operator=(const singleton&) = delete;
};

class delegate_handle
{
public:
	delegate_handle() : _id(0) {}
	explicit delegate_handle(uint64 id) : _id(id) {}

	bool is_valid() const noexcept { return _id != 0; }
	uint64 get_id() const noexcept { return _id; }

	bool operator==(const delegate_handle& Other) const noexcept { return _id == Other._id; }
	bool operator!=(const delegate_handle& Other) const noexcept { return _id != Other._id; }

private:
	uint64 _id;
};

template<typename... ARGS>
class delegate
{
public:
	using func_type = std::function<void(ARGS...)>;

	void bind(func_type Func)
	{
		_func = std::move(Func);
	}

	template<typename T>
	void bind_raw(T* Obj, void(T::* Method)(ARGS...))
	{
		_func = [Obj, Method](ARGS... Args) {
			(Obj->*Method)(std::forward<ARGS>(Args)...);
			};
	}

	template<typename T>
	void bind_sp(std::shared_ptr<T> Obj, void(T::* Method)(ARGS...))
	{
		std::weak_ptr<T> weak = Obj;
		_func = [weak, Method](ARGS... Args) {
			if (auto sp = weak.lock())
				(sp.get()->*Method)(std::forward<ARGS>(Args)...);
			};
	}

	void unbind() noexcept { _func = nullptr; }
	bool is_bound() const noexcept { return static_cast<bool>(_func); }

	void execute(ARGS... Args) const
	{
		if (_func)
			_func(std::forward<ARGS>(Args)...);
	}

	bool execute_if_bound(ARGS... Args) const
	{
		if (_func)
		{
			_func(std::forward<ARGS>(Args)...);
			return true;
		}
		return false;
	}

private:
	func_type _func;
};

// 멀티캐스트 델리게이트
template<typename... ARGS>
class multicast_delegate
{
public:
	using func_type = std::function<void(ARGS...)>;

	struct delegate_entry
	{
		delegate_handle _handle;
		func_type _func;
		delegate_entry(delegate_handle Handle, func_type Func) : _handle(Handle), _func(std::move(Func)) {};
	};

	// 람다/함수 객체 바인딩
	delegate_handle add(func_type Func)
	{
		delegate_handle handle{ ++_next_id };
		_delegates.emplace_back(handle, std::move(Func));
		return handle;
	}

	// 멤버 함수 바인딩 (raw pointer)
	template<typename T>
	delegate_handle add_raw(T* Obj, void(T::* Method)(ARGS...))
	{
		return add([Obj, Method](ARGS... Args) {(Obj->*Method)(std::forward<ARGS>(Args)...); });
	}

	// 멤버 함수 바인딩 (shared_ptr - 안전한 lifetime)
	template<typename T>
	delegate_handle add_sp(std::shared_ptr<T> Obj, void(T::* Method)(ARGS...))
	{
		std::weak_ptr<T> weak = Obj;
		return add([weak, Method](ARGS... Args) {
			if (auto sp = weak.lock())
				(sp.get()->*Method)(std::forward<ARGS>(Args)...);
			});
	}

	// 핸들로 제거
	bool remove(delegate_handle Handle)
	{
		auto it = std::find_if(_delegates.begin(), _delegates.end(), [Handle](const delegate_entry& Entry) { return Entry._handle == Handle; });

		if (it != _delegates.end())
		{
			_delegates.erase(it);
			return true;
		}
		return false;
	}

	void clear() noexcept { _delegates.clear(); }
	bool is_bound() const noexcept { return !_delegates.empty(); }
	size_t num() const noexcept { return _delegates.size(); }

	// 모든 바인딩된 함수 호출
	void broadcast(ARGS... Args) const
	{
		// 복사본으로 순회 - 콜백 내부에서 add/remove 되어도 안전
		auto snapshot = _delegates;
		for (const auto& entry : snapshot)
		{
			if (entry._func)
				entry._func(Args...);
		}
	}

private:
	std::vector<delegate_entry> _delegates{};
	uint64 _next_id{};
};