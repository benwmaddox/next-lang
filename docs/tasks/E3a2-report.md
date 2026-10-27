# E3a2 implementation report

## Delivered

E3a2 adds fixed arrays and bounded lists, including indexing and bounds checks,
element and field updates, length/count access, list insertion/removal/clear,
copy/equality/print/fill helpers, and iteration through writable element views.
List push and insert remain discard-only operations; a full list keeps its
contents and count. Nested collections are gated where their layout is not
covered by this slice.

`write` parameter modes are parsed and checked for assignable mutable places.
The checker detects overlapping write places, including same-place and
collection-alias cases. Writable loop views alias the collection storage;
structural mutations and calls that could replace the viewed collection are
rejected while the view is live. Read arguments are evaluated as values at
their argument position, write arguments retain a location, and index
expressions are evaluated once.

`StorageLocation` now models native slots and E3a1 data-stack offsets, plus
collection lane geometry (`copies`, `index`, and the compiler-side stride).
User by-reference arguments use `(anchor pointer, byte offset)` and aggregate
parameters additionally carry copy-count and active-index values. Null anchor
means the movable data-stack base; callees reload it at use sites. Field
offsets for struct-of-arrays layouts are calculated from the lane geometry.
There is no global origin. Descriptor handling retains E3a1's region offsets
and context-passing ABI.

The new implementation is in `selfhost/collections.nl` and
`selfhost/params.nl`, with integration in `selfhost/compiler.nl`,
`selfhost/main.nl`, and `selfhost/regions.nl`. `scripts/embed-core.sh` was run;
it embedded 10 files totaling 53,168 bytes, SHA-256
`786fce11325ce300511933fbdd7956a554d99f377a98c7242ab0ba062f5a2aed`.
Stage-zero sources and committed package sources/expectations were not
changed. The only new test packages are under `tests/e3/a2_*`.

## Classification

The E3a2 block is a single block at the end of `tests/e1/classification.tsv`
and has 73 rows: 27 `build`, 45 `diagnose`, and 1 `rejects`.
Seventeen new packages account for 8 build, 8 diagnose, and 1 rejects row.
Fifty-six existing packages moved from unsupported: 19 to build and 37 to
diagnose. No already-committed test package was edited or deleted.

| Classification | At E3a1 merge | Current |
| --- | ---: | ---: |
| build | 90 | 117 |
| diagnose | 115 | 160 |
| rejects | 45 | 46 |
| unsupported | 374 | 318 |

The moved packages are `tests/e1/order_file_precedence`,
`tests/e1/unsupported_type_list_test`,
`tests/e1/unsupported_type_list_unreachable`,
`tests/e1/unsupported_type_list_unused`;
`tests/e2/e2i_index_equality_snapshots`,
`tests/e2/e2i_large_read_snapshots`, `tests/e2/e2i_write_scalar`,
`tests/e2/e2i_write_struct_element`,
`tests/e2/noshadow_reference_unit_erasure`,
`tests/e2/test_e2i_expect_snapshot`;
`tests/run/o1_offset_cache_call`, `tests/run/t04_copy_and_siblings`,
`tests/run/t04_nested_call_order`, `tests/run/t04_overlap_child_first`,
`tests/run/t04_overlap_parent_first`, `tests/run/t04_overlap_same`,
`tests/run/t04_overlap_same_reverse`, `tests/run/t04_read_forward`,
`tests/run/t04_write_let`, `tests/run/t04_write_temporary`,
`tests/run/t06_discard_result`, `tests/run/t06_helper_ends_push_proof`,
`tests/run/t06_index_list_oob`, `tests/run/t06_index_negative`,
`tests/run/t06_int_index`, `tests/run/t06_negative_capacity`,
`tests/run/t06_nested_replace_element`, `tests/run/t06_nested_replace_parent`,
`tests/run/t06_nested_write_element`, `tests/run/t06_nested_write_parent`,
`tests/run/t06_overlap_child_first`, `tests/run/t06_overlap_params_unknown`,
`tests/run/t06_overlap_parent_first`, `tests/run/t06_overlap_unknown_indexes`,
`tests/run/t06_oversized_local`, `tests/run/t06_push_unhandled`,
`tests/run/t06_read_view_write`, `tests/run/t06_readonly_let_view`,
`tests/run/t06_remove_oob`, `tests/run/t06_size_overflow`,
`tests/run/t06_variable_capacity`, `tests/run/t06_view_clear`,
`tests/run/t06_view_index_write`, `tests/run/t06_view_insert`,
`tests/run/t06_view_remove`, `tests/run/t06_view_replace_collection`,
`tests/run/t06_view_write_collection`, `tests/run/t07_pool_list_element`,
`tests/run/t23_rss_list`, `tests/run/t23_rss_return`,
`tests/run/t23_rss_struct`, `tests/run/t24_array_count`,
`tests/run/t24_list_capacity`, `tests/test/t13_stack_exhaustion`,
`tests/test/t17_large_reservation`, and
`tests/test/t17_startup_reservation`.

