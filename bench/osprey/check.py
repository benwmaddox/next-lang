#!/usr/bin/env python3
"""Build each bench/osprey package with stage-0 nlc (NLC_OPT_LEVEL=3) and check its
output against Osprey's expected.txt, byte for byte. Usage:
  check.py [--time] [--no-rust] [case ...]
A case is bench/osprey/<case>/ with main.nl, package.toml, expected.txt, bench.json.
Cases whose package.toml grants "env" read their seed from the first argument; the
runner passes `0` (seed 1, what Osprey pipes on stdin). A `status` file starting
with `pending` marks a case that can't be checked yet (built if possible, reported
separately). With --time, each ready case is also timed against the Rust reference
(Osprey's own <case>.rs, built with `rustc -C opt-level=3 -C overflow-checks=off`):
best of 5 wall seconds and peak RSS from `/usr/bin/time -f "%e %M"`, pinned with
`taskset -c 8`, runs interleaved under `flock -x /home/ben/linuxbench/bench.lock`.
Wall time is measured with perf_counter around the whole `taskset time exe`
command (same overhead on both sides) because %e only has 10 ms resolution.
Environment: NLC (nlc path), OSPREY (clone of the Osprey repo, default /mnt/d/tmp/osprey),
TMPDIR (scratch, default /tmp)."""
import fcntl, os, pathlib, subprocess, sys, time

root = pathlib.Path(__file__).resolve().parent
nlc = os.environ.get("NLC", os.path.expanduser("~/.cache/next-lang/target/release/nlc"))
osprey = pathlib.Path(os.environ.get("OSPREY", "/mnt/d/tmp/osprey")) / "benchmarks" / "cases"
lock_path = "/home/ben/linuxbench/bench.lock"
args = sys.argv[1:]
timed = "--time" in args
if timed: args.remove("--time")
with_rust = "--no-rust" not in args
if not with_rust: args.remove("--no-rust")
cases = args or sorted(p.name for p in root.iterdir() if (p / "main.nl").is_file())
work = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / f"osprey-{os.getpid()}"
work.mkdir(parents=True, exist_ok=True)


def seeded(d):
    toml = (d / "package.toml").read_text()
    return '"env"' in toml


def run_args(case_dir, exe):
    return [str(exe), "0"] if seeded(case_dir) else [str(exe)]


def measure(cmd, stdin_text):
    """One run under taskset and /usr/bin/time; returns (wall seconds, peak KB, stdout)."""
    t0 = time.perf_counter()
    r = subprocess.run(["taskset", "-c", "8", "/usr/bin/time", "-f", "%e %M"] + cmd,
                       input=stdin_text, capture_output=True, text=True)
    wall = time.perf_counter() - t0
    last = r.stderr.strip().splitlines()[-1].split()
    return wall, int(last[1]), r.stdout, r.returncode


def build_rust(case):
    src = osprey / case / f"{case}.rs"
    exe = work / f"{case}_rs"
    b = subprocess.run(["rustc", "-C", "opt-level=3", "-C", "overflow-checks=off", str(src), "-o", str(exe)],
                       capture_output=True, text=True)
    return exe if b.returncode == 0 else None


ok = fail = pending = 0
rows = []
for case in cases:
    d = root / case
    want = (d / "expected.txt").read_text()
    status = (d / "status").read_text().strip() if (d / "status").is_file() else "ready"
    exe = work / case
    env = dict(os.environ, NLC_OPT_LEVEL="3")
    b = subprocess.run([nlc, "build", str(d), "-o", str(exe)], capture_output=True, text=True, env=env)
    if b.returncode != 0:
        if status.startswith("pending"):
            pending += 1; print(f"{case:12} {status} (doesn't build yet)"); continue
        fail += 1; print(f"{case:12} BUILD FAILED\n{(b.stdout + b.stderr)[:600]}"); continue
    r = subprocess.run(run_args(d, exe), capture_output=True, text=True)
    if r.returncode == 0 and r.stdout == want:
        ok += 1; print(f"{case:12} ok {r.stdout.strip()}")
        good = True
    else:
        fail += 1; good = False
        print(f"{case:12} WRONG want {want.strip()!r} got {r.stdout.strip()[:80]!r} status {r.returncode} {r.stderr[:300]}")
    if not (timed and good):
        continue
    rexe = build_rust(case) if with_rust else None
    if with_rust and rexe is None:
        print(f"{case:12} (Rust reference failed to build; timing next-lang only)")
    rust_ok = False
    if rexe:
        rr = subprocess.run([str(rexe)], input="0\n", capture_output=True, text=True)
        rust_ok = rr.stdout == want
        if not rust_ok:
            print(f"{case:12} Rust reference output differs from expected.txt; not timed")
    with open(lock_path, "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            nl, rs = [], []
            for _ in range(5):
                nl.append(measure(run_args(d, exe), None))
                if rust_ok:
                    rs.append(measure([str(rexe)], "0\n"))
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)
    best = lambda runs: (min(x[0] for x in runs), max(x[1] for x in runs)) if runs else (None, None)
    rows.append((case, best(nl), best(rs)))

print(f"{ok} ok, {fail} failed, {pending} pending")
if rows:
    print()
    print(f"{'case':12} {'next-lang s':>12} {'Rust s':>9} {'ratio':>7} {'next-lang KB':>13} {'Rust KB':>9}")
    for case, (nw, nm), (rw, rm) in rows:
        ratio = f"{nw / rw:.2f}x" if rw else "-"
        print(f"{case:12} {nw:12.3f} {(f'{rw:.3f}' if rw else '-'):>9} {ratio:>7} {nm:13d} {(str(rm) if rm else '-'):>9}")
sys.exit(1 if fail else 0)
