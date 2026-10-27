# E3b implementation report

## Delivered

E3b enables bounded-list capacity operations as ordinary fallible values:
`push` and `insert` return `Result<(), Full>`, `pop` returns `Option<T>`, and
`discard` drops only the capacity errors accepted by stage 0. `Full` is
interned and printed through the existing sum-type helpers. Proven pushes keep
their `Result` type but may be unused when the count analysis proves success.
`?.` evaluates an optional receiver once, skips arguments on `none`, and
flattens one `Option` level.

Sum-typed list elements and structs containing sum fields use whole-value
lanes. Finite sum values larger than 4,096 bytes now receive regions, including
when they are elements. `pop` gathers an aggregate payload from the correct
payload offset in its sum lane. `?` early returns run the existing exit
cleanup, so a gathered `write` parameter is stored back before control leaves.
Omitted array initializers for structs run the struct default helper once and
copy that value into each array lane; aggregate assignment to a single-element
array uses the same lane-aware store path as larger arrays.

The E3b syntax work adds `while` with per-iteration scopes, `break` and
`continue`; bitwise `~`; `<<=`, `>>=`, `&=`, `|=`, and `^=`; statement
`if`/`else if` chains without a final `else`; context-typed unsuffixed integer
literals; and inclusive `a to b` ranges. `a..=b` remains accepted with the
same meaning and has no deprecation warning. A while loop gets a 10,000,000
step counter unless it exits early; the current compiler has no while
termination proof, so it conservatively instruments every while. The fixture
for an endless loop reaches the budget error. Iteration scopes reset on
fallthrough, `break`, and `continue`.

The `expected` class is now implemented in the build and relocation harnesses
and documented in [docs/testing.md](../testing.md). It runs the selfhosted
compiler and compares exit status, stdout, and stderr with committed
`expected.exit`, `expected.stdout`, and `expected.stderr` files. The reference
compiler is skipped only for these packages.

`scripts/embed-core.sh` regenerated `selfhost/core_files.nl`: 10 embedded core
files, 53,396 bytes, SHA-256
`6c8fb96bc1af71b033de833032b590c314a6d37cec18c66ec2b0a4deb42803`.
`compiler/src/` was not changed. No committed test package source or expected
output was edited; all new packages are under `tests/e3/e3b_*`.

## Classification

The E3b classification block is one block at the end of
`tests/e1/classification.tsv`, between `# E3b begin` and `# E3b end`. It has
46 rows: 29 build, 8 diagnose, 2 rejects, and 7 expected. Seventeen are new
packages (8 build, 2 diagnose, 7 expected); 29 existing rows moved from
unsupported: 21 to build, 6 to diagnose, and 2 to rejects.

| Class | Before E3b | After E3b |
| --- | ---: | ---: |
| build | 117 | 146 |
| diagnose | 160 | 168 |
| rejects | 46 | 48 |
| unsupported | 318 | 289 |
| expected | 0 | 7 |

Movements from `unsupported`:

- `tests/run/optional_result_receiver` → `diagnose`: stage 0 rejects optional
  chaining on a `Result`; the selfhost checker now gives a real error.
- `tests/run/t06_view_pop` → `diagnose`: stage 0 rejects `pop` while a list
  view is live. Supporting `pop` makes this a reached checker error.
- `tests/e1/unsupported_assign_shr_{test,unreachable,unused}` and the
  `unsupported_op_{and,gtgt,ltlt,or,xor}_{test,unreachable,unused}` packages
  → `build`: bitwise shifts/operators and the `>>=` assignment are now emitted.
- `tests/run/bad_shift` → `build`: its shift expression is now supported and
  its runtime failure matches stage 0.
- `tests/run/noshadow_enums` → `build`: a qualified user enum case named
  `Full` remains distinct from the built-in `Full` case.
- `tests/e1/unsupported_type_full_{test,unreachable,unused}` → `diagnose`:
  `Full` is recognized as a type, so these invalid type uses reach ordinary
  type checking.
- `tests/run/t06_nested_remove_parent` → `diagnose`: the now-supported `pop`
  call reaches the live-view checker.
- `tests/run/t06_places_eval` → `build`: omitted aggregate array elements now
  run their default helper and aggregate array assignment stores through the
  lane layout, including capacity-one arrays.
