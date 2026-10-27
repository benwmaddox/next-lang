# E3a1 report: data-stack regions, growth and offsets

## Scope and classification

E3a1 adds movable data-stack storage for large fixed-size struct values, stack growth and relocation in the self-hosted compiler and core library. It also changes the core hook ABI so every context-taking hook receives the job context. Stage-0 compiler and runtime implementation files are unchanged; the requested regression fixtures were added under `compiler/tests/`. The new core code uses E1c raw syscall results; the fixtures add no E2b/E2c syntax or types.

The E2i baseline had 529 packages: 48 build, 64 diagnose and 417 unsupported. This worktree has 534: 56 build, 64 diagnose and 414 unsupported.

Three existing packages moved from unsupported to build: `tests/e2/size_over`, `tests/e2/size_padding` and `tests/e2/size_doubling_chain`. Five build fixtures were added: `tests/e3/a1_core_probes`, `a1_large_region`, `a1_loop_region`, `a1_two_phase` and `a1_nested_region`. No existing expected output changed, and no stage-0 reference fix was needed; the new fixtures include their expected outputs.

The user-package checker order is unchanged: seed built-in types, register declarations, build line positions, index and size structs, then check eligibility. Embedded core compilation now also indexes and sizes its structs before checking eligibility, so the context-field intrinsics can resolve the single `DataStackContext` declaration. Large structs are no longer rejected by the 4,097-byte value cap. Oversized sum values remain gated for E3b.

E3a1 adds no source syntax. Large fixed structs above the 4,096-byte threshold use regions; `--test-region-threshold=<bytes>` lowers that threshold in test builds, with zero forcing all aggregates through the region path. The construct classifications otherwise stay as they were at E2i.

## Context and hook ABI

`core/context.nl` is now the single declaration of `DataStackContext`. Its first 15 fields match the offset-mode C runtime layout and are checked against `offsetof`; core-only fields follow, including pin count, initial size, poison count, the `core_state` pointer and clock storage. The context and fixed poison-record table live in a nonmoving header mapping. The stack mapping is separate and movable. Mutable core state is reached through `DataStackContext.core_state`; there is no global origin or mutable process state block.

The compiler creates the context before calling hooks and passes it as the first parameter to context-taking core functions. Startup passes argc/argv/envp/auxv through to `nl_core_init` and `@main`. File and entry names use compiler-emitted static `{ ptr, i64 }` tables with explicit lengths instead of NUL-terminated registration strings. `--runtime=c` and the comparison harness's C leg were removed.

Before switching the ABI, `compiler/tests/selfhost_context_offsets.rs` recorded 14 legacy C-hook contracts as LLVM IR fixtures with expected stdout, stderr and status. The same test checks the C context prefix. The core itself owns the replacement hook tests.

The `sys` surface now includes `context`, `context_offset`, `context_size`, `is_test_build`, `stack_addr`, `stack_load8`, `stack_store8`, `remap`, `unmap` and `clock_gettime`. Stack-buffer syscalls take offsets in their core wrappers. The emitter evaluates every syscall argument first, reloads the current base, derives stack addresses, then makes the syscall with no intervening call.

## Regions, growth and locations

`selfhost/regions.nl` plans block-local slots after type checking. Within each block it places regions of at most 64 KiB before larger regions. The block base is aligned from its incoming top at runtime; nested blocks reserve above live parent regions, while sibling blocks reuse offsets after scope exit. Loop bodies reset on every iteration. Small values stay in native slots; region addresses are materialized from the reloaded context base at the point of use.

The existing `StorageLocation` descriptor gains the data-stack origin. E3a1 uses its anchor and byte offset for region references and for user by-reference arguments/results, encoded as `(ptr anchor, i64 offset)`; a null anchor denotes the current data-stack base. E3a1 accepts only one copy at index zero and fails closed for other copy/index geometry. `emit_location_pointer_materialization` creates a native pointer immediately before use so no derived pointer survives a possible growth call. E3a2 still owns lane geometry and the broader collection descriptor ABI.

Region entry saves the incoming top, aligns the block base, checks arithmetic, reserves the block's end, and takes the slow growth path only if the reservation does not fit. `lower_scope_exit` retains E2i's cleanup order and restores the function top on return/fallthrough/test exits; scope-exit emission restores block tops, including loop break and continue paths. Core helper paths that cannot grow keep their no-growth pointer ABI.

