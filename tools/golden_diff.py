#!/usr/bin/env python3
"""Compare the worktree's Sophie render with a git revision, bit for bit.

The corpus in tests/golden_dump.c hashes output samples and the complete
voice state. Compiling the same driver against the reference revision and
against the worktree catches exactness regressions without a checked-in
binary or an exhaustive test matrix.

    tools/golden_diff.py                 # HEAD against the worktree
    tools/golden_diff.py --ref fee5f51  # another revision
"""
import argparse
import hashlib
import io
import pathlib
import subprocess
import sys
import tarfile
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, check=True,
                          capture_output=True).stdout


def extract(ref, dest):
    data = git("archive", "--format=tar", ref)
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        archive.extractall(dest)


def build(source, include, driver, exe, cc, flags):
    cmd = [cc, *flags, "-I", str(include), str(driver), str(source), "-o", str(exe)]
    done = subprocess.run(cmd, capture_output=True, text=True)
    if done.returncode:
        sys.stderr.write(done.stdout)
        sys.stderr.write(done.stderr)
        raise SystemExit("golden build failed: " + " ".join(cmd))


def run(exe):
    done = subprocess.run([str(exe)], capture_output=True, text=True)
    if done.returncode:
        sys.stderr.write(done.stdout)
        sys.stderr.write(done.stderr)
        raise SystemExit("golden run failed: " + str(exe))
    return done.stdout


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--ref", default="HEAD")
    ap.add_argument("--cc", default="cc")
    ap.add_argument("--flags", default="-std=c99 -O2 -Wall -Wextra -Werror")
    args = ap.parse_args()
    flags = args.flags.split()
    driver = ROOT / "tests" / "golden_dump.c"
    ref = git("rev-parse", "--short", args.ref).decode().strip()

    with tempfile.TemporaryDirectory(prefix="sophie-golden-") as td:
        td = pathlib.Path(td)
        refdir = td / "ref"
        refdir.mkdir()
        extract(args.ref, refdir)
        refexe = td / "ref-render"
        newexe = td / "new"
        build(refdir / "sophie.c", refdir, driver, refexe, args.cc, flags)
        build(ROOT / "sophie.c", ROOT, driver, newexe, args.cc, flags)
        before = run(refexe)
        after = run(newexe)

    if before != after:
        b = before.splitlines()
        a = after.splitlines()
        for n, (x, y) in enumerate(zip(b, a)):
            if x != y:
                print("first difference at line %d" % (n + 1))
                print("  %s: %s" % (ref, x))
                print("  worktree: %s" % y)
                break
        if len(b) != len(a):
            print("line count differs: %d vs %d" % (len(b), len(a)))
        return 1
    digest = hashlib.sha256(before.encode()).hexdigest()[:16]
    cases = next((line for line in before.splitlines() if line.startswith("cases=")), "cases=?")
    print("golden: %s identical to %s (%s, sha256 %s)" % ("worktree", ref, cases, digest))
    return 0


if __name__ == "__main__":
    sys.exit(main())