`a2_noshadow_loop` is in the `rejects` class as required by DESIGN's no-name-
shadowing rule. Diagnose fixtures use `same_rejection`; they pin real stage-0
diagnostics without requiring matching rejection order or wording.

## Stage-0 probes and pinned answers

The following expected results were obtained from stage 0 and are pinned by
the new fixtures. There are no competing-error fixtures.

| Fixture | Stage-0 answer pinned |
| --- | --- |
| `a2_loop_counter` | Assigning to the iteration counter is rejected: `cannot assign to loop counter 'index'; loop counters are immutable`. |
| `a2_collections` | Arrays and lists index, compare, copy, print, fill, and honor insert/remove/clear. A discarded push or insert at capacity leaves the list unchanged; both before/after values are `[6]`. The fill callback runs once and prints `91`. |
| `a2_views` | Writable element views alias their collection through nested blocks, field updates, and iteration; array and list values print/compare with the expected field layout. |
| `a2_view_push` | A view remains valid through a push; the loop's initial iteration count is retained. Output is `2`, `[2, 2]`, `[]`. |
| `a2_view_clear`, `a2_view_insert`, `a2_view_remove` | Structural list mutation is rejected while a collection view is live, with the operation-specific real error. |
| `a2_view_replace`, `a2_view_write_collection` | Replacing the viewed collection or passing it as `write` is rejected while the view is live. |
| `a2_evaluation` | Index expressions run once; read parameters capture the value at their argument position; write arguments refer to caller storage after later arguments run. Output pins the mutations and printed values. |
| `a2_write` | Scalar, struct, and list-element write parameters update the caller; field writes, swaps, and forwarding preserve exact values. |
| `a2_overlap_collection`, `a2_overlap_same` | Overlapping writable places are rejected with `arguments overlap, and at least one is passed as write`. |
| `a2_relocation_embedded`, `a2_relocation_native_embedded` | Embedded and native anchored locations survive a later argument forcing data-stack movement; both print `[9]`. |
| `a2_relocation_write_element` | A write reference to `values[1L]` precedes a later `force_growth()` argument; after relocation the callee updates the right element. Output: `[7, 9]`, `9`, `[7, 7]`. |
| `a2_noshadow_loop` | The no-shadow package is rejected with real error text and uses the `rejects` classification. |

## Location descriptor and relocation evidence

The directed relocation fixture `a2_relocation_write_element` passes an
indexed list element as the first `write` argument and forces growth in a later
argument. With `--test-region-threshold=0` and forced move, the run printed
`nl offset stack entry 'main': initial=4096 reserved=1048576 peak_used=600184
growths=1 relocations=1 growth_ns=11237`, then the expected stdout above.
This confirms the write element's offset is resolved against the moved base
after later-argument evaluation. The relocation sweep completed at O1 and O3:
117 build packages, 169 runs, 25 relocated packages per level, zero output or
status mismatches. All three directed A2 relocation fixtures showed movement
at both levels.

