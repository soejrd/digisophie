# SOPHIE optimization plan

## Objective

Land PR #5 only after reviewing its two changes separately, then reduce the
audible render cost on the MCF54415 without changing the sound unless a change
is deliberately auditioned. Keep the existing fixed-point engine and its
portable host tests; generated `.elemod` files are verification inputs, not
code to review line by line.

## 1. Pin the baseline

- Record `fee5f51`, `make test`, `make cross-check`, and the current
  `ds_voice_render` size/opcode mix from `out/cross/sophie.o`.
- Save a small golden corpus: all four models, representative controls,
  odd/even block lengths, retrigger, model change, sleep/wake, and FOLD.
- Measure the current active-voice cost per block with digiemu's timing probe
  if available; otherwise use instruction counts and a hardware CPU-load
  reading. Do not use the PR's performance table as our baseline.

## 2. Review and incorporate PR #5

Prerequisite: GitHub access to `github.com`, `api.github.com` and
`patch-diff.githubusercontent.com`, or a user-supplied `/tmp/pr5.diff`.
Fetch `refs/pull/5/head`; do not merge from the PR description alone.

Review the two commits separately:

1. `3ea055b` — render rewrite (`sophie.c`).
   - Verify the claimed bit-exact change: the full-depth multiply to
     `mod - (mod > 0)` for the Q15 index, no signed-overflow surprises, odd
     block lengths, retriggers, sleep/wake, and state written back after the
     block.
   - Check that inlining soft clip/index conversion keeps a cold fallback and
     does not turn a rare path into an unsafe assumption.
   - Compare exact output and voice state against `fee5f51`; run host and
     cross-build tests. If it differs, isolate the change rather than accepting
     the claim.
2. `82a52d7` — machine-pages integration (`digitakt.c`, `glue.s`, `mod.json`,
   `Makefile`, `scripts/build.sh`).
   - Confirm the `"UI30"` descriptor, `struct cm_ui` layout, machine 7,
     `page_from`, knob names/ranges/defaults/value text, and the `ev_render_voices`
     order-20 subscription match the local core 3.0/machine-pages 1.1 contract.
   - Confirm the 17 old firmware sites are gone, both OS ports still match,
     `requires`/`resources.core` are correct, and saved SOPHIE tracks remain
     machine 7.
   - Verify `scripts/build.sh` builds machine-pages and the 1.53/1.54 variants;
     keep the 1.1.13 release for older elekloader.

Review `DSP.md`, `README.md`, `os*.inc`, and `release/` only for stale claims,
wrong versions, or accidental changes; rebuild artifacts rather than auditing
their bytes. Integrate in commit order: bring `3ea055b` onto a review branch
and verify it in isolation, then add `82a52d7`. Keep the two commits intact
until both pass, so an audio regression is attributable.

## 3. Exact C and codegen wins

- Change the documented target from `-mcpu=54455` to `-mcpu=54415` (with
  `-mtune=cfv4e` if supported) and compare code size, disassembly, and cycles.
  The current M68k GCC emits identical code for 54415/54455 here, so this is a
  target-correctness step, not an assumed speedup.
- Inline `ds_soft_clip` and `ds_index_phase` only after checking the compiler
  removes the call; keep the rare soft-clip fallback cold.
- Hoist block-invariant model/parameter work and keep frequently updated voice
  state in registers for the block. Measure each change separately against the
  baseline.
- Confirm and remove unused `ds_voice` fields (`mod2`, `mod3`, `sub`, `upper`,
  `split`) only if no external/test use and the ABI remains acceptable.
- Audit `movel`, `mulsl`, sign-extension and stack traffic in the hot loop.
  Prefer a smaller number of real instructions over source-level cleverness.
- Only specialize the four model loops if code size and timing justify it;
  retain one generic path and reject a cache-size regression.
- Leave the rare signed `ceiling` divide alone unless profiling shows it
  matters; any reciprocal must be compared over the full input range.

## 4. ColdFire/EMAC experiment

This is a measured experiment, not a port of the archive's 24×24 EMAC
primitive. Sophie's `ds_mul` takes 32-bit operands and usually emits one
`muls.l`, so replacing it blindly may add accumulator moves for no gain. Use
MCF54418RM chapter 5 for MACSR/ACC/ext semantics and CFDSPLibraryRM only for
saturation and cycle guidance; its 16-bit datapath is not Sophie's width.

- Build a microbenchmark of the current `ds_mul` versus an inline `mac.l`/
  `movclr.l` equivalent, with MACSR set once per block.
- Preserve ACC0, ACCext01 and MACSR around the render callback; restore MACSR
  last. Keep a portable non-EMAC build.
- Try EMAC only where several products feed one expression, and only where
  combining `(a*b >> 15) + (c*d >> 15)` into one accumulator is either proven
  equivalent or consciously accepted as a sound change after listening.
- Keep the experiment if it improves active-block cycles on the target and
  passes the golden/audio check; otherwise leave the portable path and record
  the negative result.

## 5. Release gate

- `make test`, `make cross-check`, and the PR's exactness harness.
- One elekloader lint/build on OS 1.53 and 1.54 with core 3.0/machine-pages 1.1,
  including a mixed-machine build and a saved-track load check.
- One emulator screen/audio smoke test, then one hardware pass on four tracks
  across all models at extreme controls: CPU load, no dropouts, and listening.

Do not expand this into an exhaustive per-knob or per-sample matrix. Tag only
when both PR commits and each retained optimization have before/after evidence.

## Scope guards

- Do not transplant Digitone Core B, DMA, or section-7 techniques.
- Do not change model sound as a side effect of a performance patch.
- Do not hand-edit release binaries; regenerate them from reviewed sources.
- Do not merge the PR until the actual diff and the machine-pages contract
  have both been checked.
