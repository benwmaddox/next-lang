# T13: stack contracts and destination-directed emission (milestone M3, part 1)

Depends on M2 (T06 to T12). Same rules. Restructured after docs/reviews/sol-T13-T14-r1.md, whose points are binding. Read DESIGN.md "Stacks" (in Memory), "N stacks per job", "How the compiler assigns stacks", "Keeping it fast".

This task changes how code is generated so that later tasks can put growing values on data stacks. It adds **no new language feature** beyond lifting T06's 64 KB local limit: everything existing must keep working, and the change is visible in the IR and in the new tests.

## Destination-directed emission

Today `emit_expr` returns one computed value; locals use entry-block allocas, calls return aggregates by value, and branches merge with `phi`. Change it so an expression can **build into storage it's given**: a destination (an address, and for later tasks a data stack and offset). Carry destinations through calls, `if`, `match`, returns, struct and enum construction, and `Option`/`Result` payloads. Results larger than a few registers are returned into a caller-provided destination, never by value.

## Stack contracts, the context pointer and the runtime

- Extend T01's single `lower_signature` into complete argument and result-passing rules, used by definitions, ordinary calls, `?.` calls, calls through function values (T11) and the entry wrappers (`main`, test entries). Every function takes a hidden **context pointer** to its job's stack table (bases, tops, limits) and, where its contract needs them, a hidden **base** (first stack index of its window) and **destination**.
- The **stack contract** per function, computed from its body and callees: window size `k`; per parameter, its mode; for a result, where it's built. A callee's window goes **above every stack the caller has reserved at that call**, including its destination (DESIGN.md's "first free stack" made precise: never into a hole below a live caller value). N for an entry point is the highest stack index reachable plus one, fixed scratch included. Function types (T11) carry the maximum window of every function that fits them.
- The runtime gets a job stack table: N data stacks, each a reserved address range (64 MB in this task; `mmap` with `PROT_NONE` then committing on first touch, or a guard page at the end), plus one **fixed scratch** stack. A failed reservation at startup is a clear startup failure. A test-only environment variable (read only when the runtime is built for `cargo test`) can shrink the reservation; the driver always compiles one runtime.
- **Stack tops live in registers** within a function (Goose's top caching): loaded at entry, written back before a call that can reach that stack and at exits, reloaded after such a call. A loop that pushes does no stack-table traffic per iteration: check the IR.

## Scopes and cleanup

- Every scope records the tops it saves and the stacks it owns; **every exit restores them**: falling off the end, a tail expression, `return`, `break`, `continue`, `?`, a failed `expect`. Fill in T02's cleanup hooks (now comments) with real restores. Results are copied out before scratch is reset; caller-owned output is never reset.

## Fixed scratch for large values

- Fixed-size values over 4 KB (local collections, temporaries for construction, printing, equality, payload extraction, sorting scratch, large parameters and results) live on the fixed-scratch stack, passed by address, with nested saved tops. T06's 64 KB build error goes away. Alignment and simultaneous caller and callee allocations count.

## Acceptance cases

- The whole existing suite passes unchanged.
- A 1 MB local list; a large nested collection copied and returned and still valid after its source scope ends; an outer list surviving iteration cleanup; a sort of a 100,000-element list (T12) using fixed scratch.
- IR checks: a function with a hidden context pointer and base; a callee whose window sits above a caller's reserved stacks with a gap below; a loop with no stack-table loads or stores per iteration; a large result returned through a destination.
- A test-only shrunken reservation exhausted by a legal bounded workload whose real peak exceeds it (`data stack exhausted` through `nl_fail`), and the same workload passing at the normal size.
- A debug dump (`nlc inspect contracts <package>`) printing each function's window, parameter modes and result placement.

## Report

docs/tasks/T13-report.md, including `inspect contracts` output for a few functions.