## Shared functions changed outside the E2i ownership table

These changes extend E2i-shared code for the new storage and checking rules.
The table's single-dispatch branches (`natural_node_type`, `check_one_body`,
`emit_expr_linear`, `emit_function_body`) and E3a2-owned descriptor/signature
functions remain in their assigned extension points.

- `parameter_name_token`, `parameter_mode`, `encode_parameter_name_token`,
  `binding_name_token`, and `binding_is_view` encode parameter modes and view
  state in existing compact tokens. `closest_name_candidate` reads the
  decoded name token so view metadata does not grow compiler tables or change
  stack bounds. `check_package_bodies` creates parameter bindings with the
  encoded mode.
- `intern_written_type_instances`, `size_package_types`, `main`,
  and `compile_embedded_core` resolve explicit array/list types and compute
  exact recursive layout sizes for core and user type tables.
- `compile_selfhost_package` calls `check_nested_collections_eligibility`
  after body checking, so unsupported nested collection shapes are diagnosed
  in the user package at the appropriate source location.
- `unsupported_category_for_node`, `report_unsupported`,
  `check_package_eligibility`, and `check_nested_collections_eligibility`
  classify unsupported nested collection shapes while allowing the supported
  arrays, lists, and non-nested struct elements.
- `is_unsuffixed_integer`, `body_child_expected`, `fail_assignment_error`,
  and `node_has_parent_kind` add expected-type, collection-context, and
  assignment diagnostics. The collection-specific `natural_node_type` and
  `check_one_body` logic is in the table's permitted per-node branches.
- `is_assignable_place`, `place_root_binding`, `place_root_is_view`,
  `place_alias_root_binding`, `place_path_depth`,
  `place_path_component_node`, `places_overlap`, `active_view_overlaps_place`,
  and `check_call_write_modes` validate writable places, compare their
  field/index paths, recognize distinct constant indexes, track view aliases,
  and reject overlapping mutable arguments.
- `aggregate_source_location`, `aggregate_source_kind`,
  `aggregate_source_id`, `emit_aggregate_address`, `emit_dynamic_field_lane_offset_for_descriptor`,
  `emit_parameter_field_path_address`, `emit_collection_view_name_address`,
  `emit_aggregate_copy`, `emit_aggregate_copy_to_place`, `emit_store_scalar`,
  `emit_store_scalar_to_place`, and `emit_compound_assignment` propagate
  descriptors through fields, indexes, writable views, assignments, and
  aggregate transfers.
- `emit_sys_method`, `emit_sum_payload_transfer`,
  `emit_sum_payload_to_expression`, and `emit_sum_payload_to_coalesce` adapt
  method and sum-type paths to the descriptor geometry while preserving the
  merged E2b/E2c behavior.
- `emit_function_definition` and `emit_test_definition` receive descriptors
  for parameters and establish the locals/temporaries required by list and
  view operations.
- `emit_struct_copy_helpers` keeps small and collection-containing struct
  copies fieldwise, while routing large plain structs through the generic
  bulk-copy fallback. This is the specialized-copy policy measured below.
- `mark_struct_helpers`, `emit_type_helpers_for_kind`, and
  `emit_registered_type_helpers` register and emit array/list copy, equality,
  print, fill, and default helpers through the E2i helper-registry extension
  points listed in the ownership table.
- In `selfhost/regions.nl`, `region_node_is_collection_method_receiver`,
  `region_node_is_temporary`, `region_function_for_block`,
  `region_body_for_block`, `region_scope_for_temporary`,
  `region_consider_binding`, `region_consider_temporary`,
  `region_scope_end_offset`, `region_scope_alignment`, and
  `emit_region_scope_enter` account for collection receivers, view aliases,
  and nested block lifetimes without allocating a region slot for the alias.

## Prep-brief reference audit

