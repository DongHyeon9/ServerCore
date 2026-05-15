#include "TestServerDialog.h"

void test_server_dialog::pre_init_impl()
{

}

bool test_server_dialog::init_impl()
{
	{// ── 메인 메뉴 ─────────────────────────────────────────────────────────────
		std::shared_ptr<dialog::main_menu> menu{ std::make_shared<dialog::main_menu>() };
		auto file = dialog::util::create_component<dialog::menu_bar>("File");
		auto exit = dialog::util::create_component<dialog::menu_item>("Exit");
		exit->set_event(std::bind(&test_server_dialog::close_dialog, this));
		file->add_item(exit);
		menu->add_item(file);
		_items.emplace("main_menu", menu);
	}

	return true;
}
