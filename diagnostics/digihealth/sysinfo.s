| SPDX-License-Identifier: GPL-2.0-or-later
| digihealth, SYSTEM INFO: the SETTINGS row and the readout, render and idle
| timing, and the read-only USB diagnostics channel (tools/digiusb.py).
        .ifdef  DN143                   | the Digitone mk1 1.43 (dn1/mod.json)
        .include "dn143.inc"
        .else
        .ifdef  OS154                   | the Digitakt mk1 1.54 (mod.json's port)
        .include "os154.inc"
        .else                           | the Digitakt mk1 1.53
        .include "os153.inc"
        .endif
        .endif

        .equ TICKS_PER_S, 30            | the UI's compose check runs at 30 Hz
        .equ PAGE_S,      2             | seconds per readout page

        | The USB snapshot (the STATS reply, byte for byte; tools/digiusb.py)
        .equ SNAP_LAYOUT, 1
        .equ S_HEAD,      0             | u16 layout, u16 flags (1 valid, 2 overlay on)
        .equ S_SECONDS,   4             | snapshots taken since boot
        .equ S_WINDOW,    8             | DTIM0 ticks in the last window
        .equ S_RTICKS,    12            | ticks spent rendering
        .equ S_RMAX,      16            | the longest render
        .equ S_RENDERS,   20            | renders
        .equ S_IDLE,      24            | ticks parked in the idle task
        .equ S_IDLE_R,    28            | of those, ticks spent rendering
        .equ S_HEAP,      32            | heap bytes free (validated walk)
        .equ S_FAULTS,    36            | free lists cut short by a failed check
        .equ S_TOP,       40            | the heap's highest order
        .equ S_SMP,       44            | sample pool bytes free
        .equ S_BLOCKS,    48            | u16 free blocks per order, ORDERS of them
        .equ ORDERS,      24
        .equ SNAP_BYTES,  96

        .section .run, "ax"

| ev_settings handler: the SYSTEM INFO row (was hook_settings' first row).

        .globl  si_settings
si_settings:
        pea     row_info
        move.l  8(%sp), -(%sp)          | the menu
        jsr     core_additem
        addq.l  #8, %sp
        rts

| label() -> std::string, returned through a0 (like 0x400b9880)
item_label:
        link    %a6, #-4
        move.l  %d2, -(%sp)
        pea     -1(%a6)
        pea     str_label
        move.l  %a0, %d2
        move.l  %a0, -(%sp)
        jsr     STR_CTOR
        lea     12(%sp), %sp
        move.l  %d2, %d0
        move.l  -8(%a6), %d2
        unlk    %a6
        rts

| select(payload, item): toggle, then redraw the menu (like 0x400b9972)
item_select:
        movea.l 4(%sp), %a0
        movea.l (%a0), %a0
        moveq   #0, %d0
        tst.b   enabled
        seq     %d0
        andi.l  #1, %d0
        move.b  %d0, enabled
        lea     0x38(%a0), %a0
        move.l  %a0, 4(%sp)
        jmp     INVALIDATE

| change(payload, item, delta): RIGHT on, LEFT off (like 0x400ba13a)
item_change:
        movea.l 4(%sp), %a0
        movea.l (%a0), %a0
        move.l  12(%sp), %d0
        beq.s   1f
        sgt     %d0
        andi.l  #1, %d0
        move.b  %d0, enabled
        lea     0x38(%a0), %a0
        move.l  %a0, 4(%sp)
        jmp     INVALIDATE
1:      rts

| draw(payload, item, bmp, x, y): the checkbox (like 0x400b9fc2)
item_draw:
        moveq   #0, %d0
        tst.b   enabled
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
| ev_render_in / ev_render_out handlers: render_in and render_out without the
| instructions they replaced, which core now does (move.l #$7fffffff,d0 at
| the entry; the movem restore at the exit).

        .globl  si_render_in, si_render_out
si_render_in:
        move.l  DTCN0, %d0
        move.l  %d0, t_in
        rts
si_render_out:
        move.l  DTCN0, %d0
        sub.l   t_in, %d0               | ticks this render took
        add.l   %d0, r_acc
        addq.l  #1, r_cnt
        cmp.l   r_max, %d0
        bls.s   1f
        move.l  %d0, r_max
1:      move.l  CUR_TCB, %d1
        cmpi.l  #IDLE_TCB, %d1
        bne.s   2f
        add.l   %d0, r_idle             | render time taken out of idle time
2:      rts

| ---- measurement: time in the idle task, at the context switch ----------
| At 0x40000438 (was: move.l #$ffffdfff,d0). Live: a0 = incoming TCB, a1,
| d1; interrupts masked. d0 must come back as 0xffffdfff.
        .globl  task_switch
task_switch:
        move.l  DTCN0, %d2
        move.l  CUR_TCB, %d3            | the outgoing task
        cmpi.l  #IDLE_TCB, %d3
        bne.s   1f
        tst.l   i_on
        beq.s   1f
        move.l  8(%sp), %d4             | its resume PC, above our return
        cmpi.l  #IDLE_PC, %d4           | only time parked in the idle spin
        bne.s   1f
        move.l  %d2, %d4
        sub.l   i_start, %d4
        add.l   %d4, i_acc
1:      clr.l   i_on
        cmpa.l  #IDLE_TCB, %a0
        bne.s   2f
        move.l  %d2, i_start            | idle switched in: open an interval
        moveq   #1, %d0
        move.l  %d0, i_on
2:      move.l  #0xffffdfff, %d0
        rts

| ev_tick handler: the readout's once-a-second update (core's tick event
| returns the dirty byte).

        .globl  si_tick
si_tick:
        addq.l  #1, ticks
        move.l  ticks, %d0
        cmpi.l  #TICKS_PER_S, %d0
        blt.s   9f
        clr.l   ticks
        bsr.w   stats
        tst.b   enabled
        beq.s   9f
        movea.l 4(%sp), %a0             | recompose: the readout changed
        moveq   #1, %d0
        move.b  %d0, 0x20(%a0)
9:      rts

| stats(): the last second's figures into the readout's values, and the raw
| counts into the USB snapshot (stage, then snap: see diag_rx).
stats:
        lea     -28(%sp), %sp
        movem.l %d2-%d7/%a2, (%sp)
        | Take and clear the accumulators with interrupts off.
        move.w  %sr, %d7
        move.w  #0x2700, %sr
        move.l  DTCN0, %d0
        move.l  r_acc, %d2
        move.l  r_max, %d3
        move.l  r_cnt, %d4
        move.l  i_acc, %d5
        move.l  r_idle, %d6
        clr.l   %d1
        move.l  %d1, r_acc
        move.l  %d1, r_max
        move.l  %d1, r_cnt
        move.l  %d1, i_acc
        move.l  %d1, r_idle
        move.w  %d7, %sr
        lea     stage+S_RTICKS, %a0     | render ticks, longest, count, idle,
        movem.l %d2-%d6, (%a0)          | idle inside renders
        move.l  %d0, %d1
        sub.l   last_cn, %d1            | window, in counter ticks
        move.l  %d0, last_cn
        move.l  %d1, stage+S_WINDOW
        move.l  #1000, %d0
        divu.l  %d0, %d1                | ticks per 1/1000 of the window
        clr.l   %d0
        move.l  %d0, v_valid
        tst.l   %d1
        beq.w   5f                      | the counter stands still: no figures
        tst.l   %d4
        beq.w   5f                      | no renders: audio is not running
        moveq   #1, %d0
        move.l  %d0, v_valid
        | DSP, in 0.1 %: render ticks / (window / 1000)
        move.l  %d2, %d0
        divu.l  %d1, %d0
        bsr.w   permille_to_pct
        move.l  %d0, v_dsp
        | DSP peak: the longest render against one render period
        move.l  %d1, %d0
        move.l  #1000, %d2
        mulu.l  %d2, %d0                | the window in ticks again
        divu.l  %d4, %d0                | ticks per render period
        mulu.l  %d3, %d2                | the longest render x 1000
        tst.l   %d0
        beq.s   1f
        divu.l  %d0, %d2
1:      move.l  %d2, %d0
        bsr.w   permille_to_pct
        move.l  %d0, v_peak
        | CPU: everything but the time spent idle
        sub.l   %d6, %d5                | idle minus the renders inside it
        bcc.s   2f
        clr.l   %d5
2:      move.l  %d5, %d0
        divu.l  %d1, %d0                | idle, in 0.1 %
        move.l  #1000, %d2
        sub.l   %d0, %d2
        bpl.s   3f
        clr.l   %d2
3:      move.l  %d2, %d0
        bsr.w   permille_to_pct
        move.l  %d0, v_cpu
5:      | Free heap: walk the buddy lists under the heap's own lock.
        pea     HEAPMTX
        jsr     LOCK
        addq.l  #4, %sp
        | A free block: word 0 = ~(prev + next), +4 prev, +8 next (a unit
        | index, -1 at the end), and its size in units in its last word. A
        | block is counted only if it is aligned to its order and its last
        | word is its size, and a link is followed only through an intact
        | header: a freed block whose header has been written over (seen
        | on stock 1.53, order 15) sends the next link into allocated units.
        movea.l HEAPCB+4, %a0           | base of the 16-byte units
        movea.l HEAPCB+0xc, %a1         | free-list head per order
        move.l  HEAPCB+0x10, %d3        | highest order
        move.l  %d3, stage+S_TOP
        clr.l   stage+S_FAULTS
        lea     stage+S_BLOCKS, %a2     | free blocks per order
        moveq   #0, %d4                 | free units
        moveq   #0, %d5                 | order
6:      move.l  (%a1)+, %d0
        move.l  #4096, %d6              | bound one list's walk
        moveq   #0, %d7                 | blocks on this list
        moveq   #1, %d2
        lsl.l   %d5, %d2                | units in a block of this order
7:      tst.l   %d0
        bmi.s   8f                      | the end of the list
        move.l  %d2, %d1                | aligned to its order?
        subq.l  #1, %d1
        and.l   %d0, %d1
        bne.s   81f
        move.l  %d0, %d1                | its last word its size?
        add.l   %d2, %d1
        lsl.l   #4, %d1
        cmp.l   -4(%a0,%d1.l), %d2
        bne.s   81f
        add.l   %d2, %d4                | a free block
        addq.l  #1, %d7
        lsl.l   #4, %d0
        move.l  4(%a0,%d0.l), %d1       | header intact: w0 == ~(prev+next)?
        add.l   8(%a0,%d0.l), %d1
        not.l   %d1
        cmp.l   0(%a0,%d0.l), %d1
        bne.s   81f
        move.l  8(%a0,%d0.l), %d0       | next free block
        subq.l  #1, %d6
        bne.s   7b
81:     addq.l  #1, stage+S_FAULTS      | a walk cut short by a failed check
8:      moveq   #ORDERS, %d1
        cmp.l   %d1, %d5
        bcc.s   82f
        move.w  %d7, (%a2)+
82:     addq.l  #1, %d5
        cmp.l   %d3, %d5
        ble.s   6b
        pea     HEAPMTX
        jsr     UNLOCK
        addq.l  #4, %sp
        lsl.l   #4, %d4                 | bytes
        move.l  %d4, stage+S_HEAP
        move.l  %d4, %d0
        bsr.w   to_tenths
        move.l  %d0, v_ram
        .ifdef  SMPFREE                 | a sample engine: its free memory too
        | Free sample memory, from the OS's own count.
        jsr     SMPFREE
        move.l  %d0, stage+S_SMP
        bsr.w   to_tenths
        move.l  %d0, v_smp
        .endif
| FAST AUDIO's state (r_on, r_fault: fastaudio.s) goes into the snapshot's
| flags; its watchdog is fastaudio.s's fa_tick.
85:     | Publish the snapshot: diag_rx copies it with interrupts off too.
        addq.l  #1, stage+S_SECONDS
        moveq   #0, %d0
        tst.l   v_valid
        beq.s   1f
        moveq   #1, %d0
1:      tst.b   enabled
        beq.s   2f
        addq.l  #2, %d0
2:      tst.l   r_on
        beq.s   3f
        addq.l  #4, %d0                 | FAST AUDIO running
3:      tst.l   r_fault
        beq.s   4f
        addq.l  #8, %d0                 | FAST AUDIO refused or undone
4:      ori.l   #SNAP_LAYOUT<<16, %d0   | u16 layout, u16 flags
        move.l  %d0, stage+S_HEAD
        lea     stage, %a0
        lea     snap, %a1
        moveq   #SNAP_BYTES/4, %d0
        move.w  %sr, %d7
        move.w  #0x2700, %sr
3:      move.l  (%a0)+, (%a1)+
        subq.l  #1, %d0
        bne.s   3b
        move.w  %d7, %sr
        | Page: CPU/DSP, then RAM/SMP, PAGE_S seconds each.
        addq.l  #1, secs
        move.l  secs, %d0
        cmpi.l  #PAGE_S, %d0
        blt.s   9f
        clr.l   secs
        moveq   #1, %d0
        move.l  page, %d1
        eor.l   %d0, %d1
        move.l  %d1, page
9:      movem.l (%sp), %d2-%d7/%a2
        lea     28(%sp), %sp
        rts

| d0 (bytes) -> d0 (tenths of a MiB, rounded down). Uses d1.
to_tenths:
        move.l  %d2, -(%sp)
        move.l  %d0, %d1
        andi.l  #0xFFFFF, %d1           | the part below a whole MiB
        moveq   #10, %d2
        mulu.l  %d2, %d1
        moveq   #20, %d2
        lsr.l   %d2, %d1                | its tenths
        lsr.l   %d2, %d0                | whole MiB
        moveq   #10, %d2
        mulu.l  %d2, %d0
        add.l   %d1, %d0
        move.l  (%sp)+, %d2
        rts

| d0 (0.1 %) -> d0 (%, rounded)
permille_to_pct:
        addq.l  #5, %d0
        move.l  %d1, -(%sp)
        moveq   #10, %d1
        divu.l  %d1, %d0
        move.l  (%sp)+, %d1
        rts
| ---- the overlay: on top of every composed frame ------------------------
| At 0x4000a7d6 (was: jsr 0x400ca382, drawAll(ctrl, bmp)). (sp) = return,
| 4(sp) = ctrl, 8(sp) = the frame's Bitmap. a3/a4/a6 and d2-d7/a2-a6 must
| survive. Bitmap y = 0 is the physical bottom; the top bar is y 53..63.
        .equ BOX_X0, 18
        .equ BOX_X1, 104
        .equ BOX_Y0, 54
        .equ BOX_Y1, 63
        .equ TEXT_X, 21
        .equ TEXT_Y, 57
| ev_draw handler si_draw(bmp, ctrl): the overlay, after core's drawAll.
        .globl  si_draw
si_draw:
        tst.b   enabled
        beq.w   9f
        lea     -8(%sp), %sp
        movem.l %d2/%a2, (%sp)
        movea.l 12(%sp), %a2            | the Bitmap
        clr.l   -(%sp)                  | a black box over the top bar ...
        pea     BOX_Y1
        pea     BOX_X1
        pea     BOX_Y0
        pea     BOX_X0
        move.l  %a2, -(%sp)
        jsr     FILLRECT
        lea     24(%sp), %sp
        pea     1                       | ... with a white outline
        pea     BOX_Y1
        pea     BOX_X1
        pea     BOX_Y0
        pea     BOX_X0
        move.l  %a2, -(%sp)
        jsr     FRAMERECT
        lea     24(%sp), %sp
        tst.l   page
        bne.w   2f
        tst.l   v_valid
        bne.s   1f
        pea     fmt_na                  | no figures yet
        bra.w   8f
1:      move.l  v_peak, -(%sp)          | "CPU 61%  DSP 60%/62%"
        move.l  v_dsp, -(%sp)
        move.l  v_cpu, -(%sp)
        pea     fmt_cpu
        pea     -1
        pea     TEXT_Y
        pea     TEXT_X
        pea     FONT5
        move.l  %a2, -(%sp)
        jsr     TEXTF
        lea     36(%sp), %sp
        bra.w   7f
2:
        .ifdef  SMPFREE
        move.l  v_smp, %d0              | "RAM 15.1M  SMP 64.0M"
        moveq   #10, %d1
        move.l  %d0, %d2
        divu.l  %d1, %d2                | whole MB
        mulu.l  %d2, %d1
        sub.l   %d1, %d0                | tenths
        move.l  %d0, -(%sp)
        move.l  %d2, -(%sp)
        .endif
        move.l  v_ram, %d0
        moveq   #10, %d1
        move.l  %d0, %d2
        divu.l  %d1, %d2
        mulu.l  %d2, %d1
        sub.l   %d1, %d0
        move.l  %d0, -(%sp)
        move.l  %d2, -(%sp)
        pea     fmt_ram
        pea     -1
        pea     TEXT_Y
        pea     TEXT_X
        pea     FONT5
        move.l  %a2, -(%sp)
        jsr     TEXTF
        .ifdef  SMPFREE
        lea     40(%sp), %sp
        .else
        lea     32(%sp), %sp            | "RAM 15.1M": two arguments fewer
        .endif
        bra.w   7f
8:      pea     -1
        pea     TEXT_Y
        pea     TEXT_X
        pea     FONT5
        move.l  %a2, -(%sp)
        jsr     TEXTF
        lea     24(%sp), %sp
7:      movem.l (%sp), %d2/%a2
        lea     8(%sp), %sp
9:      rts

| ---- the USB diagnostics channel ------------------------------------------
| F0 00 20 3C 7D 00 <pack7: u16 seq, u8 cmd, args> F7, answered with
| F0 00 20 3C 7D 00 <pack7: u16 seq, u8 cmd|0x80, u8 status, payload> F7
| over USB. Every command only reads. tools/digiusb.py is the other end.
        .equ DIAG_PROTO,  1
        .equ C_HELLO,     1             | -> u16 channel version, u32 seconds, name
        .equ C_STATS,     2             | -> the snapshot
        .equ C_PEEK,      3             | u32 addr, u16 len -> u32 addr, bytes
        .equ PEEK_MAX,    1024
        .equ PEEK_NRANGES, 2            | peek_ranges: DDR and the SRAM, never
                                        | the peripheral space, where a read
                                        | can clear a status bit
        .equ RQ_MAX,      16

| The entry, at 0x400d52f0 in the SysEx router 0x400d52c4 (was: lea
| 0x401b89aa,a3), for every F0 message but F0 7E, in the MIDI input task
| (0x400d4642), no lock held. a0 = a1 = the message, F0 to F7; d1 = its
| length; d2 = where it came from (2 or 4 USB, 8 or 0x10 DIN, as MidiRpc's
| test at 0x400d484c). a0, a1, d1, d2 must survive; d0, d3, a2 are free.
| The router goes on to drop 0x7D itself (0x400d531a: only 0x00-0x17 route).
        .globl  hook_sysex
hook_sysex:
        lea     -16(%sp), %sp
        movem.l %d1-%d2/%a0-%a1, (%sp)
        moveq   #7, %d0
        cmp.l   %d0, %d1
        blt.s   9f                      | shorter than header + F7
        moveq   #2, %d0                 | USB only
        cmp.l   %d0, %d2
        beq.s   1f
        moveq   #4, %d0
        cmp.l   %d0, %d2
        bne.s   9f
1:      lea     diag_hdr, %a2           | F0 00 20 3C 7D 00
        moveq   #6, %d3
2:      move.b  (%a0)+, %d0
        cmp.b   (%a2)+, %d0
        bne.s   9f
        subq.l  #1, %d3
        bne.s   2b
        move.l  %d1, %d0                | a0 = the body; d0 = its length
        subq.l  #7, %d0
        moveq   #-9, %d3                | the last byte is F7?
        cmp.b   0(%a0,%d0.l), %d3
        bne.s   9f
        move.l  %d0, -(%sp)
        move.l  %a0, -(%sp)
        bsr.w   diag_rx
        addq.l  #8, %sp
9:      movem.l (%sp), %d1-%d2/%a0-%a1
        lea     16(%sp), %sp
        lea     SYSEX_A3, %a3           | the instruction this replaced
        rts

| diag_rx(const u8 *body, u32 len): body is what lies between the 6-byte
| header and the F7. Answers on USB, through the OS's SysEx sender.
        .globl  diag_rx
diag_rx:
        lea     -20(%sp), %sp
        movem.l %d2-%d5/%a2, (%sp)
        movea.l 24(%sp), %a0
        move.l  28(%sp), %d0
        lea     rq+1, %a1               | seq at rq+1 puts the PEEK args aligned
        moveq   #RQ_MAX, %d1
        bsr.w   unpack7
        move.l  %d0, %d5                | request bytes
        moveq   #3, %d1
        cmp.l   %d1, %d5
        blt.w   9f                      | too short to answer
        lea     rp, %a2
        move.b  rq+1, %d0               | seq
        move.b  %d0, (%a2)
        move.b  rq+2, %d0
        move.b  %d0, 1(%a2)
        moveq   #0, %d2
        move.b  rq+3, %d2               | cmd
        move.l  %d2, %d0
        bset    #7, %d0
        move.b  %d0, 2(%a2)
        clr.b   3(%a2)                  | status: ok
        lea     4(%a2), %a1             | the payload
        moveq   #C_HELLO, %d1
        cmp.l   %d1, %d2
        beq.s   1f
        moveq   #C_STATS, %d1
        cmp.l   %d1, %d2
        beq.s   3f
        moveq   #C_PEEK, %d1
        cmp.l   %d1, %d2
        beq.s   5f
        moveq   #2, %d0                 | unknown command
        move.b  %d0, 3(%a2)
        bra.w   8f
1:      moveq   #DIAG_PROTO, %d0        | HELLO
        move.w  %d0, (%a1)+
        move.l  snap+S_SECONDS, (%a1)+
        lea     str_name, %a0
2:      move.b  (%a0)+, %d0
        move.b  %d0, (%a1)+
        bne.s   2b
        bra.w   8f
3:      lea     snap, %a0               | STATS: a consistent copy
        moveq   #SNAP_BYTES/4, %d0
        move.w  %sr, %d3
        move.w  #0x2700, %sr
4:      move.l  (%a0)+, (%a1)+
        subq.l  #1, %d0
        bne.s   4b
        move.w  %d3, %sr
        bra.w   8f
5:      moveq   #9, %d1                 | PEEK: seq, cmd, addr, len
        cmp.l   %d1, %d5
        blt.s   7f
        move.l  rq+4, %d3               | address
        moveq   #0, %d4
        move.w  rq+8, %d4               | length
        beq.s   7f
        cmpi.l  #PEEK_MAX, %d4
        bhi.s   7f
        lea     peek_ranges, %a0        | inside one range, end included
        moveq   #PEEK_NRANGES, %d2
55:     move.l  %d3, %d1
        sub.l   (%a0), %d1              | the offset into this range
        bcs.s   56f                     | below it
        add.l   %d4, %d1                | where the read ends
        move.l  4(%a0), %d0
        sub.l   (%a0), %d0              | the range's size
        cmp.l   %d0, %d1
        bls.s   57f
56:     addq.l  #8, %a0
        subq.l  #1, %d2
        bne.s   55b
        bra.s   7f
57:     move.l  %d3, (%a1)+
        movea.l %d3, %a0
6:      move.b  (%a0)+, %d0
        move.b  %d0, (%a1)+
        subq.l  #1, %d4
        bne.s   6b
        bra.s   8f
7:      moveq   #1, %d0                 | refused
        move.b  %d0, 3(%a2)
8:      move.l  %a1, %d0                | send: the reply ends at a1
        sub.l   %a2, %d0
        movea.l %a2, %a0
        lea     tx+6, %a1
        bsr.w   pack7
        lea     tx, %a0
        move.l  diag_hdr, %d1           | F0 00 20 3C
        move.l  %d1, (%a0)
        move.w  diag_hdr+4, %d1         | 7D 00
        move.w  %d1, 4(%a0)
        addq.l  #6, %d0
        moveq   #-9, %d1                | F7
        move.b  %d1, 0(%a0,%d0.l)
        addq.l  #1, %d0
        pea     2.w                     | port: USB
        clr.l   -(%sp)                  | no abort flag
        move.l  %d0, -(%sp)
        pea     tx
        jsr     SYSEX_SEND
        lea     16(%sp), %sp
9:      movem.l (%sp), %d2-%d5/%a2
        lea     20(%sp), %sp
        rts

| unpack7(a0 src, d0 len, a1 dst, d1 room) -> d0 bytes out. MidiRpc's packing:
| each group of up to 7 bytes follows a byte whose bit 6-k is byte k's bit 7.
unpack7:
        lea     -16(%sp), %sp
        movem.l %d2-%d5, (%sp)
        move.l  %d0, %d2                | bytes left
        moveq   #0, %d3                 | bytes out
1:      tst.l   %d2
        beq.s   9f
        moveq   #0, %d4
        move.b  (%a0)+, %d4             | the group's top bits
        subq.l  #1, %d2
        moveq   #7, %d0
2:      tst.l   %d2
        beq.s   9f
        add.l   %d4, %d4                | this byte's top bit to bit 7
        move.b  (%a0)+, %d5
        subq.l  #1, %d2
        bclr    #7, %d5
        btst    #7, %d4
        beq.s   3f
        bset    #7, %d5
3:      cmp.l   %d1, %d3
        bcc.s   4f                      | no room: drop it
        move.b  %d5, (%a1)+
        addq.l  #1, %d3
4:      subq.l  #1, %d0
        bne.s   2b
        bra.s   1b
9:      move.l  %d3, %d0
        movem.l (%sp), %d2-%d5
        lea     16(%sp), %sp
        rts

| pack7(a0 src, d0 len, a1 dst) -> d0 bytes out.
pack7:
        lea     -16(%sp), %sp
        movem.l %d2-%d4/%a2, (%sp)
        move.l  %a1, %d4                | where the output starts
1:      tst.l   %d0
        beq.s   9f
        movea.l %a1, %a2                | the group's header byte
        addq.l  #1, %a1
        moveq   #0, %d2                 | header
        moveq   #0x40, %d3              | its bit for this byte
2:      move.b  (%a0)+, %d1
        btst    #7, %d1
        beq.s   3f
        or.l    %d3, %d2
3:      bclr    #7, %d1
        move.b  %d1, (%a1)+
        subq.l  #1, %d0
        beq.s   4f
        lsr.l   #1, %d3
        bne.s   2b
4:      move.b  %d2, (%a2)
        bra.s   1b
9:      move.l  %a1, %d0
        sub.l   %d4, %d0
        movem.l (%sp), %d2-%d4/%a2
        lea     16(%sp), %sp
        rts

| The constants.
        .balign 4
peek_ranges: .long  0x40000000, 0x48000000     | DDR, cached
             .long  0x80000000, 0x80010000     | the 64 KB SRAM
row_info:   .long   item_label, item_select, item_draw, item_change
diag_hdr:   .byte   0xF0, 0x00, 0x20, 0x3C, 0x7D, 0x00
str_label:  .asciz  "SYSTEM INFO"
fmt_cpu:    .asciz  "CPU %d%%  DSP %d%%/%d%%"
        .ifdef  SMPFREE
fmt_ram:    .asciz  "RAM %d.%dM  SMP %d.%dM"
        .else
fmt_ram:    .asciz  "RAM %d.%dM"
        .endif
fmt_na:     .asciz  "CPU --  DSP --"
        .balign 4

        .section .bss
        .balign 4
enabled:    .skip 4             | the toggle (byte 0), off at power-on
ticks:      .skip 4
secs:       .skip 4
page:       .skip 4
last_cn:    .skip 4
t_in:       .skip 4
r_acc:      .skip 4
r_max:      .skip 4
r_cnt:      .skip 4
r_idle:     .skip 4
i_acc:      .skip 4
i_start:    .skip 4
i_on:       .skip 4
v_valid:    .skip 4
v_cpu:      .skip 4
v_dsp:      .skip 4
v_peak:     .skip 4
v_ram:      .skip 4
v_smp:      .skip 4
stage:      .skip SNAP_BYTES        | the UI task builds the snapshot here ...
snap:       .skip SNAP_BYTES        | ... and publishes it here
rq:         .skip RQ_MAX + 4        | a request, unpacked
rp:         .skip 8 + PEEK_MAX + 8  | a reply, before packing
tx:         .skip 1200              | a reply as sent: 6 + 1188 + 1
