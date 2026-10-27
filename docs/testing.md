# Testing

Run the release suites with `NLC_FRONTEND=rust cargo test --offline --release`
and `NLC_FRONTEND=selfhost cargo test --offline --release`. Set
`CARGO_TARGET_DIR=$HOME/.cache/next-lang/target-s3` for this worktree. The
package comparison harnesses default to half the logical CPUs; set
`NLC_TEST_JOBS` to choose another worker count.

For a focused selfhost build comparison:

```sh
scripts/compare-selfhost.sh --build --only 'tests/e3/*'
scripts/compare-selfhost.sh --build --class build
scripts/compare-selfhost.sh --build --changed
scripts/compare-selfhost.sh --build --changed main
```

The lexer/parser comparison accepts the same selectors:

```sh
scripts/compare-selfhost.sh --tokens --reference "$CARGO_TARGET_DIR/release/nlc" --selfhost /path/to/selfhost --only 'tests/run/*'
scripts/compare-selfhost.sh --parse --reference "$CARGO_TARGET_DIR/release/nlc" --selfhost /path/to/selfhost --changed
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
focused run still performs the harness's fixed CLI checks. The full build
comparison also retains its IR-bound and enum-scaling checks.
Focused comparison modes omit the generated mutation corpus and benchmark;
those packages remain part of every unfiltered comparison run.

The O3 relocation pass is part of `NLC_LONG_TESTS=1`; normal full suites check
all build packages at O1. The build comparison, lexer/parser comparison,
relocation check, E2 reference audit, context-offset audit, selfhost interface
audit, and input-policy tests select frontends explicitly or inspect
frontend-independent inputs, so the Rust suite runs them once. The input-policy
tests exercise both frontends inside each case.

The lexer/parser, build, and relocation harnesses share the cached stage-zero
selfhost executable under `CARGO_TARGET_DIR/next-lang-test-selfhost`. Its key
includes the `selfhost/` and `core/` sources, reference `nlc` binary, target,
and compiler tool versions. Editing only test packages therefore does not
rebuild the compiler. A mismatch report includes the first differing output
diff; results are shown in package order regardless of worker completion
order.
