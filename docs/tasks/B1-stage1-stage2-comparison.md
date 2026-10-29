# Stage1 vs Stage2 emitted code comparison

## Scope and provenance

Read-only comparison of the actual Stage1 IR emitted by Rust Stage0 and Stage2 IR emitted by the Stage1 seed, for the same frozen NL source/package. This is not Stage2-vs-Stage3 (those artifacts are identical). Comparison scripts, extracts, and the Stage1 link are under ignored `target/b1-stage1-stage2-comparison/`; source artifacts remain at the paths listed below.

| Artifact | Source path | Bytes / SHA-256 |
|---|---|---|
| Stage1 LLVM IR | `target/b1-stage3-timing/pilot-selfhost-gsuo952z/ir/rust-pointer-c.ll` | 21,901,677 / `ddde0162f90af276b298dd2a6252296360ca4407cf2fc273d1f50345bc788cc7` |
| Stage2 LLVM IR | `.selfhost-stage-chain-9qs1db0k/stage2.ll` | 108,556,133 / `6d77f5573e33376026a3f6886371f76a88c151bddb367664b6487522732748d9` |
| Frozen package / source fingerprint | package / chain metadata | `4d0ef0b5336540f9375bd8cd157e5316ff9baf29cd4ca7b2bd96a3bef4f4e37b` / `f5ac405ca8b3c3dba6ec83ca647c65d46a3fbe0776d8c80c3700d33849fec692` |
| Stage1 O3 binary | `target/b1-stage1-stage2-comparison/stage1-pointer` | 2,167,688 / `5e19a7c8b9b8aedf82cc02157ee1e3cdbbf84d46a9481cbdbce6f9daadedc35c` |
| Stage2 O3 binary | `.selfhost-stage-chain-9qs1db0k/stage2` | 2,598,904 / `e34e8ebcaee8fb37f151b7f6c08510dedefaea87e7e94b7861780f7d3233ac03` |

Both were linked with the installed WSL clang 18.1.3 and `-O3` plus `runtime/nl_runtime.c`; Stage1 was built from the pointer-mode Rust IR, while Stage2 used `-DNLC_STACK_MODE_OFFSET=1`. Thus the real comparison has an unavoidable pointer-vs-offset representation difference; it isolates the actual pipeline artifacts but is not a representation-matched benchmark. Build invocations: `clang -O3 target/b1-stage3-timing/pilot-selfhost-gsuo952z/ir/rust-pointer-c.ll runtime/nl_runtime.c -o target/b1-stage1-stage2-comparison/stage1-pointer`; `clang -O3 -DNLC_STACK_MODE_OFFSET=1 .selfhost-stage-chain-9qs1db0k/stage2.ll runtime/nl_runtime.c -o .selfhost-stage-chain-9qs1db0k/stage2`.

## Whole-artifact and hot-function evidence

| Measure | Stage1 | Stage2 |
|---|---:|---:|
| Raw IR lines / bytes | 477,901 / 21.9 MB | 1,427,457 / 108.6 MB |
| Stage2 / Stage1 raw IR bytes | — | 4.96× |
| `nl_fn_N` definitions | 797 (includes 11 generated `_append` variants) | 786 |
| Linked ELF file | 2,167,688 B | 2,598,904 B (+19.9%) |
| Linked ELF `.text` | 1,776,985 B | 2,264,505 B (+27.4%) |
| Linked ELF `.rodata` / `.bss` | 213,321 B / 5,374,032 B | 213,049 B / 5,374,032 B |

Function IDs are mapped using Stage1's `; function NAME` comment and then checked against same source-order ID and compatible signature in Stage2. These are raw IR instruction counts and linked O3 symbol sizes, not timing measurements.

| Function (ID) | Raw IR instructions Stage1 → Stage2 | O3 function bytes Stage1 → Stage2 |
|---|---:|---:|
| `ir_push_byte` (343) | 48 → 645 | 61 → 159 |
| `ir_write_ascii` (344) | 144 → 394 | 568 → 1,688 |
| `ir_write_bytes` (345) | 75 → 300 | 255 → 848 |
| `ir_write_number` (346) | 49 → 15 | 219 → 129 |
| `token_name_hash` (118) | 113 → 306 | 322 → 901 |

`find_binding_in_scope` (258) is an example where huge raw expansion mostly folds away: 116 → 3,049 IR instructions, but 250 → 288 O3 bytes.

## Findings and recommendation

1. **Recommend a small compiler optimization for direct scalar projection through indexed collections.** In `token_name_hash`, Stage1 gets `files[file_index].base` with a direct 8-byte scalar field load. Stage2 first materializes/gathers the full `SourceFile` aggregate using `@nl.copy.116`, including the active filename bytes and all seven scalar lanes, then reads `.base`. The 4,160-byte figure in Stage2 is region capacity reserved for that aggregate, not measured bytes copied. This gather is not inherent to the offset ABI: preserve the field projection through indexing so only the requested column/field is loaded, without aggregate scratch/copy. This is concrete, bounded, and needs no language feature.
2. **Do not treat all added offset-mode work as an optimizer bug.** In `ir_push_byte`, a context-base reload after stack growth is required because growth may relocate arena storage. The inspected assembly has a base lookup for the fast path and another lookup on the grow path; retain that relocation-safe reload. Other offset anchors/descriptors also account for expected code size.
3. **Secondary opportunity: append streaming specializations.** Stage1 emits 11 `_append` variants with 39 observed callsites (e.g. `ir_write_ascii`); Stage2 emits none. Stage1 can stream ASCII values into the destination buffer rather than build intermediate strings. Worth a narrow follow-up measurement, but avoid porting the full builder machinery without evidence.
4. **Internal linkage is only a candidate, not yet a recommendation.** Both outputs expose `nl_fn_N` definitions as externally visible even though ordinary calls are in-module. Internalizing private functions could enable IPO/constant propagation of Stage2 descriptor arguments. First audit function-address escapes/exports and the native stack-frame map: `native_stack_requirement` currently treats a missing `nl_fn_N` frame entry as `u64::MAX`. IR parsers/tests also expect `define ... @nl_fn_` (including `scripts/bench-e3c-text.py`, `scripts/run-selfhost-copy-bench.py`, and `compiler/tests/pools_ir.rs`).

**Decision:** prioritize direct scalar field projection, which avoids the whole-aggregate gather regardless of arena encoding; preserve relocation-aware arena-base reloads. Pointer-vs-offset describes these artifacts and is not a permanent backend requirement. Their whole-size comparison is not an apples-to-apples performance result. No timing benchmark was run for this comparison.

## Validation context

Validation completed: the full staged suite passed in 754s. The actual corpus (792 + 256 cases) had zero mismatches across O1/O3; O1 chain `0ndaets7` and O3 chain `9qs1db0k` both passed (see `target/b1-current-validation/stdout.log`). Two C getter forced-relocation fixtures pass at O1/O3 with exact expected output and arena-growth counts of 1 and 3. No timing benchmark was run for this code comparison.