The default reservation is 256 KiB. Growth doubles until the request fits (or uses the request), rounds to pages and reserves a following guard page. It maps a new target range while the old mapping is still occupied, uses fixed movable remap, removes the old guard page and updates only context fields. A pin count prevents growth while a kernel holds a stack address. Verification poisons old ranges in a fixed 64-entry table in the context header. Failures use kind 18. `NLC_STACK_STATS=1` reports initial/reserved/peak bytes, growths, relocations and accumulated move time.

## Relocation evidence

`scripts/check-selfhost-relocation.py` passed for all 56 build packages at O1 and O3: 98 runs per level and zero output/status mismatches. Eight packages relocated at each level. All five directed `tests/e3/a1_*` fixtures relocated at both levels, and the core probe verified both pin refusal and a full poison table fail safely with kind 18. The checker also verifies growth count equals relocation count and compares stdout and stderr after removing only the stats line.

The growth-cost workload started at 4,096 bytes, finished with a 32,768-byte reservation, used 20,800 bytes at peak, and made two growths/two relocations on every sample. Its expected output was `77`.

## Measurements

Measurements used the release self-host compiler where applicable, O1 test builds for the aggregate proxy, `ulimit -v 8000000`, and `/home/ben/linuxbench/bench.lock`. The host was WSL2 Linux 6.6.87.2 with clang 18.1.3 on an Intel Core Ultra 9 185H. Five samples were taken; the triples below are min/median/max.

| Measure | Samples and result |
| --- | --- |
| Growth time from stats | Two forced moves per run; `growth_ns` samples 15,557, 14,910, 12,436, 13,800 and 13,450 ns. Median 13,800 ns total, or 6.900 µs per move; spread 12,436/13,800/15,557 ns (6.218/6.900/7.779 µs per move). |
| Aggregate build, normal threshold | O1 test-build times 210.303, 207.387, 193.015, 198.655 and 188.228 ms; spread 188.228/198.655/210.303 ms. LLVM IR was 3,423,016 bytes. |
| Aggregate build, threshold zero | Times 216.665, 251.920, 216.316, 209.697 and 236.325 ms; spread 209.697/216.665/251.920 ms. LLVM IR was 5,483,051 bytes. Comparing best of five, threshold zero added 21.469 ms (11.41%) and 2,060,035 IR bytes. |
| Bootstrap | Release Rust `nlc build selfhost --frontend=rust` produced a 1,053,664-byte executable. Times were 7,307.262, 7,189.560, 7,260.434, 7,384.139 and 7,711.880 ms; spread 7,189.560/7,307.262/7,711.880 ms. |
| `nlc inspect stacks selfhost` | Data-stack worst case 5,115,732,521 bytes; page-rounded reservation 5,115,736,064 bytes; native-stack worst case 8,054,624 bytes and recursive. `main.tables` contributes 680,912,049 bytes and `main.compiler` 2,117,816,501 bytes. These are static bounds, not runtime RSS. |

The E2 aggregate benchmark was not present at the E2i boundary; E2c owns it. The threshold comparison therefore used the E2a-supported struct proxy: 95,073 bytes of source with 500 transformations. The comparison is a build-time/IR-size proxy, not an execution benchmark of the unavailable aggregate workload.

## Shared compiler changes and ownership

All additions and replacements in `selfhost/compiler.nl` and `selfhost/main.nl` are delimited with E3a1 markers. `selfhost/main.nl` uses inline markers around the affected code so the pinned `main.tables` stack-attribution location remains at line 96. `limits.nl` was not changed.

The following shared functions changed outside, or earlier than the scheduled ownership-table step. The reason for each group is given; the E2i owner-table interfaces remain in place.

