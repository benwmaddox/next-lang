# T02: loops and the test harness (milestone M0, part 2)

Depends on T01. Same rules as T01 (read it and docs/PLAN.md).

## Loops

- `for i in a..b { }` (stops before `b`) and `for i in a..=b { }` (includes `b`), with `break` and `continue`. Bounds are evaluated once, before the first iteration; ranges only count up, and a range whose start is past its end runs zero times.
- An inclusive range ending at the type's maximum (`for i in 0..=2147483647`) must end without overflowing the counter, also when the body uses `continue`.
- The counter's type comes from its bounds and use (DESIGN.md, "Loop counters take their type from their bounds and use"): bounds of a declared type set it; otherwise `int`; `for i: long in 0..n` declares it. If the bounds' types conflict, it's a build error asking for a cast.
- Every iteration is a scope (DESIGN.md, "Loops can't quietly fill a stack"): variables declared in the body are fresh each iteration. Keep the emitted structure such that a later milestone can add per-iteration cleanup at one place (the loop's latch block and every `break`/`continue` edge).

## `test` blocks and `nlc test`

- `test "name" { ... }` at the top level of any file, with `expect <bool>` steps; `let` and `var` between them. A failed `expect` ends that test.
- For `expect a == b` (and `!=`, `<`, `<=`, `>`, `>=`), each side is evaluated once and both values are shown on failure: `FAIL name\n  main.nl:12:5: expect a == b\n    left:  3\n    right: 4`.
- `nlc test <package-dir>` compiles the package once and runs each test in its own child process, so a runtime failure in one test (an overflow, say) fails only that test. Tests run in file-name order, then source order. Duplicate test names are a build error. Output: one line per test, `ok   name` or `FAIL name` plus details, then a summary line `N passed, M failed`; exit 0 if all pass, 1 otherwise.
- A test may call any function in the package; `main` isn't run.

## Tests (all must pass with `cargo test`)

- `tests/run/` cases for loops: `..` vs `..=` counts; nested loops with `break`/`continue`; a reversed range; the inclusive-maximum case with and without `continue`; counter typing (an `int` default, a `long` from a declared bound, a `for i: long`, a conflicting pair as a build error).
- A `tests/test/` directory kind (package with `test` blocks, `expected.stdout`, `expected.exit`) run by the integration test, with at least: all passing; one `expect` failing with both values shown; a test that overflows while others pass; a duplicate test name (build error).

## Report

docs/tasks/T02-report.md, as for T01.
