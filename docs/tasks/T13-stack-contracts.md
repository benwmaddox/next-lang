# T13: the data stack, regions and destination-directed emission (milestone M3, part 1)

Depends on M2 (T06 to T12). Same rules (docs/PLAN.md; T01's Architecture). Rewritten for Ben's stack decision ("One data stack, reserve ahead", DESIGN.md "The job's data stack" and "How the compiler places values"), folding in docs/reviews/sol-T13-T14-r1.md, sol-M3-r2.md and sol-fewstacks-r1.md.

This task changes how code is generated so that later tasks can put growing values on the data stack. It adds **no new syntax** beyond lifting T06's 64 KB local limit: the whole existing suite must keep passing.

## Destination-directed emission

Today `emit_expr` returns one computed value; locals use entry-block allocas, calls return aggregates by value, and branches merge with `phi`. Change it so an expression can **build into storage it's given**: a destination (an address in a region). Carry destinations through calls, `if`, `match`, returns, struct and enum construction, and `Option`/`Result` payloads. Results larger than a few registers are returned into a caller-provided destination, never by value.

## The data stack and regions

- **One data stack per job** (per program run and per test child here): a writable reserved range (64 MB in this task; per-entry-point sizing is T17) whose pages are committed as they're touched, with an inaccessible guard page at its end. Growth is checked against the limit explicitly (one compare); passing it calls `nl_fail` with `data stack exhausted`. A failed reservation at startup is a clear startup failure.
- **Regions:** a value placed on the data stack gets a region (a byte range), freed last in, first out with its scope. Fixed-size values over 4 KB (large local collections, temporaries for construction, printing, equality, payload extraction, sort scratch, large parameters and results) live in regions and are passed by address; under 4 KB they stay where they are now. T06's 64 KB build error goes away. Alignment and simultaneous caller and callee placements count.
- Large temporaries that would sit above a still-growing value go on the native stack instead only if T14+ needs it; in this task no growing values exist yet.

## Stack contracts and the hidden arguments

- Extend T01's single `lower_signature` into complete argument and result-passing rules, used by definitions, ordinary calls, `?.` calls, calls through function values (T11) and the entry wrappers. Every function takes a hidden **context pointer** (the job's stack base, top and limit) and, where it needs them, the current **top** to place above and a **destination** for its result.
- The **stack contract** per function: its **byte requirement** (the most bytes it and its callees can place above where it's called), and for a result, where it's built. Function types (T11) carry the largest requirement of any function that fits them.
- **Tops in registers** (Goose's top caching): loaded at entry, written back before a call that can place on the stack and at exits, reloaded after such a call. A loop that places nothing new does no stack-table traffic per iteration: check the IR.
- `nlc inspect contracts <package>` prints each function's byte requirement, parameter modes and result placement.

## Scopes and cleanup

Every scope records the top it saved; **every exit restores it**: falling off the end, a tail expression, `return`, `break`, `continue`, `?`, a failed `expect`. Fill in T02's cleanup hooks with real restores. Results are copied out (or built in the caller's destination) before a scope's space is reset; caller-owned output is never reset.

## Test-only reservation override

The reservation can be shrunk by an environment variable the runtime reads only when built with `NLC_TEST_BUILD`, which the driver already passes for `nlc test` (compiler/src/driver.rs). The driver always compiles the same runtime.

## Acceptance cases

- The whole existing suite passes unchanged.
- A 1 MB local list; a large nested collection copied and returned and still valid after its source scope ends; an outer list surviving iteration cleanup; a sort of a 100,000-element list (T12) with its scratch in a region.
- IR checks: a function with the hidden context and top; a large result returned through a destination; a loop with no stack-table traffic per iteration.
- A test-only shrunken reservation exhausted by a legal bounded workload whose real peak exceeds it (`data stack exhausted`), and the same workload passing at the normal size.
- `inspect contracts` output for a few functions.

## Report

docs/tasks/T13-report.md, including `inspect contracts` output.
