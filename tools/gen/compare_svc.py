#!/usr/bin/env python3
"""Compares the service compiler written in next-lang (tools/gen/svc) with the Python prototype (tools/svc.py).

    python3 tools/gen/compare_svc.py <path to the built svc binary>

Each case is a .svc file in a temporary package; both tools run, and the exit status, the error text and the generated
services.gen.nl must be identical. The real packages with .svc files are compared too.
"""

import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
BOX = "service Box\nstate n: long = 0L\nmailbox 8\non Put(v: long) {\n    state.n = v\n}\non Take() -> long {\n    reply(state.n)\n}\n"
A_GET = "service A\non Get() -> long {\n    reply(1L)\n}\n"
A_LOAD = "service A\non Load(answer: Sender<long>) {\n    let x = 1L\n}\n"
CASES = [
    ("names", BOX),
    ("idle", "service A\nstate n: long = 3L\non Ping() {\n    state.n += 1L\n}\nidle {\n    state.n > 0L\n}\n"),
    ("idle-tick", "service A\nconfig env: Env\non Ping() {\n}\nidle {\n    false\n}\ntick every 5 ms {\n}\n"),
    ("tick-only", "service A\nconfig env: Env\nstate t: long = 0L\non Ping() {\n}\ntick every 2 s {\n    state.t += missed\n}\n"),
    ("tick-no-env", "service A\non Ping() {\n}\ntick every 5 ms {\n}\n"),
    ("no-handler", "service A\n"),
    ("unclosed", "service A\non X() {\n"),
    ("dup-handler", "service A\non X() {\n}\non X() {\n}\n"),
    ("nothing", "nothing\n"),
    ("stop", "service A\non Stop() {\n}\n"),
    ("wait-function", A_GET + "service B\nconfig a: A\non Go() -> long {\n    let x = A_get(config.a)\n    reply(2L)\n}\n"),
    ("wait-method", A_GET + "service B\nconfig a: A\non Go() -> long {\n    let x = config.a.get()\n    reply(2L)\n}\n"),
    ("pass-reply-method", A_LOAD + "service B\nconfig a: A\non Go() -> long {\n    let f = config.a.load(reply)\n}\n"),
    ("pass-reply-function", A_LOAD + "service B\nconfig a: A\non Go() -> long {\n    let f = A_load(config.a, reply)\n}\n"),
    ("never-answers", "service A\non Get() -> long {\n    let x = 1L\n}\n"),
    ("reply-undeclared", "service A\non Put() {\n    reply(1L)\n}\n"),
    ("reply-in-comment", "service A\non Get() -> long {\n    // reply(1L)\n    let x = 1L\n}\n"),
    ("send-edges", "service A\non Put(v: long) {\n}\nservice B\nconfig a: A\non Go() {\n    discard A_put(config.a, 1L)\n    discard config.a.put(2L)\n}\n"),
    ("init-state", "service C\nconfig env: Env\nconfig db: Sender<long>\nstate a: list<long, 8> = list {}\nstate b: long = 7L\nmailbox 256\n"
                   "init {\n    let x = 1L\n    b = x\n}\non Add(k: long, w: long) {\n    state.b += k\n}\non Get(k: long) -> long {\n    reply(state.b)\n}\non Poke() {\n}\n"),
    ("comments-and-blank", "// a comment\n\nservice A\n\n// more\non X() {\n}\n\non Y(a: Option<long>, b: long) -> Option<long> {\n    reply(a)\n}\n"),
    ("unexpected", "service A\non X() {\n}\n    indented\n"),
    ("two-files-order", BOX + "service Z\non Q() {\n}\n"),
    ("snake-names", "service A\non GetAll(xs: long) -> long {\n    reply(1L)\n}\non HTTPGet() {\n}\n"),
    ("dup-service-block", "service A\non X() {\n}\nservice A\non Y() {\n}\n"),
    ("reply-comma", "service A\nconfig b: B\non Get() -> long {\n    let f = B_load(config.b, reply)\n}\nservice B\non Load(answer: Sender<long>) {\n}\n"),
    ("empty-bodies", "service A\non X() {\n\n}\non Y() {\n}\non Z() {\n}\n"),
]


def run(tool, directory):
    result = subprocess.run(tool, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=directory.parent)
    generated = directory / "services.gen.nl"
    return result.returncode, result.stderr.decode(errors="replace"), generated.read_text() if generated.exists() else None


def compare(name, make, python, native, failures):
    with tempfile.TemporaryDirectory(prefix="nl-cmp-") as base:
        results = []
        for label, tool in (("py", python), ("nl", native)):
            directory = pathlib.Path(base) / label
            directory.mkdir()
            make(directory)
            results.append(run(tool + [label], directory))
        normalise = lambda text: text.replace("py/", "X/").replace("nl/", "X/")
        py = (results[0][0], normalise(results[0][1]), results[0][2])
        nl = (results[1][0], normalise(results[1][1]), results[1][2])
        if py != nl:
            failures.append(name)
            print(f"MISMATCH {name}")
            print(f"  python: exit {py[0]} {py[1].strip()}")
            print(f"  native: exit {nl[0]} {nl[1].strip()}")
            if py[2] != nl[2] and py[2] is not None and nl[2] is not None:
                import difflib
                for line in list(difflib.unified_diff(py[2].splitlines(), nl[2].splitlines(), "python", "native", lineterm=""))[:24]:
                    print("   ", line)
        else:
            print(f"same     {name}")


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    native = [str(pathlib.Path(sys.argv[1]).resolve())]
    python = [sys.executable, str(ROOT / "tools" / "svc.py")]
    failures = []
    for name, source in CASES:
        def make(directory, source=source):
            (directory / "s.svc").write_text(source)
        compare(name, make, python, native, failures)
    for package in sorted(path.parent for path in ROOT.rglob("*.svc") if ".git" not in path.parts):
        def make(directory, package=package):
            for item in package.iterdir():
                if item.suffix == ".svc":
                    shutil.copy(item, directory / item.name)
        compare(str(package.relative_to(ROOT)), make, python, native, failures)
    print(f"{len(failures)} different" if failures else "all the same")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
