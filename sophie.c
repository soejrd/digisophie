/* SPDX-License-Identifier: MIT
 *
 * Fixed-point adaptation of Sophie, an original metallic percussion engine
 * by the Schwung Sophie contributors.  The Digitakt port deliberately omits
 * Sophie's drive and filter: its stock AMP and filter stages own those jobs.
 */
#include "sophie.h"

#define Q15 32767

static int32_t ds_clamp(int32_t x, int32_t lo, int32_t hi)
{ return x < lo ? lo : (x > hi ? hi : x); }
static int32_t ds_mul(int32_t a, int32_t b) { return (a * b) >> 15; }

/* Roughly 1.3 ms slow-control smoothing. At 24 kHz the synth updates these
 * controls every four samples, equivalent to eight 48 kHz output frames. */
static int32_t ds_slew_pow2(int32_t value, int32_t target, unsigned shift)
{
    int32_t delta = target - value;
    uint32_t mag = delta < 0 ? 0u - (uint32_t)delta : (uint32_t)delta;
    int32_t step = (int32_t)((mag + ((1u << shift) - 1u)) >> shift);
    return value + (delta < 0 ? -step : step);
}

static int32_t ds_slew8(int32_t value, int32_t target)
{ return ds_slew_pow2(value, target, 3); }

static int32_t ds_slew32(int32_t value, int32_t target)
{ return ds_slew_pow2(value, target, 5); }

/* The fixed-point oscillator uses one cached table read per sample. The
 * previous polynomial required several multiplies for every FM oscillator. */
static const int16_t ds_sine_full[1024] = {
#include "sophie_sin_table.inc"
};

static int32_t ds_sin(uint32_t phase)
{
    return ds_sine_full[phase >> 22];
}

static uint32_t ds_phase_from_radians_q15(int32_t radians)
{
    /* radians(Q15) * 65536 / (2*pi), returned in the phase accumulator's
     * high-word units.  The halved constant avoids overflowing int32_t at
     * maximum oscillator feedback. */
    return (uint32_t)((radians * 5215) >> 14) << 16;
}

static inline __attribute__((always_inline)) uint32_t ds_index_phase(int32_t index_q12, int32_t mod_q15,
                               int32_t factor_q15)
{
    /* (mod * 32767) >> 15 is mod - 1 for mod > 0 and mod otherwise (|mod| < 2^15): no multiply */
    int32_t scaled = factor_q15 == Q15 ? mod_q15 - (mod_q15 > 0) : ds_mul(mod_q15, factor_q15);
    int32_t n = (scaled >> 4) * index_q12;
    uint32_t a = n < 0 ? 0u - (uint32_t)n : (uint32_t)n;
    /* 163/131072 approximates 1/804 within 0.016%. Splitting n before
     * multiplication keeps the entire conversion in 32-bit registers and
     * avoids a long divide for every oscillator. */
    uint32_t q = (((a >> 9) * 163u) + (((a & 511u) * 163u) >> 9)) >> 8;
    return (uint32_t)(n < 0 ? -(int32_t)q : (int32_t)q) << 16;
}

/* Exact soft-clip points at 1024-unit intervals. Linear interpolation stays
 * within nine 16-bit units of the original curve and avoids two long
 * divisions per sample on ColdFire. */
static const uint16_t ds_clip_table[65] = {
    0, 992, 1927, 2808, 3640, 4428, 5173, 5881, 6553,
    7192, 7801, 8382, 8936, 9466, 9972, 10457, 10922, 11368,
    11796, 12207, 12602, 12983, 13349, 13702, 14043, 14371, 14688,
    14995, 15291, 15578, 15855, 16123, 16383, 16635, 16880, 17117,
    17347, 17570, 17788, 17999, 18204, 18403, 18597, 18786, 18970,
    19149, 19324, 19494, 19660, 19822, 19980, 20134, 20284, 20431,
    20574, 20715, 20851, 20985, 21116, 21244, 21370, 21492, 21612,
    21729, 21844
};

