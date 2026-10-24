# T17: per-entry-point reservations and inspect stacks (milestone M3, part 5)

Depends on T16. Same rules. Read DESIGN.md "N stacks per job" (reservations sized per entry point) and "Loops can't quietly fill a stack" ("The compiler adds it up", "Tests can pin it").

- **Worst case per stack, per entry point:** from the bounds the checker already has (maxima, counted loops, append contracts, the two-value peak of copy-down reassignments, fixed scratch), compute for each entry point (`main`, each `test`) the worst-case bytes on each of its N data stacks and on the native stack (frame sizes from LLVM, the deepest call chain; recursion isn't supported yet). An entry point with something it can't bound is reported as unbounded and gets the 64 MB default.
- **Reservations follow:** the runtime reserves each stack at its computed worst case, rounded up to a page, instead of 64 MB, so most programs reserve far less.
- **`nlc inspect stacks <package>`:** per entry point, N, each stack's worst case in bytes and the source lines that drive it, each loop's growth per iteration, the native-stack worst case, and anything unbounded.
- **`expect stack_peak(f) < 2 MB`** in tests: the computed worst case of entry or function `f`, so a change that raises it past a budget fails a test.
- Acceptance cases: the worked example's numbers (stack 0 holds 40,000 bytes plus page rounding; stack 1 holds 60 bytes); a program whose reservation shrinks from 64 MB to a few pages; an unbounded entry point reported as such; `stack_peak` passing and failing; a test-only shrunken reservation below the computed worst case refused at startup with a clear message (the computed bound must never be smaller than real use: run the step 2 acceptance programs and compare measured peaks with the computed worst cases, each measured ≤ computed).
- Report: docs/tasks/T17-report.md, including `inspect stacks` output for the worked example and the measured-versus-computed table.

## Corrections from Sol's second M3 review (docs/reviews/sol-M3-r2.md), binding

- Accounting counts, at each point, the caller's live storage, the callee's scratch, copy-down's old and new values, and a fixed margin for runtime helpers; function values use the maximum over every function that fits their type (T15 put byte bounds in function types).
- The native stack: this task reserves a native stack per entry point from the computed bound (with a guard page and a helper margin) and switches to it for the job, or, if that's too much now, reports the bound only and the report says so; LLVM frame sizes come from the optimised target code actually built.
- `stack_peak(f)` is a conservative total in bytes across data stacks, fixed scratch and the native stack, excluding page rounding; a function's caller-owned result counts in the caller.
- T13's runtime-exhaustion test and this task's startup refusal of an undersized reservation stay separate tests.
- Since the supported language has no legal unbounded source, the "unbounded entry point" case is an analysis-only test (a function with an unknown contract, such as a C binding stub) rather than a running program; unbounded loop growth is never allowed just to exercise the fallback.
- `inspect stacks` also lists every copy-down site, as DESIGN.md asks.

## Ben's stack-count decision (2026-10-24), overrides anything above

DESIGN.md "Few stacks, used well": **one data stack per job by default, at most two.** Where this task says "N data stacks", "fixed scratch stack", "window k = 1 on stack 1" or "N = 2", read it under these rules:

- Finished values share the current stack in last-in-first-out order; only a value still growing while something above it is alive must be on top.
- There is **no separate fixed-scratch stack**: a large fixed-size temporary goes on top of the current data stack when nothing below it will grow during its lifetime, otherwise on the native stack.
- **Build above, then slide down:** something built while a value below it is still growing is built just past that value's end, then moved down onto it. A second data stack is used only when such a piece could exceed 4 KB; never more than two.
- The worked example (`render`/`line`) runs on **one stack, N = 1**: `name` and `line`'s result are built above `out`'s end and the result slides down. Its worst case is 40,000 + 60 + 80 = 40,140 bytes plus page rounding (T17's numbers).
- `inspect contracts` / `inspect stacks` list every slide-down site and its worst-case copy size.
