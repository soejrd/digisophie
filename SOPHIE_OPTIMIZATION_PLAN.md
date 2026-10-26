# SOPHIE optimization plan

## Objective

Reduce the audible render cost on the MCF54415 without changing the sound
unless a change is deliberately auditioned. Keep the existing fixed-point
engine and its portable host tests; generated `.elemod` files are verification
inputs, not code to review line by line.

## Current state

- Local `main`: `0876e82` applies PR #5 (including its two release files);
  later commits add and update this plan. The tree also quotes the elekloader
  SDK include path in `Makefile`, fixing checkouts whose path contains spaces.
- `origin/main` is still `fee5f51`; local `main` is ahead and has **not** been
  pushed. PR #5 is still open on GitHub.
- No real merge commit with PR #5's head exists yet. The local commit has the
  reviewed PR content, not the PR branch as a parent.
- Optimize in new commits on local `main`. Do not amend or rewrite `0876e82`,
  and do not push until the publishing step below.

## 1. Pin the baseline

- Record `fee5f51`, `make test`, `make cross-check`, and the current
  `ds_voice_render` size/opcode mix from `out/cross/sophie.o`.
- Save a small golden corpus: all four models, representative controls,
  odd/even block lengths, retrigger, model change, sleep/wake, and FOLD.
- Measure the current active-voice cost per block with digiemu's timing probe
  if available; otherwise use instruction counts and a hardware CPU-load
  reading. Do not use the PR's performance table as our baseline.

## 2. PR #5 status and publishing

PR #5 has been reviewed and incorporated into local `main`; do not repeat the
source review. Evidence: the diff applied cleanly, `make test` and
`make cross-check` pass, and a 6,000-block randomized differential against
`fee5f51` produced identical output and voice-state hashes. The page descriptor
matches the old names, ranges, defaults and knob mappings; machine-pages calls
`ds_inject` at the same `0x80001a18` buffer SOPHIE already uses. The
`mod - (mod > 0)` shortcut is exact here because the sine table's minimum is
`-32767`, never `-32768`.

**Do not push yet.** Pushing local `main` without wiring in the real PR head
would publish the content but leave PR #5 open, since GitHub does not match
patch-equivalent commits. Do not click GitHub's merge button either; that would
make remote `main` diverge from local work.

After optimization commits are ready, publish with the real PR history:

```sh
git fetch origin pull/5/head:pr5
git merge --no-ff pr5        # keep the quoted Makefile include if it conflicts
make test && make cross-check ELEKLOADER=/path/to/elekloader
git log --oneline --graph -6 # confirm PR head is a parent and review commits remain
git push origin main
```

Once pushed, GitHub should mark PR #5 merged. If fetching is unavailable, the
owner can run the fetch/merge commands; as a last resort, push and close PR #5
with a comment pointing to the pushed commit, but that is less tidy.

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
