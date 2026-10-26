/* SPDX-License-Identifier: MIT */
/* Deterministic Sophie render corpus for the HEAD-to-worktree differential.
 * Hash both the output samples and the whole voice state, so a code change
 * that happens to leave one block's samples alone is still caught. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "sophie.h"

#define N 4096

static struct ds_voice v;
static struct ds_params p;
static int32_t out[N];
static int32_t folded[N];
static uint32_t audio_hash;
static uint32_t state_hash;
static unsigned cases;

static uint32_t fnv1a(uint32_t h, const void *data, size_t size)
{
    const uint8_t *p = (const uint8_t *)data;
    while (size--) {
        h ^= *p++;
        h *= 16777619u;
    }
    return h;
}

static void begin(void)
{
    memset(&v, 0, sizeof v);
    ds_voice_init(&v);
    audio_hash = 2166136261u;
    state_hash = 2166136261u;
}

static void render(uint32_t n, int trigger)
{
    ds_voice_render(&v, &p, trigger, out, n);
    audio_hash = fnv1a(audio_hash, out, (size_t)n * sizeof out[0]);
}

static void end(const char *name)
{
#ifndef DS_GOLDEN_AUDIO_ONLY
    state_hash = fnv1a(state_hash, &v, sizeof v);
    printf("%-28s audio=%08x state=%08x\n", name, audio_hash, state_hash);
#else
    printf("%-28s audio=%08x\n", name, audio_hash);
#endif
    ++cases;
}

static void fold_case(uint8_t amount)
{
    memcpy(folded, out, sizeof folded);
    ds_fold_block(folded, N, amount);
    audio_hash = fnv1a(audio_hash, folded, sizeof folded);
}

static void model_cases(unsigned model)
{
    char name[48];

    p = (struct ds_params){ 180, (uint8_t)model, 64, 90, 0, 32, 127, 0 };
    begin();
    render(32, 1);
    for (unsigned i = 1; i < 64; ++i)
        render(32, 0);
    snprintf(name, sizeof name, "model%u-default", model);
    end(name);

    p = (struct ds_params){ 68, (uint8_t)model, 127, 127, 63, 127, 1, 0 };
    begin();
    render(32, 1);
    for (unsigned i = 0; i < 128; ++i) {
        static const uint8_t lengths[8] = { 1, 2, 3, 17, 31, 33, 64, 127 };
        render(lengths[i & 7u], 0);
    }
    snprintf(name, sizeof name, "model%u-odd", model);
    end(name);

    p = (struct ds_params){ 24576, (uint8_t)model, 0, 127, -64, 127, 127, 0 };
    begin();
    render(32, 1);
    for (unsigned i = 1; i < 64; ++i)
        render(32, 0);
    snprintf(name, sizeof name, "model%u-high-sweep-down", model);
    end(name);

    p = (struct ds_params){ 8, (uint8_t)model, 127, 0, 63, 0, 64, 0 };
    begin();
    render(32, 1);
    for (unsigned i = 1; i < 64; ++i)
        render(32, 0);
    snprintf(name, sizeof name, "model%u-low-sweep-up", model);
    end(name);
}

int main(void)
{
    char name[48];
    unsigned model, i;

    for (model = 0; model < 4; ++model)
        model_cases(model);

    /* Retrigger while the previous voice is still sounding, with changing
     * controls and both silent and loud stock-AMP gates. */
    p = (struct ds_params){ 180, 0, 64, 90, 0, 32, 127, 0 };
    begin();
    for (i = 0; i < 48; ++i) {
        int trigger = (i % 5u) == 0;
        if (trigger) {
            p.velocity = (uint8_t)(16u + i * 5u);
            p.color = (uint8_t)(127u - i);
            p.metal = (uint8_t)(i * 3u);
        }
        ds_voice_gate(&v, (i & 1u) ? (1 << 23) : 0, (i & 1u) ? 3 : 0);
        render((i & 1u) ? 31u : 32u, trigger);
    }
    end("retrigger-changing");

    /* A model change with no trigger must replace the voice seamlessly in
     * the same way on both builds. */
    p = (struct ds_params){ 68, 0, 40, 70, 12, 45, 100, 0 };
    begin();
    render(32, 1);
    for (i = 1; i < 32; ++i) {
        if (i == 8) p.model = 2;
        if (i == 16) p.model = 3;
        if (i == 24) p.model = 1;
        render(32, 0);
    }
    end("model-change");

    /* Quiet stock AMP: 32 quiet blocks start the 128-sample fade, then the
     * voice sleeps. A loud gate wakes it with a fresh transition. */
    p = (struct ds_params){ 68, 3, 64, 40, 0, 32, 127, 0 };
    begin();
    render(32, 1);
    for (i = 0; i < 48; ++i) {
        ds_voice_gate(&v, 0, 0);
        render(32, 0);
    }
    ds_voice_gate(&v, 1 << 23, 3);
    for (i = 0; i < 16; ++i)
        render(32, 0);
    ds_voice_gate(&v, 0, 0);
    for (i = 0; i < 40; ++i) {
        ds_voice_gate(&v, 0, 0);
        render(32, 0);
    }
    ds_voice_gate(&v, 1 << 23, 3);
    render(32, 1);
    end("sleep-wake");

    /* FOLD after synthesis for every model, including the exact zero bypass
     * and the extremes of the one-knob curve. */
    for (model = 0; model < 4; ++model) {
        static const uint8_t amounts[5] = { 0, 1, 32, 64, 127 };
        p = (struct ds_params){ 180, (uint8_t)model, 64, 90, 0, 32, 127, 0 };
        begin();
        render(N, 1);
        for (i = 0; i < 5; ++i)
            fold_case(amounts[i]);
        snprintf(name, sizeof name, "model%u-fold", model);
        end(name);
    }

    /* A deterministic sweep across controls, models, block sizes, triggers
     * and gates. The LCG is fixed here so this is a regression corpus, not a
     * random test. */
    begin();
    {
        uint32_t seed = 0x534f5048u;
        for (i = 0; i < 192; ++i) {
            seed = seed * 1664525u + 1013904223u;
            p.model = (uint8_t)((seed >> 8) & 3u);
            p.color = (uint8_t)((seed >> 10) & 127u);
            p.metal = (uint8_t)((seed >> 17) & 127u);
            p.sweep = (int8_t)((int)((seed >> 4) & 127u) - 64);
            p.feedback = (uint8_t)((seed >> 21) & 127u);
            p.velocity = (uint8_t)((seed >> 3) & 127u);
            p.fold = (uint8_t)((seed >> 6) & 127u);
            p.phase_inc = (uint16_t)(8u + ((seed >> 12) % 24569u));
            ds_voice_gate(&v, (seed & 0x10000u) ? (1 << 23) : 0,
                          (seed & 0x20000u) ? 3 : 0);
            render(1u + ((seed >> 24) & 63u), (seed & 0x40000u) != 0);
        }
    }
    end("deterministic-mix");

    printf("cases=%u\n", cases);
    return 0;
}
