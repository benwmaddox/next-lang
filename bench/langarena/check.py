#!/usr/bin/env python3
"""Build each bench/langarena package with stage-0 nlc (NLC_OPT_LEVEL=3) and check
its output against LangArena's checksum. Usage:
  check.py [--mode test|run] [--time] [package ...]
A package is bench/langarena/<dir>/ whose `name` file holds the LangArena test
name (e.g. Binarytrees::Obj). The program receives the mode ("test" or "run") as
its first argument and prints the checksum as one decimal line. After the checksum
is verified the package is also run once more with the arguments `<mode> prep`
(prepare + warmup only, see README.md), which must exit 0 and print one decimal line
(the unverified state after warmup).
`status` file (first word decides): absent/`ready` = like-for-like port;
`pending-...` = cannot be checked yet (built only if it can be); `variant-...` =
an alternative version of a ready port (e.g. `variant-idiomatic`); `not-comparable`
= built and checked, but not a like-for-like comparison with LangArena (the reason
follows the colon). Variants and not-comparable ports are listed in separate groups."""
import json, os, subprocess, sys, time, pathlib
root = pathlib.Path(__file__).resolve().parent
nlc = os.environ.get("NLC", os.path.expanduser("~/.cache/next-lang/target/release/nlc"))
args = sys.argv[1:]
mode = "test"
if "--mode" in args:
    i = args.index("--mode")
    if i + 1 >= len(args) or args[i + 1] not in ("test", "run"):
        sys.exit("--mode must be followed by test or run")
    mode = args[i + 1]
    del args[i:i + 2]
timed = "--time" in args
if timed: args.remove("--time")
params = {t["name"]: t for t in json.loads((root / ("run.js" if mode == "run" else "test.js")).read_text())}
pkgs = args or sorted(p.name for p in root.iterdir() if (p / "name").is_file())
ok = fail = pending = 0
counts = {}
work = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / f"langarena-{os.getpid()}"
work.mkdir(parents=True, exist_ok=True)
for pkg in pkgs:
    d = root / pkg
    if not (d / "name").is_file():
        fail += 1
        print(f"{pkg:28} ERROR missing package name file")
        continue
    name = (d / "name").read_text().strip()
    status = (d / "status").read_text().strip() if (d / "status").is_file() else "ready"
    kind = status.split(":")[0].split()[0] if status else "ready"
    if kind != "ready" and not status.startswith("pending-") and kind not in ("variant-idiomatic", "not-comparable"):
        fail += 1
        print(f"{pkg:28} ERROR unknown status {status!r}")
        continue
    label = "" if kind == "ready" else f"[{status}] "
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
    run_lines = r.stdout.strip().splitlines()
    got = run_lines[-1] if run_lines else ""
    good = r.returncode == 0 and run_lines == [want]
    note = ""
    if good:
        t0 = time.perf_counter()
        p = subprocess.run([str(exe), mode, "prep"], capture_output=True, text=True)
        pt = time.perf_counter() - t0
        pl = p.stdout.strip().splitlines()
        if p.returncode != 0 or len(pl) != 1 or not pl[0].isascii() or not pl[0].isdigit():
            good = False; note = f"prep mode bad: status {p.returncode} out {p.stdout[:80]!r} {p.stderr[:200]}"
        elif timed:
            note = f"  prep {pt:.3f}s"
    if good:
        ok += 1; counts[kind] = counts.get(kind, 0) + 1
        print(f"{pkg:28} ok {got}  {label}" + (f"{dt:.3f}s" if timed else "") + note)
    else:
        fail += 1; print(f"{pkg:28} WRONG want {want} got {got!r} status {r.returncode} {r.stderr[:300]} {note}")
print(f"{mode}: {ok} ok, {fail} failed, {pending} pending  ({', '.join(f'{k} {v}' for k, v in sorted(counts.items()))})")
sys.exit(1 if fail else 0)
