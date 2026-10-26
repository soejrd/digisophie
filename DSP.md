# Digitakt Mk1 Sophie DSP reference

This note records the parts of Digitakt Mk1 OS 1.53 that Sophie actually uses,
the renderer's fixed-point choices, and the remaining performance limit. It
is for developers changing the synth, not a substitute for the stock OS or
hardware testing. Addresses below come from this project's OS 1.53 adapter
and patch manifest; they must not be reused on another firmware version.

The [RingTone DSP reference](https://github.com/DigiAlchemydsp/RingTone/blob/main/DSP.md)
inspired this layout. RingTone documents the **Digitone Mk1 OS 1.43**, whose
second CPU runs its FM voices. Its addresses, shared-memory layout and patch
sites do not describe the Digitakt or Sophie.

## Audio path

Sophie is a custom SRC machine, ID 7. Core registers it, and elekloader's
machine-pages mod (core 3.0) draws its SRC and LFO pages from the page its
descriptor names (`ds_page` in `digitakt.c`) and calls `ds_inject` from its
render event `ev_render_voices` (order 20), at `0x40077fba`, after the stock
source work. Sophie patches no firmware place of its own (up to 1.1.13 it
hooked those 17 places itself, so it could not share a build with other
machines). For each Sophie track, `digitakt.c` reads its current
controls and trigger state, writes 32 mono `int32_t` source samples to the
track buffer at `0x80001a18 + 128*track`, then lets the stock AMP, filter,
mixer and sends process them. Sophie now folds that source buffer with its C
knob before the stock stages. The C knob keeps BR's persistent value slot but
is labelled FOLD; zero bypasses the fold. A fixed, interpolated gain curve
after the fold keeps the source level close to its original range. The SAMP
slot remains stock.

The audio callback runs every 32 frames at 48 kHz, about 1,500 times per
second. It is time-critical: a synth optimization must reduce work **while
the note is audible**, not just after the voice sleeps. The adapter's
per-track state is static; retriggering replaces that track's voice instead
of accumulating another one.

## Fixed-point renderer

`sophie.c` evaluates 16 synth samples at 24 kHz for each 32-frame output
block and linearly interpolates to 48 kHz. FUSE, PIPE and SHARD use two
1024-entry sine lookups per synth sample; BOOM uses a third lookup for its
clean low body. The common soft clip uses a 65-point lookup with linear
interpolation. These are intentional sound/performance tradeoffs; the
lookup quantization is part of the current sound.

The slowly moving controls, oscillator ratio, pitch step and FM bandwidth
ceiling update every four synth samples. Feedback and oscillators still
advance every synth sample. The AMP envelope remains the stock Digitakt
envelope: an active phase keeps Sophie awake even if its instantaneous
level crosses zero. After an idle/released envelope is quiet for 32 blocks,
Sophie fades its source over 128 synth samples and then skips synthesis.

The 0–127 control-to-Q15 conversion is exact using `258*x + (x == 127)`:
`32767 = 127*258 + 1`. This removes four signed divisions per active block
without changing a parameter value. This is in the post-S027 source candidate;
the tested 0.1.7 release remains available. The FM bandwidth ceiling has a
conditional signed division on slow-control ticks when the common no-clamp
case cannot be proven. Replacing it would require an error-bounded reciprocal
and listening tests at extreme pitch/METAL settings; it is not a free win.

The render loop keeps the voice's running state in locals for the block
(`ds_render_core`): the track buffer is `int32_t` like most voice fields, so
with the state in the struct the compiler reloads and stores each field around
every output sample. The soft clip and the FM index conversion are inlined, and
the index conversion's full-depth multiply (`mod * 32767 >> 15`) is the exact
`mod - (mod > 0)`. The output is the same, sample for sample and state for
state, as before (random voices, models, controls, triggers, envelope sleep,
odd block lengths and the fold).

## Verification boundaries

`make test` checks audio continuity, model differences, long-held voices,
retriggering and envelope sleep. `make cross-check ELEKLOADER=/path/to/elekloader`
compiles the C and glue for the MCF54415 (the page needs elekloader's SDK
header `digitakt-mk1/core3.h`). The elekloader build checks the mod against the user's
stock OS and verifies the patched firmware. Those checks do not measure
hardware CPU use. The optional digihealth mod shows live CPU/DSP load and
FAST AUDIO in SETTINGS, and `tests/timing_probe.py` can measure an emulated
render path where a compatible digiemu runtime is available.

`make golden-check` compiles `tests/golden_dump.c` against `HEAD` and against
the worktree, then compares hashes of both the output samples and the whole
`struct ds_voice`. Its 24 cases cover all models, default and extreme
controls, odd and even block lengths, retriggering, model changes,
sleep/wake, FOLD and a fixed control sweep. `tools/cycle_probe.py --static`
sums digiemu's MCF54418RM instruction costs over `ds_render_core`; it is a
code-shape measure, not a run. In this environment Unicorn exits with
`SIGILL` at `mem_map`, so the dynamic timing probe and the emulator fallback
to a hardware CPU-load reading are not available; compare static costs and
instruction counts between builds of the same driver instead.

`make emac-probe` counts `ds_mul` calls and the largest product while
rendering representative voices on the host. It shows where an EMAC path
could apply and whether every product fits `mac.l`'s exact range; it does not
time the target.

## Baseline (2026-10-26, 23419d8)

Recorded before the optimization work, with GCC 16.2.0 and binutils 2.47.

| item | value |
| --- | --- |
| `make test` | pass |
| `make cross-check` | pass |
| `make golden-check` | 24 cases, `sha256 daf840ff34fbe4af` |
| `out/cross/sophie.o` | `.text` 3968, `.rodata` 2342 bytes |
| `ds_render_core` | 2916 bytes, 936 instructions, 1226 static cycles |
| `ds_voice_render` (wrapper) | 638 bytes |
| `ds_render_core` mix | 266 move, 114 shift, 84 alu, 84 moveq, 68 bcc, 57 `muls.l`, 46 movea, 26 bra, 23 sign-extend |

The golden corpus is also identical against `fee5f51`, which confirms PR #5
kept the render bit-exact. `-mcpu=54415`, `-mcpu=54455` and
`-mcpu=54415 -mtune=cfv4e` produce byte-identical objects with this
toolchain, so the target change is documentation and correctness only.

## Optimization results

Measured against the baseline, all with `make golden-check` identical to
`23419d8` (`sha256 daf840ff34fbe4af`) and with one `muls.l` per `ds_mul`:

| change | `ds_render_core` | static cycles |
| --- | --- | --- |
| baseline | 2916 bytes, 936 instructions | 1226 |
| target, redundant work, one control copy, register params | 2828 bytes, 909 instructions | 1192 |
| SHARD RNG, shared slew, dead control fields, rare clip | 2736 bytes, 863 instructions | 1142 |

`ds_voice_render` was 638 bytes at baseline. The retained changes are
bit-exact on the golden corpus and the host tests.

The EMAC experiment was measured, not ported. Sophie calls `ds_mul` 49 times
per active block (FUSE default), 93 (BOOM/PIPE) and 141 (SHARD), and every
`|a*b|` in those voices is at most 1,339,777,096, well inside `mac.l`'s exact
range. Replacing each `muls.l` with `movclr.l`/`mac.l`/`movel` was 2 bytes
larger per site and did not reduce `ds_render_core`'s static code; it also
costs an accumulator move to return a 32-bit result. Fusing two products in
one accumulator changes `(a*b >> 15) + (c*d >> 15)` by up to one LSB, which
would be a sound change, not an exact one. No EMAC code was retained.

Do not transplant RingTone's Digitone-specific EMAC, Core B, DMA-buffer or
section-7 techniques into this Digitakt source hook. A new optimization
should preserve the audible result or have an explicit sonic reason, pass
the host and cross-build tests, and then be checked on a Digitakt.
