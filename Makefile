VMOBJ=vm/disp.o vm/font8x8_basic.o vm/sched.o vm/inittask.o vm/idletask.o
VMINIT=vm/init.asm
LIB=-lm 
APPMAKE_OPTS=-Cz"--org=0 --rombase=0 --romsize=0x4000"
ASM_OPTS=-Ca"-I$(PWD)/vm"
TARGET=+z80 -startup=1 -clib=sdcc_ix

all: utalk-vm.rom
clean:
	rm -f $(VMOBJ) $(VMINIT:.asm=.o)

%.asm: %.c
	zcc $(TARGET) --c-code-in-asm -a -SO3 -o $<.asm $<
%.o: %.c
	zcc $(TARGET) -c -SO3 --list --c-code-in-asm -o $@ $<

%.o: %.asm
	z80asm --output=$@ --list --map $<

vm/disp.o: vm/disp.c vm/include/utalk-vm.h
vm/font8x8_basic.o: vm/font8x8_basic.asm
vm/sched.o: vm/sched.asm
vm/inittask.o: vm/inittask.c vm/include/utalk-vm.h
vm/idletask.o: vm/idletask.c vm/include/utalk-vm.h

utalk-vm.rom: $(VMINIT) $(VMOBJ)
	zcc $(TARGET) -zorg=0 -o utalk-vm.rom -create-app $(APPMAKE_OPTS) $(ASM_OPTS) -pragma-include:vm/pragma.inc -m $(VMOBJ) $(LIB)
