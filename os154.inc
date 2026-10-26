| SPDX-License-Identifier: MIT
| Digitakt mk1 MAIN OS 1.54: the stock code and data glue.s uses (os153.inc and
| os154.inc, one per OS; glue.s includes the one OS154 picks).
        .equ BMP_VT,            0x401b7734    | the firmware's Bitmap vtable