static inline __attribute__((always_inline)) int32_t ds_soft_clip(int32_t x)
{
    uint32_t a = x < 0 ? 0u - (uint32_t)x : (uint32_t)x;
    int32_t y;
    if (a >= 65536u) {
        /* Defensive fallback outside the oscillator's bounded range. */
        if (a > 131072u) a = 131072u;
        y = (int32_t)(((a >> 1) * Q15) / ((Q15 + a) >> 1));
    } else {
        uint32_t pos = a >> 10;
        int32_t lo = ds_clip_table[pos];
        y = lo + ((ds_clip_table[pos + 1] - lo) * (int32_t)(a & 1023u) >> 10);
    }
    return x < 0 ? -y : y;
}

/* Bipolar exponential pitch contour: roughly +/-4.5 octaves at the
 * transient, converging on the played note.  Linear interpolation inside
 * each octave is monotonic, cheap on ColdFire and close to exp2(). */
static const uint16_t ds_inverse_octave[65] = {
    32768, 32264, 31775, 31301, 30840, 30394, 29959, 29537,
    29127, 28728, 28340, 27962, 27594, 27236, 26887, 26546,
    26214, 25891, 25575, 25267, 24966, 24672, 24385, 24105,
    23831, 23564, 23302, 23046, 22795, 22550, 22310, 22075,
    21845, 21620, 21400, 21183, 20972, 20764, 20560, 20361,
    20165, 19973, 19784, 19600, 19418, 19240, 19065, 18893,
    18725, 18559, 18396, 18236, 18079, 17924, 17772, 17623,
    17476, 17332, 17190, 17050, 16913, 16777, 16644, 16513,
    16384
};

static int32_t ds_swept_inc(uint16_t base, int8_t amount, int32_t env)
{
    int32_t oct_q12 = ((int32_t)amount * env * 9) >> 10;
    int32_t octave, fraction, inc;
    if (oct_q12 >= 0) {
        octave = oct_q12 >> 12;
        fraction = oct_q12 & 4095;
        inc = ((int32_t)base * (4096 + fraction)) >> 12;
        inc <<= octave;
    } else {
        int32_t recip;
        oct_q12 = -oct_q12;
        octave = oct_q12 >> 12;
        fraction = oct_q12 & 4095;
        recip = ds_inverse_octave[fraction >> 6];
        recip += ((ds_inverse_octave[(fraction >> 6) + 1] - recip)
                  * (fraction & 63)) >> 6;
        inc = ((int32_t)base * recip) >> 15;
        inc >>= octave;
    }
    return ds_clamp(inc, 8, 24576);
}

static uint32_t ds_rand(uint32_t *rng)
{
    uint32_t x = *rng ? *rng : 0x534f5048u;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    *rng = x;
    return x;
}

static int32_t ds_noise(uint32_t *rng)
{ return (int32_t)((ds_rand(rng) >> 16) & 0xffffu) - 32768; }

void ds_voice_init(struct ds_voice *v)
{
    v->carrier = v->mod1 = v->mod2 = v->mod3 = 0;
    v->sub = v->upper = v->split = 0;
    v->amp = v->pitch = v->attack = v->feedback_z = v->noise_z = 0;
    v->rng = 0x534f5048u;
    v->color_s = v->metal_s = v->feedback_s = v->velocity_s = 0;
    v->last = v->tail = 0;
    v->transition = v->model = 0;
    v->sleeping = v->quiet_blocks = v->fade_left = 0;
    v->active = 0;
}

/* Stock AMP owns note-off and duration. Its level passes through zero at the
 * start of an active envelope, so level alone must never put a held note to
 * sleep. Phase zero is the released/idle state. Once that phase is quiet,
 * fade our still-oscillating source before sleeping. */
void ds_voice_gate(struct ds_voice *v, int32_t amp_level, int32_t amp_phase)
{
    uint32_t mag;
    if (!v->active) return;
    mag = amp_level < 0 ? 0u - (uint32_t)amp_level : (uint32_t)amp_level;
    if (amp_phase != 0 || mag > (1u << 19)) {
        v->quiet_blocks = 0;
        if (v->fade_left) {
            v->tail = v->last;
            v->transition = 64;
            v->fade_left = 0;
        }
        if (v->sleeping) {
            v->sleeping = 0;
            v->tail = 0;
            v->transition = 64;
        }
    } else if (v->quiet_blocks < 32) {
        if (++v->quiet_blocks == 32) {
            v->fade_left = 128; /* 256 output frames, about 5.3 ms */
        }
    }
}

