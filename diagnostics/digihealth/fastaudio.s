| SPDX-License-Identifier: GPL-2.0-or-later
| digihealth, FAST AUDIO: the SETTINGS row, the render block run from SRAM,
| and its watchdog. Its tables are the linker's: fa_copies (the block, then
| every mod's .fast) and fa_fixups (the block's own references); build.py
| generates them, and the call-site stubs (fa_stubs.s), from the stock file.
        .ifdef  OS154                   | the Digitakt mk1 1.54 (mod.json's port)
        .include "os154.inc"
        .else                           | the Digitakt mk1 1.53
        .include "os153.inc"
        .endif

| ---- FAST AUDIO: hot render code run from the free on-chip SRAM ----------
| The render runs ~17 KB of code a block through an 8 KB I-cache: about
| 1,000 misses a block, ~30 cycles each on the device (docs/FINDINGS.md).
| build.py generates three tables:
|   fa_copies: blocks of MAIN OS to copy (src, dst, len) into the SRAM at
|              0x80003360-0x80007FFF, which the OS zeroes and never uses;
|   fa_fixups: (SRAM address, value) for each of the copy's absolute
|              references to itself, rewritten to point into the copy;
|   stub_tab:  (&pointer, image entry, SRAM entry) per function the render
|              calls in. Its call sites call a stub,
|              r_<addr>: move.l rp_<addr>,-(sp) ; rts, so the pointer says
|              which copy runs.
| The block has no PC-relative reference or branch out of it (checked at
| build), so the copy computes exactly what the image's code does.
        .equ RT_SRC,  0
        .equ RT_DST,  4
        .equ RT_LEN,  8                 | a multiple of 4
        .equ RT_SIZE, 16
        .equ ST_PTR,  0
        .equ ST_SRC,  4
        .equ ST_DST,  8
        .equ ST_SIZE, 12


        .section .run, "ax"

| ev_settings handler: the FAST AUDIO row.

        .globl  fa_settings
fa_settings:
        pea     row_fast
        move.l  8(%sp), -(%sp)          | the menu
        jsr     core_additem
        addq.l  #8, %sp
        rts

| The row: select/RIGHT turn it on, select/LEFT off. It is on by default:
| fa_boot turns it on two seconds after the UI starts, once; unticking it
| keeps it off until the next power-on. (The safety nets: reloc_on refuses
| SRAM that is in use, the watchdog goes back to the image's code if the
| copy is ever overwritten, and FUNC at power-on or the stock OS file
| recover the unit.)
fa_label:
        link    %a6, #-4
        move.l  %d2, -(%sp)
        pea     -1(%a6)
        pea     str_fast
        move.l  %a0, %d2
        move.l  %a0, -(%sp)
        jsr     STR_CTOR
        lea     12(%sp), %sp
        move.l  %d2, %d0
        move.l  -8(%a6), %d2
        unlk    %a6
        rts

fa_select:
        move.l  %d2, -(%sp)
        movea.l 8(%sp), %a0
        move.l  (%a0), %d2              | the menu
        tst.b   fast
        bne.s   2f
1:      bsr.w   reloc_on
        move.b  %d0, fast
        bra.s   fa_done
2:      bsr.w   reloc_off
        clr.b   fast
fa_done:
        moveq   #1, %d1                 | the user's choice: fa_boot leaves it
        move.l  %d1, fa_auto
        movea.l %d2, %a0
        lea     0x38(%a0), %a0
        move.l  (%sp)+, %d2
        move.l  %a0, 4(%sp)
        jmp     INVALIDATE

fa_change:
        move.l  12(%sp), %d0            | delta
        beq.s   9f
        move.l  %d2, -(%sp)
        movea.l 8(%sp), %a0
        move.l  (%a0), %d2
        tst.l   %d0
        bpl.s   1b                      | RIGHT: on
        bra.s   2b                      | LEFT: off
9:      rts

fa_draw:
        moveq   #0, %d0
        tst.b   fast
        beq.s   1f
        moveq   #0x1c, %d0
1:      add.l   CHECKBOXES, %d0
        move.l  12(%sp), %d1
        move.l  %d1, 4(%sp)
        move.l  %d0, 8(%sp)
        move.l  16(%sp), %d1
        move.l  %d1, 12(%sp)
        move.l  20(%sp), %d1
        move.l  %d1, 16(%sp)
        clr.l   20(%sp)
        jmp     BLIT

| ev_tick handler, once a second: the watchdog (the SRAM copies must still
| be what was copied; if anything wrote over them, go back to the image's
| code for good), then fa_boot.

        .globl  fa_tick
fa_tick:
        addq.l  #1, fa_ticks
        move.l  fa_ticks, %d0
        cmpi.l  #30, %d0
        blt.s   85f
        clr.l   fa_ticks
        tst.l   r_on
        beq.s   84f
        bsr.w   reloc_sum
        cmp.l   r_sum, %d0
        beq.s   84f
        bsr.w   reloc_off
        moveq   #1, %d0
        move.l  %d0, r_fault
        clr.b   fast
84:     | Diagnostic Sophie build: leave FAST AUDIO off unless selected.
85:     rts

| FAST AUDIO on by default: at the second one-second tick (two seconds
| after the UI's first check, the boot's SRAM clear long done), switch it
| on as the SETTINGS row does, once. Not if the row was used first, or if
| the copies were refused or undone (r_fault).
fa_boot:
        tst.l   fa_auto
        bne.s   9f
        addq.l  #1, fa_secs
        moveq   #2, %d0
        cmp.l   fa_secs, %d0
        bgt.s   9f                      | not yet
        moveq   #1, %d0
        move.l  %d0, fa_auto
        tst.b   fast
        bne.s   9f
        tst.l   r_fault
        bne.s   9f
        bsr.w   reloc_on
        move.b  %d0, fast
9:      rts

| fa_copies and fa_fixups are the linker's tables (fa_copies_n, fa_fixups_n).
| reloc_on() -> d0 = 1 when the SRAM copies run, 0 when refused (r_fault).
| The first time: every destination must read all zero (unused), then each
| function is copied, compared and summed. Then the pointers switch.
reloc_on:
        lea     -12(%sp), %sp
        movem.l %d2-%d3/%a2, (%sp)
        tst.l   r_sum_ok
        bne.w   5f                      | copied and checked before
        lea     fa_copies, %a2
        move.l  #fa_copies_n, %d2
1:      movea.l RT_DST(%a2), %a0
        move.l  RT_LEN(%a2), %d0
        lsr.l   #2, %d0
2:      tst.l   (%a0)+
        bne.w   8f                      | something uses it
        subq.l  #1, %d0
        bne.s   2b
        lea     RT_SIZE(%a2), %a2
        subq.l  #1, %d2
        bne.s   1b
        lea     fa_copies, %a2
        move.l  #fa_copies_n, %d2
3:      movea.l RT_SRC(%a2), %a0
        movea.l RT_DST(%a2), %a1
        move.l  RT_LEN(%a2), %d0
        lsr.l   #2, %d0
4:      move.l  (%a0)+, %d1
        move.l  %d1, (%a1)+
        cmp.l   -4(%a1), %d1
        bne.w   8f                      | did not read back
        subq.l  #1, %d0
        bne.s   4b
        lea     RT_SIZE(%a2), %a2
        subq.l  #1, %d2
        bne.s   3b
        | The copy's references to itself, to their SRAM addresses. The
        | operands are 2-aligned: written as two words.
        lea     fa_fixups, %a2
        move.l  #fa_fixups_n, %d2
        beq.s   44f
43:     movea.l (%a2)+, %a0
        move.l  (%a2)+, %d0
        move.w  %d0, 2(%a0)
        swap    %d0
        move.w  %d0, (%a0)
        subq.l  #1, %d2
        bne.s   43b
44:     bsr.w   reloc_sum
        move.l  %d0, r_sum
        moveq   #1, %d0
        move.l  %d0, r_sum_ok
5:      lea     stub_tab, %a2           | point each stub at its copy
        move.l  #stub_count, %d2
6:      movea.l ST_PTR(%a2), %a0
        move.l  ST_DST(%a2), (%a0)
        lea     ST_SIZE(%a2), %a2
        subq.l  #1, %d2
        bne.s   6b
        moveq   #1, %d0
        move.l  %d0, r_on
        bra.s   9f
8:      moveq   #1, %d0
        move.l  %d0, r_fault
        moveq   #0, %d0
9:      movem.l (%sp), %d2-%d3/%a2
        lea     12(%sp), %sp
        rts

| reloc_off(): every stub back to the image's copy. Uses d0, a0, a1.
reloc_off:
        lea     stub_tab, %a0
        move.l  #stub_count, %d0
1:      movea.l ST_PTR(%a0), %a1
        move.l  ST_SRC(%a0), (%a1)
        lea     ST_SIZE(%a0), %a0
        subq.l  #1, %d0
        bne.s   1b
        clr.l   r_on
        rts

| reloc_sum() -> d0, the sum of every copy's longwords. Uses d1, a0, a1.
reloc_sum:
        move.l  %d2, -(%sp)
        lea     fa_copies, %a1
        move.l  #fa_copies_n, %d1
        moveq   #0, %d0
1:      movea.l RT_DST(%a1), %a0
        move.l  RT_LEN(%a1), %d2
        lsr.l   #2, %d2
2:      add.l   (%a0)+, %d0
        subq.l  #1, %d2
        bne.s   2b
        lea     RT_SIZE(%a1), %a1
        subq.l  #1, %d1
        bne.s   1b
        move.l  (%sp)+, %d2
        rts

| The row and its label.
        .balign 4
row_fast:   .long   fa_label, fa_select, fa_draw, fa_change
str_fast:   .asciz  "FAST AUDIO"
        .balign 2

        .section .bss
        .balign 4
        .globl  fast, r_on, r_fault, r_sum_ok, r_sum, fa_auto
fast:       .skip 4             | FAST AUDIO (byte 0): fa_boot turns it on
fa_auto:    .skip 4             | fa_boot has run, or the row was used
fa_secs:    .skip 4             | one-second ticks seen before fa_boot
r_on:       .skip 4             | the stubs point at the SRAM copies
r_fault:    .skip 4             | refused (SRAM in use) or undone (overwritten)
r_sum_ok:   .skip 4             | the copies are made and checked
r_sum:      .skip 4             | their sum
| The watchdog's tick count.
fa_ticks:   .skip 4
