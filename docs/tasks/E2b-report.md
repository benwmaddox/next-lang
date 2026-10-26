# E2b report: enums and `match` in the self-hosted compiler

## Result

The self-hosted compiler now accepts user enums with or without payloads and
`match` expressions and statements over enums, integers and booleans. Enum
values pass through the E2i type-kind, storage-location, helper-registry and
hidden-result interfaces. `Option`, `Result`, `?`, `??`, and the core error
wrappers remain unsupported for E2c. No core hooks were added, mutable globals
remain unsupported, and no file under `compiler/` changed.

Enum layouts use a four-byte `i32` tag at offset 0. Each case's payload parts
overlap, start at offset 4, and align like struct fields. The enum alignment is
at least 4 and its size is the largest case end rounded to that alignment. For
example, `Shape { Circle(int), Wide(long), Pair(bool, int), Nested(Small),
Empty, Unit(()) }` has alignment 8 and size 16: `Circle` has its integer at
offset 4, `Wide` its long at offset 8, `Pair` its bool and int at offsets 4
and 8, and `Unit(())` occupies no payload bytes. The 4096-byte fixture wraps a
4088-byte struct at offset 8 and builds; a 4096-byte payload becomes a 4104-
byte sum and is unsupported. A second over-limit fixture reaches 4104 only
after payload and final alignment padding. The over-limit fixture constructs
its sum through an unqualified case in an unannotated `let`, pinning that
inference does not bypass enum size eligibility.

The checker registers enum names before payloads, checks every enum payload
before struct fields, then runs the shared infinite-size walk. It resolves
constructors by expected enum, unique case, then ambiguity, with function
calls taking precedence. Match arms are checked in source order: pattern
compatibility, qualifier and arity, reachability/duplicates, payload bindings,
body, reachable arm type, then exhaustiveness. Sum exhaustiveness reports
missing cases in declaration order; booleans report `true` then `false`; integer
matches require `_`. The registration-order and multi-file fixtures pin the
phase boundaries.

Construction evaluates payload expressions left to right into a fresh
temporary, stores each part at its aligned offset, and writes the tag. Copy,
equality and print helpers dispatch on the active tag and touch only active
parts. Equality compares tags first and short-circuits through the active
payload. Printing matches stage 0's case spelling and punctuation. Unit payloads
have no storage and print as `()`. Enum fields, read parameters, results,
constructors, and aggregate match results use the shared aggregate-location
operations. Match evaluates its scrutinee once, copies named payload bindings
at arm entry, joins scalar values through a phi over real predecessors, and
copies aggregate results into a destination slot. `never` arms do not join;
an all-`never` match emits no join block.

## Classification

The E2i baseline was 529 packages: 48 build, 64 diagnose, 417 unsupported.
The final table has 547 packages: 52 build, 85 diagnose, 410 unsupported.
The net movement is nine existing packages from unsupported to diagnose, plus
18 new E2b packages (4 build, 12 diagnose, 2 unsupported).

Existing movements, all `unsupported` → `diagnose`:

- `tests/run/ambiguous_case`
- `tests/run/bool_match_non_exhaustive`
- `tests/run/integer_match_no_catchall`
- `tests/run/match_duplicate`
- `tests/run/match_empty`
- `tests/run/match_non_exhaustive`
- `tests/run/match_payload_arity`
- `tests/run/match_unreachable`
- `tests/run/unknown_enum_case`

New build packages: `tests/e2/enum_match_runtime`,
`tests/e2/enum_match_never`, `tests/e2/enum_multifile`, and
`tests/e2/enum_size_exact`.

New diagnostic packages: `enum_constructor_ambiguity`,
`enum_constructor_arity`, `enum_duplicate_case`, `enum_registration_order`,
`enum_recursive`, `enum_recursive_mutual`, `enum_unknown_payload`,
`match_arm_type`, `match_bool_duplicate`, `match_duplicate_binding`,
`match_integer_duplicate`, and `match_qualifier`, all under `tests/e2/`.

New unsupported packages: `tests/e2/enum_size_over` and
`tests/e2/enum_size_padding`. Rust builds these values, while E2b rejects the
self-hosted values over its 4096-byte limit. Every new package has Rust
`expected.stdout`, `expected.stderr`, and `expected.exit` oracles. The two size
packages also pin their exact self-hosted unsupported diagnostic in
`expected.selfhost.stderr`. No existing expected output changed.

## Limits and measurements

`limits.nl` now gives the case and payload tables capacities bounded by
`MAX_TREE_NODES`. The IR limit adds a per-node term, the existing 256-byte
table term, a 768-byte E2b table extension, source bytes, and fixed sections.
Enum declarations, case records, and payload records correspond to distinct
syntax nodes, so their combined count is bounded by the node limit. The
640-byte node term covers constructor and match use sites; the table terms
cover helper bodies and labels.