/* The synthesis of synth samples i, i + 2, .. below end (output frames i .. end - 1, end - i even),
 * into out. The voice's running state is held in locals (the CPU's registers) meanwhile: the output
 * buffer is int32_t like most of its fields, so with them in the struct the compiler would reload and
 * store each one around every output sample. */
/* the slow controls of a block, as set at its last control tick */
struct ds_ctl { int32_t feedback, fbk, ratio, index, inc, mod_inc; };

static __attribute__((noinline)) void
ds_render_core(struct ds_voice *v, const struct ds_params *p, uint8_t model,
               int32_t color_target, int32_t metal_target, int32_t feedback_target,
               int32_t velocity_target, struct ds_ctl *ctl, int32_t *out, uint32_t i, uint32_t end)
{
    int32_t feedback = ctl->feedback, fbk = ctl->fbk;
    int32_t ratio = ctl->ratio, index = ctl->index, inc = ctl->inc, mod_inc = ctl->mod_inc;
    int32_t rate = 0;
    uint32_t carrier, mod1;
    int32_t pitch, amp, attack, feedback_z, noise_z, last, tail;
    int32_t color_s, metal_s, feedback_s, velocity_s;
    uint32_t transition, fade_left;
    uint32_t sleeping = v->sleeping;
    uint32_t rng = v->rng;
    uint16_t phase_inc = p->phase_inc;
    int8_t sweep = p->sweep;
    carrier = v->carrier; mod1 = v->mod1;
    pitch = v->pitch; amp = v->amp; attack = v->attack;
    feedback_z = v->feedback_z; noise_z = v->noise_z; last = v->last; tail = v->tail;
    color_s = v->color_s; metal_s = v->metal_s; feedback_s = v->feedback_s; velocity_s = v->velocity_s;
    /* COLOR and METAL equal their smoothed values after every control tick,
     * so the smoothed locals are the only copy in the loop. */
    transition = v->transition; fade_left = v->fade_left;
    /* A two-operator core at 24 kHz. The models share one inharmonic modulator
     * and one pitched carrier; only BOOM reads the carrier twice so its clean
     * low-frequency body survives an aggressively FM'd attack. */
    for (; i < end; i += 2, out += 2) {
        int32_t mod, raw, fb, phase_mod;
        int32_t y;
        uint32_t control_tick = (i & 7u) == 0;
        if (control_tick) {
            color_s = ds_slew8(color_s, color_target);
            metal_s = ds_slew8(metal_s, metal_target);
            feedback_s = ds_slew8(feedback_s, feedback_target);
            velocity_s = ds_slew8(velocity_s, velocity_target);
            feedback = ds_mul(feedback_s, feedback_s);
            fbk = 8192 + ((metal_s * 40960) >> 15);
            switch (model) {
            default: ratio = 1925 + ((ds_mul(color_s, color_s) * 31130) >> 15); break;
            case 1: ratio = 2457 + ((color_s * 17203) >> 15); break;
            case 2: ratio = 5366 + ((color_s * 24576) >> 15); break;
            case 3: ratio = 1925 + ((color_s * 32767) >> 15); break;
            }
        }
        pitch -= (pitch * 48 + 32767) >> 15;
        amp -= (amp * 10 + 32767) >> 15;
        if (attack < Q15) attack = ds_slew32(attack, Q15);
        if (control_tick) {
            int32_t inc_ratio;
            inc = sweep ? ds_swept_inc(phase_inc, sweep, pitch) : phase_inc;
            inc_ratio = inc * ratio;
            mod_inc = inc_ratio >> 11;
            rate = inc_ratio >> 12;
        }
        carrier += (uint32_t)inc << 17;
        mod1 += (uint32_t)mod_inc << 16;
        /* Diet: with no feedback the loop contributes exactly 0
         * (ds_mul(z, 0) == 0), so skip the modulator read, the radian
         * conversion and the smoother update. Bit-exact while FBK stays
         * 0; raising FBK mid-note reconverges from the frozen smoother
         * within samples (inaudible). */
        if (feedback) {
            fb = ds_mul(feedback_z, feedback);
            fb = (fb * fbk) >> 12;
            mod = ds_sin(mod1 + ds_phase_from_radians_q15(fb));
        } else {
            mod = ds_sin(mod1);
        }
        if (control_tick) {
            int32_t shape = 8192 + 3 * (8192 + ds_mul(amp, 24576));
            int32_t metal2 = ds_mul(metal_s, metal_s);
            int32_t bandwidth, ceiling;
            index = ((metal2 >> 2) * shape) >> 13;
            rate = ((rate >> 4) * (4096 + ((metal_s * 10240) >> 15))) >> 8;
            if (rate < 1) rate = 1;
            bandwidth = 16384 - inc;
            if (bandwidth < 256) bandwidth = 256;
            if (index <= 4096 && rate <= 4096 &&
                index * rate <= bandwidth * 4096) {
            } else {
                ceiling = (bandwidth * 4096) / rate;
                if (index > ceiling) index = ceiling;
            }
        }
        phase_mod = ds_index_phase(index, mod, Q15);

        switch (model) {
        default:
            raw = ds_sin(carrier + phase_mod);
            break;
        case 1: {
            int32_t body = ds_sin(carrier);
            int32_t edge = ds_sin(carrier + phase_mod);
            int32_t edge_mix = 2048 + ds_mul(metal_s, amp) / 2;
            raw = ds_mul(body, Q15 - edge_mix) + ds_mul(edge, edge_mix);
            break;
        }
        case 2: {
            int32_t body = ds_sin(carrier + phase_mod);
            int32_t ring = ds_mul(body, mod);
            int32_t ring_mix = 10240 + (metal_s >> 1) + (amp >> 3);
            raw = ds_mul(body, Q15 - ring_mix) + ds_mul(ring, ring_mix);
            raw += raw >> 2;
            break;
        }
        case 3:
            raw = ds_sin((carrier & 0xf8000000u) + phase_mod);
            /* Diet: at METAL 0 the bloom term is exactly 0, so skip the
             * LPF and the LFSR advance. Bit-exact while METAL stays 0;
             * raising it restarts from frozen state (white restarts
             * white — statistically identical, inaudible). */
            if (metal_s) {
                noise_z += ds_mul(ds_noise(&rng) - noise_z, 655 + ds_mul(color_s, 11469));
                raw = ds_mul(raw, 27852 - (metal_s >> 2))
                    + ds_mul(noise_z, ds_mul(ds_mul(metal_s, amp), 13762));
            } else {
                raw = ds_mul(raw, 27852);
            }
            break;
        }
        /* Frozen while feedback is 0 (see above); resumes on raise. */
        if (feedback)
            /* ((raw * 45) >> 5) is exactly raw + ((raw * 13) >> 5): the
             * extra 32*raw is divisible before the floor shift. */
            feedback_z += (ds_soft_clip((raw * 45) >> 5) - feedback_z) / 8;
        if (attack < Q15) raw = ds_mul(raw, attack);

        y = ds_mul(raw, velocity_s);
        y = ds_soft_clip(y) / 2;
        if (transition) {
            y = (y * (64 - (int32_t)transition) + tail * (int32_t)transition) / 64;
            transition = transition > 2 ? transition - 2 : 0;
        }
        if (fade_left) {
            y = (y * (int32_t)fade_left) / 128;
            if (--fade_left == 0) {
                sleeping = 1;
                tail = 0;
                transition = 0;
            }
        }
        out[0] = ((last + y) / 2) * 65536;
        out[1] = y * 65536;
        last = sleeping ? 0 : y;
    }
    v->carrier = carrier; v->mod1 = mod1;
    v->pitch = pitch; v->amp = amp; v->attack = attack;
    v->feedback_z = feedback_z; v->noise_z = noise_z; v->last = last; v->tail = tail;
    v->color_s = color_s; v->metal_s = metal_s; v->feedback_s = feedback_s; v->velocity_s = velocity_s;
    v->rng = rng;
    v->transition = (uint8_t)transition; v->fade_left = (uint8_t)fade_left;
    v->sleeping = (uint8_t)sleeping;
    ctl->feedback = feedback; ctl->fbk = fbk;
    ctl->ratio = ratio; ctl->index = index; ctl->inc = inc; ctl->mod_inc = mod_inc;
}


