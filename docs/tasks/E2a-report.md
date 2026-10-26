# E2a report: self-hosted structs

## Result

The self-hosted compiler now handles non-generic struct layouts, literals and declaration-scope defaults, field shorthand, nested field reads and writes, compound field assignment, structs passed as read parameters, and structs returned through fresh hidden destinations. Aggregate values use byte-array slots and one addressing helper with constant byte offsets. Bool storage uses one byte; empty structs have alignment 1; unit remains erased.

Aggregate copies, equality and printing use shared per-type helpers. Default expressions and fill helpers are shared as well. Aggregate operands and call arguments preserve their value at the evaluation point. The default dependency and call graphs include synthetic helpers, and the native slot budget checks build entries and test entries before emission. `compiler/src` remains unchanged; the only `compiler/` edit is the stack-contract test updated for E2's larger compiler tables.

Struct sizing is iterative and memoized with unvisited/in-progress/done states. Cycles and unresolved types propagate as unknown to the checker; additions and alignment saturate at 4,097 bytes. Inferred struct types are interned by their type id as needed by expressions. Fixtures cover the exact 4,096-byte boundary, alignment padding, oversized values, doubling chains, cycles, unknown types beside large known fields, nested empty structs, and shared-helper DAGs. Struct printing, structural equality and aggregate expectation output match Rust nlc byte for byte. The core library now supplies the raw print and expectation hooks those helpers call.

Enums, payload constructors, `match`, `Option`/`Result`, `?`, `??`, and the E2 core-library result wrappers remain unsupported in the self-hosted frontend, as assigned to E2b/E2c.

## Comparison and classification

The checked table grew from **484 packages** (36 build, 43 diagnose, 405 unsupported at the current base) to **519 packages** (48 build, 64 diagnose, 407 unsupported). The final `NLC_LONG_TESTS=1 scripts/compare-selfhost.sh --build` run passed at O1 and O3 across both core and C runtime legs with zero mismatches. Each level also matched all 8 seeded builds and 8 seeded diagnostics.

Existing packages moved from unsupported to diagnose:

- `tests/run/t04_duplicate_field`
- `tests/run/t04_missing_field`
- `tests/run/t04_nested_let_write`
- `tests/run/t04_nested_required`
- `tests/run/t04_unknown_field`

E2 packages now classified as build:

- `tests/e2/reference_default_later`
- `tests/e2/reference_default_override`
- `tests/e2/reference_default_shadow`
- `tests/e2/struct_equal_print`
- `tests/e2/struct_fields`
- `tests/e2/test_struct_expect`
- `tests/e2/test_struct_dag`
- `tests/e2/test_default_dag`
- `tests/e2/test_zero_size_leaves`
- `tests/e2/frame_budget_exact`
- `tests/e2/test_frame_budget`
- `tests/e2/tolong`

E2 packages now classified as diagnose:

- `tests/e2/reference_default_break`
- `tests/e2/reference_default_call_cycle`
- `tests/e2/reference_default_continue`
- `tests/e2/reference_default_cycle`
- `tests/e2/reference_default_cycle_order`
- `tests/e2/reference_default_expect`
- `tests/e2/reference_default_phase_body`
- `tests/e2/reference_default_phase_entry`
- `tests/e2/reference_default_return`
- `tests/e2/reference_default_scope`
- `tests/e2/reference_default_two_cycle`
- `tests/e2/reference_default_unused`
- `tests/e2/reference_unit_field`
- `tests/e2/size_direct_cycle`
- `tests/e2/size_mutual_cycle`
- `tests/e2/size_unknown_with_large_part`

These E2 packages remain unsupported:

- `tests/e2/reference_default_try`
- `tests/e2/reference_unit_erasure`
- `tests/e2/frame_budget_over`
- `tests/e2/frame_budget_chain`
- `tests/e2/size_over`
- `tests/e2/size_padding`
- `tests/e2/size_doubling_chain`

The E2a source additions extend `tests/e2/struct_fields/expected.stdout` with `12`, `20`, `10`, and `11` for shorthand, whole-struct swap, and nested field-path coverage. New E2 package oracles were checked against Rust nlc; explicit `expected.selfhost.stderr` files pin the new unsupported size and frame-budget diagnostics. E2a did not change the Rust checker or emitter or rewrite an existing Rust reference oracle. The earlier reference fixes and their oracle changes are in commit `0557c35`.

## Measurements

Measurements ran on WSL2 Linux 6.6.87.2, Intel Core Ultra 9 185H, Ubuntu clang 18.1.3, pinned logical CPU 0, with `RLIMIT_STACK=8192 KiB`. Build measurements used the bench lock, O1, the core runtime, an 8,000,000 KiB virtual-memory limit, and direct process timing. RSS is `/usr/bin/time` maximum resident set size in KiB.

### IR growth and size

The self-host-only helper bound probe produced **303,754 bytes at depth 20** and **343,538 bytes at depth 40**. The 39,784-byte increase over 20 more levels passed the comparator's linear-growth check.