The cited names and locations in `prep-E3a2.md` were checked against the
merged stage-zero and selfhost sources. Several references were stale or
approximate:

- `check_capacity_value()` is named `Checker::capacity_value()` in
  `compiler/src/checker.rs` (around line 2405). `ArrayIndex` is the older AST
  name; the current node is `ExprKind::Index` in `compiler/src/ast.rs`.
- The cited element restriction around checker line 8230 does not describe
  the current type resolver. List and array type cases are in the current
  checker type-resolution paths (around lines 1067 and 1393); collection
  interning is around 2291. `check_collection_index` around 8448 is valid.
- `resolve_place` and `place_is_mutable` are methods in `checker.rs` (around
  12747 and 12915), not `resolver.rs`. Rust package declaration registration
  is `check_package` (line 78); `register_package_declarations` is the
  selfhost function, currently in `selfhost/compiler.nl` around line 3460.
- The Rust parser's index emitter is the `ExprKind::Index` arm in
  `compiler/src/emit.rs` around line 21972. The brief's 11900 range describes
  a different helper. `emit_call_argument` is around 11946, while call
  argument gathering is around 12107 and is invoked from around 12970.
- Rust helper line references in the brief were approximate: `type_size` is
  around emit.rs:3946; collection element/call gathering is around 8222/8337;
  fill around 10385; index guard around 11039; print around 17470; equality
  around 19612.
- The selfhost descriptor helpers are in `selfhost/params.nl`:
  `emit_location_descriptor_argument`,
  `emit_location_descriptor_parameter`, `emit_location_argument`, and
  `emit_location_parameter`. There are no functions named
  `pass_location_as_argument` or `receive_parameter_as_location`.
- The brief's `emit_layout_address`, `StorageLocation`, type-kind, helper
  registry, and cleanup-table ownership pointers were checked against the
  current ownership block at the head of `selfhost/compiler.nl` and the
  implementations; the merged source uses the E3a1 regions/offset/context
  code plus E2b/E2c sum and fallible-type emitters.

## Specialized-copy and performance measurements

Benchmarks ran with the release compiler, under `flock -x
/home/ben/linuxbench/bench.lock`, and produced matching checksums. The triples
are best/median/worst seconds. `empty` is a timing baseline; the other rows
exceed one second per timed run.

| Workload | Checksum | Rust best / median / worst | Selfhost best / median / worst |
| --- | --- | ---: | ---: |
| empty | `(empty)` | 0.004085 / 0.004533 / 0.004775 | 0.003398 / 0.003919 / 0.003972 |
| list_loop | 9783015026 | 1.499340 / 1.515864 / 1.536884 | 1.362780 / 1.380355 / 1.544732 |
| soa_loop | 16281792706 | 4.172138 / 4.202772 / 4.253973 | 4.021700 / 4.615085 / 5.052735 |
| write_call_loop | 11257354506 | 2.933519 / 3.113164 / 3.210999 | 2.525342 / 2.573675 / 2.639626 |
| e2_aggregate | 12000000000 | 20.479220 / 20.903419 / 21.996824 | 1.159601 / 1.164133 / 1.191455 |

The `e2_aggregate` row is the E2c 3-billion-iteration sum/enum/Result
aggregate workload and acts as a cross-step aggregate parameter proxy; there
is no dedicated new struct-parameter loop in `bench/e3a2`.

Specialized copy measurements use best/median/worst picoseconds per copy.
The last column is generic median / specialized median in thousandths; values
over 1000 favor the specialized path.

