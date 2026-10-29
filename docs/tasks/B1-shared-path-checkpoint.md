# Shared compiler path performance checkpoint

Date: 2026-10-29. Source commit `a8dd0c9` passes stage identity, full corpus comparison, and the required staged-tree suite. It does not meet the full 1.1× speed target.

## What changed

The self-hosted compiler avoids gathering an indexed aggregate row when the expression immediately projects one of its fields. The checker and region planner limit work to relevant scopes and block subtrees. Region temporary scopes are classified once per function body and then assigned to their smallest enclosing block using the existing cache, replacing a full body scan for each temporary node. Identifier interning initializes only the active power-of-two prefix needed by the package and uses masked probing, while retaining its declared maximum capacity. Ascii, Bytes, and core literal emission count decoded bytes directly without first building a large temporary byte collection; ordinary Text still decodes to count Unicode codepoints.

These are shared compiler paths for different input packages. They preserve source syntax, data-stack lifetimes, and bulk reclamation. Field projection removes an unused temporary reservation and copy. No copy or snapshot rule changed. The data stack remains the core memory idiom. Pointer-versus-index addressing remains an implementation choice under measurement; this checkpoint does not decide it.

The region cache relies on function and test body subtrees being disjoint top-level ranges and on each body's root Block being non-temporary. Scope assignment preserves the existing smallest-subtree selection and block traversal order. The new assignment work is linear in a body plus the sum of block-subtree sizes; extreme nested blocks can still make that part quadratic.

## Correctness evidence

The final O3 Stage2-to-Stage3 chain passed. Stage2 and Stage3 emitted identical LLVM IR (SHA-256 `5cbd391413a5ea484a3dc511dd86593e2cec565d583a748c040e720e81cbbdb7`) and identical executables (SHA-256 `92087dee4aefc520a5b2d9dcd7aed5505b7ad289bc8ef86f63caf89e9847c1ce`). The chain source fingerprint is `c80fc250a2fe1e5347e61c7d0c0e4624afa3e313353d023a82e36e2e8e6b6c70` (`.selfhost-stage-chain-9m83m4b2/report.json`).

The pre-fix compiler also compiled the updated self-host source to LLVM byte-for-byte identical with final Stage2. Both hashes are `5cbd391413a5ea484a3dc511dd86593e2cec565d583a748c040e720e81cbbdb7`; the output is `target/b1-shared-optimization-validation/prior-scope-fix.ll`, produced by `.selfhost-stage-chain-qy27oxtp/stage3`.

The direct scalar-field projection fixture passes at O1 and O3. The quiet enum scaling check on the Stage0-built seed passes at 1,600 / 3,200 / 6,400 enums in 0.116 / 0.260 / 0.827 seconds. The final C bootstrap goldens also passed at O1 and O3 (eight runs).

The final Stage3 corpus passes at O1 and O3: 793 registered plus 256 seeded cases, with zero mismatches. The required staged-tree command, `NLC_FRONTEND=selfhost cargo test --offline --release -q --test '*'`, passes in 779 seconds with `NLC_LONG_TESTS=1`, `NLC_E1_GENERATED_COUNT=64`, `NLC_TEST_JOBS=4`, and `RUST_TEST_THREADS=1`. Serial Rust test cases retain the cold-cache test's internal concurrent builds. Logs and zero exit markers are under `target/b1-shared-final-validation/`.

The initial staged run failed the enum-scaling guard; an isolated rerun reproduced it at 1.101 seconds for 6,400 enums. Profiling led to the region-scope scan change above. No guard or threshold was relaxed. The corrected source passed both the isolated guard and the full suite.

The final indexed-field fixture also passes with the C runtime at O1 and O3 under `NLC_STACK_VERIFY=1 NLC_STACK_STATS=1`. Both runs match the expected output and record one arena growth and one relocation (peak 512,968 bytes, reserved 524,288 bytes). Probe files are `target/b1-shared-final-validation/projection-O{1,3}.*`.

## Performance result

The fixed matrix used one warm-up and three measured IR-generation runs per frontend and case, alternating execution order on CPU 0. Rust Stage0 ran in pointer mode; Stage3 ran in offset mode. Both compiled identical inputs to LLVM with the C runtime. Timed runs used the same timeout and GNU-time wrapper; primary wall duration comes from `time.monotonic()` rounded to 1 ms. The wrapper and rounding contribute materially to short-case measurements, so the results are checkpoint evidence rather than fine-grained compiler-only timings. The raw 99,566-byte report is copied verbatim to [B1-shared-path-matrix.json](B1-shared-path-matrix.json), SHA-256 `1363c758b1b2e17c14261dc6f528d9786cab83a9c0157dcb4649c48556954dc2`.

| Input | Rust Stage0 median | Stage3 median | Stage3 / Stage0 | Goal (≤ 1.1×) |
| --- | ---: | ---: | ---: | --- |
| Self-host compiler | 1.875 s | 1.321 s | 0.704533× | Pass |
| Generated 128 functions | 0.046 s | 0.040 s | 0.869565× | Pass |
| Generated 2,048 functions | 0.210 s | 0.271 s | 1.290476× | Fail |

The matrix **fails overall**: the large generated case remains about 29% slower than Rust Stage0. Do not average it against the faster self-host case.

Measured peak RSS medians were 269,500 KiB Rust vs 187,264 KiB Stage3 for self-host; 8,148 vs 22,352 KiB for 128 functions; and 60,408 vs 44,176 KiB for 2,048 functions. These process measurements do not describe static arena reservations on their own. The frontends' stack modes also differ, so they do not isolate the effect of arena representation.

Cold-start behavior, end-to-end compile/link time, and a broader range of real packages remain to be measured. See the next investigation below for the measured large-input lead.

## Next investigation

Sparse GDB samples compiling the 2,048-function input repeatedly stopped in
`clear_function_regions` and `is_top_level_function`. These samples identify
recurring paths; they are not CPU percentages. Profile evidence is in
`target/b1-large-package-profile/`.

Two small changes are now the next candidates. They are **not implemented**:

1. **Clear only the current function or test's `expected` entries.** The table
   is initialized to `-1` in `add_compiler_links`, and every indexed read or
   write is in region-offset handling; the checker does not read it. Region
   slots are attached to temporary nodes in the body or eligible local binding
   nodes in the body. Parameters and views are excluded, and generated default
   helpers are not region-planned. Function and test body subtrees are
   disjoint. This supports clearing the current body subtree while retaining
   the resets of the global current-size and maximum-size scalars. Keep the
   table's `-1` empty-slot behavior and verify slot lifetimes before landing.
2. **Remove `is_top_level_function` from the `NodeKind.Function` support
   check.** `parse_function_decl` is called only by the root `parse_file` item
   loop and is the only parser routine that constructs `NodeKind.Function`.
   Nested function declarations are not a statement form; anonymous function
   expressions are rejected, and function types have distinct node kinds.
   The checker calls this helper only from the `NodeKind.Function` eligibility
   arm. The generic-function rejection `value.aux > 0L` remains required.

Both changes add no tables or metadata. Re-run exact IR and the fixed matrix
after implementing them. Defer the broader per-function binding-range searches
(`plan_function_regions`, `populate_frame_slot_bytes`, local alloca emission,
`binding_for_node`, and `region_node_has_binding`) until these simpler candidates
are measured; do not combine them all into one change.