- `tests/run/t15_append_growth` and `tests/run/noshadow_t06_core` → `rejects`:
  their `err(Full)` payload bindings shadow the built-in type name.

New build packages are `e3b_array_default`, `e3b_capacity`, `e3b_optional`,
`e3b_proven`, `e3b_range_inclusive`, `e3b_relocation`,
`e3b_sum_collection`, and `e3b_write_question`. New diagnose packages are
`e3b_discard_pop` and `e3b_proven_branch`. New expected packages are
`e3b_compound`, `e3b_if_chain`, `e3b_long_context`, `e3b_range_to`, `e3b_tilde`,
`e3b_while`, and `e3b_while_budget`.

`tests/run/t10_queue_pop_view` remains unsupported because queues are outside
E3b. There were no reference fixes and no expected-output changes to existing
packages. The aggregate-array build fixture, `e3b_array_default`, pins the
stage-0 behavior that evaluating an omitted struct default runs once and copies
the resulting value into each array element.

The hand-written outputs for syntax that stage 0 rejects are:

| Package | Expected exit | Expected output |
| --- | ---: | --- |
| `e3b_compound` | 0 | `9\n` |
| `e3b_if_chain` | 0 | `2\n` |
| `e3b_long_context` | 0 | `3000000000\n4000000000\n` |
| `e3b_range_to` | 0 | `[1, 2, 3]\n` |
| `e3b_tilde` | 0 | `-10\n0\n` |
| `e3b_while` | 0 | `15\n6\n` |
| `e3b_while_budget` | 1 | empty stdout; stderr is `main.nl:2:5: loop step budget exhausted\n` |

All seven expected packages have empty stderr except the while-budget fixture.
The expected class is also included in relocation selection.

## Stage-0 probes and pinned answers

The checked-in stage-0 fixtures pin capacity, `pop`, `?`, `?.`, sum layout,
proven pushes, and write-back behavior. Additional probes established these
answers:

| Probe | Stage-0 answer |
| --- | --- |
| `push`/`insert` at capacity | Return `err(Full)` and leave the list unchanged. Printing includes `err(Full)` and `Full`; `ok(())` prints as before. |
| `pop` | Returns `some(value)` when nonempty and `none` when empty. Both `??` and `match` forms agree. |
| proven pushes | A bounded, in-capacity push can be left unused. A branch-dependent push without a proof is rejected as an unused `Result`; `insert` is never proven. |
| `discard xs.pop()` | Rejected: `discard accepts only built-in operations whose Result error is capacity Full`. |
| `?.` on `Result` | Rejected: optional chaining requires `Option`; convert a `Result` with `.ok()` first. `?.` on `Option` flattens one level. |
| list `pop` with a live view | Rejected: `cannot call list<long,2>.pop while a collection view is live; move operation after loop`. |
| `while` syntax | Stage 0 reports `expected a newline or ';' between statements`. The selfhost-only runaway fixture pins exit 1 and the loop-step error. |
| `~` and compound bitwise assignments | Stage 0 rejects `~` as an unexpected character and does not parse compound shift/bitwise assignments. The selfhost outputs are pinned in `expected.*`. |
| statement `if` chain without final `else` | Stage 0 rejects it with `an if expression needs an else branch`. |
| `a to b` | Stage 0 does not parse this separator (the representative probe expects `{`); the selfhost fixture returns `[1, 2, 3]`. |
| `a..=b` | Stage 0 accepts it as inclusive and prints `[1, 2, 3]`; selfhost matches. |
| unsuffixed long literal in `long` context | Stage 0 rejects values beyond `int` range and asks for an `L` suffix. Selfhost follows the expected `long` context and prints `3000000000` and `4000000000`. |
| omitted struct initializer in `Cell[2]` | The default expression runs once, then its value is copied to both elements; `e3b_array_default` prints `1` followed by `[Cell { value: 7 }, Cell { value: 7 }]`. |
| write parameter on `?` | The call returns `err(Full)` and the caller sees the final stored-back value. Output is `err(Full)`, `4`, `8`, `6`. |
| write parameter on `?? return` | The write value is stored back before the early return; `e3b_write_question` observes the updated caller value `6`. |

Errors need real text, but the first diagnostic and wording need not match
stage 0. The two diagnose fixtures therefore use the existing
`same_rejection` comparison rather than matching exact diagnostics.

