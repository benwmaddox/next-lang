# E3c implementation handoff

**Status: E3c acceptance passed.** The complete long O1/O3 suite, default
staged-tree suite, formatting and diff checks, Text/copy/bootstrap measurements,
and committed-HEAD performance comparisons all passed.

The binding scope is [`prompt-E3c.md`](prompt-E3c.md) together with the E3c
row and sections of [`E3-selfhost-collections-text.md`](E3-selfhost-collections-text.md).
The prompt takes precedence over stale preparation notes. The Stage0/Rust
compiler remains unchanged; there are no edits under `compiler/src/`.

## Delivered scope

- `byte` is a checked built-in refinement for storage, byte indexing, casts,
  checked byte-list literals, and range validation. `(byte)x` fails the job
  outside 0..255; `unchecked((byte)x)` keeps the low eight bits. Byte literal
  elements for arrays, lists, and `Bytes` are checked at build time. The
  intentional out-of-range literal rejection names `256`.
- Bounded `Ascii`, `Text`, and `Bytes` values work as locals, struct fields,
  and enum, `Option`, and `Result` payloads. The implementation covers their
  literals and empty constructors, lengths, byte indexing, slicing, comparison,
  printing, concatenation, fitting, and conversions.
- ASCII can be passed to a read-only `Text` parameter without allocating a
  source-sized conversion temporary. Text/Ascii mixed comparisons and
  concatenation use the same read representation. Stored `Text` values are
  materialized in the caller-provided destination.
- Formatting is in `selfhost/format_text.nl` and `core/text_format.nl`:
  `str`, `str_hex`, `str_bin`, `pad`, `pad_right`, `pad_zero`, and
  `ascii_upper`. Constant numeric expressions narrow inferred `str` capacity;
  bounds include the destination header and are checked before arithmetic.
- The T18 text-parsing methods are implemented in
  `selfhost/parse_number.nl` and `core/parse_number.nl`:
  `parse_int`, `parse_long`, their radix forms, and `parse_int_literal`.
  Parsing scans the source bytes and writes `Option` directly to its result
  destination. No `parse_long_literal` API was added.
- UTF-8 boundary validation and trusted Text operations remain separate in
  `core/utf8_validate.nl` and `core/utf8_trusted.nl`. In test builds, generated
  Text constructors revalidate and fail with kind 22 on corrupted Text;
  ordinary program builds emit no such assertion.
- The `.bytes()` call on a const `Ascii` receives a real diagnostic that names
  the const and method. `Text.upper()` and text-containing collection elements
  remain deferred to E3e. Builder operations remain deferred to E3d1; valid
  `try_append`/`Bytes.push` forms use the `text builders` unsupported reason,
  while malformed arguments and writes through a `write` parameter are real
  diagnostics. `str(bool)` remains rejected, and no `ascii_lower` method was
  added.

## Classification and fixture movements

Counts at the branch's classification freeze, confirmed by the parent on
2026-10-28:

| Class | Before E3c | Current | Change |
| --- | ---: | ---: | ---: |
| `build` | 164 | 189 | +25 |
| `diagnose` | 173 | 205 | +32 |
| `rejects` | 48 | 49 | +1 |
| `unsupported` | 300 | 263 | -37 |
| `expected` | 13 | 21 | +8 |
| `expected-reject` | 0 | 1 | +1 |
| **Total** | **698** | **728** | **+30** |

Thirty-nine existing packages moved out of `unsupported`:

- To `build` (10): `tests/run/r1_byte_match`, `t14_ascii_cast_failure`,
  `t14_ascii_loops`, `t14_ascii_packed`, `t16_ascii_read_text`,
  `t16_bytes_view_argument`, `t16_mixed_maxima`, `t16_text_slice_bounds`,
  `t30_locality`, and `tests/test/t14_ascii_expect`.
