#!/usr/bin/env python3
"""Same-machine comparison of the next-lang LangArena ports with LangArena's own
Rust implementation. Usage:
  compare-rust.py [--runs N] [package ...]
Each port is built with the self-hosted compiler (IR, then clang -O3 with the live runtime and the offset
stack) and optionally also with a BASELINE compiler (for example the previous release's nlc-selfhost) to show
what a change did. Per test, per round:
  nl run    `exe run`       prepare + warmup + the timed iterations (whole process)
  nl prep   `exe run prep`  prepare + warmup only (whole process)
  rust      `benchmarks run.js <name>`; LangArena's own timer, which covers only the
            timed iterations after prepare and warmup (rust_p = its whole process)
All are pinned with `taskset -c 8`, interleaved, best of N (default 3), under
`flock -x /home/ben/linuxbench/bench.lock`. next-lang's reported time (nl s)
estimates run-body time as best(run) - best(prep) from separate whole-process
measurements; it includes timing noise and is not an in-process measurement.
`nl_p` is the whole-process `run` time. Peak RSS (`/usr/bin/time -f %M`) is of
the `run` process on both sides.
Groups (from each package's `status` file): the headline geometric mean covers only
ready (like-for-like) ports; `variant-*` packages (e.g. *_idiomatic) and
`not-comparable` ports are reported in separate sections, never in the headline.
Environment: NLC (the compiler under test; default: the cached compiler built from the seed),
BASELINE (optional second compiler; adds base columns), LANGARENA (clone, default /mnt/d/tmp/langarena),
RUST_BENCH (built binary, default ~/.cache/langarena-rust/max-perf/benchmarks;
build it with `cargo build --profile max-perf` in $LANGARENA/rust)."""
import fcntl, json, os, pathlib, re, subprocess, sys, time

root = pathlib.Path(__file__).resolve().parent
repo = root.parent.parent
arena = pathlib.Path(os.environ.get("LANGARENA", "/mnt/d/tmp/langarena"))
rust = os.environ.get("RUST_BENCH", os.path.expanduser("~/.cache/langarena-rust/max-perf/benchmarks"))
lock_path = "/home/ben/linuxbench/bench.lock"
nlc = os.environ.get("NLC") or subprocess.run([sys.executable, str(repo / "scripts/build-selfhost-cached.py")],
                                              capture_output=True, text=True, check=True).stdout.strip()
baseline = os.environ.get("BASELINE")
args = sys.argv[1:]
runs = 3
if "--runs" in args:
    i = args.index("--runs")
    if i + 1 >= len(args):
        sys.exit("--runs requires a positive integer")
    try:
        runs = int(args[i + 1])
    except ValueError:
        sys.exit("--runs requires a positive integer")
    if runs < 1:
        sys.exit("--runs requires a positive integer")
    del args[i:i + 2]
pkgs = args or sorted(p.name for p in root.iterdir() if (p / "name").is_file())
params = {item["name"]: str(item["checksum"]) for item in json.loads((root / "run.js").read_text())}
work = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / f"langarena-rust-{os.getpid()}"
work.mkdir(parents=True, exist_ok=True)


def timed(cmd, cwd=None):
    t0 = time.perf_counter()
    r = subprocess.run(["taskset", "-c", "8", "/usr/bin/time", "-f", "%M"] + cmd,
                       capture_output=True, text=True, cwd=cwd)
    wall = time.perf_counter() - t0
    lines = r.stderr.strip().splitlines()
    if not lines or not re.fullmatch(r"\d+", lines[-1]):
        raise RuntimeError(f"timing wrapper returned no valid peak RSS: {r.stderr[-300:]!r}")
    rss = int(lines[-1])
    return r, wall, rss


def geomean(xs):
    g = 1.0
    for x in xs: g *= x
    return g ** (1 / len(xs))


