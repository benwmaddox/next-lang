# Self-hosting critical path

Priority: Ben, 2026-10-28 â€” get the compiler self-hosting, benchmark the self-built
compiler, then improve it from measurements. Existing correctness and performance
checks remain guards throughout. New benchmark ports and unrelated features wait.
This queue refines the historical phase order in PLAN.md using actual compiler
source requirements; it does not claim language parity is already reached.

## Current checkpoint (2026-10-29)

The indexed sum-parameter geometry fix is on commit `5067d85`. Its required
staged suite passed in 758 seconds, and the actual Stage3 corpus passed at O1/O3
with 792 registered and 256 seeded cases and zero mismatches. Stage2/Stage3
chains and eight C-runtime golden runs passed at O1/O3. The 25.4-second O3
self-source emission is a chain measurement, not a matched-input Rust
comparison; the 3x performance gate remains open. The compile-error scope
question remains open separately; no snapshot policy or enforcement changed.
See the [sum-parameter geometry report](B1-sum-parameter-geometry.md).

Memory baseline clarified by Ben, 2026-10-28: a reusable job instance may have
optional StasisLang-style static storage that persists across its runs. Most
work uses per-run stack arenas that may move/grow and are reclaimed in bulk.
The current core-managed data stack starts at 256 KiB and grows/moves with
overflow and OS-failure guards; it has no configurable hard arena cap. Existing
collection capacities and test limits are not an arena cap. Cap implementation
is deferred and is not a B1 prerequisite.
Main configures job counts, triggers, and mailboxes within its startup CPU/RAM
grant, which may be a subset of the host. Each job instance runs serially;
mailbox-full is an explicit send status. See the
[Revision 1 discussion draft](../design/memory-revision-1.md).
The confirmed future policy is a typed job-level `MemoryLimit` if a hard cap is
implemented: the current run ends, completed persistent-state writes stay, and
the run arena is cleared. There is no per-allocation memory `Result`, retry, or
resume. No configurable hard-cap checks or typed exception dispatch exist in
the current runtime, which remains one job process. See
[Revision 2](../design/job-failures-revision-2.md).
Extra ownership, allocation, or lifetime machinery needs a concrete requirement
and a defense; the older task proposals are not a reason to introduce it.
Hard constraint (Ben, 2026-10-28): no GC, borrow checker, or loan/move/inferred-
ownership/lifetime analysis to legalize ordinary code; simplify, restrict, or
defer a prerequisite that seems to need one. Scope planning and arena reset are
ordinary compiler work, not checker exceptions. Review each feature through an
ordinary example, the simplest alternative, and its needed guarantee/cost, then
get user review before adding language rules. See [DESIGN.md](../DESIGN.md).
Before adding `.unwrap()` or an equivalent hidden failure path, get user review
of the concrete failure, why explicit result/status handling is insufficient,
and the simplest alternative; review existing uses as they are touched.

## Completed prerequisite: remove the name-check blocker

The direct post-E3c compiler self-build probe at `ed7e867` reports:

```text
collections.nl:214:5: error: name 'count' conflicts with package or built-in declaration 'count'; choose a different name
```

DESIGN's narrowed no-variable-shadowing rule already permits local/parameter
names to match functions, built-ins, types, and constants. Visible variables and
bare enum-case names remain protected. The implementation also has a package-wide
cubic name search documented in [the compile-time investigation](../research/selfhost-compile-time.md).
Fix the semantic mismatch and function-local traversal together, preserving
package declaration uniqueness and rejected variable-shadow cases. Rename genuine
collisions in the compiler source rather than weakening the rule. Names sharing
an unimplemented builtin or constant must advance to that feature gate; this task
does not add unrelated builtin or constant implementations.

Acceptance: supported name-sharing programs work, supported direct named calls
follow the DESIGN rule, legitimate shadowing is still rejected, repeated-name packages no
longer scale cubically, and the self-build probe advances to a specific remaining
feature gate. Passing that probe's name checks is not B1 completion. Stage0 remains
frozen; intentional DESIGN forms it rejects use reviewed expected-output fixtures.

The name-scope prerequisite is implemented and passed the full staged O1/O3
suite (734 registered plus 256 generated packages), relocation, and scaling
checks in source commit `a18eb70`. That advanced the compiler to the unsupported
constant-declarations gate at collections.nl:7. See the
[name-scope completion report](B1-name-scopes-report.md).

