#!/usr/bin/env python3
"""Estimate core cycles of one active Sophie voice block on an MCF5441x.

Builds sophie.c for ColdFire, runs ds_voice_render under Unicorn, and costs
every retired instruction with digiemu's MCF54418RM timing model. The default
is the static instruction cost (no pipeline stalls, branch predictor or
i-cache); use --stalls for CycleClock's pipeline/branch model. Both are
estimates, so compare runs of the same driver, not absolute numbers.

    tools/cycle_probe.py [--digiemu PATH] [--stalls] [--source PATH]

Set DIGIEMU or point --digiemu at a digiemu checkout containing emu/cftiming.py.
If Unicorn cannot run here (a JIT that the sandbox blocks), --static reports
the same cost model over a static profile of the render loop instead.
"""
import argparse
import collections
import os
import pathlib
import subprocess
import sys
import tempfile
import types

ROOT = pathlib.Path(__file__).resolve().parent.parent
BLOCKS = 200

DRIVER = r'''
#include <stdint.h>
#include "sophie.h"

static struct ds_voice voice;
static struct ds_params params;
static int32_t output[32];

void cycle_run(void)
{
    uint32_t n;
    params.phase_inc = INC;
    params.model = MODEL;
    params.color = COLOR;
    params.metal = METAL;
    params.sweep = SWEEP;
    params.feedback = FEEDBACK;
    params.velocity = VELOCITY;
    params.fold = 0;
    ds_voice_init(&voice);
    ds_voice_render(&voice, &params, 1, output, 32);
    for (n = 0; n < 200; ++n)
        ds_voice_render(&voice, &params, 0, output, 32);
}
'''

START = r'''
    .text
    .globl _start
_start:
    move.l  #0x7ff00, %sp
    jsr     cycle_run
    .globl  done
done:
    .word   0x4afc
'''

# Cases match tests/timing_probe.py's "default" and DS_HOT control sets, so the
# host estimate lines up with the emulator's full-firmware probe.
CASES = (
    ("FUSE default", 0, 64, 64, 32),
    ("BOOM default", 1, 64, 64, 32),
    ("PIPE default", 2, 64, 64, 32),
    ("SHARD default", 3, 64, 64, 32),
    ("FUSE hot", 0, 64, 127, 127),
    ("BOOM hot", 1, 64, 127, 127),
    ("PIPE hot", 2, 64, 127, 127),
    ("SHARD hot", 3, 64, 127, 127),
)


def find_digiemu(arg):
    candidates = [arg, os.environ.get("DIGIEMU"),
                  ROOT.parent / "digiemu",
                  "/Users/s.klatser/coding projects/digitakt modding/digiemu",
                  "/Users/s.klatser/coding projects/decompplanner/digiemu"]
    for cand in candidates:
        if cand and (pathlib.Path(cand) / "emu" / "cftiming.py").is_file():
            return pathlib.Path(cand).resolve()
    raise SystemExit("no digiemu checkout with emu/cftiming.py (use --digiemu or DIGIEMU)")


def build(tmp, source, model, color, metal, feedback, cross, extra):
    drv = tmp / "cycle_driver.c"
    start = tmp / "cycle_start.s"
    elf = tmp / ("cycle-%d-%d.elf" % (model, metal))
    drv.write_text(DRIVER)
    start.write_text(START)
    defines = ["-DMODEL=%d" % model, "-DCOLOR=%d" % color, "-DMETAL=%d" % metal,
               "-DSWEEP=0", "-DFEEDBACK=%d" % feedback, "-DVELOCITY=127",
               "-DINC=180"]
    cmd = [cross + "gcc", *extra, *defines, "-I", str(ROOT), "-nostartfiles",
           "-o", str(elf), str(start), str(drv), str(source)]
    done = subprocess.run(cmd, capture_output=True, text=True)
    if done.returncode:
        sys.stderr.write(done.stderr)
        raise SystemExit("cycle build failed")
    return elf


def load(elf, uc, r):
    header = subprocess.run([os.environ.get("CROSS", "m68k-elf-") + "objdump",
                             "-h", str(elf)], capture_output=True, text=True,
                            check=True).stdout
    img = elf.read_bytes()
    sections = []
    for line in header.splitlines():
        f = line.split()
        if len(f) >= 7 and f[1].startswith(".") and f[1] not in (".comment", ".note"):
            try:
                size, va, off = int(f[2], 16), int(f[3], 16), int(f[5], 16)
            except ValueError:
                continue
            if size:
                uc.mem_write(va, img[off:off + size])
                sections.append((va, img[off:off + size]))
    symbols = {}
    sym = subprocess.run([os.environ.get("CROSS", "m68k-elf-") + "nm", str(elf)],
                         capture_output=True, text=True, check=True).stdout
    for line in sym.splitlines():
        f = line.split()
        if len(f) == 3:
            symbols[f[2]] = int(f[0], 16)
    return symbols, sections