The helper-bound comparison measured 304,110 bytes at depth 20 and 343,894 at
depth 40, a 39,784-byte increase; its linear-growth check passed. `nlc inspect
stacks selfhost` reports a data-stack worst case of 6,859,732,537 bytes and a
reservation of 6,859,735,040 bytes. Against E2i, the computed bound increases
by 1,744,000,016 bytes and the reservation by 1,743,998,976 bytes. The native
stack worst case is 8,054,624 bytes. The stack-contract fixture now pins these
values and checks that the compiler remains below 7 GB, within the task's
8,000,000 KiB process limit.

The five-sample aggregate benchmark contains an enum constructor and a payload
match in each of 1.5 billion loop iterations. Both compilers print the checksum
`9000000000`. The input is 546 source bytes; self-host IR is 270,404 bytes
(495.245 bytes/source byte) and Rust IR is 13,896 bytes (25.450 bytes/source
byte). Measurements ran on WSL2 Linux 6.6.87.2, Intel Core Ultra 9 185H, Ubuntu
clang 18.1.3, pinned logical CPU 0, O1, the core runtime, the bench lock, and an
8,000,000 KiB virtual-memory limit. RSS is in KiB. Each row reports min/median/
max across five direct process runs.

| Phase | Elapsed seconds | Peak RSS |
| --- | ---: | ---: |
| Rust nlc bootstrap building selfhost | 8.280 / 8.400 / 8.500 | 189,632 / 189,800 / 189,812 |
| Whole selfhost build, warm cache | 0.510 / 0.540 / 0.620 | 105,060 / 105,240 / 105,244 |
| Selfhost compile to IR | 0.080 / 0.080 / 0.080 | 151,712 / 151,712 / 151,712 |
| `link-ir` | 0.190 / 0.200 / 0.250 | 86,944 / 86,944 / 86,944 |
| Rust whole build | 0.430 / 0.490 / 0.510 | 105,060 / 105,068 / 105,244 |
| Selfhost aggregate runtime | 1.600 / 1.610 / 1.660 | 1,760 / 1,760 / 1,760 |
| Rust aggregate runtime | 1.840 / 1.860 / 1.890 | 1,760 / 1,760 / 1,760 |

The scalar regression benchmark generated 10,000 functions from 500,042 source
bytes. Its self-host IR is 6,413,374 bytes (12.826 bytes/source byte), and its
Rust IR is 6,564,786 bytes (13.128 bytes/source byte). Relative to the E2a
report, self-host IR grew by 308 bytes (0.0048%) and Rust IR was unchanged.
The following phase measurements use the same five-run method and environment;
the direct compile-to-IR row is separate from whole-build time.

| Phase | Elapsed seconds | Peak RSS |
| --- | ---: | ---: |
| Selfhost compile to IR | 1.340 / 1.370 / 1.390 | 176,176 / 176,176 / 176,176 |
| Rust compile to IR | 0.210 / 0.210 / 0.220 | 82,572 / 82,748 / 82,928 |
| Whole selfhost build, warm cache | 6.600 / 6.750 / 6.790 | 205,012 / 205,012 / 205,016 |
| `link-ir` | 5.640 / 5.710 / 5.830 | 245,348 / 245,348 / 245,352 |
| Rust whole build | 6.020 / 6.350 / 6.460 | 186,132 / 186,144 / 186,144 |

The empty-program runtime was 0.000210 / 0.000227 / 0.000315 seconds for
selfhost and 0.000503 / 0.000529 / 0.000552 seconds for Rust, measured with a
high-resolution process timer; both peaked at 1,760 KiB. GNU `time` rounds
those empty runs to 0.00 seconds.

## Deviations and remaining work

No stage-0 reference change was needed. The parser represents a case pattern's
qualifier as a direct token while a qualified constructor uses the extra-token
table; the checker and diagnostics account for that distinction. The binding
spec excludes guards, so guarded patterns remain syntax errors in both
compilers.

The required full suite exposed a harness edge case: `manifest_bad` is an
expected status-3 manifest tool failure without the word `error`, and the
comparator rejected identical Rust/selfhost results. The comparator now allows
that exact matching result only for the recognized manifest case.

E2c still needs built-in `Option` and `Result` layouts and constructors,
propagation and coalescing, their methods and diagnostics, and the core syscall
error wrappers. Existing Option/Result/`?`/`??` packages remain classified as
unsupported after E2b. No hooks were necessary for E2b.

## Validation

- `NLC_FRONTEND=rust cargo test --offline`: passed.
- `NLC_FRONTEND=selfhost cargo test --offline`: passed.
- `cargo test --offline --test selfhost_interfaces`: passed.
- `cargo fmt --all -- --check` and `git diff --check`: passed.
- `scripts/compare-selfhost.sh --build`: 52 build, 85 diagnose, 410 unsupported; zero mismatches.
- `NLC_LONG_TESTS=1 scripts/compare-selfhost.sh --build`: same counts at O1 and O3, zero mismatches, including the C runtime leg.
