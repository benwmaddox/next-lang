# O1: bring the offset runtime into main, and make stack allocation inline

First task of the offset addressing milestone (docs/PLAN.md; DESIGN.md "The job's data stack", "References into the data stack are offsets"). Read docs/tasks/X1-offset-stack-spike.md, X1-round2.md, X1-round3.md and the full X1 report on the branch `spike/offset-stack` (worktree /mnt/d/code/next-lang-spike, read-only for this task), docs/tasks/T29-report.md, T31-report.md and T32-report.md.

## 1. Port the spike onto current main

The spike branch was cut from main at 5f427b6; main has changed a lot since (T27 to T32 rewrote text storage, collection lanes and number output). Don't merge the branch: port its changes (`git -C /mnt/d/code/next-lang-spike diff 5f427b6 spike/offset-stack -- compiler runtime`) onto current main by hand:

- `NLC_STACK_MODE=pointer|offset` (default pointer), the offset runtime (base in the context, `mremap` growth doubling from 256 KB, guard page after each move, `NLC_STACK_PREALLOC`, `NLC_STACK_STATS`, `NLC_STACK_VERIFY` poisoning old mappings), the cached base with reloads after calls that may grow, the alias scopes between list counts and lanes.
- The working slice (large local lists and struct lists, read and `write` list parameters, list results through destinations, Ascii builders with `try_append`, `str`, `grow` parameters), re-done on top of T29's inline text storage and T31's pointer-free lanes. Everything outside the slice still fails closed in offset mode with a clear build error.
- The spike's fixtures and benchmarks (spike/offset-slice, offset-cache-call, offset-tight-list, offset-struct-list, offset-calls, offset-builder) as tests and bench/ programs; the poison-verified runs in `cargo test`.

## 2. Inline stack allocation (both modes)

`nl_stack_alloc` is an out-of-line runtime call for every data-stack allocation, with `nl_context_set_top` beside it: 11.5% plus in T32's lexer profile and about 17% in the parser's. Emit allocation inline: align the cached top, add the size, compare against the cached limit, and call an out-of-line slow path only when the region doesn't fit (in pointer mode: the existing exhaustion failure; in offset mode: grow the stack, reload base and limit). Write the top back only where T13's rules require it (before calls that may place or suspend, at exits), not per allocation. Keep T23's live-only touching, T17's accounting, T30's placement order and every exhaustion message.

## Acceptance

- The whole suite passes in pointer mode (the default), including the selfhost comparisons; the offset slice fixtures pass under `NLC_STACK_VERIFY=1` at -O1 and -O3.
- No call to `nl_stack_alloc` on the fast path in the IR of a function that allocates regions (an IR test), in both modes.
- Measurements, best of 5, interleaved before and after: scripts/bench-selfhost.sh (lexer and parser), bench/t30_locals, bench/t32_number_output, and the X1 benchmarks in pointer and offset modes; a perf profile of the selfhost parser after.
- Run large builds under `ulimit -v 8000000` and `timeout`.
- Report: docs/tasks/O1-report.md.
