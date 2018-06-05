// TODO this should probably be rewritten in assembly language for performance
// reasons, but I really can't be bothered right now.

#include "vm/include/utalk-vm.h"

byte curs_x, curs_y, attrib;

void scrollUp ()
{
    // FIXME move screen content up too!
    curs_y --;
}

void _f(putch(char ch))
{
    byte * line;
    
    if (ch == '\n' || curs_x == 32)
    {
	curs_x = 0;
	curs_y ++;
	if (curs_y > 24) scrollUp ();
	if (ch == '\n') return;
    }
    *ATTRBLOCK(curs_y,curs_x) = attrib;
    line = SCREENLINE(curs_y) + (curs_x++);
    if (ch <= 32)
    {
	for (byte i = 0; i < 8; i ++)
	    *SCANLINE(line,i) = 0;
    }
    else
    {
	byte * fontent = font8x8_basic + ((ch - 32)<<3);
	for (byte i = 0; i < 8; i ++)
	    *SCANLINE(line,i) = *(fontent++);
    }
}

void _f(puts(const char * str))
{
    while (*str)
	putch(*(str++));
}

void init_disp ()
{
    attrib = 0x47; /* flash(0) bright(1) paper(000) ink (111) */
    curs_x = 0;
    curs_y = 0;
}
