# Working in next-lang (for agents and new contributors)

next-lang is a compiled language with bounded memory; the compiler is written in itself (`selfhost/*.nl`, library in `core/`).
The Rust compiler in `compiler/` is **frozen** (stage 0): change it only if the self-hosted compiler cannot otherwise be built.

## Environment

Linux or WSL with `clang` 18 and `python3`. On Windows run everything through `wsl` (use `MSYS_NO_PATHCONV=1` from Git Bash).
`cargo` is needed only for stage-0 work. Nothing else to install: the first `scripts/nlc` call builds the compiler from
`seed/seed.ll.gz` (cached under `target/next-lang-test-selfhost-seed`, keyed by the sources).

## Everyday commands

```
scripts/nlc check <package>    # compile only, ~50 ms: the fast way to find build errors (one error is reported at a time)
scripts/nlc run   <package>    # build and run (arguments after --)
scripts/nlc test  <package>    # run the package's `test` blocks
scripts/nlc --help
```

A package is a directory of `.nl` files and must be given as a path relative to the current directory. Language reference:
[docs/LANGUAGE.md](docs/LANGUAGE.md) (what compiles today) with a runnable tour in `docs/examples/tour`. Design intent:
[docs/DESIGN.md](docs/DESIGN.md), short form [docs/OVERVIEW.md](docs/OVERVIEW.md). Plan and roadmap: [docs/PLAN.md](docs/PLAN.md),
[docs/design/web-app-plan.md](docs/design/web-app-plan.md). Snags found while writing real programs: [docs/campfire-friction.md](docs/campfire-friction.md).

## Testing

- While working: `scripts/test-related.sh` runs the Python tests that map to the files you changed (or name them:
  `scripts/test-related.sh jobs mailbox`); `scripts/nlc test --filter <text> <package>` runs only the tests whose name
  contains the text. Or run one Python test by hand, e.g. `python3 -m unittest discover -s tests/py -p test_jobs.py`
  (`pytest` is not installed), or, for compiler test packages (a few seconds),
  `scripts/run-frozen-suite.sh "$(python3 scripts/build-selfhost-cached.py)" --only 'tests/e3/b1_byte*'`.
- Before committing: the pre-commit hook (`scripts/install-hooks.sh`) runs the whole selfhost suite (3 to 4 minutes; skipped for
  docs-only commits). Details: [docs/testing.md](docs/testing.md).
- Compiler tests are directories under `tests/*/<name>/` with `main.nl` and `expected.{exit,stdout,stderr}`. A new language
  feature needs a package there and, where it is a user-visible feature, a line in `docs/LANGUAGE.md` and `docs/examples/tour`.

## Rules that have bitten before

- The compiler's own source (`selfhost/*.nl`) can use only what the **seed** compiler supports. After a language change the
  compiler's code wants to use, run `scripts/update-seed.sh` (it checks stage 2 equals stage 3 first).
- Emitters write LLVM IR in one flat pass: no nested temporaries or re-copying a prefix, unless there is a strong reason.
- Allocas that are passed by address to a call must be made in the function's entry block, not inside a loop (they are never
  freed until return).
- Trust computed bounds (stack sizes, text maxima); do not add safety factors. If a bound cannot be trusted, fix the
  computation.
- No mutable globals in programs: state is a local in `main`, passed down.
- Editing files with backslashes or quotes: use the editor tool, not `sed` or heredoc rewrites (`\n` inside IR strings is
  easily corrupted).
- `git add` named files only. Scratch directories (`.c-bootstrap-smoke-*`, `e3c-scratch`, `.selfhost-*`) are untracked.
- Benchmarks (`bench/`) share cores 8 to 21 between sessions: wrap runs in `flock -x /home/ben/linuxbench/bench.lock`.
  Every program in `bench/` or `apps/` gets a scoreboard row against a Rust counterpart, memory included.
- Do not commit the output of a measurement run, or any file over a few hundred KB, without checking `git diff --stat` first.

## Where things are

`selfhost/` compiler and `core/` library, `runtime/nl_runtime.c` the C runtime (threads, epoll, HTTP, SQLite glue),
`seed/` the bootstrap IR, `scripts/` drivers and checks, `tools/gen/` generators written in next-lang (services, templates),
`apps/` and `bench/` programs, `tests/` everything with expected output, `docs/` design and plans.
