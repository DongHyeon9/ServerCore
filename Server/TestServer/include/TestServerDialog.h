#pragma once
#include "ServerDialog.h"

class test_server_dialog : public server_dialog_base<test_server_dialog>
{
protected:
	bool init_impl() override
	{
		return true;
	}
};
