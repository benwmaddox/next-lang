# B1 prerequisite: source-used recursion and native-stack checks

Status: deferred by Ben, 2026-10-28, pending further language design.
The unmerged compiler/runtime/linker prototype and its added fixtures were
removed. Existing recursion gates remain in place. The notes below record the
previous proposal; they are not authorization to resume its implementation.

Ben's direction is to keep syntax and rules close to StasisLang and require a
specific justification for Rust-derived approaches. Resolve these questions
before selecting a replacement recursion design:

- DESIGN describes the recursion budget as additional to the nonrecursive
  requirement, while the existing C runtime caps whole-job native stack use.
- T19 derives the default from the process stack, while DESIGN gives each job
  its own mapped native stack. Choose an explicit, understandable default.
- The current rule permits a small recursive local but rejects a slightly
  larger one when storage placement creates a data-stack region. Decide whether
  this size-dependent restriction is acceptable or needs a simpler model.

Prefer ordinary caller-provided workspace where useful; do not introduce
lifetime parameters or a general ownership system without a defended need.
Use Ben's clarified memory baseline: optional StasisLang-style static storage
that persists across runs of a reusable job instance, with most work in per-run
stack arenas that may move/grow up to a cap and are reclaimed in bulk. A future
recursion proposal must fit that model before adding another memory mechanism.
The compiler's own-source probe remains blocked on recursion. Continue
independent self-hosting prerequisites without claiming B1 completion.

## Trigger and scope

After direct Bytes fields are supported, the own-source probe stops at
`collections.nl:107:1: generic or recursive functions`. The declaration is
`recursive fn evaluate_collection_capacity`, not a generic function. The current
source has 76 recursive declarations, including the parser, checker, scalar
constant evaluator, and collection walkers.

Support direct calls among concrete, explicitly recursive functions used by the
compiler. Keep generic functions, function values/indirect calls, recursive
language-level const calls, and unrelated features gated. The historical
[T19 contract](T19-recursion.md), including its binding corrections, governs
native stack safety and regions; this is a source-closed subset of that work.

## Architecture and required bridge

- Separate the recursive flag from the generic-function gate. Preserve it in
  function metadata; validate direct-call cycles so every cycle member is marked,
  and keep unmarked/default-initializer cycle errors. Make frame-path analysis
  SCC-aware instead of assuming a DAG or giving a back edge zero cost.
- Enforce no callee-created data-stack region live across a call back into its
  cycle, including hidden result destinations and temporaries. Borrowed caller
  structures through read/write/grow parameters may remain live. Audit the
  compiler's actual recursive helpers and refactor caller-owned workspace if
  needed; do not disable this rule to fit the source.
- Check actual remaining native stack before the callee frame is allocated.
  Required space includes its measured optimized frame, deepest nonrecursive
  descendants, helper/reporting and alignment costs, and the specified 64 KiB
  foreign-call margin. Respect the actual usable stack limit and manifest cap;
  `selfhost/package.toml` currently sets `recursion_budget = 7800KiB`.
- Use final clang object-code frame sizes at O1 and O3. No guessed frame costs.
  Inspect existing `check_call_cycles`, `compute_frame_slot_paths`, the Stage0
  two-pass `.stack_sizes` protocol, and runtime check before editing.

Frozen Stage0 `link-ir` rejects recursion target metadata. The comparison and
relocation harnesses currently use that linker, so recursion fixtures need an
external measured-frame patch/link path that invokes clang directly. It must
validate metadata, measure the final optimized object, patch guarded call sizes,
and link with equivalent options. Keep ordinary nonrecursive validation intact.
This also prepares the stage-chain harness without requiring the product's
future in-language process driver.

`nl_recursion_check` exists in the C runtime, but the current core path lacks an
equivalent emitted check. Supply and verify the core/native-limit implementation
and context setup too; patching an integer placeholder alone is insufficient.
Audit context offsets, versions, fixtures, and deterministic oracles if the ABI
changes. Do not modify frozen Stage0 or rely on Rust checking/emission/linking
after the bootstrap seed to claim B1.

## Acceptance and validation

- Direct and mutual recursion execute correctly; unmarked cycles receive real
  diagnostics naming the functions. Generic and indirect forms remain gated.
- A caller-owned borrowed structure survives recursion. Per-level large local
  regions, mutual-cycle live regions, hidden result slots, and temporary copies
  are rejected according to T19 rather than exceeding data-stack admission.
- Deep and lowered-budget recursion fail with `recursion budget exhausted` at
  the call's location, correct run/test failure status, and no segfault. Cover
  large optimized frames and foreign/helper headroom at O1/O3.
- Preserve raw measured-frame evidence and patched metadata for deterministic
  tests. Validate the core checker and budget cap independently of the C runtime.
- Fresh own-source probe advances to the next specific gate; no stage-chain or
  self-hosting claim until stages 2/3 and corpus correctness pass.
- Run exact failing commands, focused O1/O3 comparison/relocation with the new
  measured linker, related ABI/budget checks, formatting/diff checks, and the
  installed full staged suite. Keep old fixtures/oracles intact; add new ones.

Implementation remains Luna/max. Sol resolves architecture, debugging, review,
and evidence before PR/merge. Compiler benchmarking follows the B1 stage chain.