## Completed prerequisite: scalar constants

The scalar-constant implementation evaluated 212 explicit long declarations.
At that milestone, the direct own-source probe exited 2 without IR at
`collections.nl:18:12`, reporting `text in collections`. The parameter is
`files: list<SourceFile, MAX_SOURCE_FILES>`, whose element has a bounded Bytes
name. Source commit `8dbcce0` passed the full staged suite in 694 seconds,
including all 755 registered and 256 generated packages at O1/O3. The
[scalar report](B1-scalar-constants-report.md) records focused tests, the
immediate-operand regression fixes, and final acceptance.
At the current checkpoint, Stage3 package comparisons have not begun because
the enum scaling precheck timed out, and the own-source pilot exceeds the 3x
gate by timeout lower bound. Full corpus and small/large benchmark coverage
remain outstanding; B1 is not accepted. See the current checkpoint above.

## Completed prerequisite: Bytes fields in struct collections

At that checkpoint, the Bytes-field implementation advanced the own-source
probe to `collections.nl:107:1: generic or recursive functions`, making
source-used recursion the next demonstrated gate. The [Bytes-field
report](B1-bytes-fields-report.md) records the focused O1/O3 results,
copy/stride review, and a confirmed relocation while the populated list remains
live. Source commit `7dc2b4e` passed the full staged suite in 642 seconds,
including 762 registered and 256 generated packages at O1/O3. Recursion,
builders, and compiler C-runtime support have since reached the current
Stage2/Stage3 checkpoint.

## Dependency queue

Static census of `selfhost/` at `ed7e867` (excluding generated embedded-core byte
strings) found 207 constants, 200 grow-Bytes annotations, and 72 recursive
functions. These counts are a baseline, not a permanent target; refresh them and
run the direct self-build probe after each prerequisite lands.
The current Bytes-field source has 212 constants, 201 grow-Bytes annotations,
and 76 recursive declarations.

1. **Source-used scalar constants (complete).**
   The original 207 declarations were all `long`: 194 literals, nine references,
   and four arithmetic expressions. Four fact flags and one layout-overflow
   state constant bring the current count to 212. The bounded
   [scalar task](B1-scalar-constants.md) keeps strings,
   aggregates, calls, other scalar kinds, and future expression forms gated.
2. **Source-used Bytes fields in collections (complete).**
   `SourceFile.name: Bytes max 4096` resides in `list<SourceFile, ...>`.
   The bounded [Bytes-field task](B1-bytes-fields.md) preserves layout,
   independent live bytes, indexed stride, gather, and relocation. Broad nesting,
   Ascii/Text lanes, sum elements, and reachability optimization stay deferred.
3. **Source-used recursion (implemented checkpoint).** Ordinary explicitly
   marked recursion and arena scopes now compile through the O1/O3 Stage2/Stage3
   chain. Follow
   [B1-recursion.md](B1-recursion.md): ordinary calls and arena scopes, with OS
   process termination on native-stack exhaustion. Controlled diagnostics are
   deferred; the removed prototype's budgets and live-region ban are superseded.
   Full compiler-corpus correctness remains pending.
4. **Compiler-used builders (implemented checkpoint).** Keep the smallest working subset and
   simplify the broader proposal as needed. Follow [B1-builders.md](B1-builders.md):
   source-used builder descriptors/mutators first. Defer call-output append
   variants and unrelated semantic migrations unless the compiler needs them.
   Use the existing prep as an oracle, not as authorization
   for bundled `take`/move tracking or unrelated optimizations. Equal maxima,
   explicit capacity-result handling, relocation-safe access, and rollback of
   one failed append remain required. Full Stage3 package comparisons are
   blocked by the enum scaling timeout. The required staged-tree suite passed
   for commit `23a7e64`.
5. **E3f1 capability/I/O requirements (implemented C-runtime checkpoint).** `Env`, arguments,
   `Out.write`, and Fs listing/join/read/write support are required. The package
   grants fs/out/env. Deterministic source ordering from `list_with_extension`
   is part of the compiler's reproducibility contract. Ben chose the existing
   C runtime for the first self-hosted compiler; defer the core I/O port and
   add only the compiler lowering/adapters needed to reuse C. Stdin, atomic writes, and
   streaming writers need not precede B1 unless an actual source dependency appears.
   The Stage3 C-runtime golden and Stage2 smoke-parse checks pass at O1/O3; the
   core I/O port remains deferred.
