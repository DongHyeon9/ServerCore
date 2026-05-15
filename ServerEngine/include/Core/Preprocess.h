#pragma once

#define DECLARE_DELEGATE(Delegate_Name, ...) using Delegate_Name = delegate<__VA_ARGS__>
#define DECLARE_MULTICAST_DELEGATE(Delegate_Name, ...) using Delegate_Name = multicast_delegate<__VA_ARGS__>