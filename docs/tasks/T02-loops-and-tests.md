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

## Decisions from Sol's review (docs/reviews/sol-T02-r1.md), all binding

- **Counter typing:** body uses count as constraints before defaulting: `for i in 0..2 { f(i) }` with `fn f(x: long)` makes `i` a `long`. An explicit counter type and typed bounds constrain the same type; incompatible constraints need a cast, never implicit widening. Unsuffixed bound literals take the counter's type; computed bounds keep T01's typing.
- **Counter scope:** the counter is immutable and visible only in the body; nested loops may shadow it. `break`/`continue` target the nearest loop; outside a loop they're build errors. A loop's type is `()`; a `return` inside a loop that might run zero times doesn't satisfy a function's required result.
- **Cleanup points:** the per-iteration cleanup hook must also cover `return` out of any number of enclosing loops, not just the latch and `break`/`continue`.
- **Test bodies:** any T01/T02 statement (calls, loops, `print`) is allowed; `expect` may appear in nested blocks inside a test but is a build error in ordinary functions; `return` directly in a test is a build error. `expect` needs a `bool`. A parenthesised comparison still shows both sides; any other failing `bool` shows its source text and `false`. Show the source of the `expect` with leading indentation stripped.
- **Entry points:** `nlc test` accepts a package with no `main`; if `main` exists it's checked but not run. `nlc run`/`build` check test bodies but don't run them. An empty suite prints `0 passed, 0 failed` and exits 0. Any build error stops all tests.
- **Exit codes:** `nlc test` keeps T01's codes: 0 all passed, 1 a test failed, 2 a build error (so the duplicate-name case expects 2), 3 a tool failure. `tests/test/` cases get an `expected.stderr` too, normalised as in T01.
- **Output routing:** each test child's stdout and stderr are captured; the harness prints the test's status line, then forwards the captured output to the matching stream, before the next test. Status lines, `expect` details and the summary go to stdout. A child that dies abnormally gets a named failure detail. Arithmetic failures still go through `nl_fail`. `expect` operands are captured as typed values and never evaluated again for the message. Test entry functions use the shared signature-lowering path.

## More acceptance cases (from the same review)

- Bounds with side effects are evaluated once, left to right, even when the range is empty; changing a variable used in the bound inside the body doesn't change the end. Equal endpoints; negative bounds; a single-element range at `int`'s and `long`'s maximum, with and without `continue` (not billions of iterations).
- Build errors: assigning to the counter; using it after the loop; a non-integer bound; `break`/`continue` outside a loop. A fresh body local each iteration; `break` and `continue` in nested loops; `return` from inside nested loops.
- Every comparison operator in `expect`; a plain `bool` expectation; operands evaluated once and in order; short-circuiting inside `expect`; a failing step skips the rest of its test while later tests still run.
- Several test files whose names sort opposite to their declaration order; duplicate names across files; a package with no `main`; an empty suite; tests calling functions; a test that prints (output captured and forwarded); the exact runtime failure location and the summary counts.

## Follow-ups from the T01 review (Claude), small, do them first

- Declare the failure function so LLVM knows it never returns and is rarely taken: `declare void @nl_fail(i32, i32, i32, i32) noreturn cold nounwind` in the IR, `_Noreturn` on the C definition, and mark every guard branch unlikely (branch weights, `!prof !{!"branch_weights", i32 1, i32 2000}` or `llvm.expect`), so the fast path is laid out straight.
- A method that doesn't exist for a type (`5L.to_long()`, since `to_long` is only on `int`) currently reports "cannot combine int and long"; it should say `no method 'to_long' on long` and, where one exists, suggest the right one. Add a build-error case.
