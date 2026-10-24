T02 needs these decisions before implementation:

- **Counter inference:** “bounds and use” conflicts with “otherwise int” unless body constraints precede defaulting. Answer: with untyped bounds, `fn f(x: long) {}` plus `for i in 0..2 { f(i) }` infers `long`. Explicit counter types and typed bounds constrain the same type; incompatible constraints require casts, never implicit widening. Unsuffixed bound literals take that type; computed expressions retain T01’s ordinary typing rules.
- **Counter scope and control flow:** specify an immutable counter, visible only in its body, with nested shadowing allowed. `break`/`continue` target the nearest loop; outside one they are build errors. Loops have unit type; a return inside a potentially empty loop cannot satisfy a function’s required result. Cleanup planning must include `return` through every enclosing iteration, beyond T02’s latch/break/continue list.
- **Test grammar:** allow ordinary T01 statements and loops inside tests, including calls and `print`; permit `expect` inside nested test-body blocks, but reject it in ordinary functions. Reject direct `return` from a test so early success cannot silently skip expectations. Require boolean conditions. Parenthesized comparisons should still show operands; other boolean failures show source text and `false`. Show source including `expect`, stripping leading indentation and preserving internal newlines.
- **Entry points:** `nlc test` must accept packages without `main`; an existing `main` is checked but not invoked automatically. Define `run`/`build` as checking test bodies without executing them. Empty suites print `0 passed, 0 failed` and succeed. Any package build error prevents all test execution.

T01 integration conflicts and missing contracts:

- T02’s “exit 0 … 1 otherwise” must preserve T01’s **2 for build errors and 3 for tool failures**. The duplicate-name fixture therefore expects 2. Add `expected.stderr` to `tests/test/`, with T01’s path normalization, to verify duplicate-name locations and runtime failures.
- Child output routing is unspecified. Answer: capture each child’s stdout/stderr; emit its status before forwarding captured output to the matching streams, before the next test. Harness statuses, expectation details and summary go to stdout; abnormal termination gets a named failure detail. Keep arithmetic failures through T01’s `nl_fail`, preserving stderr diagnostics; expectation operands must remain captured typed values, never evaluated again to format diagnostics. Test entry functions use the shared signature-lowering path.

Missing acceptance cases:

- Side-effecting bounds evaluated once, left-to-right, even for empty ranges; body mutation cannot change the endpoint. Equal endpoints; negative bounds; `int` and `long` maximum singleton ranges, with/without `continue` (avoid billions of iterations).
- Immutable/out-of-scope counters, invalid bound types, out-of-loop exits, per-iteration local initialization, nested exits and return from nested loops.
- Every comparison operator, boolean expectations, operand evaluation order/once, short-circuiting, and proof that failure skips subsequent steps while later tests run.
- Multiple files in deliberately reversed discovery order; duplicate names across files; no-main/empty suites; function calls; captured prints; exact runtime diagnostic location and summary counts.
