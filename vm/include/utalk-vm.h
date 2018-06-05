#define _f(decl) decl __z88dk_fastcall
#define SCREENLINE(y) ((char *) (0x4000 | (((y)&0x18)<<8) | ((y)&7)<<5))
#define SCANLINE(base,line) ((char *)(((unsigned int)(base)|((line)<<8))))
#define ATTRBLOCK(y,x) ((char *) (0x5800 | ((y)<<5) | (x)))

typedef unsigned char byte;

// =========================================================================
// module vm/init.asm
// =========================================================================

extern const char copyright[];
//  _memsetdw is not usable from C, as it requires reg params
void halt ();
void ret ();

// =========================================================================
// module vm/font8x8_basic.c
// =========================================================================
extern byte font8x8_basic[];

// =========================================================================
// module vm/disp.c
// =========================================================================
extern byte curs_x, curs_y, atrib;

void init_disp ();
void scrollUp ();
void _f(putch(char));
void _f(puts(const char *));

// =========================================================================
// module vm/sched.asm
// =========================================================================
typedef struct sched_task
{
    byte flags;
    byte link;
    void * saved_sp;
} TASK, *HTASK;

typedef void (*PFN_VOID) ();
    
extern TASK  sched_tasks[];
extern HTASK sched_task_current;
extern unsigned int ticks;

#define TASK_FLAG_ALLOCATED     0x01
#define TASK_FLAG_PRIORITY_MASK 0x06
#define TASK_FLAG_TAIL          0x80
#define TASK_PRIORITY_HIGHEST   0x06
#define TASK_PRIORITY_MEDIUM    0x04
#define TASK_PRIORITY_LOW       0x02
#define TASK_PRIORITY_IDLE      0x00

void      sched_suspend      ();
HTASK _f( sched_starttask    (PFN_VOID task_main) );
void _f(  sched_queue_insert (HTASK task)         );
void _f(  sched_killcurrent  ()                   );
void _f(  sched_invoketask   (HTASK task)         );

