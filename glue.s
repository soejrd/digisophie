| SPDX-License-Identifier: MIT
| (Digitakt mk1 OS 1.53 and 1.54: the addresses in the comments are 1.53's;
| the code takes them from os153.inc or os154.inc.)
        .ifdef  OS154                   | the Digitakt mk1 1.54 (mod.json's port)
        .include "os154.inc"
        .else                           | the Digitakt mk1 1.53
        .include "os153.inc"
        .endif
| Sophie's machine registration. Its SRC and LFO pages are elekloader's
| machine-pages mod's (core 3.0): the descriptor's tail names the page it draws
| them from (digitakt.c ds_page), and machine-pages' render event calls
| ds_inject (mod.json), so SOPHIE hooks no firmware place of its own.
        .section .run, "ax"
        .balign 4
        .globl ds_machine
ds_machine:
        .long   7, ds_name, ds_short, ds_icon_bmp, 3, 7
        .long   0x55493330, ds_page     | core 3.0: "UI30", the page
ds_name: .asciz "SOPHIE"
ds_short: .asciz "SOPH"
        .balign 4
ds_icon_bmp:
        .long BMP_VT, 11, 7, 1, ds_icon_px, ds_icon_mask, 0
ds_icon_px:
        .long 0x10400000,0x28a00000,0x55400000,0xaa800000
        .long 0x55400000,0x28a00000,0x10400000,0x00000000
        .long 0x00000000,0x00000000,0x00000000
ds_icon_mask:
        .long 0xfe000000,0xfe000000,0xfe000000,0xfe000000
        .long 0xfe000000,0xfe000000,0xfe000000,0x00000000
        .long 0x00000000,0x00000000,0x00000000
