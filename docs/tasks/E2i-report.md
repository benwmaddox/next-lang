# E2i report: shared interfaces and argument-timing audit

## Result and classification

E2i establishes the shared compiler interfaces for the parallel E2b/E2c and E3a1/E3a2 work. The self-hosted compiler still accepts the same constructs; collection, sum-type and data-stack features remain closed until their assigned steps.

The E2a baseline has 519 packages: 48 build, 64 diagnose and 407 unsupported. E2i adds ten stage-0 audit fixtures, all classified `unsupported` for selfhost until E3a2. The resulting table has 529 packages: 48 build, 64 diagnose and 417 unsupported. No existing package moved class, and no existing `expected.*` file changed.

The ten new packages are `e2i_write_struct_element`, `e2i_write_scalar`, `e2i_large_read_snapshots`, `e2i_large_list_snapshot`, `e2i_index_equality_snapshots`, `test_e2i_expect_snapshot`, `e2i_global_hidden_write_snapshot`, `e2i_global_transitive_hidden_write_snapshot`, `e2i_global_equality_hidden_write_snapshot` and `e2i_global_read_only_no_snapshot`. The successful fixtures pin the reference results at O1 and O3; the failing `expect` fixture exits 1 and prints the original left value beside the mutated right value.

## Stage-0 argument-timing audit

The audit found four observable mismatches, fixed in `compiler/src/emit.rs`:

- A gathered struct-element `write` argument was copied before later arguments ran. Gathering now happens after all arguments are evaluated, so the callee sees the later update and the emitter does not scatter an older value over it. `e2i_write_struct_element` prints `9`, `0`, `9`.
- Large read arguments passed a place directly even when a later argument could mutate it. The emitter now snapshots an overlapping large read place when a later argument may write that place. The small and over-4,096-byte struct cases and the large-list case retain their earlier values (`1`, `0`, `9` for each case).
- Aggregate equality could lose its left-operand snapshot when the right operand mutated that place. The equality path now preserves the left value, including lazy collection copies. `e2i_index_equality_snapshots` prints `4`, `0`, `false`, `false`; `test_e2i_expect_snapshot` confirms the failure message prints `Cell { value: 1 }` on the left and `Cell { value: 9 }` on the right.
- The place analysis missed writes to a global by name inside a later call. `e2i_global_hidden_write_snapshot` passed a large global as a read argument, then called `bump()`, which assigns `g.a = 9`; without a snapshot stage 0 printed `9`, while left-to-right evaluation requires `1`. The emitter now uses the checker's closed, transitive global-write summaries for direct and optional calls and resolved indirect-call targets. If an indirect call has no known targets, its function type's declared write paths determine whether a global place can change. The direct and transitive fixtures print `1`; `e2i_global_equality_hidden_write_snapshot` prints `false` for the preserved `g` against the updated copy. The read-only control prints `1`, `1` and reserves no snapshot scratch.

`e2i_write_scalar` also pins the already-correct scalar `write` timing (`9`, `0`, `9`). Snapshot scratch accounting now uses the same place-overlap, parameter-mode and global-effect analysis as emission, so its reservation follows the snapshots the emitter creates. `compiler/src/checker.rs` exposes `places_overlap` and the checked global-effect summaries within the crate for that shared analysis. The summaries also cover pool, map and set mutations inside called functions. `fs.read`, `fs.list` and `fs.list_with_extension` are explicit output-buffer writes and are included; environment, output and file-write effects do not receive writable places and cannot mutate one. These are the only stage-0 behavior changes; the fixtures and Rust expected outputs pass at O1 and O3.

## Shared interfaces

### Type table and kind classification

`TypeRecord` is the type-table row, indexed by stable type ID. IDs 0 through 5 remain the built-ins `int`, `long`, `bool`, unit, never and core address; user records append after them. Type kind and struct-sizing state share one packed word, and the helper operation mask is kept in that row so the helper registry adds no second table sized to the input limit. `TYPE_TABLE_CAPACITY` includes the six built-in rows.

The type module owns record indexing and exposes `type_kind`, `is_aggregate_type`, `value_type_size`, `value_type_align`, `resolve_value_type`, `known_non_scalar_type` and `is_builtin_type_name`, along with struct-to-type-ID mapping. Existing aggregate decisions use the classifier. The kind set reserves scalar, unit, never, struct, enum, option, result, array, list, ascii, text, bytes and address; only the kinds already implemented by E2a have storage and helper emitters. Unimplemented registered kinds fail closed.

### Storage locations

`StorageLocation` records origin, anchor kind and node, byte offset, copy count and copy index. E2i supports a native slot with one copy at index zero. Other origins and lane geometry set the internal IR error flag. `emit_layout_address` accepts a location; aggregate call arguments, hidden destinations, received parameters and helper operands use the shared location functions. E3a1 owns new origins; E3a2 owns lane geometry and the descriptor ABI.

