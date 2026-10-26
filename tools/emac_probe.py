#!/usr/bin/env python3
"""Measure where an EMAC replacement for ds_mul would apply.

The host build counts every ds_mul call while rendering representative
voices, and records the largest |a*b| it sees. An EMAC mac.l with MACSR
0xA0 (signed fractional) holds products below 2^47 exactly; above that it
saturates, so the range check gates the experiment. It also reports the
multiply count per 32-frame block, which is the upper bound on the work an
EMAC path can remove. This does not time the target.

    tools/emac_probe.py
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
BLOCKS = 256

DRIVER = r"""
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include "sophie.h"

extern unsigned long ds_mul_calls;
extern unsigned long ds_mul_max;

#define BLOCKS 256

static struct ds_voice voice;
static struct ds_params params;
static int32_t output[32];

static void run(const char *name, unsigned model, unsigned color,
                unsigned metal, int sweep, unsigned feedback, unsigned velocity)
{
    unsigned b;
    ds_voice_init(&voice);
    params.phase_inc = 68;
    params.model = (uint8_t)model;
    params.color = (uint8_t)color;
    params.metal = (uint8_t)metal;
    params.sweep = (int8_t)sweep - 64;
    params.feedback = (uint8_t)feedback;
    params.velocity = (uint8_t)velocity;
    params.fold = 0;
    ds_mul_calls = 0;
    ds_voice_render(&voice, &params, 1, output, 32);
    for (b = 1; b < BLOCKS; ++b)
        ds_voice_render(&voice, &params, 0, output, 32);
    printf("%-12s %7.2f calls/block  max|product|=%lu%s\n", name,
           (double)ds_mul_calls / BLOCKS, ds_mul_max,
           ds_mul_max >= (1UL << 47) ? "  OUT OF EMAC RANGE" : "");
}

int main(void)
{
    static const char *models[4] = { "FUSE", "BOOM", "PIPE", "SHARD" };
    unsigned m;
    for (m = 0; m < 4; ++m) {
        char name[16];
        snprintf(name, sizeof name, "%s default", models[m]);
        run(name, m, 64, 64, 64, 32, 127);
    }
    for (m = 0; m < 4; ++m) {
        char name[16];
        snprintf(name, sizeof name, "%s hot", models[m]);
        run(name, m, 64, 127, 127, 127, 127);
    }
    run("FUSE sweep", 0, 64, 40, 0, 32, 127);
    run("SHARD bloom", 3, 127, 127, 127, 127, 127);
    return 0;
}
"""


def main():
    source = (ROOT / "sophie.c").read_text()
    source = source.replace(
        "static int32_t ds_mul(int32_t a, int32_t b) { return (a * b) >> 15; }",
        "unsigned long ds_mul_calls, ds_mul_max;\n"
        "static int32_t ds_mul(int32_t a, int32_t b)\n"
        "{\n"
        "    int64_t p = (int64_t)a * b;\n"
        "    uint64_t mag = p < 0 ? (uint64_t)(-p) : (uint64_t)p;\n"
        "    ++ds_mul_calls;\n"
        "    if (mag > ds_mul_max) ds_mul_max = (unsigned long)mag;\n"
        "    return (a * b) >> 15;\n"
        "}")
    if "ds_mul_calls" not in source:
        raise SystemExit("could not find ds_mul to instrument")
    with tempfile.TemporaryDirectory(prefix="sophie-emac-") as td:
        td = pathlib.Path(td)
        counted = td / "sophie_counted.c"
        driver = td / "emac_probe.c"
        exe = td / "emac_probe"
        counted.write_text(source)
        driver.write_text(DRIVER)
        cmd = ["cc", "-std=c99", "-O2", "-Wall", "-Wextra", "-Werror",
               "-I", str(ROOT), str(driver), str(counted), "-o", str(exe)]
        done = subprocess.run(cmd, capture_output=True, text=True)
        if done.returncode:
            sys.stderr.write(done.stdout)
            sys.stderr.write(done.stderr)
            return 2
        done = subprocess.run([str(exe)], capture_output=True, text=True)
        sys.stdout.write(done.stdout)
        sys.stderr.write(done.stderr)
        return done.returncode


if __name__ == "__main__":
    sys.exit(main())