The 10,000-function scalar benchmark has 500,042 source bytes. Current IR is 6,413,066 bytes from the self-hosted compiler (**12.825 IR bytes per source byte**) and 6,564,786 bytes from Rust nlc (**13.128**). E1c's reported C/core compile medians were 1,597.088/1,633.403 ms; this run measured 1,161.431/1,175.665 ms, 27.3%/28.0% lower on the same benchmark and machine. The seven compile samples were 1,144.899–1,180.655 ms for C and 1,168.732–1,186.020 ms for core.

For the 801-byte `struct_equal_print` package, self-host IR was 272,463 bytes (**340.154 bytes/source byte**) and Rust IR was 19,246 bytes (**24.027**). This small-package ratio is dominated by the self-host core module's fixed IR; the full E2 aggregate benchmark remains for E2c.

The struct sample's five direct process measurements were:

| Phase | Elapsed min / median / max | Peak RSS min / median / max |
| --- | ---: | ---: |
| Self-host compile to IR | 0.070 / 0.070 / 0.080 s | 151,536 / 151,536 / 151,536 KiB |
| `link-ir` | 0.170 / 0.190 / 0.200 s | 86,944 / 86,944 / 86,944 KiB |
| Rust whole build | 0.400 / 0.410 / 0.440 s | 105,240 / 105,244 / 105,244 KiB |

The E1 scalar benchmark's seven-sample medians were 1,161.431 ms (C runtime) and 1,175.665 ms (core); links were 4,686.248 and 4,950.850 ms. The stage-zero bootstrap in that run was 6,043.990 ms. A separate five-sample release bootstrap measured 5.810 / 5.910 / 8.260 s elapsed and 174,184 / 174,184 / 174,188 KiB peak RSS.

### Compiler stack tables

`nlc inspect stacks selfhost` reports a data-stack worst case of **5,115,732,009 bytes** and reservation of **5,115,736,064 bytes**. E1 reported 3,478,494,879 and 3,478,495,232 bytes, so E2's tables add **1,637,237,130 bytes** to the computed bound and **1,637,240,832 bytes** to the reservation. The native-stack worst case rose from E1's 8,054,176 to **8,054,656 bytes**, a 480-byte increase. The updated stack-contract test pins the E2 totals and attribution.

### Native aggregate path fixtures

Slot totals are the conservative E2 count before LLVM optimization. `-fstack-size-section` reports optimized function frames separately. In every row the measured per-function frames were the same at O1 and O3. Rust can build the over-budget fixtures; E2a rejects them before emission.

| Fixture | Computed aggregate slots on path | E2a classification | O1/O3 generated function frames | O1/O3 native path from `inspect stacks` |
| --- | ---: | --- | --- | ---: |
| `frame_budget_exact` | 1,048,576 bytes (256 × 4,096) | build | user main 24 B; process main 40 B | 65,688 B |
| `frame_budget_over` | 1,052,672 bytes (257 × 4,096) | unsupported | Rust user main 24 B; process main 40 B | 65,688 B |
| `frame_budget_chain` | 1,720,320 bytes (420 × 4,096) | unsupported | each of 8 user functions 24 B; process main 40 B | 66,752 B |
| `test_frame_budget` | 12 bytes across the test and `shared` | build | small test below budget | below 1 MiB |

Five executions per binary had stdout redirected to `/dev/null`. Peak RSS min/median/max was 1,584/1,584/1,584 KiB for Rust O1 exact and over; 1,408/1,408/1,408 KiB for Rust O3 exact and over; 1,408/1,408/1,408 KiB for Rust O1 chain; and 1,584/1,584/1,584 KiB for Rust O3 chain. The self-host exact fixture measured 352/352/352 KiB at both O1 and O3. These process RSS figures, frame-section sizes, and computed slot totals are separate measurements.

The 1 MiB check counts aggregate slots along call, default, fill, and test paths. The recorded limitation remains: scalar frames, spills, LLVM inlining that can duplicate callees' slots, and fixed core frames are not included; they share the remaining 7 MiB of the default native stack. A follow-up for the native-stack task should compute a bound from `-fstack-size-section` frames and include those components.

## Validation

- `NLC_LONG_TESTS=1 scripts/compare-selfhost.sh --build`: O1/O3, core/C legs, seeded cases; zero mismatches.
- Full `cargo test` with `NLC_FRONTEND=rust`: passed under the 8,000,000 KiB limit.
- Full `cargo test` with `NLC_FRONTEND=selfhost`: passed under the same limit.
- `cargo fmt --all -- --check` and `git diff --check`: passed.

## Remaining for E2b/E2c

E2b/E2c still add enum payload layouts and constructors, equality/copy/print for active cases, `match`, inferred `Option`/`Result` layouts, `?`, `??`, their methods and diagnostics, and the core-library fallible syscall wrappers. Those constructs remain fail-closed in E2a. The generated aggregate compile benchmark combining structs with enums, matches and `?`, and the at-least-one-second aggregate runtime/checksum comparison, wait until those forms are implemented.