### Prep-brief reference audit

The classification line estimates in `prep-E3b.md` were checked against
`git show HEAD:tests/e1/classification.tsv`: `optional_result_receiver` is at
line 220, `t06_view_pop` at 296, and `t10_queue_pop_view` at 351. The cited
Rust checker names were verified in the merged source: `Checker::capacity_value`
is `compiler/src/checker.rs:2405`; `Checker::check_method_call` is at 6533;
`max_loop_iterations` is at 12990; `collect_loop_pushes`,
`prepare_loop_push_proofs`, and `finish_loop_push_proofs` are at 13332, 13502,
and 13533. Optional-call emission is `compiler/src/emit.rs:18449` and
`emit_optional_call_to` is at 18563. The line references are approximate and
will drift as stage 0 evolves; the checked names and ownership are current.

## Checker order and construct table

Unsupported eligibility still runs before body checking. The E3b typed gate
for collection `Option`/`Result` operations was removed; sum types in
collections and the E2 oversized-sum eligibility event also leave. Finite
oversized sums now use exact layout and region placement. Unsupported
diagnostics retain their existing precedence; rejection order and exact text
are not treated as parity requirements. `Full` is no longer an unsupported
built-in case.

Now supported in the selfhost subset: `Result<(), Full>` and its E2c
operations; capacity `push`/`insert`; `pop`; stage-0-equivalent proven push
facts; supported `discard`; `?.`; sum-typed collection values and struct
fields; large sum regions; the `?`/`write` cleanup path; and all E3b friction
syntax. No-name-shadowing remains `rejects`, not `unsupported`.

Still outside this step: `byte`, `Ascii`/`Text`/`Bytes` as stored values,
builders and `grow`, `const`, unbounded collections, nested collections,
default initialization of arrays with aggregate elements, function values and
attributes, unsigned integers, floats, interpolation, and mutable globals.
Mutable globals remain removed from the language.

The typical-run stack-start estimator belongs to E3d2 and is not present yet;
when added, a `while` must count as five iterations for that estimate. The
current step budget is conservative: no while-termination proof exists, so
every while loop has a budget counter. A loop with an obvious induction
variable can therefore hit the budget after ten million iterations until a
proof is added.

## Layout, interfaces, and ABI

No ABI or location-descriptor change was needed. E3b reuses the existing
native/data-stack descriptor, type-kind table, helper registry, context-passing
ABI, and scope-exit cleanup registry. A collection of sums uses one lane of
whole values, with tag at offset 0 and payload at its aligned offset. Finite
sum types above 4,096 bytes go into data-stack regions; the relocation fixture
uses a 4,104-byte payload. There is still no global origin.

The E2i exit cleanup writes gathered `write` values back on each exit, including
`?`. The new fixtures exercise this for a function returning `Result` and
under a forced data-stack move. No new cleanup kind or `selfhost/params.nl`
change was needed. Region scope exits are emitted for loop fallthrough and
lowered through the shared exit path for `break` and `continue`.

## Shared compiler changes outside the ownership table

The permitted per-node dispatch points (`unsupported_category_for_node`,
`check_one_body`, `emit_expr_linear`, and `emit_function_body`) received E3b
branches. Other shared edits were:

- `builtin_case_name`, `builtin_full_type_id`, `intern_builtin_full`,
  `emit_enum_print_helpers`, and `emit_file_globals` register `Full`, remove
  its unsupported-case event, and emit its printed form.
- `BindingRecord`, `add_local_binding`, and
  `collection_push_is_proven` retain and update list-count facts used by the
  proven-push checker. `collections.nl` contains the count/proof walk and
  invalidates facts on the stage-0 operations that make them unknown.
  `invalidate_collection_counts_for_write_call` clears a direct list binding's
  count fact after passing it to a `write` parameter; the full-suite audit
  exposed this missing invalidation in `t06_helper_ends_push_proof`.
- `body_child_expected` and `check_one_body` propagate `long` context to
  unsuffixed literals and check capacity results, `discard`, optional calls,
  and while statements.
- `lower_scope_exit` adds the while-step branch target while keeping the
  existing per-iteration region reset for all exits.
- `emit_checked_shift` and `emit_compound_assignment` emit the added unary and
  compound bitwise operations.
