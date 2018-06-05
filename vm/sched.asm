	;;
	;; Microtalk task scheduler
	;;
	;; Interacts with the task switcher which is part of the timer
	;; tick (RST 38h) interrupt handler.
	;;

	;; Exported symbols
	XDEF _sched_tasks, _sched_task_current, _sched_init
	XDEF _sched_yield_to_task, _sched_suspend, _ticks
	XDEF _sched_starttask, _sched_queue_insert, _sched_killcurrent
	XDEF _sched_invoketask
	XDEF TASK_STACK_SIZE, TASK_FLAG_ALLOCATED, TASK_FLAG_PRIORITY_MASK
	XDEF TASK_PRIORITY_HIGHEST, TASK_PRIORITY_MEDIUM
	XDEF TASK_PRIORITY_LOW, TASK_PRIORITY_IDLE, TASK_FLAG_TAIL
	
	;; Imported symbols
	XREF _idletask_main, _inittask_main
	
	;; align data here to a 256-byte boundary in order to simplify
	;; access to the task table (which needs fast access in order to
	;; minimize overhead in the task switcher)
	
	SECTION bss_align_256
	ORG 0x5c00

	;; Constants
	
	;; TASK_STACK_SIZE: amount of memory to allocate to each task's stack
	;;  (a task may be created with a specified stack, in which case this
	;;  setting isn't used)
	defc TASK_STACK_SIZE = 0x100

	;; TASK_FLAG_ALLOCATED: flag value to indicate that the task table entry
	;;  is in use.
	defc TASK_FLAG_ALLOCATED=1

	;; TASK_FLAG_PRIORITY_MASK: mask to extract task priority from the
	;;  task flags. Numerically lower priorities are allocated CPU after
	;;  numerically higher priorities.
	defc TASK_FLAG_PRIORITY_MASK = 0x06

	;; TASK_PRIORITY_xxxx: symbolic values for defined task priorities
	defc TASK_PRIORITY_HIGHEST = 0x06
	defc TASK_PRIORITY_MEDIUM  = 0x04
	defc TASK_PRIORITY_LOW     = 0x02
	defc TASK_PRIORITY_IDLE    = 0x00

	;; TASK_FLAG_TAIL: indicates that new tasks should always be added before
	;; this one
	defc TASK_FLAG_TAIL = 0x80
	
_sched_tasks:
	;; entries for 16 tasks (uses 64 bytes)
	
;; each entry looks like this:
	defb 0			; task flags (see TASK_FLAG_XXXX above)
	defb 0                  ; bits 2-4: next task index; bit 7: hold for next tick
	defw 0			; saved SP
	;; remaining entries:
	defw 0,0		; entry 1
	defw 0,0		; entry 2
	defw 0,0		; entry 3
	defw 0,0		; entry 4
	defw 0,0		; entry 5
	defw 0,0		; entry 6
	defw 0,0		; entry 7
	defw 0,0		; entry 8
	defw 0,0		; entry 9
	defw 0,0		; entry a
	defw 0,0		; entry b
	defw 0,0		; entry c
	defw 0,0		; entry d
	defw 0,0		; entry e
	defw 0,0		; entry f

_sched_task_current:
	;; 
	;; pointer to current task entry (although note that the
	;; high order byte is constant, and the same as the high
	;; order byte of the address of the pointer, so can be 
	;; ignored in many circumstances -- it is only provided
	;; for convenience).
	;;
	;; note that there must always be a current task; we
	;; set up task F as an always-runnable task that performs
	;; background operations (e.g. garbage collection / heap
	;; compacting / etc) so that there is always something
	;; to default to.
	;; 
	defw 0

_ticks:
	;; counter timer tick (50Hz / 60Hz on Timex machines) interrupts
	defw 0
	
	;; allocate 61 bytes here for the task F stack
_taskf_stack_base:
	defs 60, 0
_taskf_stack_top:

_task0_stack_base:
	defs 128, 0
_task0_stack_top:	
	
	section code_user

	;;
	;; _sched_yield_to_task
	;;
	;; switch task and reschedule current task
	;;
	;; to call:
	;;     b    task to invoke (must NOT be the idle task)
	;;    sp    pointer to stack containing ip and other registers
	;;          required to allow the current task to resume
	;;    *     all other registers saved on stack (if required)
	;;
	;; after execution:
	;;    indicated task starts executing
	;;    current task is reinserted in queue at appropriate point
	;;    for its priority
	;;
	;; NOTE this function currently has the linked list insert
	;; inlined for performance reasons. This costs ~30 bytes and
	;; saves ~20 cycles per invocation, so may not be a good tradeoff.
	;;
	
_sched_yield_to_task:
	;; save current task stack
	ld ix, (_sched_task_current)
	ld hl, 0
	add hl, sp
	ld (ix+2), l
	ld (ix+3), h

	;; reinsert current task in appropriate location in the list
	ld a, (ix+0)		; current task flags byte
	and TASK_FLAG_PRIORITY_MASK
	ld c, a			; keep this for comparisons later
	ld d, ixh		; save current task pointer
	ld e, ixl
	ld ixl, b		; first entry to consider inserting after is the new current task
	push de			; save current task entry pointer
	
	;; check if ix points to the entry to insert into
check_insert_here:	
	ld e, (ix+1)		; de points to next entry
	ld a, (de)		; get flags
	or a			; sets bit 7 -> sign flag
	jp m, insert_here	; if bit 7 is set, the next task is the enforced tail, so insert before it
	and TASK_FLAG_PRIORITY_MASK
	cp c			; otherwise check against current priority
	jp m, insert_here	; current priority > next item priority, so insert before it
	ld ixl, e		; move to next entry
	jr check_insert_here	; and repeat

insert_here:
	;; (ix) is the task after which the current task should be placed in the list
	;; (de) is the next task after that in the list
	pop hl			; task to be inserted
	ld (ix+1), l		; link (ix) -> current
	inc l
	ld (hl), e		; link current -> (de)
	
	;; store new task as head of list
	ld l, _sched_task_current & 0xFF ; h is already correct
	ld (hl), b
	
	;; switch task
	ld ixl, b
	ld l, (ix+2)
	ld h, (ix+3)
	ld sp, hl
	ei			; ensure interrupts are enabled in every task
	ret
	

	;; 
	;; _sched_suspend
	;;
	;; suspend the current task and switch to the next task, without
	;; reinserting the current task in the queue
	;;
	;; to call:
	;;    sp - the current task's stack pointer, with ip and any required
	;;         registers saved on the stack
	;;
_sched_suspend:
	;; save current task stack
	ld ix, (_sched_task_current)
	ld hl, 0
	add hl, sp
	ld (ix+2), l
	ld (ix+3), h

	;; store next task entry as current task
	ld a, (ix+1)
	ld (_sched_task_current), a

	;; switch task
	ld ixl, a
	ld l, (ix+2)
	ld h, (ix+3)
	ld sp, hl
	ei
	ret

	;;
	;; _sched_init
	;;
	;; creates scheduler structures, intializes task f (the idle task) and task 0
	;; (initial task)
	;;
	;; task F is initialised with the following:
	;;   flags = TASK_PRIORITY_IDLE|TASK_FLAG_TAIL|TASK_FLAG_ALLOCATED
	;;   stack = _taskf_stack_top - 2
	;;   stack contents = saved IP (_idletask_main)
	;;   scheduling queue link = self
	;;
	;; task 0 is initialised with the following:
	;;   flags = TASK_PRIORITY_MEDIUM|TASK_FLAG_ALLOCATED
	;;   scheduling queue link = task F, don't reschedule next time slice
	;;
	;; task 0 is then set as the current task and executed with
	;; stack set to _task0_stack_top starting at _inittask_main
	;; interrupts are enabled in im 1 prior to launching inittask.
	;;
	;; this procedure does not return.

_sched_init:
	;; initialize idle task
	ld ix, _sched_tasks
	ld hl, _taskf_stack_top - 2
	
	ld (ix+60), 0x81
	ld (ix+61), 0x3C
	ld (ix+62), l
	ld (ix+63), h
	ld de, _idletask_main
	ld (_taskf_stack_top - 2), de

	;; initialize init task (don't need to store stack, as we'll
	;; start executing it directly - just set up sp instead)
	ld (ix+ 0), 0x07
	ld (ix+ 1), 0xBC
	ld sp, _task0_stack_top

	;; set current task ref
	xor a
	ld l, a
	ld (_sched_task_current), hl	; assumes that _taskf_stack_top is in task table's page

	;; enable interrupts and jump to main task
	im 1
	ei
	jp _inittask_main

	;;
	;; _sched_starttask
	;;
	;; creates a new task with default stack size and normal
	;; priority, and begins executing at a specified address. a
	;; return value is pushed onto the stack that causes the
	;; task to exit if the code executes a return.
	;;
	;; on entry:
	;;   hl - location of function to execute
	;;
	;; on successful return:
	;;   hl - contains task descriptor pointer
	;;   zero flag clear (unless new task is number 0, which shouldn't happen)
	;;
	;; on failure:
	;;   hl - zero
	;;   zero flag set
	;;
	
_sched_starttask:
	ex de, hl
	ld hl, _sched_tasks
	ld c, 16
	;; prevent interrupts while the task control structures are changing
	di	
find_free_task:
	ld a, (hl)
	and a, TASK_FLAG_ALLOCATED
	jr z, found_free_task
	ld a, l
	add a, 16
	ld l, a
	djnz find_free_task
	;; set up failure return
	ei
	xor a
	ld l, a
	ld h, a
	ret

found_free_task:	
	ld c, l			; store this temporarily
	ld (hl), TASK_PRIORITY_MEDIUM|TASK_FLAG_ALLOCATED
	inc l			; task queue link will be filled in later
	inc l

	;;
	;; FIXME for now we preallocate stacks for tasks
	;; 1 - 14 in the range 0x6000 to 0x6c00; so
	;; initial stack top becomes 0x6000 + (taskofs<<6)
	;; (we assume that tasks 0 and 15 never terminate
	;; so cannot be allocated via this call)
	;;
	;; we preinitialize the stack pointer with top-4
	;; because we start the process with the stack
	;; preloaded with (function to call) (_sched_killcurrent)
	;;
	
	ld a, c
	srl a
	srl a
	add a, 0x5F

	ld (hl), a
	inc l
	ld (hl), 0xFC
	
	;; prefill the stack
	ex de, hl
	ld h, a
	ld l, 0xFC
	ld (hl), e
	inc l
	ld (hl), d
	inc l
	ld (hl), _sched_killcurrent & 0xFF
	inc l
	ld (hl), _sched_killcurrent / 0x100
	ex de, hl
	
	;; schedule task
	ld l, c
	call _sched_queue_insert_intdisabled
	dec l 			; reverse change done by _sched_queue_insert
	ret


	;; 
	;; _sched_queue_insert
	;;
	;; inserts a task into the appropriate location in the scheduler queue
	;;
	;; on entry:
	;;   hl   - pointer to task structure to insert into queue
	;;
	;; on entry to alternative entry point _sched_queue_insert_intdisabled:
	;;   hl   - as above
	;;   interrupts disabled
	;;
	;; on exit:
	;;   hl   - task structure + 1
	;;   ix   - previous task
	;;   de   - next task
	;;   task inserted into queue in location (other than head) that is
	;;   appropriate for its priority
	;;   interrupts enabled
	;; 

_sched_queue_insert:
	di				; disable interrupts while modifying task structures
_sched_queue_insert_intdisabled:	
	ld a, (hl)			; current task flags byte
	and TASK_FLAG_PRIORITY_MASK
	ld c, a				; keep this for comparisons later
	ld ix, (_sched_task_current)	; first entry to consider inserting after is the current task
	ld d, h				; for making pointers to next entries
	
	;; check if ix points to the entry to insert into
sqi_check_insert_here:	
	ld e, (ix+1)			; de points to next entry
	ld a, (de)			; get flags
	or a				; sets bit 7 -> sign flag
	jp m, sqi_insert_here		; if bit 7 is set, the next task is tail, so insert before it
	and TASK_FLAG_PRIORITY_MASK
	cp c				; otherwise check against current priority
	jp m, sqi_insert_here		; current priority > next item priority, so insert before it
	ld ixl, e			; move to next entry
	jr sqi_check_insert_here	; and repeat

sqi_insert_here:
	;; (ix) is the task after which the required task should be placed in the list
	;; (de) is the next task after that in the list
	;; (hl) is the task to insert
	ld (ix+1), l		; link (ix) -> current
	inc l
	ld (hl), e		; link current -> (de)
	ei			; reenable interrupts before returning
	ret
	

	;;
	;; _sched_killcurrent
	;;
	;; terminates the current task, and reschedules to the next thread in the list
	;;
	;; on entry: no specific requirements
	;; does not return to caller
	;;

_sched_killcurrent:
	di				; disable interrupts while modifying task state
	ld hl, (_sched_task_current)
	ld (hl), 0			; mark task block as available
	inc hl
	ld a, (hl)			; get next task pointer
	and a, 0x3C			; mask out extra flag bits
	ld l,a				; hl = current task pointer

	;; fall through to sched_invoketask

	;;
	;; _sched_invoketask
	;;
	;; switches to a selected task without rescheduling the current task
	;; saving stack state or updating the scheduler queue
	;;
	;; on entry:
	;;   hl - pointer to task descriptor to switch to
	;; does not return to caller
	;; 
_sched_invoketask:
	ld a, l
	ld (_sched_task_current), a	; set current task ref
	inc l				; find correct stack pointer location
	inc l
	ld e, (hl)			; load stack pointer
	inc l
	ld d, (hl)
	ex de, hl
	ld sp, hl
	ei				; ensure interrupts enabled
	ret				; restart task
	
	