- To `diagnose` (29): `tests/e1/unsupported_type_{ascii,byte,bytes,text}_`
  `{test,unreachable,unused}` (12); `tests/run/{r1_byte_match_no_catchall,
  result_coalesce,t14_ascii_non_ascii,t14_ascii_write_append,
  t15_uninferred_loop_builder,t16_bytes_view_return,t16_bytes_view_write,
  t16_text_byte_limit,t16_text_write_ascii,t16_text_write_byte_limit,
  t18_bad_radix,t20_invalid_byte,t24_ascii_array_type_suggestion,
  t24_ascii_hex_escape,t24_text_hex_escape}` (15); and
  `tests/e3/s0fix5_byte_{invalid,negative}` (2).

Thirty new packages were added: 15 `build` (`e3c_ascii_text_promotion`,
`e3c_byte_array_literals`, `e3c_byte_list_literals`, `e3c_parse_{valid,invalid}`,
`e3c_text_concat`, `e3c_text_large_slice`, `e3c_receiver_order`, and
`e3c_values_{compare,conversions,fields,fit,slice_exclusive_bounds,str_bounds,text_slices}`);
3 `diagnose` (`e3c_deferred_result_type`, `e3c_parse_bad_radix`,
`e3c_values_str_bool`); 8 `expected` (`e3c_ascii_methods`, the four byte cast
and Bytes-literal packages, `e3c_values_inclusive_slices`,
`e3c_values_slice_inclusive_bounds`, and `e3c_values_slice_overflow`); one
`expected-reject` (`e3c_values_const_bytes`); one `rejects`
(`e3c_byte_literal_out_of_range`); and two `unsupported`
(`e3c_deferred_enum_text` and `e3c_deferred_option_text`).

The only edits to existing E3b fixture packages are the authorized
`step_budget.main = 10000000` manifest entries for
`e3b_while_budget`, `e3b_fix1_l1_runaway`, and `e3b_fix1_l1_cross_call`.
Other expected files belong to new packages. In particular, the expected
slice oracles encode the corrected inclusive `..=` behavior while Stage0 is
left frozen.

## Stage0 probes and recorded differences

- Stage0 accepts `byte[N]` and `list<byte, N>` literals, but its array checker
  accepts `[1, 256, 3]` and prints `256`. E3c explicitly requires checking each
  element, so the selfhost compiler rejects that package with a real error;
  this is the `rejects` class. Stage0's parser rejects the new checked and
  unchecked byte cast syntax and a Bytes literal-list form, so those use
  hand-written `expected.*` outputs.
- The `e3c_ascii_methods` expected-output fixture pins Ascii indexing,
  iteration, slicing, `contains`, `starts_with`, and `Ascii.bytes()` passed to
  a Bytes parameter. A fresh Stage0 probe rejects `word.contains("ell")` at
  compile time with `method 'Ascii max 8.contains' takes no arguments`; the
  fixture's `true`, `true`, and `false` outputs are therefore handwritten,
  not a Stage0 comparison. No Stage0 behavior for the `starts_with` call is
  claimed here.
- Stage0 treats `..=` as an exclusive end. The E3c parser/checker/emitter
  preserve inclusivity; expected-class fixtures cover the final code point,
  one-past-end failure, and overflow at `long` maximum.
- Stage0 prepares a slice receiver's byte and code-point metrics before
  evaluating effectful bound expressions, while the payload remains borrowed
  from the receiver's source location. `e3c_receiver_order` mutates Text from
  seven bytes to three before the slice reads payload (`KQ`), then grows a
  one-code-point receiver to three code points and confirms the bound still
  uses the captured count by failing with kind 16. This rule is specific to
  method receiver descriptors; read-only function arguments and concat
  operands retain their separate value-snapshot behavior.
- Stage0 formats `str(int)` and `str(long)` with their bounded maxima and
  accepts the constant-width examples `str(7)`, `str(-1)`, and `str(1 + 2)`.
  The width probe confirms `pad`/`pad_right` accept a nonnegative constant or
  refined `long`; a `byte` width is rejected, so no source-order byte-width
  fixture was added. Text widths count code points; Ascii widths count bytes.
- Stage0 rejects `str(bool)` with a real compile diagnostic, so the selfhosted
  compiler rejects it too. `ascii_lower` is not a Stage0 method and is outside
  this step; `Text.upper()` remains the E3e Unicode operation.
