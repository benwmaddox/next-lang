# X1: measurement spike, a relocatable data stack addressed by offsets

An experiment, not a feature: it decides whether next-lang adopts a movable data stack (Ben, 2026-10-25). It runs on the branch `spike/offset-stack` in its own worktree and is never merged as is. T28 (the capped reservation) is on hold until this is measured.

## The idea being tested

Today every reference into a job's data stack is a machine pointer, so the stack can never move, and its whole possible size must be reserved up front (DESIGN.md "The job's data stack"). The alternative:

1. **Offset addressing:** every reference into the data stack (region payloads, Ascii/Text/Bytes descriptors' payload references, collection lanes, views, `write` parameters, hidden result destinations, the cached top) is an offset from the job's stack base. The base lives in the job context and is cached in a register like the top (T13); an access is `base + offset`.
2. **Growth points:** the stack grows only where it must (a region creation or append that doesn't fit the current reservation). After any call that may grow, the compiler reloads the base, as it reloads the top. No raw pointer into the data stack is held across a growth point; deriving a raw pointer is allowed only between growth points (and for foreign or runtime calls, during which the stack is pinned and can't grow).
3. **Moving:** on Linux, `mremap(..., MREMAP_MAYMOVE)` to a reservation twice as large (or larger if one region needs more), which moves page mappings without copying bytes and keeps untouched pages untouched. Start at 256 KB (later: the entry point's recent demand × 1.25).

## What to build (the smallest version that measures honestly)

- A compiler switch `NLC_STACK_MODE=pointer|offset` (default pointer), so the same compiler builds both variants of a program.
- Offset mode for the paths the benchmarks need: large local lists and arrays (including struct lanes), Ascii and Bytes builders (append, `try_append`, `push`, concatenation streaming), copies, returns into destinations, `write` parameters, loops and scope cleanup, sort scratch. Anything else in offset mode may be a build error ("not supported in the offset spike"), as long as it never miscompiles.
- Runtime: the base in the context, a growth function using `mremap`, a guard page kept at the end after each move, growth counted and timed for the report.
- Correctness: the existing test suite passes in pointer mode; a set of fixtures (or the existing T13, T14, T15, T16, T23 fixtures that only use supported features) passes in offset mode, including growth triggered in the middle of a builder append, inside a loop, inside a callee with a `write` parameter, and with several builders open.

## What to measure (the decision data)

Release-built compiler (`cargo build --release`), programs at -O1 and -O3, best of 5, both modes, in WSL:

1. ~/bench-style program: map inserts and lookups, a function returning an 8 KB list in a loop, pool churn, a one-million-element sort.
2. A growth-heavy program: builders and lists growing from empty to tens of MB, forcing many relocations; and the same with the stack pre-sized so no relocation happens (to separate addressing cost from move cost).
3. A tight inner loop over a large local list (sum, and an indexed update), to show the per-access cost of `base + offset` and any lost LLVM optimisation (check the IR: is the base kept in a register, are loads hoisted?).
4. The self-hosted lexer (selfhost/) if offset mode can compile it; if not, say exactly which features block it.
5. Peak RSS and reserved address space for each.

## Report

docs/tasks/X1-report.md in the spike worktree: the measurements (a table per benchmark, pointer vs offset), the IR findings, what full adoption would have to change (every emitter path and runtime interface, estimated size), new language rules it needs (no pointers across growth points, pinning), risks, and a recommendation.
