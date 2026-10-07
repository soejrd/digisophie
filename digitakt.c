/* SPDX-License-Identifier: MIT */
/* Digitakt Mk1 OS 1.53 and 1.54 adapter for the Sophie fixed-point engine. */
#include "sophie.h"
#ifdef OS154                       /* the Digitakt mk1 1.54 (mod.json's port) */
#include "os154.h"
#else                              /* the Digitakt mk1 1.53 */
#include "os153.h"
#endif

typedef unsigned char u8;
typedef unsigned short u16;
typedef signed short s16;
typedef signed long s32;
typedef unsigned long u32;

#define DS_MACHINE 7
#define TRACKS 8
#define TBUF(t) ((s32 *)(unsigned long)(OS_TBUF + 128u * (u32)(t)))
#define MACH(t) (*(volatile const u8 *)(unsigned long)(OS_MACH + (u32)(t)))
#define VP(t, o) (*(volatile const s16 *)(unsigned long)(OS_VP + 106u * (u32)(t) + (u32)(o)))
#define NOTE(t) (*(volatile const s32 *)(unsigned long)(OS_NOTE + 4u * (u32)(t)))
#define VEL(t) (*(volatile const s16 *)(unsigned long)(OS_VEL + 2u * (u32)(t)))
#define TRIG_BITS (*(volatile const u32 *)(unsigned long)OS_TRIG_BITS)
#define AMP_LEVEL(t) (*(volatile const s32 *)(unsigned long)(OS_AMP_LEVEL + 12u * (u32)(t)))
#define AMP_PHASE(t) (*(volatile const s32 *)(unsigned long)(OS_AMP_PHASE + 12u * (u32)(t)))
#define PITCH_TAB ((const u32 *)(unsigned long)OS_PITCH_TAB)

/* SLICE's persistent SRC slots: A..H.  Core makes those values recallable,
 * lockable and reachable via MIDI CC/NRPN for custom machines. */
#define P_TUNE 0
#define P_MODEL 2
#define P_FOLD 4
#define P_SWEEP 8
#define P_METAL 10
#define P_FEEDBACK 12
#define P_COLOR 14

static struct ds_voice ds_voices[TRACKS];

char *ds_fmt_model(char *out, s32 value)
{
    static const char names[4][6] = { "FUSE", "BOOM", "PIPE", "SHARD" };
    const char *in = names[(((u32)value >> 8) & 0x1fu) >> 3];
    u32 i = 0;
    while (in[i]) { out[i] = in[i]; ++i; }
    out[i] = 0;
    return out;
}

char *ds_fmt_sweep(char *out, s32 value)
{
    s32 n = (s32)(((u32)value >> 8) & 0x7fu) - 64;
    char *p = out;
    u32 magnitude;
    if (n > 0) *p++ = '+';
    else if (n < 0) { *p++ = '-'; n = -n; }
    magnitude = (u32)n;
    if (magnitude >= 10) *p++ = (char)('0' + magnitude / 10);
    *p++ = (char)('0' + magnitude % 10);
    *p = 0;
    return out;
}

char *ds_fmt_u7(char *out, s32 value)
{
    u32 n = ((u32)value >> 8) & 0x7fu;
    char *p = out;
    if (n >= 100) { *p++ = '1'; n -= 100; *p++ = (char)('0' + n / 10); }
    else if (n >= 10) *p++ = (char)('0' + n / 10);
    *p++ = (char)('0' + n % 10);
    *p = 0;
    return out;
}

static u32 ds_u7(s32 track, s32 offset)
{ return ((u32)(u16)VP(track, offset) >> 8) & 0x7fu; }

static u32 ds_pitch_ratio(s32 track)
{
    s32 pitch = ((s32)VP(track, P_TUNE) - 0x4000) * 256
        + NOTE(track) + (3 << 16);
    if (pitch < 0) pitch = 0;
    if (pitch > (87 << 16)) pitch = 87 << 16;
    return PITCH_TAB[(u32)pitch / 384u]; /* Q29, as stock playback uses. */
}

static void ds_read_params(s32 track, struct ds_params *p)
{
    u32 ratio = ds_pitch_ratio(track);
    p->phase_inc = (u16)(ratio >> 23); /* 50 Hz is 68 phase units/sample. */
    if (p->phase_inc < 8) p->phase_inc = 8;
    /* Four eight-step zones: deliberate, without excessive travel. */
    p->model = (u8)(ds_u7(track, P_MODEL) >> 3);
    p->fold = (u8)ds_u7(track, P_FOLD);
    p->color = (u8)ds_u7(track, P_COLOR);
    p->metal = (u8)ds_u7(track, P_METAL);
    p->sweep = (signed char)((s32)ds_u7(track, P_SWEEP) - 64);
    p->feedback = (u8)ds_u7(track, P_FEEDBACK);
    p->velocity = (u8)(((u32)(u16)VEL(track) >> 8) & 0x7fu);
}

void ds_inject(void)
{
    u32 triggers = TRIG_BITS;
    s32 track;
    for (track = 0; track < TRACKS; ++track) {
        struct ds_params params;
        u32 i;
        int trigger;
        if (MACH(track) != DS_MACHINE) {
            if (ds_voices[track].active) ds_voice_init(&ds_voices[track]);
            continue;
        }
        trigger = (triggers & (1u << track)) != 0;
        ds_voice_gate(&ds_voices[track], AMP_LEVEL(track), AMP_PHASE(track));
        if (!trigger && (!ds_voices[track].active || ds_voices[track].sleeping)) {
            s32 *out = TBUF(track);
            for (i = 0; i < DS_BLOCK_SIZE; ++i) out[i] = 0;
            continue;
        }
        ds_read_params(track, &params);
        ds_voice_render(&ds_voices[track], &params, trigger,
                        TBUF(track), DS_BLOCK_SIZE);
        ds_fold_block(TBUF(track), DS_BLOCK_SIZE, params.fold);
    }
}