- `emit_optional_call_start`, `emit_optional_call_invoke`,
  `optional_payload_location`, and the `emit_expr_linear` dispatch lower `?.`
  in stages so receiver evaluation and argument suppression match the
  reference.
- `emit_function_definition` and `emit_test_definition` allocate and
  initialize the while step counter; `emit_function_body` increments it and
  emits the kind-23 failure branch.
- `type_node_is_oversized` now rejects only invalid-size sentinels. Finite
  oversized sum types can proceed to exact layout and the region planner.
- `emit_collection_default_array_aggregate` calls the element struct's fill
  helper once and distributes its default value over array lanes. The
  `emit_aggregate_copy_to_place` lane-aware branch now also handles capacity-one
  arrays; previously it fell through to an address that aggregate indexing
  intentionally does not materialize.
- `compiler/tests/stack_contracts.rs` updates the selfhost compiler's exact
  static stack total for the added per-binding collection facts and loop-push
  proof table. Its 8 GB virtual-memory guard remains in place.
- Parser/lexer integration and the parse/dump node serialization were updated
  for the E3b syntax. `selfhost/main.nl` removes the retired E3a2 collection
  result event.

`core/fail.nl` and `runtime/nl_runtime.c` add failure kind 23,
`loop step budget exhausted`. No stage-0 compiler code was changed.

E3b did not perform a merge: the E3a1/E3a2 and E2b/E2c merge was already on
`main`. The 29 existing-package classification movements are listed above.

## Relocation evidence

`tests/e3/e3b_relocation` combines a sum value over 4,096 bytes, a read-only
sum argument, and a `write int` parameter whose mutation must be stored back
when a capacity `push` propagates `Full` with `?`. A
`list<bool, 300000>` forces growth. With
`--test-region-threshold=0`, `NLC_TEST_STACK_FORCE_MOVE=1`,
`NLC_STACK_VERIFY=1`, and `NLC_STACK_STATS=1`, the run reported:

```text
nl offset stack entry 'main': initial=4096 reserved=1048576 peak_used=653472 growths=2 relocations=2 growth_ns=14194
7
err(Full)
5
7
```

This shows the caller observes the write-back after the early return and the
sum value remains readable after both relocations. The focused relocation
check selected `e3b_relocation` and passed at O1. Final full O1/O3 relocation
results are recorded below after acceptance runs.

## Measurements

Measurements used the release compiler and `ulimit -v 8000000`. Bootstrap ran
five times with `nlc build selfhost --frontend=rust`:

| Measure | Samples and result |
| --- | --- |
| Bootstrap wall time | 9.43, 12.86, 9.51, 9.25, 12.67 s; best/median/worst 9.25/9.51/12.86 s. The executable was 1,472,976 bytes. |
| `nlc inspect stacks selfhost` | Data-stack worst case 7,007,732,625 bytes; page-rounded reservation 7,007,735,808 bytes; native-stack worst case 8,062,120 bytes, recursive. `main.tables` contributes 680,912,049 bytes, `main.compiler` 2,473,816,605 bytes, and `main.ir` 3,403,497,480 bytes. These are static stack bounds, not RSS. The count facts and loop-push proof worklists are included in `main.compiler`. |
| Specialized copy, O3, best/median/worst ps per operation | `struct-8`: 1257/1345/1390 specialized vs 1201/1230/1390 generic (ratio 914 milli); `struct-40`: 1339/1384/1430 vs 1249/1372/1410 (991); `struct-64`: 1274/1297/1322 vs 1266/1300/1322 (1002); `struct-256`: 4764/5190/5436 vs 4685/4847/5275 (933); `struct-4096`: 17821/18186/18296 vs 18090/18283/18354 (1005). |
| Specialized list copy, O3, best/median/worst ps per operation | Three-field `Cell` list: capacity 8 (144 bytes) 3625/3753/3853 vs 3576/3722/3855 (991); capacity 64 (1,096 bytes) 10368/10382/10780 vs 10127/10254/10502 (987); capacity 1,024 (17,416 bytes) 61035/61172/65825 vs 60527/61169/61528 (999). |

The copy benchmark was run under `flock -x
/home/ben/linuxbench/bench.lock`. Ratios are generic median divided by
specialized median in thousandths; 1,000 is parity and a larger value favors
the specialized helper. An independent repeat produced these medians and
ratios:

