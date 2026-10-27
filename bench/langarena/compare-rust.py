#!/usr/bin/env python3
"""Same-machine comparison of the next-lang LangArena ports with LangArena's own
Rust implementation. Usage:
  compare-rust.py [--runs N] [package ...]
Builds each ready port with stage-0 nlc (NLC_OPT_LEVEL=3) and runs it in `run`
mode; runs the Rust binary for the same test (`benchmarks run.js <name>`), one
test per process. Both are pinned with `taskset -c 8`, interleaved, best of N
(default 3), under `flock -x /home/ben/linuxbench/bench.lock`; peak RSS comes from
`/usr/bin/time -f %M`. Times reported:
  nl      next-lang whole-process wall time (startup, setup and the run)
  rust    LangArena's own timer: the measured run only, after prepare and warmup
  rust_p  Rust whole-process wall time (includes prepare and a warmup pass)
Environment: NLC (nlc path), LANGARENA (clone, default /mnt/d/tmp/langarena),
RUST_BENCH (built binary, default ~/.cache/langarena-rust/max-perf/benchmarks;
build it with `cargo build --profile max-perf` in $LANGARENA/rust)."""
import fcntl, os, pathlib, re, subprocess, sys, time

root = pathlib.Path(__file__).resolve().parent
nlc = os.environ.get("NLC", os.path.expanduser("~/.cache/next-lang/target/release/nlc"))
arena = pathlib.Path(os.environ.get("LANGARENA", "/mnt/d/tmp/langarena"))
rust = os.environ.get("RUST_BENCH", os.path.expanduser("~/.cache/langarena-rust/max-perf/benchmarks"))
lock_path = "/home/ben/linuxbench/bench.lock"
args = sys.argv[1:]
runs = 3
if "--runs" in args:
    i = args.index("--runs"); runs = int(args[i + 1]); del args[i:i + 2]
pkgs = args or sorted(p.name for p in root.iterdir() if (p / "name").is_file())
work = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / f"langarena-rust-{os.getpid()}"
work.mkdir(parents=True, exist_ok=True)


def timed(cmd, cwd=None):
    t0 = time.perf_counter()
    r = subprocess.run(["taskset", "-c", "8", "/usr/bin/time", "-f", "%M"] + cmd,
                       capture_output=True, text=True, cwd=cwd)
    wall = time.perf_counter() - t0
    rss = int(r.stderr.strip().splitlines()[-1]) if r.stderr.strip() else 0
    return r, wall, rss


print(f"{'package':24} {'nl s':>7} {'rust s':>7} {'rust_p s':>8} {'nl/rust':>8} {'nl MB':>7} {'rust MB':>8}")
rows = []
with open(lock_path, "w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    for pkg in pkgs:
        d = root / pkg
        status = (d / "status").read_text().strip() if (d / "status").is_file() else "ready"
        if status.startswith("pending"):
            print(f"{pkg:24} {status}"); continue
        name = (d / "name").read_text().strip()
        exe = work / pkg
        b = subprocess.run([nlc, "build", str(d), "-o", str(exe)], capture_output=True, text=True,
                           env=dict(os.environ, NLC_OPT_LEVEL="3"))
        if b.returncode != 0:
            print(f"{pkg:24} BUILD FAILED {b.stderr[:200]}"); continue
        best = {"nl": 1e9, "rust": 1e9, "rust_p": 1e9}
        mem = {"nl": 0, "rust": 0}
        ok = True
        for _ in range(runs):
            r, wall, rss = timed([str(exe), "run"])
            ok &= r.returncode == 0
            best["nl"] = min(best["nl"], wall); mem["nl"] = max(mem["nl"], rss)
            r, wall, rss = timed([rust, str(arena / "run.js"), name], cwd=arena / "rust")
            m = re.findall(r"^(\S+): OK in ([\d.]+)s", r.stdout, re.M)
            if len(m) != 1 or m[0][0] != name:
                ok = False; print(f"{pkg:24} RUST RUN PROBLEM {r.stdout[-300:]!r}"); break
            best["rust"] = min(best["rust"], float(m[0][1])); best["rust_p"] = min(best["rust_p"], wall)
            mem["rust"] = max(mem["rust"], rss)
        if not ok:
            print(f"{pkg:24} FAILED"); continue
        ratio = best["nl"] / best["rust"]
        rows.append(ratio)
        print(f"{pkg:24} {best['nl']:7.3f} {best['rust']:7.3f} {best['rust_p']:8.3f} {ratio:8.2f} "
              f"{mem['nl'] / 1024:7.1f} {mem['rust'] / 1024:8.1f}", flush=True)
    fcntl.flock(lock, fcntl.LOCK_UN)
if rows:
    geo = 1.0
    for r in rows: geo *= r
    print(f"geometric mean nl/rust: {geo ** (1 / len(rows)):.2f} over {len(rows)} tests")
