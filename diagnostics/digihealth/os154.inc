| SPDX-License-Identifier: GPL-2.0-or-later
| Digitakt mk1 MAIN OS 1.54: stock routines and data this mod calls or reads
        | ---- stock routines and data (MAIN OS 1.54) ----------------------
        .equ OP_NEW,      0x400d43a8    | operator new(size) -> d0
        .equ ITEM_CTOR,   0x400c4464    | MenuItem(this, label, select, draw, change, id, step)
        .equ MENU_ADD,    0x400c3c9a    | Menu::addItem(menu, item)
        .equ FN_MGR,      0x401376a0    | std::function manager, 4-byte payload
        .equ STR_CTOR,    0x4017af20    | std::string(this, const char*, alloc&)
        .equ INVALIDATE,  0x400c9a3a    | View::invalidate(view)
        .equ BLIT,        0x400c2b88    | blit(dst, src, x, y, centre)
        .equ CHECKBOXES,  0x421f8a3c    | -> Bitmap[2], 0x1c each: empty, ticked
        .equ DRAWALL,     0x400ca5aa    | ViewController::drawAll(ctrl, Bitmap&)
        .equ FILLRECT,    0x400c1bce    | (bmp, x0, y0, x1, y1, colour)
        .equ FRAMERECT,   0x400c19b2    | (bmp, x0, y0, x1, y1, colour), outline
        .equ TEXTF,       0x400c27a4    | (bmp, rawfont, x, y, maxlen, fmt, ...)
        .equ FONT5,       0x40200ebc    | the stock 5-px font
        .equ LOCK,        0x400018ec    | mutex lock(m)
        .equ UNLOCK,      0x40001a0e    | mutex unlock(m)
        .equ HEAPMTX,     0x4219cc00    | the heap's mutex
        .equ HEAPCB,      0x4020bec4    | buddy allocator control block
        .equ SMPFREE,     0x400eb9aa    | sample pool free bytes -> d0
        .equ SYSEX_SEND,  0x400d7046    | bool (buf, len, abort*, port); 2 = USB
        .equ DTMR0,       0xFC070000    | DMA timer 0 mode
        .equ DTCN0,       0xFC07000C    | DMA timer 0 counter, bus clock
        .equ PPMSR0,      0xFC04002D    | peripheral clock set register
        .equ CUR_TCB,     0x4399E798    | the running task's TCB
        .equ IDLE_TCB,    0x4198597C    | the idle task (the init task, parked)
        .equ IDLE_PC,     0x4006932E    | where it spins: bra.b *
        .equ VBR_FN,      0x40001c94    | the call 0x40000538 made
        .equ SYSEX_A3,    0x401b8d2a    | the SysEx router's table (the lea hook_sysex replaces)
