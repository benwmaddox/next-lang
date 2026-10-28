# E3b fix round 1 report

Implemented the findings from `docs/reviews/opus-E3b-r1.md` in the self-hosted
compiler. New regression packages are under `tests/e3/e3b_fix1_*`; no existing
test package was edited.

## Findings and fixes

### C1 — branch and loop count joins

Added count-change snapshots and rollback/join helpers in `selfhost/compiler.nl`
(around `set_binding_collection_count`, `begin_collection_count_join`, and
`finish_loop_count_snapshot`). `if` and `match` now check each reachable branch
from the same baseline, then keep a count only when the reachable results
agree; differing or unknown facts become unknown. `for`, `for each`, and
`while` now join the count before the loop with the count after its body. This
prevents a `clear()` in a checked body from becoming a post-loop fact when the
loop may run zero times.

Fixtures and stage-0 results:

- `e3b_fix1_c1_if` (`build`): `[5]`.
- `e3b_fix1_c1_loop` (`build`): `[5]`.
- `e3b_fix1_c1_match` (`expected`): stage 0 prints `[5, 7]` for a capacity-1
  list; the corrected expected output is `[5]`. The stage-0 match result is
  itself unsound, so it is not used as this fixture's oracle.

### C2 — invalid loop push proofs

`selfhost/collections.nl` now refuses a loop proof if its body can insert,
remove, pop, clear, assign to the list, or pass it to a `write` parameter.
`loop_push_is_proven` also requires a known current count. At loop exit, the
snapshot join preserves a push proof's final count only if the body left a
known fact; other differing before/after counts become unknown. This prevents
`finish_loop_push_proofs` from restoring a count the body invalidated.

Fixtures and stage-0 results:

- `e3b_fix1_c2_insert`: `[1, 0, 0, 1]`.
- `e3b_fix1_c2_write`: `[0, 1, 1, 1]`.
- `e3b_fix1_c2_assign`: `[8, 8]`.
- `e3b_fix1_c2_pop`: `[9]`.
- `e3b_fix1_c2_pop_unhandled` (`diagnose`): stage 0 and selfhost reject the
  unhandled `Full` result at `main.nl:11:5` (exit 2).

The four runtime fixtures are selected by relocation checks and each relocates
while the tested list is live.

### H1 — proven push at an `if` block tail

The block checker marks a proven-success push tail as unit in
`selfhost/compiler.nl`; the block emitter now evaluates that tail without
copying a nonexistent aggregate result. Fixture `e3b_fix1_h1_tail` matches
stage 0: `[1]`. It also relocates under the forced-move check.

### H2 — statements in `if` and match blocks

`emit_expr_linear` delegates non-tail block statements to the shared
`emit_function_body` dispatcher. If any statement kind reaches the emitter's
fallback, it records the node kind and `selfhost/main.nl` reports an internal
compiler error instead of silently skipping the statement.

`e3b_fix1_h2_blocks` covers `discard`, `for`, `for each`, and nested blocks in
an `if`, `else if`, `else`, and match arm. Stage 0 prints `[1, 2, 3, 4]` and
`12`. `e3b_fix1_h2_while` covers `while` in each of those branch positions;
stage 0 rejects its unsupported syntax at `main.nl:9:21`, while its
hand-written expected output is `4`. Both runtime fixtures relocate under the
forced-move check.

### H3 — array-literal list counts

Removed array literals as a source of initial list count facts in
`selfhost/compiler.nl`; only `list {}` and defaults seed a count. Stage 0 and
selfhost diagnose `e3b_fix1_h3_array_list` at `main.nl:3:5`: the `Full` result
must be handled (exit 2). `e3b_fix1_h3_array_list_move` handles the result and
prints `[1, 2]`; it relocates under the forced-move check.

### M1 — expected type for bitwise literals

Bitwise child inference now lets the expected numeric type take precedence
over an unsuffixed literal's default `int`. `e3b_fix1_m1_shift` matches stage
0 and prints `1099511627776` for `let value: long = 1 << 40`.

### M2 — unsuffixed comparison literal with `long`

Comparison inference now uses the known numeric operand to type an
unsuffixed integer literal. `e3b_fix1_m2_compare` matches stage 0 and prints
`true`, `true`, `true` for the `long` comparisons.

### L1 — per-job while step budget

Added `step_budget` to `DataStackContext` in `core/context.nl`; it is
zero-initialized with the job context. Every emitted `while` step calls the
shared context helper, so calls and sequential loops spend from one job
allowance. Neither DESIGN nor the spec states a numeric limit, so the existing
10,000,000-step limit is retained.

`e3b_fix1_l1_sequential` expects and prints `4000000` twice. The runaway
`e3b_fix1_l1_runaway` exits 1 with `main.nl:2:5: loop step budget exhausted`
(kind 23). `e3b_fix1_l1_cross_call` runs a 6,000,000-step loop in a helper
twice and exits 1 at `main.nl:3:5` with the same failure. Stage 0 rejects all
three at the first `while` with `expected a newline or ';' between statements`
(exit 2); the expected-class results are hand-written for the DESIGN behavior.

### L2 — optional-call receiver snapshot

`emit_optional_call_start` now snapshots the optional receiver payload before
arguments run; invocation uses that snapshot. The snapshot supports aggregate
receivers and preserves field offsets when materializing a native address.
`e3b_fix1_l2_receiver` matches stage 0: `some(1)`, then
`some(Item { value: 9 })`.

## Classifications and supporting change

Added 19 entries to `tests/e1/classification.tsv`: 12 `build`, 5 `expected`,
and 2 `diagnose`. `e3b_fix1_c1_loop` is `build` because its output matches
stage 0. The match-count case and the stage-0-unsupported `while` cases use
`expected`; the other `expected` packages cover the L1 loops. The two
diagnostics cover H3 and the unhandled-pop-result case.

The new count logs raise the selfhost compiler's exact attributed stack bound.
Updated `compiler/tests/stack_contracts.rs` to pin the measured bound at
7,248,095,393 bytes and reservation at 7,248,097,280 bytes; both remain below
the 8,000,000,000-byte limit.

## Verification

- Focused stage-0 comparison: 19 packages; 12 builds and 2 diagnoses matched,
  plus 5 expected-class outputs matched; zero mismatches.
- `NLC_LONG_TESTS=1` comparison: the same 19 packages passed at O1 and O3 with
  zero mismatches.
- Focused forced-move relocation: all 11 C/H runtime fixtures relocated at
  O1. Long relocation passed at O1 and O3; 11 of 17 selected runtime packages
  relocated at each level.
- `NLC_FRONTEND=selfhost cargo test --offline --release -q --test '*'`: passed.
- `cargo fmt --all -- --check` and `git diff --check`: passed.

The first full-suite attempt caught the stale exact stack-bound assertion;
after updating it, the focused stack-contract test and final full suite passed.
No further implementation bug beyond these findings was found.
