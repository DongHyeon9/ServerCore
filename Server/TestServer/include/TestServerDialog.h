#pragma once
#include "ServerDialog.h"

class TestServerDialog : public server_dialog_base<TestServerDialog>
{
protected:
	bool init_impl() override
	{
		// Custom initialization for TestServerDialog
		return true;
	}
};