No data-stack or global origin, region planner, stack-growth point or relocation behavior is added here. The native-slot location form remains the E2a slot-plus-offset representation.

### Helper emission and exits

The helper registry interface is keyed by type ID and operation mask: copy, equality, print, fill and default. Dispatch selects the emitter by type kind; E2a's struct helpers are the first registered emitter. Later kinds add an emitter through this dispatch.

`register_exit_cleanup` records a scope, action and owner. `lower_scope_exit` handles return, fallthrough, test success/failure, break, continue and branches, invoking registered actions in innermost-first order. E2i registers no cleanup producers. Unknown cleanup actions fail closed. Region resets, write store-backs, view ends, `?`/`??`, and writer aborts remain future owners.

## Ownership table

This table is also documented at the top of `selfhost/compiler.nl`.

| Shared code | Owner after E2i | Others may |
| --- | --- | --- |
| Type table, kind classification, `value_type_size`/`_align`, `resolve_value_type`, `known_non_scalar_type`, `is_builtin_type_name` | E2i (interface frozen) | Append a kind and its branches |
| `emit_layout_address` and the location record | E3a1 (origins), E3a2 (lane geometry) | Nothing; sum layouts reach it only through the layout table |
| Passing a location as an argument or destination, receiving a parameter as a location | E3a2 (descriptor ABI) | Nothing; E2b and E2c call them for sum parameters and results |
| Helper registry | E2i | Register an emitter for their kind |
| Exit and cleanup function | E2i | Register a cleanup; call it from a new exit |
| `register_package_declarations`, signatures | E3a2 (parameter modes) | E2b: enums; E2c: result types |
| `natural_node_type`, `check_one_body`, `emit_expr_linear`, `emit_function_body` | None | One dispatch branch per new node kind |
| `unsupported_category_for_node`, `unsupported_node_message` | None | Remove their nodes, append their rows |
| `core_sys_*`, hook table, frame-budget walk | E3a1 | E2b/E2c add only unavoidable hooks with a C contract fixture |
| `limits.nl` | None | Append one delimited block with derivations |

Shared changes outside this table: `empty_compiler_tables` remains a direct record literal, while `main.nl` seeds the built-in rows after it returns. This avoids a second full `CompilerTables` value on the stack. `reset_compiler_tables` reseeds the rows after clearing. In stage 0, `places_overlap` visibility, checked global-effect summaries and the corresponding stack-contract measurement were updated for the audit.

## Checker, constructs and merge

The E2 checker order and construct table are unchanged. All prior E2 constructs retain their E2a status; the six new audit fixtures are unsupported by selfhost until E3a2. There are no package movements beyond those added rows.

The worktree can now add region and collection branches through the location and exit interfaces. E2b/E2c can append kinds and helper emitters without renumbering built-in IDs. The E2i merge itself has no moved buildable or diagnosable packages; later merged-only movements belong in E3a2's report.

No relocation check or positive relocation evidence applies to E2i because it adds no moving stack origin or growth point.

## Measurements and validation

| Measure | Result |
| --- | --- |
| `nlc inspect stacks selfhost`, data-stack worst case | 5,115,732,521 bytes |
| `nlc inspect stacks selfhost`, reservation | 5,115,736,064 bytes (unchanged from E2a) |
| `nlc inspect stacks selfhost`, native-stack worst case | 8,054,640 bytes |
| Self-host IR bound, depth 20 / depth 40 | 303,802 / 343,586 bytes; linear-growth check passed |
| Default build comparison, O1 | 48 build, 64 diagnose, 417 unsupported; 0 mismatches; 8 seeded builds and 8 seeded diagnostics matched |
| Long build comparison, O1 and O3 | Same counts and zero mismatches at both levels; all seeded cases matched |

The data-stack worst-case increase from E2a is 512 bytes: six stable type rows and the one-entry cleanup table, with the native reservation unchanged. The native-stack estimate decreased by 16 bytes after returning the large compiler record directly. These are compiler stack estimates, not runtime memory or RSS measurements.

Both complete suites passed under the 8,000,000 KiB virtual-memory limit:

- `NLC_FRONTEND=rust cargo test --offline`
- `NLC_FRONTEND=selfhost cargo test --offline`
- `cargo fmt --all -- --check`
- `cargo test --offline --test selfhost_interfaces`
- `git diff --check`

The source-scan test confirms that `TY_STRUCT_BASE` is not used as a kind comparison, there are no `struct_types[...]` accesses, and type-table indexing stays inside the marked type module. The full Rust and selfhost suites also passed the E2 reference fixture test and the corpus lexer/parser/build parity test.

## Notes and next step

The audit's list-equality expression could not use a raw block expression in that position, so the mutating RHS is expressed through a small helper function. This keeps the test focused on the evaluation point supported by the language.

Next, E2b/E2c can proceed in this checkout and E3a1/E3a2 can proceed from the E2i boundary in the separate worktree. Each change should follow the ownership table and leave unimplemented origins, kinds and cleanup actions fail-closed.
