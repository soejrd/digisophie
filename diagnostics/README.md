# Hardware diagnostics (S027)

The S027 build bundles digihealth's `SYSTEM INFO` monitor, from
[irpina/digihealth](https://github.com/irpina/digihealth) at commit
`72f0183383e67c3313146bf77df6f71dd7996a8f`, with that repository's OS 1.54
port (`6d2a956`, irpina/digihealth#4) applied on top. The copied source and
license are in `digihealth/`. It is GPL-2.0-or-later; Sophie itself remains
MIT licensed.

The one local behavior change is in `fastaudio.s`: FAST AUDIO no longer
switches itself on after boot. Its SETTINGS row remains available for a
separate experiment, but leave it off when measuring Sophie's own cost.
The `SYSTEM INFO` row enables a top-bar readout that alternates between
CPU/DSP usage and free heap/sample RAM. DSP shows current load and the peak
in the last second. The readout starts off; enable it in SETTINGS.

For a reproducible hardware test, start an otherwise empty project and
record CPU, DSP and DSP peak in these states: before Sophie has sounded,
while holding/retriggering one Fuse note, after its AMP tail, and while
holding/retriggering Boom. Repeat with FAST AUDIO on only after collecting
the off measurements. A DSP peak approaching 100% alongside late LEDs or
STOP confirms audio-render pressure. Healthy DSP numbers during the lag
would point to a different stall and should be investigated separately.

The diagnostic code adds render-entry/exit timer reads even while its
top-bar readout is hidden. It is intentionally retained in the S027
firmware so the device can measure the same image that you hear.