def run_case(elf, digiemu, stalls):
    sys.path.insert(0, str(digiemu))
    from emu import cfisa, cftiming
    from unicorn import Uc, UC_ARCH_M68K, UC_MODE_BIG_ENDIAN, UC_HOOK_CODE
    from unicorn.m68k_const import (UC_CPU_M68K_CFV4E, UC_M68K_REG_PC)

    uc = Uc(UC_ARCH_M68K, UC_MODE_BIG_ENDIAN)
    uc.ctl_set_cpu_model(UC_CPU_M68K_CFV4E)
    uc.mem_map(0, 0x1000000)
    uc.mem_map(0x80000000, 0x1000000)
    symbols, sections = load(elf, uc, None)
    entry, done = symbols["_start"], symbols["done"]

    # The decoder needs the original bytes, independent of emulated writes.
    image = bytearray(0x1000000)
    for va, data in sections:
        image[va - 0x80000000:va - 0x80000000 + len(data)] = data

    def read16_at(addr):
        def read(off):
            i = addr + off - 0x80000000
            return (image[i] << 8) | image[i + 1]
        return read

    extb = {0x49C0, 0x49C1, 0x49C2, 0x49C3, 0x49C4, 0x49C5, 0x49C6, 0x49C7}
    cache = {}
    cycles = 0
    instructions = 0
    by_op = collections.Counter()
    by_op_n = collections.Counter()

    def hook(_uc, addr, _size, _data):
        nonlocal cycles, instructions
        e = cache.get(addr)
        if e is None:
            if read16_at(addr)(0) in extb:
                e = (1, "extb", 2)
            else:
                try:
                    ins = cfisa.decode(read16_at(addr), addr)
                    e = (cftiming.static_cost(ins), ins.op, ins.length)
                except Exception:
                    e = (1, "UNDEC", 2)
            cache[addr] = e
        c, op, _ = e
        cycles += c
        instructions += 1
        by_op[op] += c
        by_op_n[op] += 1

    uc.hook_add(UC_HOOK_CODE, hook)
    clock = None
    if stalls:
        from types import SimpleNamespace
        machine = SimpleNamespace(uc=uc, raise_vector=lambda *a, **k: False)
        clock = cftiming.CycleClock(machine, stalls=True)
    uc.emu_start(entry, done, count=400_000_000)
    if uc.reg_read(UC_M68K_REG_PC) != done:
        raise SystemExit("cycle driver did not finish")
    total = clock.cycles if clock else cycles
    return total / BLOCKS, instructions / BLOCKS, by_op, by_op_n, cycles


def static_profile(source, digiemu, cross, flags):
    """Cost ds_render_core once from its disassembly (a floor, not a run).

    This is the same MCF54418RM cost table the emulator probe uses, summed
    over every instruction in the function. It says where the cycles sit and
    compares code size between builds; it cannot weight the branches that a
    particular model and control setting take.
    """
    sys.path.insert(0, str(digiemu))
    try:
        import unicorn  # noqa: F401
    except ImportError:
        stub = types.ModuleType("unicorn")
        stub.UC_HOOK_BLOCK = 1
        sys.modules["unicorn"] = stub
    from emu import cfisa, cftiming

    with tempfile.TemporaryDirectory(prefix="sophie-static-") as td:
        td = pathlib.Path(td)
        obj = td / "sophie.o"
        cmd = [cross + "gcc", *flags, "-I", str(ROOT), "-c", str(source), "-o", str(obj)]
        done = subprocess.run(cmd, capture_output=True, text=True)
        if done.returncode:
            sys.stderr.write(done.stderr)
            raise SystemExit("static profile build failed")
        text = td / "text.bin"
        subprocess.run([cross + "objcopy", "-O", "binary", "--only-section=.text",
                        str(obj), str(text)], check=True)
        nm = subprocess.run([cross + "nm", "-S", str(obj)], capture_output=True,
                            text=True, check=True).stdout
        start = size = None
        for line in nm.splitlines():
            f = line.split()
            if len(f) == 4 and f[3].startswith("ds_render_core"):
                start, size = int(f[0], 16), int(f[1], 16)
        if start is None:
            raise SystemExit("ds_render_core not found in " + str(obj))
        data = text.read_bytes()
        insns = list(cfisa.disassemble_lengths(data, 0, start, start + size))
        costs = [cftiming.static_cost(ins) for _, ins in insns]
        by_op = collections.Counter()
        n_op = collections.Counter()
        for _, ins in insns:
            by_op[ins.op] += cftiming.static_cost(ins)
            n_op[ins.op] += 1
        total = sum(costs)
        print("%s ds_render_core: %d bytes, %d instructions, %d static cycles" %
              (source, size, len(insns), total))
        print("  " + ", ".join("%s %d (%d)" % (op, by_op[op], n_op[op])
                               for op in ("mul_l", "mul_w", "div_l", "move",
                                          "shift", "bcc", "bra")))
        return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--digiemu", default=None)
    ap.add_argument("--source", default=str(ROOT / "sophie.c"))
    ap.add_argument("--stalls", action="store_true",
                    help="include CycleClock's pipeline and branch model")
    ap.add_argument("--static", action="store_true",
                    help="static profile of ds_render_core, no Unicorn")
    args = ap.parse_args()
    digiemu = find_digiemu(args.digiemu)
    cross = os.environ.get("CROSS", "m68k-elf-")
    os.environ["CROSS"] = cross
    flags = os.environ.get("CYCLE_CFLAGS",
                           "-mcpu=54455 -O2 -ffreestanding -fno-builtin -nostdlib "
                           "-fno-pic -fno-pie -fomit-frame-pointer -Wall -Wextra "
                           "-Werror").split()
    source = pathlib.Path(args.source).resolve()
    if args.static:
        return static_profile(source, digiemu, cross, flags)
    print("source %s" % source)
    print("%-14s %9s %9s %7s" % ("case", "cycles", "instr", "cyc/ins"))
    with tempfile.TemporaryDirectory(prefix="sophie-cycles-") as td:
        td = pathlib.Path(td)
        for name, model, color, metal, feedback in CASES:
            elf = build(td, source, model, color, metal, feedback, cross, flags)
            cycles, instrs, by_op, by_op_n, static = run_case(
                elf, digiemu, args.stalls)
            print("%-14s %9.0f %9.0f %7.2f" %
                  (name, cycles, instrs, static / max(1, instrs * BLOCKS)))
            if name.endswith("hot"):
                print("  top: " + ", ".join(
                    "%s %.0f%%" % (op, 100.0 * c / max(1, static))
                    for op, c in by_op.most_common(6)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
