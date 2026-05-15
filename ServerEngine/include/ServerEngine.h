#pragma once
#include "Core/Struct.h"
#include "Core/Preprocess.h"

DECLARE_MULTICAST_DELEGATE(on_label_change_delegate, const std::string&/*Before*/, const std::string&/*After*/);