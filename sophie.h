/* SPDX-License-Identifier: MIT */
#ifndef DIGISOPHIE_SOPHIE_H
#define DIGISOPHIE_SOPHIE_H

#include <stdint.h>

#define DS_BLOCK_SIZE 32
/* Exact 0..127 to Q15 mapping without a ColdFire signed divide:
 * 32767 = 127*258 + 1. */
static inline int32_t ds_u7_q15(uint8_t x)
{ return ((int32_t)x << 8) + ((int32_t)x << 1) + (x == 127); }

/* SRC values are decoded by the Digitakt adapter into these native domains. */
struct ds_params {
    uint16_t phase_inc;
    uint8_t model;
    uint8_t color;
    uint8_t metal;
    int8_t sweep;
    uint8_t feedback;
    uint8_t velocity;
    uint8_t fold;
};

struct ds_voice {
    uint32_t carrier;
    uint32_t mod1;
    int32_t amp;
    int32_t pitch;
    int32_t attack;
    int32_t feedback_z;
    int32_t noise_z;
    uint32_t rng;
    int32_t color_s, metal_s, feedback_s, velocity_s;
    int32_t last, tail;
    uint8_t transition, model;
    uint8_t active, sleeping, quiet_blocks;
    uint8_t fade_left;
};

void ds_voice_init(struct ds_voice *voice);
void ds_voice_gate(struct ds_voice *voice, int32_t amp_level,
                   int32_t amp_phase);
void ds_voice_render(struct ds_voice *voice, const struct ds_params *params,
                     int trigger, int32_t *output, uint32_t size);
void ds_fold_block(int32_t *output, uint32_t size, uint8_t amount);

#endif