void ds_voice_render(struct ds_voice *v, const struct ds_params *p,
                     int trigger, int32_t *out, uint32_t n)
{
    struct ds_ctl ctl = {0, 0, 0, 0, 0, 0};
    uint32_t i;
    uint8_t model = p->model & 3u;
    int32_t color_target = ds_u7_q15(p->color);
    int32_t metal_target = ds_u7_q15(p->metal);
    int32_t feedback_target = ds_u7_q15(p->feedback);
    int32_t velocity_target = ds_u7_q15(p->velocity);
    if (trigger || (v->active && v->model != model)) {
        if (!v->active) {
            v->color_s = color_target; v->metal_s = metal_target;
            v->feedback_s = feedback_target; v->velocity_s = velocity_target;
        }
        v->tail = v->last;
        v->transition = 64;
        v->model = model;
        v->carrier = v->mod1 = v->mod2 = v->mod3 = 0;
        v->sub = v->upper = v->split = 0;
        v->amp = Q15;
        v->pitch = Q15;
        v->attack = 0;
        v->feedback_z = v->noise_z = 0;
        v->rng ^= 0x9e3779b9u + ((uint32_t)p->velocity << 16);
        v->sleeping = v->quiet_blocks = v->fade_left = 0;
        v->active = 1;
    }
    if (!v->active) {
        for (i = 0; i < n; i++)
            out[i] = 0;
        return;
    }
    if (n & 1) {                                /* an odd length: its last frame from a whole sample */
        int32_t pair[2];
        ds_render_core(v, p, model, color_target, metal_target, feedback_target, velocity_target,
                       &ctl, out, 0, n - 1);
        ds_render_core(v, p, model, color_target, metal_target, feedback_target, velocity_target,
                       &ctl, pair, n - 1, n + 1);
        out[n - 1] = pair[0];
    } else {
        ds_render_core(v, p, model, color_target, metal_target, feedback_target, velocity_target,
                       &ctl, out, 0, n);
    }
}