- Stage0's `Bytes.to_ascii()` returns `TextError.NonAscii` for bytes above
  ASCII, including truncated UTF-8. It does not return `InvalidUtf8` for that
  conversion. `validate_utf8()` and `to_text()` do report the malformed input
  offset; the fixtures pin both behaviors.
- Stage0's `SIGNATURE.bytes()` on a const exits during compilation with an
  unrelated unknown-enum message. The `expected-reject` class instead requires
  an exact status-2 selfhost diagnostic naming `SIGNATURE` and `.bytes()`,
  empty stdout, and no IR.

The repository did not contain the Unicode Consortium UTF-8 stress corpus,
Unicode case-mapping files, or their licenses. The task forbids network access,
so [`tests/data/unicode/README.md`](../../tests/data/unicode/README.md) documents this
gap. `compiler/tests/selfhost_utf8.rs` uses 306 original boundary vectors
against Rust's independent UTF-8 decoder; these vectors are not represented as
a substitute for the official corpus. Full Text case mapping remains E3e.

## Checker, layout, and ABI

The eligibility pass retains fixed unsupported reasons. A type-graph walk
reports `text in collections` when `Ascii`, `Text`, or `Bytes` occurs below an
array/list, including through structs, enums, `Option`, or `Result`. Standalone
text fields and payloads are accepted. Typed builder checks validate the place,
mutability, parameter mode, arity, and argument before reporting `text
builders`; the checker gives in-range `Bytes.push` literals a `byte` context
before range-checking them. Result-context mismatches remain real errors.

The normal aggregate location descriptor remains four lanes:
`(anchor, offset, copies, index)`. A read-only `Text` parameter is also four
lanes total, but its fields are `(data anchor, data offset, byte length,
code-point count)`. The emitter prepares it with `include_geometry=false`;
`%arg.copies` carries byte length and `%arg.index` carries code-point count,
not copy count and lane index. For a stored Text source, the data offset skips
the 16-byte header and the metrics come from the two header lanes. For an
Ascii source passed as Text, the data offset skips its 8-byte header and both
byte length and code-point count equal the ASCII length. This avoids
materializing an Ascii-to-Text copy just to call a read parameter. A copy into
owned Text writes the destination's length, points, and byte lanes, then emits
the test-build invariant assertion.

Fresh constructors, conversions, and concatenations write into the caller's
fresh destination. The emitters account for the Ascii/Bytes 8-byte header and
Text 16-byte header when addressing payload bytes. Function read arguments and
the left operand of Text concatenation retain their required value snapshots.
Method receivers follow the Stage0 descriptor behavior: byte length and code
point count are captured before effectful arguments, while payload access
continues to borrow from the receiver's source location. The source location is
rematerialized after arguments so relocation and in-place payload mutation are
observed without reloading the captured metrics or copying the source-sized
value. `e3c_receiver_order` pins both the live-payload/old-metrics slice result
and the corresponding kind-16 bounds failure. Aggregate copies route through
the destination descriptor rather than inventing a separate payload buffer.

The deferred text-collection eligibility walk memoizes each type in two
contexts: beneath a collection and outside one. Its per-check local byte list is
bounded by `2 * TYPE_TABLE_CAPACITY`; it does not add a persistent compiler
table field or alter an ABI. This avoids revisiting shared struct fields
exponentially in types such as the size-doubling chain while preserving the
collection-ancestry distinction. Cycles encountered while a state is active do
not trigger another recursive traversal; recursive sized types are rejected
before this pass. Depth-limited walks stay unresolved rather than becoming
cached negative results.

The region planner no longer uses `expected[0]` as scratch for total planned
bytes. `CompilerTables.region_current_size` and `region_max_size` hold planner
state independently, so AST node 0 can own a real region slot. Private
`emit_destination_*` fields carry the current aggregate output destination.
`CompilerTables.test_build` separately identifies test-mode code generation;
ordinary functions in a test package keep ordinary return semantics while
Text constructors still get kind-22 assertions.

The E3c type-table allowances are derived from the input bounds:

- `TYPE_TABLE_CAPACITY = MAX_TREE_NODES + 9`: at most one user type per tree
  node plus seven primitive built-in records and the `Utf8Error` and
  `TextError` records. Derived Text/Result and fit/Option instances are
  interned at their syntax nodes; the method and receiver nodes cover the
  second derived record where a method constructs both.