6. **B1 stage chain (O1/O3 identity passed; corpus mismatches, own-source timing fails).** Use Stage0 to build the seed compiler;
   use that compiler to emit stage 2, then stage 2 to emit stage 3. Require exact
   stage-2/stage-3 LLVM IR and binary identity, plus compiler corpus correctness.
   LLVM/clang remains the backend and links the existing C runtime. The bootstrap harness may invoke clang
   directly; after the seed build, do not depend on Rust nlc's checker, emitter,
   or link-ir driver to claim the full B1 gate. A Rust link-ir bridge may help
   diagnose progress but must be labeled as a bridge. E3g's in-language process
   driver is a separate product milestone if the harness can already link with
   clang directly. A required linker/core runtime gap re-enters this queue as a
   demonstrated blocker, rather than being assumed solved. The Stage2/Stage3
   chain passed at O1 and O3. An earlier Stage3 corpus attempt timed out before
   package comparisons; the latest completed its scaling checks and selected
   package run with 16 mismatches. The required staged-tree suite passed for
   commit `27256a3`; see the current checkpoint and working-data report.
7. **Benchmark the self-built compiler (own-source failure observed; full benchmark pending).** Pin toolchain, flags, source revision,
   and corpus; verify outputs before timing. Measure IR generation and end-to-end
   builds separately, cold and warm runs, peak RSS, data/native-stack measures,
   and output sizes. Include the compiler compiling its own source, small/large
   generated packages, and representative real packages. Preserve raw samples,
   best/median/spread, and exact commands; distinguish static reservations from
   resident memory. Keep runtime benchmarks as separate regression evidence.
   Ben's acceptance gate (2026-10-28): more than **3x the Rust-implemented
   Stage0 `nlc` compile time is a failure**. Compare the same inputs and
   equivalent work with matching optimization/runtime/link settings. Report
   per-case ratios; do not average away a failing case or hide compiler time
   behind shared link time. The Rust-built language compiler is not this
   baseline.
   Rust Stage0 rejects this compiler source in offset mode (large
   `CompilerTables` is outside its supported slice). Use its normal supported
   pointer mode against the self-built compiler's offset mode and report that
   representation difference explicitly; it does not waive the 3x gate or
   authorize Stage0 changes. The O1/O3 chain totals (398.79/402.39 seconds) are
   pipeline diagnostics, not Rust comparisons or benchmark acceptance. The
   latest isolated own-source Stage3/Rust pilot used one sample, no warmups,
   CPU 0, O3, and C runtime. Stage3 completed IR generation at 13.4813x Rust
   Stage0 time, exceeding the per-case gate. This is not a full benchmark;
   small and large cases remain to be measured. Exact commands and raw
   measurements are in the [working-data report](B1-working-data-copies.md)
   and [pilot record](B1-working-data-pilot.json).
8. **Improve measured bottlenecks (further profiling).** Prioritize checker/emitter scaling,
   bootstrap memory, generated IR size, LLVM/link time, or runtime costs according
   to the profile. A five-sample GDB trace on an earlier source revision showed
   repeated `CompilerTables` copies on the own-source compile path; the current
   census found no whole-file call sites for the audited working-data helpers.
   Each optimization needs correctness coverage and before/after data. The
   source lookup hoists preserve emitted-program argument semantics. Further
   profiling continues; the scope of the compile-error rule remains open
   separately.

## Explicitly deferred until evidence requires them

The current compiler uses fixed-capacity collections and bounded text. There are
no source interpolation forms, unbounded declarations, direct sort/sort_by calls,
or type aliases in the census. E3d2 unbounded storage, E3d3 interpolation, E3f2
streaming writer, generic nested-list layouts, sorting, float work, and broad P1
runtime optimization therefore do not block the current source-closed B1 route.
Large buffers (including the 3,403,497,472-byte IR capacity bound) still need
actual build/memory validation; a concrete failure can make a storage prerequisite
necessary. Do not work around it by weakening the stage-chain gate.

## Validation discipline

Use focused comparison/relocation selectors during a task, a direct self-build
probe at each gate, and the required staged-tree full suite before source commits.
Stage0 behavior or reviewed expected outputs remain the oracles. Do not edit old
fixture contents to make them pass. Work in the canonical checkout on one active
task branch; preserve inherited scratch. Each prerequisite gets a completion
report and reviewable PR, merged only when its acceptance holds.
