# Testing

Run the release suites with `NLC_FRONTEND=rust cargo test --offline --release`
and `NLC_FRONTEND=selfhost cargo test --offline --release`. Set
`CARGO_TARGET_DIR=$HOME/.cache/next-lang/target-s3` for this worktree. The
package comparison harnesses default to half the logical CPUs; set
`NLC_TEST_JOBS` to choose another worker count.

The regular selfhost suite checks every classified package against the
selfhosted compiler at O1. It also runs the O1 relocation matrix, E2 reference
audit, context-offset and interface checks, and the input-policy cases (which
drive both frontends). The build comparison keeps checking the Rust reference
result against each package's checked-in `expected.*` files and compares the
selfhost result on every run. It also runs the IR-bound and enum-scaling
checks. On a reference-cache hit, the Rust frontend does not rebuild and run
the package; the Rust `nlc` linker/test runner still validates the newly
generated selfhost IR. The Rust suite skips these selfhost-owned checks.

Rust reference results are stored under
`$CARGO_TARGET_DIR/next-lang-reference-results`. Each cache key hashes the
stage-zero `nlc` binary, all package files, O1, the commands and stdin passed
by the harness, the complete environment passed to the reference command
(including the retained `NLC_*` values), and the clang version. Entries contain the normalized build status,
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
includes the `selfhost/` and `core/` sources, reference `nlc` binary,
target/platform, `NLC_STACK_MODE`, and clang/rustc versions. Editing only test
packages therefore does not rebuild the compiler. A mismatch report includes
the first differing output diff; results are shown in package order regardless
of worker completion order.

The pre-commit hook snapshots the staged tree and always runs
`NLC_FRONTEND=selfhost cargo test --offline --release -q`. It also runs the
Rust suite when staged files touch `compiler/src/`, `compiler/Cargo.toml`, or
`compiler/build.rs`. The one-hour timeout, 8 GB virtual-memory limit, and skip
for docs-, benchmark-, and hook-only commits remain in effect.
