# Testing

## Working loop (implementers)

While working on a step, use the focused selectors below (`--only`, `--class`,
`--changed`) on the packages you touch. Run the full selfhost suite
(`NLC_FRONTEND=selfhost cargo test --offline --release -q --test '*'`) once at
the end of the step, not after every change; the pre-commit hook runs it again
on every commit. Run the Rust suite only if you change stage 0
(`compiler/src/`), which is frozen. Stage-0 parity (`NLC_STAGE0_PARITY=1`)
is for deliberate audits, not the everyday loop.

## Suites

Run the release suites with `NLC_FRONTEND=rust cargo test --offline --release`
and `NLC_FRONTEND=selfhost cargo test --offline --release`. The
package comparison harnesses default to half the logical CPUs; set
`NLC_TEST_JOBS` to choose another worker count.

The regular selfhost suite checks every classified package against the
selfhosted compiler at O1. It also runs the O1 relocation matrix, E2 reference
audit, context-offset and interface checks, and the self-hosted side of the
input-policy cases. The build comparison keeps checking the Rust reference
result against each package's checked-in `expected.*` files and compares the
selfhost result on every run. It also runs the IR-bound and enum-scaling
checks. On a reference-cache hit, the Rust frontend does not rebuild and run
the package; the Rust `nlc` linker/test runner still validates the newly
generated selfhost IR. The Rust suite skips these selfhost-owned checks.

The `expected` classification is for packages whose syntax or behavior the
stage-zero compiler cannot serve as a reference. The build comparison runs the
selfhost compiler, then compares its status, stdout, and stderr directly with
the package's committed `expected.exit`, `expected.stdout`, and
`expected.stderr` files. These packages also participate in relocation checks
when selected by the relocation harness.

Under `NLC_FRONTEND=selfhost`, `language` and `parse_dump` would drive the
hybrid frontend (the self-hosted lexer and parser feeding the frozen stage-0
checker), which is parse parity with stage 0; they run only with
`NLC_STAGE0_PARITY=1`. The stage-0 side of the input-policy cases also runs
only in that mode.

Rust reference results are stored under
`$CARGO_TARGET_DIR/next-lang-reference-results`. Each cache key hashes the
stage-zero sources (`compiler/src/`, `compiler/Cargo.toml`, `Cargo.lock`) and
the rustc version, all package files, the optimization level, the commands and
stdin passed by the harness, the environment passed to the reference command
(including the retained `NLC_*` values, with the checkout root replaced by a
placeholder and cargo's path variables, `PWD` and `OLDPWD` left out), and the
clang version. The key does not depend on the checkout path, so pre-commit
snapshots reuse it. Entries contain the normalized build status,
diagnostics, run status, stdout and stderr. Cache files are published
atomically, so concurrent workers or suites can safely fill the same key. To
discard the reference results, remove that directory; the separately cached
selfhost compiler is in `$CARGO_TARGET_DIR/next-lang-test-selfhost`.

Use `--no-reference-cache` to force a fresh Rust reference run and refresh its
entry:

```sh
scripts/compare-selfhost.sh --build --reference "$CARGO_TARGET_DIR/release/nlc" --no-reference-cache
```

`NLC_STAGE0_PARITY=1` is the on-demand stage-zero parity mode. It requires
`NLC_LONG_TESTS=1`, reruns the Rust references without reading the result
cache, runs the lexer and parser comparisons, and includes the seeded build
cases and generated mutation corpus. The long-test setting also adds the O3
comparison and relocation checks; regular runs remain O1. For example:

```sh
NLC_FRONTEND=selfhost NLC_STAGE0_PARITY=1 NLC_LONG_TESTS=1 cargo test --offline --release -q
```

The lexer/parser comparison accepts the same selectors and remains available
for direct runs:

```sh
scripts/compare-selfhost.sh --tokens --reference "$CARGO_TARGET_DIR/release/nlc" --selfhost /path/to/selfhost --only 'tests/run/*'
scripts/compare-selfhost.sh --parse --reference "$CARGO_TARGET_DIR/release/nlc" --selfhost /path/to/selfhost --changed
```

For a focused selfhost build comparison:

```sh
scripts/compare-selfhost.sh --build --only 'tests/e3/*'
scripts/compare-selfhost.sh --build --class build
scripts/compare-selfhost.sh --build --changed
scripts/compare-selfhost.sh --build --changed main
```

Run focused relocation checks with the same selectors:

```sh
scripts/check-selfhost-relocation.py --reference "$CARGO_TARGET_DIR/release/nlc" --only 'tests/e3/*'
scripts/check-selfhost-relocation.py --reference "$CARGO_TARGET_DIR/release/nlc" --class build
scripts/check-selfhost-relocation.py --reference "$CARGO_TARGET_DIR/release/nlc" --changed
```

`--changed` compares package files against `HEAD` by default; pass a commit or
tag to compare against another revision. Multiple `--only` globs are combined
as an inclusive set, while `--class` and `--changed` further narrow it. A
focused run still performs the harness's fixed CLI checks. The O3 relocation
matrix runs with `NLC_LONG_TESTS=1`.

The lexer/parser, build, and relocation harnesses share the cached stage-zero
selfhost executable under `$CARGO_TARGET_DIR/next-lang-test-selfhost`. Its key
includes the `selfhost/` and `core/` sources, the stage-0 sources,
target/platform, `NLC_STACK_MODE`, and clang/rustc versions. Editing only test
packages therefore does not rebuild the compiler. A mismatch report includes
the first differing output diff; results are shown in package order regardless
of worker completion order.

The pre-commit hook snapshots the staged tree and always runs the selfhost
integration tests (`NLC_FRONTEND=selfhost cargo test --offline --release -q
--test '*'`; the library's unit tests cover frozen stage 0). It also runs the
full Rust suite when staged files touch `compiler/src/`, `compiler/Cargo.toml`, or
`compiler/build.rs`. The one-hour timeout, 8 GB virtual-memory limit, and skip
for docs-, benchmark-, and hook-only commits remain in effect. Commits take
turns through `$HOME/.cache/next-lang/precommit.lock`, because the main
checkout and worktrees share the hook's build directory.
