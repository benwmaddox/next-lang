#!/usr/bin/env python3
"""Build each bench/langarena package with stage-0 nlc (NLC_OPT_LEVEL=3) and check
its output against LangArena's checksum. Usage:
  check.py [--mode test|run] [--time] [package ...]
A package is bench/langarena/<dir>/ whose `name` file holds the LangArena test
name (e.g. Binarytrees::Obj). The program receives the mode ("test" or "run") as
its first argument and prints the checksum as one decimal line. Packages whose
`status` file says `pending-floats` (or `pending-...`) are built only if they can
be and are reported separately."""
import json, os, subprocess, sys, time, pathlib
root = pathlib.Path(__file__).resolve().parent
nlc = os.environ.get("NLC", os.path.expanduser("~/.cache/next-lang/target/release/nlc"))
args = sys.argv[1:]
mode = "test"
if "--mode" in args:
    i = args.index("--mode"); mode = args[i + 1]; del args[i:i + 2]
timed = "--time" in args
if timed: args.remove("--time")
params = {t["name"]: t for t in json.loads((root / ("run.js" if mode == "run" else "test.js")).read_text())}
pkgs = args or sorted(p.name for p in root.iterdir() if (p / "name").is_file())
ok = fail = pending = 0
work = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / f"langarena-{os.getpid()}"
work.mkdir(parents=True, exist_ok=True)
for pkg in pkgs:
    d = root / pkg
    name = (d / "name").read_text().strip()
    status = (d / "status").read_text().strip() if (d / "status").is_file() else "ready"
    want = str(params[name]["checksum"])
    exe = work / pkg
    env = dict(os.environ, NLC_OPT_LEVEL="3")
    b = subprocess.run([nlc, "build", str(d), "-o", str(exe)], capture_output=True, text=True, env=env)
    if b.returncode != 0:
        if status.startswith("pending"):
            pending += 1; print(f"{pkg:28} {status} (doesn't build yet)"); continue
        fail += 1; print(f"{pkg:28} BUILD FAILED\n{b.stderr[:600]}"); continue
    t0 = time.perf_counter()
    r = subprocess.run([str(exe), mode], capture_output=True, text=True)
    dt = time.perf_counter() - t0
    got = r.stdout.strip().splitlines()[-1] if r.stdout.strip() else ""
    if r.returncode == 0 and got == want:
        ok += 1; print(f"{pkg:28} ok {got}" + (f"  {dt:.3f}s" if timed else ""))
    else:
        fail += 1; print(f"{pkg:28} WRONG want {want} got {got!r} status {r.returncode} {r.stderr[:300]}")
print(f"{mode}: {ok} ok, {fail} failed, {pending} pending")
sys.exit(1 if fail else 0)
