/* -*- c -*- */

// describes the expected memory layout and runtime customisations
// in use to the C compiler/linker/app builder

#pragma output CRT_ORG_CODE=0x0000
#pragma output CRT_ORG_DATA=0x5B00
#pragma output CRT_ORG_BSS=-1
#pragma output CRT_MODEL=1
#pragma output CRT_INCLUDE_PREAMBLE=1
#pragma output CRT_INITIALIZE_BSS=0

#pragma output CLIB_OPT_PRINTF=0x7607
#pragma output CLIB_MALLOC_HEAP_SIZE = 0   
#pragma output CRT_ENABLE_CLOSE = 0
#pragma output CLIB_EXIT_STACK_SIZE = 0
#pragma output CLIB_STDIO_HEAP_SIZE = 0
#pragma output CRT_STACK_SIZE = 256
//#pragma output CLIB_FOPEN_MAX = -1
//#pragma output CLIB_OPEN_MAX = -1
