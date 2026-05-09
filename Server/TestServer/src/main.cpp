#include "TestServerDialog.h"

int main()
{
    test_server_dialog::get_instance().init();
    test_server_dialog::get_instance().run();
    test_server_dialog::get_instance().terminate();

    return 0;
}
