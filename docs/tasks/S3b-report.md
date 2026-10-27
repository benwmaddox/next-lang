# S3b: selfhost-first testing report

## Timing

Measurements used the `s3-suite-speed` worktree, `/home/ben/linuxbench/bench.lock`,
`CARGO_TARGET_DIR=$HOME/.cache/next-lang/target-s3`, and `ulimit -v 8000000`.
The default command measured was
`NLC_FRONTEND=selfhost cargo test --offline --release -q`.

| Measurement | Wall time | Maximum RSS reported by `/usr/bin/time` |
| --- | ---: | ---: |
| Before S3b: old hook ran Rust and selfhost suites | 720.86 s (12m 01s) | 4,438 MiB observed across the run* |
| S3b default, cold reference cache | 397.66 s (6m 38s) | 3,141,288 KiB |
| S3b default, warm reference cache | 366.28 s (6m 06s) | 3,141,288 KiB |
| Full `NLC_STAGE0_PARITY=1 NLC_LONG_TESTS=1` selfhost run | 664.46 s (11m 04s) | 3,141,464 KiB |

* The previous S3 RSS is a process-tree aggregate from its report; the S3b
  values are GNU `/usr/bin/time` maximum-RSS readings, so the RSS columns are
  not directly comparable.

The prior combined-suite baseline is from [S3's report](S3-report.md). Its
selfhost command alone took 230.62 s, but S3 routed the selfhost comparisons
and audits into the separate Rust command. S3b moves those checks into the
selfhost command, so the standalone selfhost times cover more work. The
default hook command is now about 45% faster cold and 49% faster warm than the
prior combined command.

The full parity run passed. The build comparison returned success at zero
mismatches for every classified package and seeded case; the lexer/parser
comparisons and generated mutation corpus also passed. The comparison test
captures its child output, so Cargo's quiet run does not print the per-class
counts on success.

## What runs when

Regular `NLC_FRONTEND=selfhost` runs compare all 624 classified packages at
O1, check the O1 relocation matrix, run the E2 reference, context-offset,
selfhost interface, and input-policy checks, and retain the IR-bound and
enum-scaling checks. Input-policy cases explicitly exercise both frontends.
The Rust suite skips these selfhost-owned checks.

The `--tokens` and `--parse` stage-zero comparisons are gated by
`NLC_STAGE0_PARITY=1` and require `NLC_LONG_TESTS=1`. This mode also runs the
seeded build/diagnostic cases and the generated lexer/parser mutation corpus,
and forces fresh Rust reference results with `--no-reference-cache`.
`NLC_LONG_TESTS=1` adds O3 comparisons and relocation checks. Direct
`scripts/compare-selfhost.sh` lexer/parser runs remain available.

Stage zero still supplies cached Rust reference build status, diagnostics,
run status, stdout, and stderr to the regular build comparison. A cache miss
runs the Rust frontend and stores its normalized result; a hit skips those
package build/run commands. Every run still invokes the Rust `nlc` linker or
test runner on newly generated selfhost IR, so selfhost compilation and
execution remain checked. The source-hash cache for the selfhost executable
also uses stage zero when that compiler artifact needs to be built.

## Reference-result cache

Entries live at
`$CARGO_TARGET_DIR/next-lang-reference-results/<key>.json`. The SHA-256 key
covers the stage-zero `nlc` binary, every package file and its relative path,
the optimization level, invocation arguments/cwd/stdin, the complete
environment passed to the reference commands (including the retained
`NLC_*` variables), and `clang --version`. Results store build status, status, and normalized stdout
and stderr. A temporary file followed by `os.replace` publishes each entry
atomically across workers and concurrent suites.

`--no-reference-cache` ignores entries, runs stage zero, and refreshes the
cache. Remove `$CARGO_TARGET_DIR/next-lang-reference-results` to clear all
reference results.

## Injected failures

- **Wrong reference cache entry:** I replaced the cached stdout for
  `tests/run/arithmetic` with an intentionally wrong value. A normal focused
  comparison read that entry (`hits=1`) and failed with “Rust reference differs
  from checked-in expected.* files” (`mismatches=1`). The same comparison with
  `--no-reference-cache` bypassed it (`forced-fresh=1`), refreshed the entry,
  and passed with zero mismatches.
- **Selfhost miscompile:** I temporarily swapped the checked add/sub IR
  selection in `selfhost/compiler.nl`. The regular warm-cache selfhost suite
  failed with Cargo status 101 and reported mismatches between Rust and
  selfhost outputs, including selfhost runtime failures. The source was
  restored byte-for-byte: its SHA-256 before and after was
  `62abd5587a92c68a74fc72dcc11b26dda0d2ee819f4ac58696bf3c0ecb3d62b2`.

`cargo fmt --all -- --check` and `git diff --check` passed. Focused Rust-suite
targets also passed with `NLC_FRONTEND=rust`, confirming they skip these
selfhost-owned checks.

## Git index cleanup limitation

`.gitignore` now ignores `__pycache__/`. The requested
`git rm --cached scripts/__pycache__/test_harness.cpython-312.pyc` could not
update the index: this worktree's index is under the shared, read-only
`/mnt/d/code/next-lang/.git/worktrees/next-lang-s3` metadata directory. The
failed command made no index change, and no other Git write was attempted.