- `ENUM_CASE_TABLE_CAPACITY = MAX_TREE_NODES + 2`: user enum cases plus the
  two `TextError` cases.
- `FIELD_TABLE_CAPACITY = MAX_TREE_NODES + 1`: user fields plus the
  `Utf8Error.valid_up_to` field.

Arithmetic for explicit and derived maxima includes layout headers before
interning and rejects overflow with real errors. The parent-run
`selfhost_text_capacity` integration test passed 11 explicit/derived boundary
cases, including Text/Bytes/Ascii maxima and overflow in conversion,
concatenation, `Result`, `Option`, padding, and `pad_zero` layouts.

The context-passing ABI adds a `requested_step_budget` argument to
`nl_context_create`, immediately after its recursion-budget argument; the
allowance is stored at context prefix offset 22. An
absent budget is `-1` and emits no while-loop check; an explicit budget is
shared across calls in the job. This changes `core/context.nl` and the
selfhosted emitted `main` call only. Legacy C declarations and the frozen
runtime ABI tests remain unchanged. The budget contract tests cover malformed
and overflowing values, duplicates, zero, exact allowance, shared calls, and
an unbudgeted loop over ten million steps.

## Shared functions and files

The implementation extends the existing interfaces rather than changing the
type-kind or location-descriptor contract. Shared edits outside the direct
text helpers include:

- `unsupported_category_for_node` and typed dispatch in `check_one_body` for
  E3c types, TextError, const-byte diagnostics, and deferred text constructs;
- `body_child_expected`, call argument checking, `require_text_read_argument`,
  and `emit_text_parameter_descriptor` for read-only Text ABI and Ascii
  adaptation;
- `emit_aggregate_copy`, aggregate destination selection, field/collection
  result stores, and the region planner for direct results, source snapshots,
  and node-zero relocation safety;
- `mark_struct_helpers` for printing operands of ordered aggregate
  comparisons;
- the parser/checker/lowering path for inclusive slices and checked byte
  literals/casts;
- manifest parsing, `core/context.nl`, and emitted entry-point creation for
  optional step budgets;
- `selfhost/core_files.nl`, regenerated to include the new core modules.

New and focused reports:

- [Deferred text and collection gates](E3c-deferred-report.md)
- [Byte fixture handoff](E3c-byte-fixtures.md)
- [Stored values and conversion fixtures](E3c-value-fixtures.md)
- [Formatting implementation](E3c-format-report.md)
- [Text integer parsing](E3c-parse-report.md)
- [UTF-8 boundary vectors](../../tests/data/unicode/README.md)

## Relocation and measurements

`compiler/tests/selfhost_text_relocation.rs` builds a temporary package with a
generated 1 MiB first-expression Bytes literal, passes it through a helper,
returns a four-byte slice, and checks it under threshold-zero forced movement,
stack verification, and statistics. The child prints `1048576`; it records
`initial=4096`, `reserved=4194304`, `peak_used=2097184`, `growths=1`, and
`relocations=1`. The peak is the source and bounded result plus small headers
and frame state; the test requires it to stay below 3 MiB, ruling out another
source-sized temporary. The fixture passes.

The output-checked Text-heavy, specialized-copy, bootstrap, and stack
measurements are complete; see [E3c-benchmark-report.md](E3c-benchmark-report.md)
for exact commands, best/median/worst samples, spreads, and limitations. The
26-million-iteration Text workload matches its independent stdout oracle on
both compilers. All nine Text-copy shapes pass byte/checksum checks. The
frozen compiler exhausts its predicted data stack for the 4096-byte fixture;
that exact reference preflight failure is recorded, while the selfhost and
copy measurements still pass. Builder execution remains deferred to E3d1.

The committed-HEAD standard benchmark exited 0 at `5ea0a5a`. All four E3a3
regression pairs passed, with best times 0.22s / 0.64s / 0.78s / 0.50s for
calls / increment-heavy / struct-update / tight-list, respectively.

## Validation status

Completed focused evidence:

- Fresh selfhost source build with `CARGO_TARGET_DIR=/home/ben/.cache/next-lang/target`,
  `ulimit -v 8000000`, and the release reference at
  `/home/ben/.cache/next-lang/target/release/nlc`.
