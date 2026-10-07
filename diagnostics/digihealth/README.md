# digihealth

> This is the upstream README retained for attribution. The Sophie copy
> changes FAST AUDIO to **off by default**; the upstream descriptions below
> saying “on by default” do not apply to the Sophie build. See
> [the local diagnostic notes](../README.md).

A performance and diagnostics mod for the Digitakt (mk1), OS 1.53 and 1.54. It adds
two rows to SETTINGS:

- **FAST AUDIO** (on by default) runs the audio render's hot code from the
  processor's free on-chip SRAM instead of DDR. It is the same code, so the
  audio is identical, and the DSP load is lower. Measured on a unit, with
  the same song before and after:
  - the render went from 537 to 480 µs a block;
  - DSP load went from 80.5 to 72.0 %.
- **SYSTEM INFO** shows CPU, DSP, RAM and free sample memory in the top bar.
  A read-only USB diagnostics channel lets `tools/digiusb.py` read the same
  figures, and more, from a computer.

On the **Digitone (mk1) and Digitone Keys**, OS 1.43, it is SYSTEM INFO
alone (digihealth 1.1): see [The Digitone](#the-digitone).

It is an [elekloader](https://github.com/irpina/elekloader) mod.
elekloader builds a custom OS file on your own machine, from your stock OS
file and the mods you pick; nothing from Elektron is distributed.

## FAST AUDIO

The render's hot code, 0x400716c0-0x4007629a (about 19 KB), is copied into
the SRAM, which the OS clears at boot and never uses. The copy's
references to itself are pointed at the copy, and the render's calls go
through stubs that pick the copy or the original.

- **When it switches on:** two seconds after the unit's screen comes up,
  once. Untick it in SETTINGS and it stays off until the next power-on;
  unticking isn't saved.
- **Safety nets:**
  - It refuses to start if that SRAM isn't empty.
  - Once a second it checks the copy against its checksum. If anything has
    written over it, it goes back to the original code for good.
  - FUNC at power-on and the stock OS file always recover the unit.

Why it is faster: the render runs about 17 KB of code for every block
through an 8 KB instruction cache, which costs about a thousand cache
misses a block. The SRAM answers without wait states.

## SYSTEM INFO

- **The top bar** shows two pages, two seconds each:
  - CPU and DSP load (DSP now and its peak in the last second);
  - free RAM (the heap) and free sample memory.
- **The USB channel** is SysEx with Elektron's manufacturer header and a
  device byte (0x7D) that no Elektron machine uses, so a stock OS ignores
  it. It has three commands, all read-only: HELLO, STATS (the once-a-second
  snapshot: render and idle time, the heap by block size, free sample
  memory, FAST AUDIO's state) and PEEK (DDR and the SRAM only).

```text
python tools/digiusb.py cfw          # which mod answers, and its uptime
python tools/digiusb.py stats 10     # ten readings, one a second
python tools/digiusb.py peek 0x4020bb14 64
```

`digiusb.py` runs on Windows (winmm, through ctypes; no packages). Close
Elektron Transfer first: Windows lets one program at a time open a MIDI
port.

## The Digitone

digihealth 1.1 is SYSTEM INFO for the Digitone mk1 and Digitone Keys, OS
1.43: the same row, readout and USB channel, built from the same source
with the Digitone's addresses (`dn1/`).

- **CPU** is the main CPU's load, as on the Digitakt.
- **DSP** is the main CPU's audio render: the effects and the mix. The FM
  voices run on the Digitone's second CPU, which no mod changes, so their
  load is not shown.
- **The second page** is free RAM alone: the Digitone has no sample memory.
- **FAST AUDIO** is not ported yet. The Digitone's render is different code,
  and less of the SRAM is free.

It needs the Digitone's core (`core-dn1-2.0a.elemod`), which elekloader 0.4.0
builds in.

## Install

You need three things:
- **elekloader**:
  - **Windows:** download `elekloader-<version>-windows.exe` from
    [elekloader's releases](https://github.com/irpina/elekloader/releases/latest)
    and run it. The core mod, which every linkable mod needs, is built in
    (the Digitone's from elekloader 0.4.0).
  - **Other systems:** run elekloader from source with Python 3.9 or newer
    (see [its README](https://github.com/irpina/elekloader#install)). There
    you also need the core for your device and OS (`core-2.0a.elemod` or
    `core-2.1.elemod` for the Digitakt on 1.53, `core-2.1-os1.54.elemod`
    on 1.54, `core-dn1-2.0a.elemod` for the Digitone), attached to this
    repository's releases too.
- **This mod**, from
  [this repository's releases](https://github.com/irpina/digihealth/releases/latest):
  `digihealth-1.0.elemod` for the Digitakt mk1 on OS 1.53,
  `digihealth-1.0-os1.54.elemod` on OS 1.54 (the same mod), or
  `digihealth-1.1.elemod` for the Digitone mk1.
- **The stock OS file:** `Digitakt_OS1.54.syx` or `Digitakt_OS1.53.syx`, from
  [Elektron's Digitakt downloads](https://www.elektron.se/support-downloads/digitakt),
  or `Digitone_and_Digitone_Keys_OS1.43.syx`, from Elektron's Digitone
  downloads (the `.zip` works as it is). elekloader recognises the file by
  its hash.

Then build your OS in elekloader's window:

1. **Your stock OS file:** elekloader asks for it the first time; **Change
   stock firmware...** (top right) picks another.
2. **+ Install from file...**: choose the digihealth for your device and
   OS. From source, install its core the same way.
3. **Tick digihealth.** core is ticked with it. The check below the list should
   say "No conflicts ... Ready to build". To add other mods, such as [digislicer](https://github.com/irpina/digislicer), install and tick them as well.
4. **OS version shown**: the 4 characters the unit will show, for example
   `DH10`.
5. **BUILD FIRMWARE**, and save the `.syx`. elekloader verifies it before
   writing it.

Flash it with Elektron Transfer, as for any OS update
([Elektron's instructions](https://support.elektron.se/support/solutions/articles/43000662890-how-to-update-your-device)):
1. Connect the unit over USB.
2. In Transfer, select the unit and **Connect**.
3. Drag the `.syx` onto **Drop files here**.
4. Press **YES** on the unit.

Don't turn it off until the upgrade is done.

Or on the command line (elekloader from source):

```bash
python -m elekloader.patch --stock Digitakt_OS1.54.syx \
    --mod core-2.1-os1.54.elemod --mod digihealth-1.0-os1.54.elemod \
    --out Digitakt_OS1.54-health.syx --version DH10
```

**Recovery:** elekloader never changes the bootloader, so the stock OS
file always restores the unit. Hold **FUNC** while powering on for the
startup menu, and press **TRIG 4** for OS UPGRADE. Then send the stock
`.syx` with Transfer's legacy OS upgrade mode.

## Build it from source

The Digitakt mk1 cross toolchain (m68k binutils and gcc; on Debian or
Ubuntu, `apt install binutils-m68k-linux-gnu gcc-m68k-linux-gnu`; on
Windows, inside WSL) and elekloader, importable (installed, or on
`PYTHONPATH`):

```bash
python build.py --stock Digitakt_OS1.53.syx      # -> out/digihealth-1.0.elemod
python build.py --stock Digitakt_OS1.54.syx      # -> out/digihealth-1.0-os1.54.elemod
python build.py --stock Digitone_and_Digitone_Keys_OS1.43.syx   # -> out/digihealth-1.1.elemod
python -m elekloader.lint out/digihealth-1.0.elemod --stock Digitakt_OS1.53.syx --with core-2.0a.elemod
```

Use `build.py`, not `elekloader.sdk.build` alone, with an elekloader that
knows `mod.json`'s `ports` (0.4.0 or later). FAST AUDIO needs parts
worked out from your stock file:
- the checks that the code block can run from the SRAM;
- its fix-ups;
- the render's call-site stubs.

`build.py` computes them with elekloader's ColdFire decoder, then hands
them to elekloader's SDK.

| file | |
|---|---|
| `mod.json` | the mod: its sites, handlers, tables and resources; `fast_audio` is `build.py`'s input; under `ports`, 1.54's sites |
| `build.py` | FAST AUDIO's plan from the stock file, then the SDK |
| `fastaudio.s` | the FAST AUDIO row, the copy, the stubs' switch and the watchdog |
| `sysinfo.s` | the SYSTEM INFO row and readout, the render and idle timing, the USB channel |
| `os153.inc`, `os154.inc` | the stock routines it calls, for each OS (1.54's port defines `OS154`) |
| `dn1/mod.json`, `dn1/dn143.inc` | the Digitone mk1's mod (SYSTEM INFO; `sysinfo.s` with `DN143`) and its stock routines |
| `tools/digiusb.py`, `tools/winmidi.py` | the USB channel's other end |

## How it was checked

These checks ran in digikit's emulator, which runs the stock OS and the
mods through the real bootloader.

- **Bit-exact audio:** with FAST AUDIO on, every output sample and the audio
  engine's whole state after every render are identical to stock's. Four
  scenarios: a sample-heavy pattern, a trig-heavy pattern, all eight tracks
  busy, and parameter changes while playing (6,000-7,500 renders each).
  This holds for digihealth alone and combined with digislicer.
- **A cold boot against stock** (35.6 s): FAST AUDIO comes on by itself,
  then the row is unticked and ticked again, with playing in between.
  - Every sample of the audio is identical to stock's. The recording stops
    one 1 ms block earlier: the hook bus changes the UI task's timing by a
    few instructions, and `core` alone does the same.
  - The screens are those of the custom build the mod comes from, to the
    pixel.
- **On a unit:** FAST AUDIO and SYSTEM INFO ran on a Digitakt mk1 in the
  custom builds this mod comes from, where the figures above were
  measured.
- **The Digitone** (digihealth 1.1 with its core): every stage of digikit's
  firmware check passes, from the file's own bootstrap and updater to a
  scripted session, against stock.
  - With SYSTEM INFO off, every screen is identical to stock.
  - Switched on in SETTINGS, the readout shows "CPU 58%  DSP 54%/54%" and
    "RAM 13.8M" in the top bar. The emulator's own measurement of stock is
    58 % CPU.
  - The audio is identical to stock until PLAY, then the same sound, shifted
    by when the key press lands. Stock against itself with PLAY 0.3 ms later
    differs in the same way.
  - Its routines and sites are the Digitakt 1.53's found again in 1.43: the
    same code, instruction for instruction, but for its addresses.
  - Not yet on a unit, and the USB channel not yet tried.
- **The Digitakt mk1 on OS 1.54** (the same mod, with 1.54's
  addresses), in the emulator:
  - core + digihealth against stock 1.54: every stage passes, and the
    check's nine screens are identical, FAST AUDIO on.
  - With digislicer and digineighbor too, against the same four for
    1.53: the FAST AUDIO script (on, playing, off, playing) is
    identical screen for screen. With SYSTEM INFO on, its RAM page
    reads the same on both; its two pages alternate at different
    moments. 1.54's CPU page read "CPU 10%  DSP 3%/45%" while playing.
    The emulator's cold boot has no samples, so these runs play
    silence: they check the screens and that nothing sounds, not
    the audio of a playing sample.
  - FAST AUDIO copies the same render block in 1.54, at the same
    addresses; build.py plans its fix-ups and stubs from the 1.54 file
    (10 and 14, as for 1.53). Bit-exact audio has not been measured on
    1.54, nor tried on a unit.

## Licence

GPL-2.0-or-later. digihealth is free software: you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation, either version 2 of the
License, or (at your option) any later version. It is distributed in the
hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU General Public License for more details: [LICENSE](LICENSE)
holds version 2.

Not affiliated with Elektron. Digitakt and Digitone are trademarks of
Elektron. Custom firmware is at your own risk.