/* Fold the 16.16 source after synthesis, before the stock AMP/filter path.
 * The triangular wrap needs no division or lookup.  Zero is a bit-exact
 * bypass, including for old sounds whose BR slot was left at zero. */
void ds_fold_block(int32_t *out, uint32_t n, uint8_t amount)
{
    uint32_t i;
    uint32_t index, fraction;
    int32_t drive, level;
    /* Measured against sustained FUSE, BOOM, PIPE and SHARD output.  The
     * inverse gain eases back up above 64 because repeated folding then
     * reduces RMS.  Interpolate once per block, not once per sample. */
    static const uint16_t level_q8[17] = {
        256, 171, 128, 102, 85, 73, 64, 61, 59,
        63, 67, 72, 77, 82, 87, 91, 95
    };
    if (!amount) return;
    drive = 256 + (int32_t)amount * 16; /* 1.0625x .. 8.9375x */
    index = amount >> 3;
    fraction = amount & 7u;
    level = ((int32_t)level_q8[index] * (8 - (int32_t)fraction)
           + (int32_t)level_q8[index + 1] * (int32_t)fraction + 4) >> 3;
    for (i = 0; i < n; ++i) {
        /* Shifts, not divides: |x| <= 32768 and drive <= 2288, so
         * |x * drive| <= 75M < 2^31; |folded * level| <= 8.4M. Exact on
         * multiples, +-1 LSB elsewhere (inherent, inaudible). */
        int32_t x = out[i] >> 16;
        int32_t driven = (x * drive) >> 8;
        uint32_t phase = ((uint32_t)(driven + 32768)) & 0x1ffffu;
        int32_t folded = (int32_t)(phase < 65536u ? phase : 131071u - phase) - 32768;
        out[i] = ((folded * level) >> 8) * 65536;
    }
}