- A 42-package focused O1 comparison, zero mismatches: 15 builds, 11
  diagnostics, one intentional rejection, six unsupported cases, eight
  expected outputs, and one expected rejection. It included all
  `tests/e3/e3c_*`, the byte match and no-catchall cases, byte builder
  regressions, and promoted Text/view/loop cases.
- The byte/deferred-text owner reran a 15-package selector with the release
  reference: one build, four diagnostics, ten unsupported cases, zero
  mismatches, including valid `Bytes.push(0/255)`, invalid `push(300/-1)`,
  and enum/Option text-collection gates.
- The release-reference O1 selector for `tests/e2/size_doubling_chain` and
  `tests/e3/e3c_receiver_order` matched both packages with zero mismatches in
  9.54 seconds. This addresses the chain timeout seen in the first complete
  suite; the fresh complete-suite rerun subsequently passed.
- Parent-run contract checks passed: core embedding freshness, context offsets,
  interfaces, harness contracts, step-budget parsing/runtime cases, 11 text
  capacity cases, the 1 MiB forced-relocation case, and 306 UTF-8 vectors with
  three injected-corruption kind-22/status-70 checks.
- `git diff --check` passed before this report was drafted.

Final correctness acceptance passed on the frozen source key
`7d963a47d2d217d00b56cdd413b2f4da6c96c55484cfb0fadf8bddad4b616a85`:

```sh
export CARGO_TARGET_DIR=/home/ben/.cache/next-lang/target-takeover-e3c-20261028
ulimit -v 8000000
NLC_FRONTEND=selfhost NLC_LONG_TESTS=1 NLC_E1_GENERATED_COUNT=64 \
NLC_TEST_JOBS=4 timeout 3600 cargo test --offline --release -q --test '*'
```

The complete command exited 0. It includes the O1 and O3 comparison of all 728
registered packages and 256 generated packages at zero mismatches, O1/O3 forced
relocation, expanded UTF-8 checks, capacity boundaries, manifest budgets, and
the real 1 MiB relocation case. The earlier broad run found the exponential
type walk; the first generated audit found receiver evaluation behavior. Both
were fixed without increasing timeouts or removing generated expressions.

`cargo fmt --all -- --check`, Python syntax checks for changed harnesses and
the benchmark runner, `bash -n scripts/compare-selfhost.sh`, and
`git diff --check` also passed. The full Stage0 Rust suite is not required
because `compiler/src/` is unchanged.

The installed pre-commit hook also passed the complete default selfhost suite
on exactly the staged tree in 518 seconds before source commit `5ea0a5a`.
Text-heavy, specialized-copy, bootstrap, stack, and committed-HEAD standard
performance measurements passed; no E3a3 pair regressed. Exact results and
limits are in [E3c-benchmark-report.md](E3c-benchmark-report.md).

## Awkwardness, limits, and next step

The main implementation constraint was bridging Text's inline stored layout
and borrowed read-parameter form without copying large values or changing the
four-lane location descriptor. The read view reuses the descriptor's last two
parameters for byte length and code-point count instead of adding two more
lanes. Direct destination plumbing avoids full-sized intermediates. Generated
boundary vectors were necessary because the required official Unicode data
could not be vendored without network access.

E3c leaves E3d1 builder transactions, `+=`/`try_append` execution,
`Bytes.push`, `take`, and `grow` parameters deferred; E3d2 owns unbounded
collections and starting-size estimation; E3d3 owns interpolated strings;
E3e owns const values, nested/text collection lanes, reachable-only emission,
and Unicode Text case mapping. General numeric refinements, aliases, numeric
`fit`, and unrelated parsers remain outside E3c.

The next implementation step is E3d1. Keep the fixed `text builders` and
`text in collections` boundaries in place until those later steps implement the corresponding
storage and lifetime rules.

The agent-created `.scratch-e3c-debug` and `.scratch-e3c-memory-debug`
directories were removed after validation. The inherited `.scratch-e3c-text-smoke`
and `e3c-scratch` directories remain preserved as evidence. None are report
inputs or commit artifacts.
