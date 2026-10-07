| SPDX-License-Identifier: MIT
| Digitakt mk1 MAIN OS 1.54: the stock code and data glue.s uses (os153.inc and
| os154.inc, one per OS; glue.s includes the one OS154 picks).
        .equ BMP_VT,            0x401b7734    | the firmware's Bitmap vtable
        .equ LAY_SLICE,         0x4197df5c    | SLICE's SRC page layout
        .equ INJECT_LEA,        0x4199f444    | what the inject site's lea loads into a4
        .equ DESC_TAB,          0x401aa09c    | the parameter descriptor table (52-byte rows)
        .equ DESC_TAB_40,       0x401aa0c4    | ...its +40 field (the popup's name)
        .equ DESC_TAB_48,       0x401aa0cc    | ...its +48 field (the overview's name)
        .equ STR_SAMP,          0x401cce3e    | the stock SAMP parameter's name
        .equ PARAM_VT,          0x4017ee58    | the SRC page's parameter object's vtable
        .equ SNDREF_VT,         0x40181630    | the vtable of the object at its +16
        .equ PRANGE_FN,         0x40078f0c    | the parameter range lookup
        .equ LAYOUT_ON,         0x400657d2    | the page layout, past its site
        .equ UI_REC_ON,         0x4006579e    | the UI record, past its site
        .equ POP_TEXT_ON,       0x400657f8    | the pop-up text, past its site
        .equ LAB_SHORT_ON,      0x4000fe94    | the short label, past its site
        .equ LAB_LONG_ON,       0x4000feb6    | the long label, past its site
        .equ VAL_TEXT_ON,       0x4000f32c    | a knob's value text, past its site
        .equ KNOB_GFX_ON,       0x4000f2c4    | a knob's graphic, past its site
        .equ LFO_LABEL_ORIG,    0x40060b94    | the LFO destination's descriptor lookup, as stock
        .equ LFO_LABEL_ON,      0x40060baa    | the LFO destination label, past its site
        .equ POPUP_NAME_ON,     0x400a44d6    | the destination popup name, past its site
        .equ POPUP_FALLBACK_ON, 0x400a4552    | the destination popup fallback, past its site
        .equ OVERVIEW_GROUP_ON, 0x40065dec    | the LFO overview group, past its site
        .equ OVERVIEW_NAME_ON,  0x40065e68    | the LFO overview name, past its site
