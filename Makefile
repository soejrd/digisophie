CC ?= cc
CFLAGS ?= -std=c99 -O2 -Wall -Wextra -Werror
CROSS ?= m68k-elf-
ELEKLOADER ?= ../elekloader
CROSS_CFLAGS = -mcpu=54455 -O2 -ffreestanding -fno-builtin -nostdlib -fno-pic -fno-pie -fomit-frame-pointer -Wall -Wextra -Werror

.PHONY: test cross-check golden-check cycle-probe cycle-static
PYTHON ?= python3
out:
	mkdir -p out
out/test_sophie: sophie.c sophie.h tests/test_sophie.c | out
	$(CC) $(CFLAGS) -I. sophie.c tests/test_sophie.c -o $@
test: out/test_sophie
	./out/test_sophie
golden-check:
	$(PYTHON) tools/golden_diff.py --ref HEAD
cycle-probe:
	$(PYTHON) tools/cycle_probe.py
cycle-static:
	$(PYTHON) tools/cycle_probe.py --static
cross-check: | out
	mkdir -p out/cross
	$(CROSS)as -mcpu=54455 -o out/cross/glue.o glue.s
	$(CROSS)gcc $(CROSS_CFLAGS) -I. -I"$(ELEKLOADER)/elekloader/sdk/include" -c digitakt.c -o out/cross/digitakt.o
	$(CROSS)gcc $(CROSS_CFLAGS) -I. -c sophie.c -o out/cross/sophie.o
