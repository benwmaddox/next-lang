# E3a3: performance parity with stage 0

## Changes

- `selfhost/regions.nl` emits TBAA metadata with sibling `context base` and
  `program storage` types under a private root. The load in
  `nl_context_current_base` gets the context tag; typed user-language scalar,
  compound, and collection stores get the program tag, including stores in
  callees that receive `write` parameters. Raw `sys` operations and core-mode
  context stores remain untagged. This uses Sol's alias-information approach;
  it does not cache a base pointer across calls or growth points.
- The region planner excludes array/list receivers for indexing and method
  calls only when the emitted access can borrow the receiver without a read
  snapshot. Effectful index evaluation and effectful method arguments retain
  their planned storage.
- Empty scopes emit no top bookkeeping. Scope exits restore the compiler's
  current-top slot without publishing to the context; scope entry publishes
  the context top only on the growth path. Functions with no planned regions
  skip return-time top publication. Existing peak notes remain at allocation
  points, and growth, failure, output, and flush paths retain their required
  synchronization.
- `compiler/tests/selfhost_performance_ir.rs` builds the four benchmark
  modules with the working-tree selfhost compiler and inspects their
  optimized LLVM IR.

## Benchmarks

Baseline is the pre-change `scripts/bench-vs-rust.sh --selfhost --time` run,
which builds selfhost from committed HEAD. The after run used a selfhost
compiler built from the working tree with
`NLC_OPT_LEVEL=3 target/release/nlc --frontend=rust build selfhost`, then
built each pair with `--runtime=core` and linked it with stage 0 at O3. Both
comparisons used CPU 8, the exclusive `/home/ben/linuxbench/bench.lock`, and
best-of-five timings. Build and output checks matched the benchmark script;
stage-0 outputs also matched Rust, and each supported selfhost output matched
stage 0. Times are seconds, rounded to 0.01.

| Pair | Stage 0 before | Selfhost before | Stage 0 after | Selfhost after |
| --- | ---: | ---: | ---: | ---: |
| calls | 0.91 | 0.71 | 0.91 | 0.22 |
| increment_heavy | 0.73 | 1.80 | 0.68 | 0.68 |
| struct_update | 0.80 | 1.89 | 0.84 | 0.83 |
| tight_list | 0.53 | 0.65 | 0.53 | 0.53 |
| struct_math | 0.33 | 0.34 | 0.33 | 0.33 |
| collatz | 0.57 | — | 0.58 | — |
| nested_lists | 0.85 | — | 0.85 | — |
| request_scratch | 1.04 | — | 1.02 | — |
| search_heavy | 0.51 | — | 0.51 | — |
| text_format | 0.88 | — | 0.92 | — |
| tokenize | 0.79 | — | 0.80 | — |

The after `struct_update` result is from a separate locked best-of-five
confirmation after the full benchmark batch had measured 0.80s for stage 0
and 0.83s for selfhost. An additional 15-run diagnostic batch had both at
0.82s. The generated inner loop has the same checked scalar operations as
stage 0; this pair is close to the timer's observed run-to-run variation.

## IR regression markers

The regression test copies each benchmark's `main.nl` into a temporary
package, compiles it with the working-tree selfhost compiler, and runs
`clang -O3 -S -emit-llvm`. It identifies natural loops containing the
`%coll.index.` bounds-check marker. In every such loop it rejects
`%nl.scope.end.` and calls to `nl_context_reservation_bytes` or
`nl_stack_grow`, and rejects any TBAA-tagged context-base pointer load. The
last check is stricter than only checking between stores: no base reload may
remain anywhere in the indexed hot loop. It also checks the raw IR's TBAA
hierarchy, verifies the one context-base load is tagged, verifies typed stores
are tagged, and verifies raw `sys` stores are not.

## Relocation and stack accounting

The directed `a2_relocation_*` fixtures passed with threshold zero and forced
stack movement. This includes `a2_relocation_write_element`, where a growing
callee is reached through a `write` argument and a later argument grows the
stack. The final `NLC_LONG_TESTS=1` selfhost suite passed, including its O1/O3
comparison and relocation runs.

For the three directed fixtures, `NLC_STACK_STATS=1` and
`NLC_STACK_VERIFY=1` reported:

| Fixture | HEAD peak | E3a3 peak | Growths/relocations, both | Output |
| --- | ---: | ---: | ---: | --- |
| `a2_relocation_embedded` | 628888 | 628872 | 2 / 2 | `[9]` |
| `a2_relocation_native_embedded` | 600160 | 600144 | 1 / 1 | `[9]` |
| `a2_relocation_write_element` | 600184 | 600112 | 1 / 1 | `[7, 9]`, `9`, `[7, 7]` |

The lower peaks come from excluding receiver copies whose emitted access
borrows the original collection place; the emitter does not use those slots.
Output, growth counts, relocation counts, and verifier results are unchanged.

## Differences from Sol's experiment and remaining work

The receiver patch here keeps Sol's index-receiver exclusion but guards it
with the effect/snapshot conditions required by the evaluation-order rules.
The alias fix is generalized to typed user stores throughout collections,
assignments, and `write` callees instead of the selected benchmark stores in
the IR patches. Context metadata is attached only to the named base load; no
descriptor anchor receives `nonnull` or `dereferenceable`. Scope-exit
publication is removed when the top stays local, while growth and functions
with planned regions still synchronize it. No proven bounds or overflow
checks were removed, and no vectorization was added.

P1 should handle range-proven bounds/overflow elimination and the resulting
vectorization, with the differential arithmetic and failure-order checks
specified there. The performance IR test deliberately confirms that the
existing checks remain in the optimized loops.
