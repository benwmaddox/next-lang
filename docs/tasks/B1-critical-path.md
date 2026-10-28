# Self-hosting critical path

Priority: Ben, 2026-10-28 â€” get the compiler self-hosting, benchmark the self-built
compiler, then improve it from measurements. Existing correctness and performance
checks remain guards throughout. New benchmark ports and unrelated features wait.
This queue refines the historical phase order in PLAN.md using actual compiler
source requirements; it does not claim language parity is already reached.

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

## Scalar constants: final staged validation

The scalar-constant implementation evaluates the current source's 212 explicit
long declarations. The direct own-source probe now exits 2 without IR at
`collections.nl:18:12`, reporting `text in collections`. The parameter is
`files: list<SourceFile, MAX_SOURCE_FILES>`, whose element has a bounded Bytes
name. The [scalar report](B1-scalar-constants-report.md) records focused tests,
the immediate-operand regression fixes, and final acceptance when available.
The compiler does not yet self-host.

## Dependency queue

Static census of `selfhost/` at `ed7e867` (excluding generated embedded-core byte
strings) found 207 constants, 200 grow-Bytes annotations, and 72 recursive
functions. These counts are a baseline, not a permanent target; refresh them and
run the direct self-build probe after each prerequisite lands.
The current scalar-constant source has 212 constants, 200 grow-Bytes annotations,
and 75 recursive declarations.

1. **Source-used scalar constants (implemented; final staged validation).**
   The original 207 declarations were all `long`: 194 literals, nine references,
   and four arithmetic expressions. Four fact flags and one layout-overflow
   state constant bring the current count to 212. The bounded
   [scalar task](B1-scalar-constants.md) keeps strings,
   aggregates, calls, other scalar kinds, and future expression forms gated.
2. **Source-used Bytes fields in collections.** This is the next demonstrated
   gate, ahead of builders: `SourceFile.name: Bytes max 4096` resides in
   `list<SourceFile, ...>`. Implement the bounded
   [Bytes-field task](B1-bytes-fields.md), preserving layout, independent live
   bytes, indexed field stride, whole-element gather, and relocation. Broad
   nesting, Ascii/Text lanes, sums, and reachability optimization stay deferred.
3. **E3d1 builder prerequisites.** `ir_push_byte` writes through `grow Bytes`,
   and the compiler uses checked appends. Implement grow descriptors, byte pushes,
   append transactions, width checks, and the required proof/rollback rules.
   Use [prep-E3d1.md](prep-E3d1.md), especially its manager answers: equal maxima
   only; keep `+=` through grow refused with the `try_append(x)?` hint; rollback
   covers one append. Recount existing fixture classifications because E3c
   already promoted four rows from the old prep table.
4. **E3f1 capability/I/O requirements used by the compiler.** `Env`, arguments,
   `Out.write`, and Fs listing/join/read/write support are required. The package
   grants fs/out/env. Deterministic source ordering from `list_with_extension`
   is part of the compiler's reproducibility contract. Stdin, atomic writes, and
   streaming writers need not precede B1 unless an actual source dependency appears.
5. **E4s recursion and native-stack budget.** Support the source's recursive
   parser/checker helpers with bounded failure behavior and measured call cost.
   The older count of 65 and five sort calls is stale: the baseline found 72
   recursive declarations and zero direct sort/sort_by calls; scalar constant
   evaluation and its capacity dependency walk bring recursion to 75 declarations.
6. **B1 stage chain and reproducibility.** Use Stage0 to build the seed compiler;
   use that compiler to emit stage 2, then stage 2 to emit stage 3. Require exact
   stage-2/stage-3 LLVM IR and binary identity, plus compiler corpus correctness.
   LLVM/clang remains the backend. The bootstrap harness may invoke clang
   directly; after the seed build, do not depend on Rust nlc's checker, emitter,
   or link-ir driver to claim the full B1 gate. A Rust link-ir bridge may help
   diagnose progress but must be labeled as a bridge. E3g's in-language process
   driver is a separate product milestone if the harness can already link with
   clang directly. A required linker/core runtime gap re-enters this queue as a
   demonstrated blocker, rather than being assumed solved.
7. **Benchmark the self-built compiler.** Pin toolchain, flags, source revision,
   and corpus; verify outputs before timing. Measure IR generation and end-to-end
   builds separately, cold and warm runs, peak RSS, data/native-stack measures,
   and output sizes. Include the compiler compiling its own source, small/large
   generated packages, and representative real packages. Preserve raw samples,
   best/median/spread, and exact commands; distinguish static reservations from
   resident memory. Keep runtime benchmarks as separate regression evidence.
8. **Improve measured bottlenecks.** Prioritize checker/emitter scaling, bootstrap
   memory, generated IR size, LLVM/link time, or runtime costs according to the
   profile. Each optimization needs correctness coverage and before/after data.

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
