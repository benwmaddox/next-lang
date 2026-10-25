# T27: explain and fix the self-hosted parser's 192 GB stack worst case

Same rules (docs/PLAN.md). From the S1a-2 review.

`nlc inspect stacks selfhost` reports a data-stack worst case of 192,745,324,820 bytes (and reserves that much address space), while the regions it lists add up to about 100 MB, the parser's tables (`ParseTables` in selfhost/parser.nl: nodes, extra, literals, nesting, scratch, frames) to about 550 MB by hand, and the process touches about 60 MB on the 54,145-line benchmark. Either the analysis overcounts (for example multiplying per-call storage through the recursive parser cycle, or counting a `write ParseTables` parameter as a copy) or the generated code really copies large values (SoA gathers, copy-downs of `ParseTables` or the token list).

1. **Attribution:** `inspect stacks` must account for its whole worst case: print the chain of calls and regions whose sum is the reported number (the critical path), with each contribution, so a reader can see where every byte comes from. Add a check that the listed contributions sum exactly to the total.
2. **Find the cause** of the 192 GB with that output and fix it: an overcount in the analysis (then the analysis is wrong and gets a regression test) or a real copy in generated code (then remove the copy, e.g. pass by pointer, and measure). If recursion multiplies a bound, T19's rule (no region alive across a recursive call) should keep the data-stack bound independent of depth; say whether that holds.
3. **Target:** the self-hosted parser's computed worst case within a small factor of its real tables (a few hundred MB at most, all of it reserve-ahead or large-table regions), every measured peak still at or below the computed bound, the selfhost comparison still passing.
4. Also look at the five 1 MiB copy-down temporaries for `buffer` in selfhost/dump.nl (lines 68, 72, 103, 128, 175): if they come from a pattern like `buffer = f(buffer)`, either the analysis or the selfhost code should avoid a copy per call.

Report: docs/tasks/T27-report.md, with before/after `inspect stacks` totals and the critical path.
