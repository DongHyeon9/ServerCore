#include "TestServerDialog.h"

int main()
{
    TestServerDialog::get_instance().init();
    TestServerDialog::get_instance().run();
    TestServerDialog::get_instance().terminate();

    return 0;
}
