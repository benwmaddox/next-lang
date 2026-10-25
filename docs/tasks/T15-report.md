# T15 report: append mode and loop growth

Implemented append variants for functions returning `Ascii` and `Result<Ascii, E>`. A streamed call receives the destination data region and an accepted-length slot. The caller only publishes the new builder length after success. Direct and indirect calls use append mode, including Result calls through function values. Result errors restore the producer checkpoint; `try_append` checks a maximum-sized fast path first and uses a bounded scratch region when the remaining capacity is smaller, then checks the actual output length before copying it into the builder.

`Result<Ascii, E>` producers can use `?` while appending; `??` remains Option-only. Conditional and `match` Result returns are covered. Function types accept narrower Ascii or Result-Asciis when their error types match, and record whether append mode is supported. `out += f(out)` uses scratch storage for the overlapping call. Reassignment such as `acc = merge(acc, x)` builds a temporary and copies it into the reserved builder region.

The checker proves plain append growth across bounded counted loops and reports overflow at the loop. `try_append` relies on the builder's declared maximum. An unannotated `Ascii.empty()` inside a loop names the builder and loop counter and gives both bounded-growth and `try_append` fixes. Loop iteration storage is reclaimed between iterations.

## Acceptance coverage

- `tests/run/t15_append_growth` runs the `render`/`line` example, exact-maximum fresh and append results, `out += f(out)`, and an accumulating `acc = merge(acc, piece)` assignment. Its fallible cases verify a producer prefix followed by `err(Full)`, rollback and successful reuse, capacity `Full` after the producer streams a prefix into bounded scratch storage, and the distinction between producer `Full` propagated by `?` and capacity `Full` returned by `try_append`.
- The same fixture covers `match field(x) { ok(f) => buf.try_append(f), err(_) => ok(()) }` with direct and indirect Result producers; narrower and wider callback result maxima; append calls through a function value; three interleaved builders; and an inner successful append followed by an outer capacity failure and reuse.
- `tests/run/t15_loop_overflow` checks growth inside an expression-valued `if` and expects a builder-specific overflow error. `tests/run/t15_uninferred_loop_builder` checks the diagnostic and both fixes for `Ascii.empty()` inside a loop.
- The million-iteration case creates a one-byte temporary each time and returns length 1,000,000. `inspect contracts` reports 1,000,033 bytes for that function, independent of iteration count. The worked example reports 76 bytes above `render`'s 40,016-byte destination region, for a 40,092-byte requirement. `merge_in_loop` reports 147 bytes including the temporary/copy peak.

## Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — passed (31 unit and integration tests; doc-tests passed).
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target scripts/update-parse-dumps.sh --update` — refreshed snapshots for all three T15 fixtures.
- `nlc run tests/run/t15_append_growth` — matched the expected output, including the million-byte length.
- `/usr/bin/time -v /tmp/t15_append_growth` — maximum resident set size 2,464 KB.

The initial Result coalescing exception described during implementation was removed in Fix round 1 below.

No T15 acceptance work remains. `Text`, `Bytes`, and collections of growing values remain in T16 as scoped by the task.

## Fix round 1

Removed the `??` extension for `Result<Ascii, E>`. `??` accepts `Option` only; any `Result` now produces the diagnostic `use 'match' to handle a Result or '?' to pass its error up`. The Result-specific append-streaming branch for coalescing was removed as well. The `Result<Ascii>` rejection fixture now checks a Result in a context with an expected Ascii return type.

Updated `log_line` and `log_callback` in `tests/run/t15_append_growth` to use the explicit `match` form. A `match` over `Result<Ascii, E>` materializes the Result value first because the current match emitter needs its tag before it selects an arm. On `ok`, the bound Ascii value is then passed to `buf.try_append(f)`, which performs the capacity check and checkpointed append. Direct `out += producer()?` and `buf.try_append(producer()?)` cases still select the producer's append variant and roll back on producer errors.

Verification for this fix round:

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — passed (31 unit and integration tests; doc-tests passed, including the T15 fixture and Result coalescing diagnostic fixture).
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt -- --check` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target scripts/update-parse-dumps.sh --update` — passed; refreshed the changed T15 and Result coalescing snapshots.