def build(compiler, package, tag):
    """Compile a port to an executable with `compiler`; returns the path or None (the reason is printed)."""
    ir = repo / "target" / "langarena-cmp" / f"{package.name}.{tag}.ll"
    ir.parent.mkdir(parents=True, exist_ok=True)
    ir.unlink(missing_ok=True)
    built = subprocess.run([compiler, "build", str(package.relative_to(repo)), "-o", str(ir.relative_to(repo)), "--runtime=c"],
                           capture_output=True, text=True, cwd=repo)
    if built.returncode != 0 or not ir.is_file():
        first = (built.stderr.strip().splitlines() or ["?"])[0]
        print(f"{package.name:26} {tag}: does not build: {first[:110]}")
        return None
    exe = work / f"{package.name}.{tag}"
    linked = subprocess.run(["clang", "-O3", "-DNLC_STACK_MODE_OFFSET=1", str(ir), str(repo / "runtime/nl_runtime.c"), "-o", str(exe)],
                            capture_output=True, text=True)
    if linked.returncode != 0:
        print(f"{package.name:26} {tag}: CLANG FAILED {linked.stderr[:200]}")
        return None
    return exe


def cell(value, width, digits=3):
    return f"{value:{width}.{digits}f}" if value is not None else f"{'-':>{width}}"


HEADER = (f"{'package':26} {'nl s':>7} {'base s':>7} {'rust s':>7} {'nl/rust':>8} {'base/rust':>9} {'nl/base':>7} "
          f"{'nl_p s':>7} {'rust_p s':>8} {'nl MB':>7} {'base MB':>7} {'rust MB':>8}  note")
