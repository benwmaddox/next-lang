# T17: per-entry-point reservations and inspect stacks (milestone M3, part 5)

Depends on T16. Same rules. Read DESIGN.md "The job's data stack" (reservations sized per entry point) and "Loops can't quietly fill a stack" ("The compiler adds it up", "Tests can pin it").

- **Worst case per stack, per entry point:** from the bounds the checker already has (maxima, counted loops, append contracts, reserved regions, the two-value peak of copy-down reassignments, large fixed values in regions), compute for each entry point (`main`, each `test`) the worst-case bytes on its data stack and on the native stack (frame sizes from LLVM, the deepest call chain; recursion isn't supported yet). An entry point with something it can't bound is reported as unbounded and gets the 64 MB default.
- **Reservations follow:** the runtime reserves each stack at its computed worst case, rounded up to a page, instead of 64 MB, so most programs reserve far less.
- **`nlc inspect stacks <package>`:** per entry point, N, each stack's worst case in bytes and the source lines that drive it, each loop's growth per iteration, the native-stack worst case, and anything unbounded.
- **`expect stack_peak(f) < 2 MB`** in tests: the computed worst case of entry or function `f`, so a change that raises it past a budget fails a test.
- Acceptance cases: the worked example's numbers (one data stack: 40,000 bytes for `out`'s region plus 60 for `name`, plus descriptors and alignment, rounded up to a page); a program whose reservation shrinks from 64 MB to a few pages; an unbounded entry point reported as such; `stack_peak` passing and failing; a test-only shrunken reservation below the computed worst case refused at startup with a clear message (the computed bound must never be smaller than real use: run the step 2 acceptance programs and compare measured peaks with the computed worst cases, each measured ≤ computed).
- Report: docs/tasks/T17-report.md, including `inspect stacks` output for the worked example and the measured-versus-computed table.

## Corrections from Sol's second M3 review (docs/reviews/sol-M3-r2.md), binding

- Accounting counts, at each point, the caller's live storage, the callee's scratch, copy-down's old and new values, and a fixed margin for runtime helpers; function values use the maximum over every function that fits their type (T15 put byte bounds in function types).
- The native stack: this task computes and reports each entry point's native-stack bound (frame sizes from the optimised target code actually built, plus a helper margin), carried through calls via function values too, but does not yet reserve or switch to a per-job native stack; that comes with the job scheduler (deferred explicitly in PLAN.md).
- `stack_peak(f)` is a conservative total in bytes across the data stack and the native stack, excluding page rounding; a function's caller-owned result counts in the caller.
- T13's runtime-exhaustion test and this task's startup refusal of an undersized reservation stay separate tests.
- Since the supported language has no legal unbounded source, the "unbounded entry point" case is an analysis-only test (a function with an unknown contract, such as a C binding stub) rather than a running program; unbounded loop growth is never allowed just to exercise the fallback.
- `inspect stacks` also lists every copy-down site, as DESIGN.md asks.


- `inspect stacks` also lists each reserved region over 64 KB (address space reserved ahead) and any slide-down sites the compiler chose as an optimisation.
