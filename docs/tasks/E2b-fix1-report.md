# E2b fix round report

This round addresses Sol's five E2b review findings, checks the shared paths
against E2c's Option and Result constructors, and implements the binding rule
that a declaration cannot shadow a visible name.

## Finding 1: aggregate sources in struct fields

Struct-field initialization now uses the shared `aggregate_source_kind` and
`aggregate_source_id` classification instead of a second, incomplete
classification. That lets the field copier distinguish local storage from
nullary enum and sum constructors, including `E.A`, bare `A`, and `none`.

`tests/run/enum_aggregate_sources` covers qualified and bare nullary cases in
struct fields, nested literals, defaults, and enum payloads. It also pins the
E2c crash case:

```next
struct Box { a: Option<long>, b: long }
let b1 = Box { a: none, b: 1L }
print(b1)
```

Stage 0 prints
`Box { a: none, b: 1, inner: Inner { state: A, maybe: none } }` in the
expanded fixture, with matching selfhost output.
`tests/run/sum_aggregate_constructors` adds `some(Record)`, `ok(Record)`, and
`err(Record)` payloads so the shared classification is covered for the built-in
sum constructors too.

## Finding 2: terminating constructor payloads

Constructor emission now propagates non-fallthrough payload expressions. The
constructor frame is closed without emitting a payload store, tag, later
arguments, or instructions after the exit. Child fallthrough facts are shared
with the enclosing expression emitter.

`tests/run/enum_terminating_payloads` checks `E.C(return 6)`, `continue`, and
`break`, `some(return x)`, `ok`/`err` returns, and `?` inside a payload. It is a
build fixture whose stdout matches Stage 0.

## Finding 3: no name shadowing

`selfhost/compiler.nl` now reserves package functions, types, constants,
unique bare-usable enum cases, and built-ins (`print`, `some`, `none`, `ok`,
`err`, plus the built-in file-system error cases such as `NotFound`). It checks
declarations against those names and the lexically visible locals, parameters,
loop variables, and match bindings. Same-scope redeclarations remain errors;
sibling scopes can reuse a name. Calls resolve a visible local before package
functions and enum constructors, preserving Stage 0's behavior for calls whose
names do not violate the new rule.

`tests/run/shadow_*` provides rejects fixtures for `let`, `var`, parameters,
loop variables, match bindings, package functions/types/constants, enum cases,
and the `print`, `some`, `none`, `ok`, and `err` names.
`tests/run/shadow_builtin_not_found` pins a built-in file-system case as well.
The shadow fixtures use the new `rejects` class:
Stage 0 builds each package, while selfhost exits 2 with an error and no IR.
`tests/run/shadow_sibling_scopes` is a build fixture. The
`tests/run/local_constructor_collision` and
`tests/run/local_ambiguous_constructor_collision` diagnostics pin local-first
call resolution, including the ambiguous case name that is not bare-usable.

Existing packages moved to `rejects`:

- `tests/e1/functionshadow`
- `tests/e2/enum_match_runtime`, `tests/e2/reference_default_shadow`,
  `tests/e2/reference_unit_erasure`
- `tests/run/arithmetic`, `tests/run/div_min_div_neg_one`, `tests/run/enums`,
  `tests/run/loops`, `tests/run/mod_min_div_neg_one`, `tests/run/t04_core`,
  `tests/run/t06_core`, `tests/run/t06_discard_capacity`,
  `tests/run/t07_zero_capacity`, `tests/run/t13_stack_contracts`,
  `tests/run/t16_text_output`, `tests/run/t17_worked_reservation`,
  `tests/run/t20_args`, `tests/run/t20_channels`, `tests/run/t20_probe`,
  `tests/run/t23_live_elements`, `tests/run/t29_inline_text_fields`
- `tests/test/enums`, `tests/test/t12_sorting`, `tests/test/t16_text_bytes`,
  `tests/test/t18_number_text`, `tests/test/t20_io`,
  `tests/test/t20_result_error`, `tests/test/t24_byte_escape`,
  `tests/test/t25_bytes`,
  `tests/test/t32_number_format`

`tests/run/t16_bytes_view_store`, `tests/run/t18_unbounded_width`, and
`tests/run/t20_args_without_grant` remain `diagnose`: Stage 0 already rejects
them for unrelated errors, so they cannot satisfy `rejects`' requirement that
Stage 0 build the package. No existing package source, expected output, or
parse dump was edited. In particular, `tests/run/enums` retains its optional
chaining (`?.`) coverage; it is rejected by the earlier shadow check.

The required B1 source audit found these names in the existing
`selfhost/*.nl` and `core/*.nl` code: core `bytes`/`count`, selfhost `args` and
`width`, and compiler/parser locals `result_ty`, `bound_index`, `kind`,
`source`, `return_ty`, and `first`. The conflicting bindings were renamed
(`data`/`contents`/`byte_count`, `arguments`, `unit_width`, and more specific
local names). The selfhost source now passes its no-shadow precheck, and a
fixture build with embedded core succeeds.

The compiler tables also increase the measured selfhost data-stack bound. The
exact stack-contract test now pins a 6,943,732,617-byte worst case and a
6,943,735,808-byte reservation, both below the 7 GB acceptance bound.

## Finding 4: helper discovery follows resolved constructors

Helper discovery now classifies each resolved call from its checked function,
type, and constructor facts rather than from the callee spelling. A case named
`print` therefore registers the copy helper for its aggregate payload.

`tests/run/enum_builtin_print_payload` covers the `E.print(S)` collision from
the review. `tests/run/sum_aggregate_constructors` also verifies copy helpers
for `some`, `ok`, and `err` payloads.

## Finding 5: indexed enum lookup and scaling

Enum types retain stable type IDs in `enum_type_ids`, and an interned-name
index (`enum_type_by_name`) resolves qualified constructors directly. Case
lookup takes the stable type ID, avoiding repeated scans that translated enum
ordinals back into type-table IDs.

The comparison harness compiles 1,600, 3,200, and 6,400 distinct enum
constructors. It takes the median of three IR-build timings per size and
checks that per-enum cost does not grow by more than 1.75x on a size doubling;
this catches the old quadratic lookup growth while allowing timing noise.

| Distinct enums | Sol's pre-fix selfhost IR time | Fixed default run | Fixed long run |
| ---: | ---: | ---: | ---: |
| 1,600 | 4.626 s | 0.165 s | 0.168 s |
| 3,200 | 35.200 s | 0.309 s | 0.313 s |
| 6,400 | >45 s timeout | 0.892 s | 0.842 s |

## E2c diagnostics

The E2c `none` aggregate crash is pinned by `tests/run/enum_aggregate_sources`.
The unused-Result message now closes the `??` quote. The new
`tests/run/unused_result_message` diagnose fixture pins the corrected
`'??' where supported` text without changing the existing
`tests/run/t20_unhandled_result` package.

## Acceptance

- `NLC_FRONTEND=rust cargo test --offline`: passed.
- `NLC_FRONTEND=selfhost cargo test --offline`: passed.
- `NLC_FRONTEND=selfhost cargo test --offline --test selfhost_interfaces`:
  passed.
- `cargo fmt --all -- --check`: passed.
- Default comparison: passed with zero mismatches; 57 builds, 115 diagnoses,
  45 rejects, 356 unsupported packages; 8 seeded builds and 8 seeded
  diagnostics matched.
- Long comparison: passed at O1 and O3 with zero mismatches; each level had
  57 builds, 115 diagnoses, 45 rejects, and 356 unsupported packages; 8 seeded
  builds and 8 seeded diagnostics matched at each level.
- `git diff --check`: passed.
