#include "include/utalk-vm.h"

void idletask_main ()
{
    while (1)
    {
	__asm
	    halt
	__endasm;
    }
}
