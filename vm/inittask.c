#include "include/utalk-vm.h"

void colourChangingTask ()
{
    while (1)
    {
	byte * p = ATTRBLOCK(0,0);
	byte a = *p;
	a = (a & 0xF8) | ((a & 7)+1)&7;

	for (byte i = 32; i > 0; --i)
	{
	    *(p++) = a;
	}

	__asm
	    halt
	__endasm;
    }
}

void animatingTask ()
{
    while (1)
    {
	byte c = 0;
	byte * ptr = SCREENLINE(0);
	SCANLINE(ptr,c)[31] = 0;
	c = (c+1)&0x7;
	SCANLINE(ptr,c)[31] = 0xFF;

       	__asm
	    halt
	__endasm;
    }
}

void inittask_main ()
{
    puts("\n\nInit booting...\n");
    sched_starttask (colourChangingTask);
    sched_starttask (animatingTask);
    while (1) { 
	sched_suspend ();
	puts ("Init resumed from suspend ?!");
       	__asm
	    halt
	__endasm;
    }
}