- **Type sizing and eligibility:** `resolve_value_type`, `size_align_saturated`, `size_package_structs`, `type_node_is_oversized` and `unsupported_category_for_node` now compute exact large struct layouts, place large struct values in regions and retain the large-sum gate. This extends the type sizing and unsupported-category interfaces for E3a1's large-struct support.
- **Location origins and early descriptor passing:** `native_location`, `compiler_location`, `aggregate_destination_location`, `aggregate_source_location`, `emit_layout_address`, `emit_aggregate_address`, `emit_field_path_value`, `emit_location_pointer_materialization`, `emit_location_pointer_reference`, `emit_location_pointer`, `emit_location_argument`, `emit_location_parameter`, `emit_location_descriptor_argument`, `emit_location_descriptor_parameter`, `emit_hidden_destination_argument`, `emit_hidden_destination_parameter` and `emit_hidden_descriptor_parameter` now represent relocatable locations and materialize pointers at use. Although E2i assigns general descriptor passing to E3a2, E3a1 needed the restricted null-plus-offset form so an argument or hidden result can survive growth.
- **Helper registry emitters:** `emit_aggregate_copy`, `emit_type_helper_call_one`, `emit_type_helper_call_two`, `emit_default_field_helper_symbol`, `mark_struct_helpers`, `emit_contains_index_helper`, `emit_struct_copy_helpers`, `emit_struct_eq_helpers`, `emit_struct_print_helpers`, `emit_struct_print_text_call`, `emit_struct_fill_helpers` and `emit_struct_default_helpers` now pass context and materialize relocatable operands. The E2i helper registry remains the dispatch interface; helper bodies do not hold derived stack pointers across calls.
- **Region exits and control flow:** `lower_scope_exit`, `emit_expect_statement`, `emit_expect_after_expression`, `emit_expr_linear`, `emit_function_body`, `emit_function_definition` and `emit_test_definition` emit block/loop region entry and exit, use per-function region plans and restore stack tops on all relevant exits. `lower_scope_exit` changes the E2i exit implementation only to add the E3a1 region reset; it keeps innermost-first cleanup handling.
- **Core syscall/context ABI:** `core_sys_operation`, `core_sys_argument_count`, `core_sys_argument_type`, `core_sys_result_type`, `core_syscall_number`, `core_external_symbol`, `core_function_has_context`, `context_struct_index`, `context_core_state_field_index`, `context_base_field_index`, `context_field_offset`, `is_stack_address_node` and `emit_sys_method` add context/layout intrinsics, growth syscalls, context injection and two-phase stack address lowering.
- **Hook tables and startup:** `ir_write_core_function_symbol`, `ir_write_struct_identifier_global`, `ir_write_test_global`, `ir_write_token_text`, `emit_file_table_global`, `emit_file_globals`, `emit_core_file_globals`, `emit_core_registration`, `emit_core_start_assembly`, `append_embedded_core_sources`, `emit_main_function`, `compile_embedded_core` and `compile_selfhost_package` create the stable context, emit static pointer/length tables, register files with context and compile the core with the new ABI.
- **Failure calls:** `emit_runtime_failure` and `emit_checked_division` pass context to `nl_fail`, as required by the context-taking failure hook.
- **CLI:** `usage_build` and `main` add the test threshold option and remove `--runtime=c` while keeping the core runtime option.

## Differences and E3a2 handoff

The E2 aggregate measurement was unavailable and is documented above. The context prefix and legacy hook contracts were recorded before the ABI switch as required. One tooling detail mattered: standalone marker lines in `main.nl` shifted the exact source position that `selfhost_stack_bound_has_an_exact_attributed_path` pins, so those markers are inline while preserving the delimited regions. The block planner also needed block-local offsets: nested blocks reserve above their parents, while siblings reuse offsets after exit.

E3a2 should extend the location descriptor with lane geometry while preserving the data-stack origin and the just-in-time base reload. Keep the current one-copy/index-zero rule fail-closed until each collection layout is implemented. Collection growth and write-parameter calls must use offsets after argument evaluation and obey stack pinning. Preserve per-block bases, nested-region lifetime and sibling reuse. The merged E2b/E2c work will need to update core raw-result conventions and combined fixture classifications while retaining this context-passing hook ABI and static tables.

## Acceptance checks

- `NLC_FRONTEND=rust cargo test --offline`: passed.
- `NLC_FRONTEND=selfhost cargo test --offline`: passed.
- `cargo fmt --all -- --check`: passed.
- `selfhost_interfaces`: passed in both full suites.
- `scripts/compare-selfhost.sh --build`: 56 built, 64 diagnosed, 414 unsupported, zero mismatches; eight seeded builds and eight seeded diagnostics matched.
- `NLC_LONG_TESTS=1 scripts/compare-selfhost.sh --build`: zero mismatches at O1 and O3 with the same class counts and seeded results.
- `scripts/check-selfhost-relocation.py`: 56 packages, 98 runs at O1 and 98 at O3, zero mismatches and positive growth/relocation evidence.
- `scripts/embed-core.sh`: regenerated nine core files, 49,439 bytes, SHA-256 `099df77ad27149ca23b2b3d80ff232f877c038dc328671506baa96dc6c768e8f`.
- `scripts/check-core-test-index.py` and `git diff --check`: passed.