kinds = ("ready", "closest-possible", "variant", "not-comparable")
groups = {kind: [] for kind in kinds}  # (pkg, ratio)
lines = {kind: [] for kind in kinds}
failures = 0
with open(lock_path, "w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    for pkg in pkgs:
        d = root / pkg
        status = (d / "status").read_text().strip() if (d / "status").is_file() else "ready"
        if not (d / "name").is_file():
            print(f"{pkg:26} ERROR missing package name file")
            failures += 1
            continue
        name = (d / "name").read_text().strip()
        kind = "variant" if status.startswith("variant-") else "not-comparable" if status.startswith("not-comparable:") else "ready"
        if kind == "ready" and status not in ("", "ready") and not status.startswith("pending-"):
            print(f"{pkg:26} ERROR unknown status {status!r}")
            failures += 1
            continue
        audit_path = d / "audit"
        if not audit_path.is_file():
            print(f"{pkg:26} ERROR missing comparison audit")
            failures += 1
            continue
        verdict = audit_path.read_text().strip().split(":", 1)[0]
        if kind == "ready":
            if verdict not in ("like-for-like", "rewritten-to-match", "closest-possible"):
                print(f"{pkg:26} ERROR unknown audit verdict {verdict!r}")
                failures += 1
                continue
            if verdict == "closest-possible":
                kind = "closest-possible"
        if name not in params:
            print(f"{pkg:26} ERROR missing LangArena checksum for {name!r}")
            failures += 1
            continue
        expected = params[name]
        exe = build(nlc, d, "nl")
        if exe is None:
            failures += 1
            continue
        base_exe = build(baseline, d, "base") if baseline else None
        best = {"run": 1e9, "prep": 1e9, "rust": 1e9, "rust_p": 1e9, "run_b": 1e9, "prep_b": 1e9}
        mem = {"nl": 0, "rust": 0, "base": 0}
        ok = True

        def check_nl(exe_path, tag, key_run, key_prep, mem_key):
            good = True
            r, wall, rss = timed([str(exe_path), "run"])
            output = r.stdout.strip().splitlines()
            if r.returncode != 0 or output != [expected]:
                good = False
                print(f"{pkg:26} {tag} RUN FAILED status={r.returncode} output={r.stdout[:200]!r} {r.stderr[-200:]!r}")
            best[key_run] = min(best[key_run], wall); mem[mem_key] = max(mem[mem_key], rss)
            r, wall, rss = timed([str(exe_path), "run", "prep"])
            output = r.stdout.strip().splitlines()
            if r.returncode != 0 or len(output) != 1 or not output[0].isascii() or not output[0].isdigit():
                good = False
                print(f"{pkg:26} {tag} PREP FAILED status={r.returncode} output={r.stdout[:200]!r} {r.stderr[-200:]!r}")
            best[key_prep] = min(best[key_prep], wall)
            return good

        for _ in range(runs):
            ok = check_nl(exe, "NEXT-LANG", "run", "prep", "nl") and ok
            if base_exe is not None:
                ok = check_nl(base_exe, "BASELINE", "run_b", "prep_b", "base") and ok
            r, wall, rss = timed([rust, str(arena / "run.js"), name], cwd=arena / "rust")
            m = re.findall(r"^(\S+): OK in ([\d.]+)s", r.stdout, re.M)
            if r.returncode != 0 or len(m) != 1 or m[0][0] != name or float(m[0][1]) <= 0:
                ok = False; print(f"{pkg:26} RUST RUN PROBLEM {r.stdout[-300:]!r}"); break
            best["rust"] = min(best["rust"], float(m[0][1])); best["rust_p"] = min(best["rust_p"], wall)
            mem["rust"] = max(mem["rust"], rss)
        if not ok:
            print(f"{pkg:26} FAILED")
            failures += 1
            continue
        net = best["run"] - best["prep"]
        if net <= 0:
            print(f"{pkg:26} INVALID TIMING: best run ({best['run']:.6f}s) <= best prep ({best['prep']:.6f}s)")
            failures += 1
            continue
        net_base = best["run_b"] - best["prep_b"] if base_exe is not None else None
        if net_base is not None and net_base <= 0:
            print(f"{pkg:26} INVALID BASELINE TIMING: best run ({best['run_b']:.6f}s) <= best prep ({best['prep_b']:.6f}s)")
            failures += 1
            continue
        ratio = net / best["rust"]
        groups[kind].append((pkg, ratio))
        note = status if kind in ("variant", "not-comparable") else "see audit" if kind == "closest-possible" else ""
        line = (f"{pkg:26} {cell(net, 7)} {cell(net_base, 7)} {best['rust']:7.3f} {ratio:8.2f} "
                f"{cell(net_base / best['rust'] if net_base is not None else None, 9, 2)} "
                f"{cell(net / net_base if net_base is not None else None, 7, 2)} {best['run']:7.3f} {best['rust_p']:8.3f} "
                f"{mem['nl'] / 1024:7.1f} {cell(mem['base'] / 1024 if base_exe is not None else None, 7, 1)} {mem['rust'] / 1024:8.1f}  {note}")
        lines[kind].append(line)
        print(line, flush=True)
    fcntl.flock(lock, fcntl.LOCK_UN)

titles = {"ready": "HEADLINE: like-for-like and rewritten-to-match ports",
          "closest-possible": "CLOSEST POSSIBLE (known differences; not in the headline)",
          "variant": "VARIANTS (alternative versions, not in the headline)",
          "not-comparable": "NOT COMPARABLE (library substitutes etc., not in the headline)"}
print()
print("nl s = best(run) - best(prep), rust s = LangArena timer, nl/rust = their ratio; base = the BASELINE compiler "
      "(when given), nl/base below 1 means the compiler under test is faster; "
      "nl_p / rust_p = whole-process times; MB = peak RSS of the run process. "
      "nl s estimates the run-body time from separate whole-process measurements; "
      "it includes timing noise and is not an in-process measurement.")
for kind in kinds:
    if not lines[kind]: continue
    print(f"\n== {titles[kind]} ==")
    print(HEADER)
    for l in lines[kind]: print(l)
    print(f"geometric mean nl/rust: {geomean([r for _, r in groups[kind]]):.2f} over {len(groups[kind])} tests")
print(f"comparison: {sum(map(len, groups.values()))} measured, {failures} failed")
