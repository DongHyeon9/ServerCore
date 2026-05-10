#pragma once
#include "ServerDialog.h"

class test_server_dialog : public server_dialog_base<test_server_dialog>
{
protected:
	void pre_init_impl() override;
	bool init_impl() override;

};