| Shape | First run specialized/generic (ratio) | Repeat specialized/generic (ratio) |
| --- | ---: | ---: |
| struct-8 | 1345/1230 (914) | 1397/1285 (919) |
| struct-40 | 1384/1372 (991) | 1362/1312 (963) |
| struct-64 | 1297/1300 (1002) | 1318/1313 (996) |
| struct-256 | 5190/4847 (933) | 5090/4832 (949) |
| struct-4096 | 18186/18283 (1005) | 19049/19126 (1004) |
| list-cell-8 | 3753/3722 (991) | 3768/3986 (1057) |
| list-cell-64 | 10382/10254 (987) | 10586/10184 (962) |
| list-cell-1024 | 61172/61169 (999) | 64646/64512 (997) |

The struct-8, struct-40, and struct-256 helper medians were slower in both
runs; struct-64 and list-cell-8 moved across parity; struct-4096 was about
0.4–0.5% faster; the larger list helpers were slightly slower. The E3b patch
does not add a new struct-copy form. It retains E3a2's required small
straight-line copies and generic bulk fallback for large plain structs; list
helpers also need to copy only live elements when count is below capacity.
The copy results are near parity and do not justify changing that policy in
this step. The selfhost compiler cannot compile its own source package yet
(`const` remains unsupported until E3e), so an emission-frequency count from a
selfhosted build of `selfhost/` is not available in E3b; reporting a frequency
here would be misleading.

## Final verification

- `NLC_FRONTEND=selfhost cargo test --offline --release -q --test '*'`: passed
  after updating the exact stack-bound assertion for the additional E3b
  checker state.
- Default comparison: 658 packages, O1, zero mismatches (146 build, 168
  diagnose, 48 rejects, 289 unsupported, 7 expected).
- `NLC_LONG_TESTS=1` comparison: the same 658 packages at O1 and O3, zero
  mismatches at both levels.
- `NLC_LONG_TESTS=1` relocation: 153 packages, 211 runs and 27 packages
  relocated at each of O1 and O3; the sum-region and write-back-on-`?` fixture
  is included.
- `cargo fmt --all -- --check`, `git diff --check`, and the check that
  `compiler/src/` is unchanged all passed.

## What was awkward in next-lang

The main implementation friction was the selfhost checker’s compact syntax
tree and fixed-capacity compiler tables. Proven-push analysis has to keep a
count fact per binding and conservatively merge branches; `insert`, `pop`,
`remove`, `clear`, other writes, and passing a list as `write` invalidate facts.
Loop proofs also have to mirror stage 0's rule that nested loops and direct
statement `if` paths do not establish the required proof. The emitter needed
to distinguish a block's final expression from a discarded unit-valued
capacity result.

Sum-typed `pop` exposed an offset mistake that scalar tests could not catch:
the copied value starts at the payload offset inside each sum lane. Optional
calls also required staged lowering to test the tag before evaluating method
arguments and to flatten exactly one option level. The hand-expected syntax
fixtures make stage-0 rejections useful without changing the frozen reference.

## Spec gaps and E3c plan

- The E3a2 array table covers struct defaults, now pinned by
  `e3b_array_default` and `t06_places_eval`. Sum-typed array defaults are not
  separately pinned; add one if the E3c default machinery or a later collection
  change makes that form constructible.
- The E3d2 typical-run starting-size estimator is not part of E3b; the stated
  five-iteration rule for `while` must be used when that estimator lands.
- While termination proof is not implemented. All while loops are budgeted,
  including loops an optimizer or later analysis could prove finite.
- The prep brief asks for specialized-copy emission-frequency counts from a
  selfhosted build of the compiler, while the compiler cannot selfhost its
  current `const`-using source until E3e. The available copy benchmark reports
  timings but cannot produce that compiler-source frequency count.
- No deprecation-warning mechanism is added for `..=`; this is the agreed
  later warning stage.

E3c will add `byte`, stored `Ascii`/`Text`/`Bytes`, literals, indexing,
slicing, comparisons, printing, conversions, and `fit<Ascii max N>()`; it will
also handle the E3c friction items and the inclusive-slice reference fix. The
existing location descriptor and moving-stack paths remain the basis for
large text and bytes values.
