	;; ==========================================================================
	;; microtalk initialisation routines 
	;; spectrum 48K/128K
	;; ==========================================================================
	
	;; imported symbols
	XREF _init_disp, _puts, _ticks, _sched_task_current, _sched_init
	XREF TASK_FLAG_TAIL, TASK_FLAG_PRIORITY_MASK, _sched_yield_to_task

	;; exported symbols
	XDEF _copyright, _memsetdw, _main, _ret

	;; ==========================================================================
	;; reset vector
	;; ==========================================================================
	;; we only have 8 bytes available before the RST 08 vector;
	;; use this space for basic initialisation, then jump t
	;; the rest of the routine to finish:
	;;
	;; this code is also called by RST 0, which effectively provides a "warm
	;; reboot" option.
	
	ld bc, $C000 / 4	; ramclr counts 4-byte chunks, so clear 48K/4 chunks
	ld hl, $4000		; starting at 4000h
	jr _ramclr

	;; ==========================================================================
	;; RST vectors
	;;
	;; RST 0 is restricted to reset function (unavoidably due to the presence of
	;; fixed ROM at address 0 in this hardware); 8 bytes each are available
	;; for implementing 7 other functions.  RST 38h is reserved for handling
	;; the spectrum's timer tick interrupt; the remaining 6 can be used for
	;; software services.  Small functions or short strings may be placed
	;; between vectors that use less than 8 bytes.
	;; ==========================================================================
_rst08vec:
	defb 0,0,0,0,0,0,0

	;; ==========================================================================
	;; a RET instruction that can be jumped to indirectly to terminate a function
	;; call
	;; ==========================================================================
_ret:	ret
	
_rst10vec:
	
	defs $18 - asmpc, 0
_rst18vec:
	defb 0,0,0,0,0,0,0,0
_rst20vec:
	defb 0,0,0,0,0,0,0,0
_rst28vec:
	defb 0,0,0,0,0,0,0,0
_rst30vec:
	defb 0,0,0,0,0,0,0,0

_rst38vec:
	push af
	push de
	push hl
	
	;; increment timer tick counter
	ld de, (_ticks)
	inc de
	ld (_ticks), de
	
	;; check to see if we need to switch tasks
	ld hl, (_sched_task_current) ; hl = current task pointer
	ld a, (hl)		     ; a = current task flags
	and TASK_FLAG_PRIORITY_MASK  ; a = current task priority
	ld d, a			     ; save in d
	inc l			     ; (hl) => next task pointer 
	ld e, (hl)		     ; low-order byte of next task entry
	ld a, e
	and 0x80		; check timeslice extend flag
	jr z, timeslice_over	; continue after the nmi handler vector
	
	;; timeslice was extended - clear the extend flag and save
	xor e
	ld (hl), a
sched_finished:
	pop hl
	pop de
	pop af
	ei
	reti

	

	;; ==========================================================================
	;; ramclr - clear memory
	;;
	;; this is the first operation performed at startup; after completion
	;; execution continues at 'startupmsg'
	;; ==========================================================================
_ramclr:
	;; interrupts start disabled and in IM0, but calling RST 0 doesn't guarantee
	;; this, so set up interrupts how we want them now:
	di			; no interrupts until init finished
	im 1			; interrupts always call RST 38h
	
	;; continue with memory clearing
	xor a			; byte to use for clearing
	ld ix, _startupmsg	; continuation
	jr _memsetdw		; go

_spare_v1:
	defs $66 - asmpc, 0

	;; ==========================================================================
	;; nmivec - fixed location of NMI handler, 0x0066
	;; ==========================================================================
_nmivec:
	retn

_copyright:
	defb "Microtalk (C) 2018 PeriataTech", 0

	;; ==========================================================================
	;; rst38 handler continues here
	;; ==========================================================================
	;;
	;; at entry here we know the current timeslice is over (although the next
	;; task to be scheduled may be the same as the current task, or may be
	;; lower priority, in which case we keep on this task).
	;;
	;; hl -> the next task entry in the current task's descriptor
	;; e = the value of the next task entry (which has bit 7 clear)
	;; d = the current task priority
	;; a = 0
timeslice_over:
	ld a, (_sched_task_current) ; get the current task id
	cp e			    ; check whether it's the same as the next task
	jr z, sched_finished	    ; and abort if it is
	ld l, e			    ; hl => next task descriptor base
	ld a, (hl)		    ; next task flags
	and TASK_FLAG_PRIORITY_MASK ; a = next task priority
	cp d			    ; compare with this task priority
	jp m, sched_finished	    ; abort if current priority higher than next
	;; if we get here, we need to switch tasks
	;; save remaining unsaved registers
	push bc
	push ix
	push iy
	;; and reschedule
	ld b, e
	call _sched_yield_to_task
	;; when we regain the processor, execution continues here
	;; interrupts are reenabled by the task switcher, so don't need to do this
	;; here
	pop iy
	pop ix
	pop bc
	jr sched_finished
	
	
_main:
_startupmsg:
	call _init_disp
	ld hl, _copyright
	call _puts
	jp _sched_init


	;; =========================================================================
	;; memsetdw - fast memset operation for calling using registers
	;; =========================================================================
	;; on entry:
	;;   hl    - pointer to block to be set
	;;   a     - value to be used for setting block
	;;   bc    - number of 4-byte words to set
	;;   ix    - location to jump to at end (may be _ret to return to caller)
	;; on exit:
	;;   hl    - points to end of block
	;;   a, de - unchanged
_memsetdw:
	
	;; we decrement and break on reaching zero before executing any stores,
	;; so increment the counter before starting:
	inc bc

	;; fall into the loop to begin.
memsetdw_loop:
	;; decrement bc, abort if we reach zero
	;; - we don't use the dec bc instruction because decrementing c and checking
	;;   for overflow is faster
	dec c			; sets ZF when reaching 0
	jr z, memsetdw_overflow
	
memsetdw_zero:
	;; zero 4 bytes
	ld (hl), a
	inc hl
	ld (hl), a
	inc hl
	ld (hl), a
	inc hl
	ld (hl), a
	inc hl
	jr memsetdw_loop

memsetdw_overflow:
	;; when we get here, c has overflowed.
	;; if decrementing the original copy of 'b' also overflows, that means the
	;; loop is finished.  however, we incremented 'b' before starting the loop
	;; which means that instead, we should be checking for zero rather than
	;; overflow, which rather handily can be done in a single instruction
	djnz memsetdw_zero
	jp (ix)

	
	
	
	
	
