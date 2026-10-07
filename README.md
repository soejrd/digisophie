# Sophie for Digitakt

Sophie is a metallic percussion synth machine for the original Digitakt
(Mk1), OS 1.53 and 1.54. It began as a fixed-point adaptation of
[Sophie for Schwung](https://github.com/mestela/schwung-sophie) by [mestela](https://github.com/mestela) and evolved
into four different models: FUSE, BOOM, PIPE
and SHARD. It uses Digitakt's regular AMP,
filter, mixer and effects path. The source, not a modified Elektron OS,
is what this repository distributes.

## Changelog

- **OS 1.54:** SOPHIE and the optional diagnostic also build for Digitakt
  OS 1.54, from the same source and with the same behavior: one
  `.elemod` for each OS. Needs elekloader 0.4.0 or later.
- **S031:** BR is replaced with Sophie’s FOLD wavefolder.

Get the current `.elemod` and release notes from the
[v1.1.13 release](https://github.com/soejrd/digisophie/releases/tag/v1.1.13).

---

<strong><font color="red">USE AT YOUR OWN RISK.</font></strong> This modifies your instrument's firmware; back up your projects and sounds, and keep a stock OS file for recovery.

One instance runs without FAST AUDIO; the original hardware
test found two instances practical with FAST AUDIO enabled. Eight-track
operation is **not** claimed.

## Controls

| SRC knob | Control | What it does |
| --- | --- | --- |
| A | TUNE | Pitch |
| B | MODEL | FUSE / BOOM / PIPE / SHARD |
| C | FOLD | Sophie-only wavefolder with output level compensation; zero bypasses it |
| D | SAMP | Stock sample selector; Sophie does not use the sample |
| E | SWEEP | Bipolar pitch sweep toward the played note |
| F | METAL | FM/ring intensity |
| G | FBK | Oscillator feedback |
| H | COLOR | Inharmonic character |

The custom controls can be parameter-locked. The normal AMP page controls
the note envelope: set HOLD to `NOTE` for TRIG LEN to determine when the
release begins. Use a finite DEC to hear that release. DEC `INF` can keep
the sound going indefinitely. Retriggering chokes the previous voice on
that track, with a brief transition to suppress a click.

SWEEP starts at zero. Turning right begins above the played pitch; turning
left begins below it. Holding FUNC while turning uses the stock TUNE
octave-step behavior (-60 to +24); ordinary turning reaches the complete
-64 to +63 range.


## Install: no compiler required

You need only the prebuilt Sophie mod for your OS
([OS 1.53](release/digisophie-1.1.13.elemod),
[OS 1.54](release/digisophie-1.1.13-os1.54.elemod)),
[elekloader](https://github.com/irpina/elekloader/releases/latest)
(0.4.0 or later for OS 1.54), and your own original Digitakt Mk1 OS 1.53 or
1.54 `.syx`
The `.elemod` contains this project's code, **not** Elektron's firmware.
You do not need ColdFire tools, Python, or a source checkout to install it.

1. Open elekloader and select your stock OS using **Change stock firmware**.
2. Choose **Install from file** and select `digisophie-1.1.13.elemod` (OS 1.53)
   or `digisophie-1.1.13-os1.54.elemod` (OS 1.54); elekloader refuses the
   file made for the other OS.
   Enable SOPHIE. elekloader's built-in **core 2.1** should enable with it.
   If your elekloader has an older core or shows a dependency error, update
   elekloader before building.
3. Optional: install and enable the bundled digihealth diagnostic for your OS
   ([OS 1.53](release/digihealth-1.0.1.elemod),
   [OS 1.54](release/digihealth-1.0.1-os1.54.elemod)) too. This is
   the configuration used for the earlier S027 hardware test. It adds SYSTEM INFO
   and an opt-in FAST AUDIO setting; without it Sophie still works.
4. Wait for elekloader's **Ready to build** check, set the four-character
   OS version to `S033`, then choose **Build Firmware**. Save the generated
   `.syx` on your computer.
5. Send that `.syx` to the Digitakt with Elektron Transfer

Elekloader builds and verifies the OS; **Elektron Transfer does the actual
upload to the instrument**. Do not power off during the update. Neither
the stock nor modified OS file belongs in this repository.

### Build the mods from source (developers only)

ColdFire tools are needed only to change or recompile the mod. You need
Python 3.9+, a source checkout of
[elekloader](https://github.com/irpina/elekloader), a ColdFire cross-toolchain
(`m68k-linux-gnu-` or `m68k-elf-` assembler, GCC and linker), and your own
stock OS 1.53 or 1.54 file. From this repository:

```sh
ELEKLOADER_CROSS=m68k-elf- sh scripts/build.sh \
  /path/to/your/Digitakt_OS1.54.syx /path/to/elekloader
```

This builds core 2.1, Sophie and the optional diagnostic from source for the
OS of the file you give it, lints the combination, and writes the verified
custom OS to `out/Digitakt_OS1.54_SOPHIE_S033.syx` (`1.53` for a 1.53
file). To test DSP alone, run `make test`;
`make cross-check` additionally compiles for ColdFire. Optional emulator
probes in `tests/` require [digiemu](https://github.com/irpina/digiemu).

## Use and recovery

This changes firmware on the instrument. Back up projects and sounds first,
check that your stock OS is OS 1.53 or 1.54 for the *original* Digitakt, and keep
that stock file for recovery. If you install the optional diagnostic,
FAST AUDIO is off by default; SYSTEM INFO and FAST AUDIO can be enabled
separately in SETTINGS. See [diagnostics](diagnostics/README.md) for the monitor.

Sophie is independent of, and not endorsed by, Elektron or the estate of
SOPHIE. It contains no Elektron firmware or samples.

## Source layout

The Digitakt addresses the mod uses are kept apart from the code that uses
them: `os153.inc` / `os154.inc` for `glue.s`, `os153.h` / `os154.h` for
`digitakt.c`. The OS 1.54 build defines `OS154` (`mod.json`, under
`ports`), which picks the 1.54 files and the 1.54 patch sites; the OS 1.53
build is the same code as before.

## Source and licenses

The Sophie adaptation is [MIT licensed](LICENSE). The original Sophie
attribution and the separate GPL-2.0-or-later digihealth source are
documented in [THIRD_PARTY.md](THIRD_PARTY.md). The digihealth license is
also included in its source directory.

The [DSP audit](SOPHIE_DSP_AUDIT.md),
[hardware performance notes](SOPHIE_HARDWARE_LAG_AUDIT.md),
[SPICE architecture idea](SPICE_ARCHITECTURE.md) and
[oscilloscope feasibility note](OSCILLOSCOPE_FEASIBILITY.md) record the
development history; the latter two are ideas, not implemented features.