| Shape | Bytes | Specialized best / median / worst | Generic best / median / worst | Ratio |
| --- | ---: | ---: | ---: | ---: |
| struct-8 | 8 | 1238 / 1250 / 1512 | 1232 / 1365 / 1390 | 1092 |
| struct-40 | 40 | 1282 / 1310 / 1352 | 1308 / 1342 / 1442 | 1024 |
| struct-64 | 64 | 1324 / 1353 / 1420 | 1355 / 1399 / 1423 | 1033 |
| struct-256 | 256 | 4372 / 4594 / 4711 | 4531 / 4644 / 4807 | 1010 |
| struct-4096 | 4096 | 17909 / 17993 / 18214 | 18013 / 18157 / 18181 | 1009 |
| list-cell-8 | 144 | 3439 / 3608 / 3683 | 3499 / 3569 / 3652 | 989 |
| list-cell-64 | 1096 | 9518 / 9632 / 9780 | 9600 / 10129 / 10861 | 1051 |
| list-cell-1024 | 17416 | 61934 / 65483 / 67167 | 61638 / 67926 / 69825 | 1037 |

The list measurements exercise full-capacity copy and the per-live-element
fallback. Small list copy is within noise and slightly slower here; the larger
cases are modestly faster. Plain large structs use generic memcpy as designed,
so their results are effectively parity. Synthetic modules cover five struct
sizes and three list sizes; this runner does not include an array-copy case.

The selfhost package's stage-zero Rust-bootstrap LLVM IR was 16,600,848 bytes.
It contained zero emitted `nl.copy` helper definitions/calls and zero actual
memcpy/memmove/memset instructions. The bootstrap's compiler tables contain
write references and the literal `@memcpy` is part of the code-generation
template; the count is for emitted LLVM instructions, not template text. A
direct selfhost-of-selfhost build still reaches E3e's unsupported `const`
declarations and is outside this slice.

`nlc inspect stacks selfhost` reported data-stack worst case 6,943,732,617
bytes and reservation 6,943,735,808 bytes; native-stack worst case
8,061,864 bytes (recursive). Relative to the E2c baseline, the data-stack
bound grew 84,000,080 bytes and the native bound 7,240 bytes. A debug stage-zero
Rust bootstrap took 21.80 seconds and peaked at 246,072 KiB RSS.

The long comparison's generated-shape checks measured struct-helper IR at
655,510 bytes for depth 20 and 713,014 bytes for depth 40 (linear-growth
check passed). Enum constructor scaling measured 0.216 seconds for 1,600
enums, 0.374 seconds for 3,200, and 0.982 seconds for 6,400 (sub-quadratic
check passed).

## Spec gaps and merge needs

- `const` declarations remain unsupported by the selfhost compiler until
  E3e; consequently direct selfhost-of-selfhost compilation is not yet a
  valid E3a2 acceptance path. The normal Rust stage-zero bootstrap succeeds.
- The dedicated benchmark set has no array-copy workload and no isolated
  struct-parameter loop; copy-size coverage and the existing E2c aggregate
  proxy are reported separately above.
- Nested collections remain gated; the E3a2 subset does not claim collection
  elements that themselves contain collections.
- No stage-zero source change or expected-output fix is needed for merge.
  Preserve the descriptor's null-anchor/data-stack convention and
  copies/index lane geometry, its base reload after calls that can grow, the
  E2b/E2c context and sum paths, and the A2 relocation fixture. Regenerate
  `selfhost/core_files.nl` with `scripts/embed-core.sh` if embedded core
  sources change.

## Acceptance status

- Both full suites passed: `NLC_FRONTEND=rust cargo test --offline` and
  `NLC_FRONTEND=selfhost cargo test --offline`.
- `cargo fmt --all -- --check` passed.
- `cargo test --offline --test selfhost_interfaces` passed (1 test).
- Default and `NLC_LONG_TESTS=1` selfhost build comparisons passed with zero
  mismatches. O1 final counts: 117 build, 160 diagnose, 46 rejects, 318
  unsupported; the long run also checked O3. Seeded builds and diagnostics
  matched at both levels.
- The O1/O3 relocation sweep passed with positive movement evidence and zero
  mismatches. Final sweep: 117 build packages, 169 runs and 25 relocated
  packages at each level; all three directed relocation fixtures moved at
  both levels. The write-element relocation case is detailed above.
- `git diff --check` passed.
- `cargo fmt --all -- --check` passed on the final tree.
