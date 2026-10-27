# Stage 0 fix 5 report

Ben's stage-0 release fixes, 2026-10-27. Changes are limited to the Rust checker,
new test packages, their appended classification rows, and this report.

## Collection count joins

In `compiler/src/checker.rs`, `check_match` now checks every arm from the same
entry count facts and joins only the facts shared by all arms that can continue.
`check_if` uses the same conservative join. `finish_loop_push_proofs` joins the
pre-loop and post-body facts when a loop can run zero times, preserves the
pre-loop facts for an exact zero-iteration loop, and uses a post-body fact only
when the range proves an iteration and the body has no `break` or `continue`
path. The existing bounded-push proof still accounts for the maximum loop
iteration count.

Before the fix, a clear in a zero-iteration loop or a match arm that was not
selected could leave a false zero count. The later unhandled push was then
emitted without its capacity check; the review reproduction printed `[5, 7]`
from a capacity-one list. The new `s0fix5_count_loop`, `s0fix5_count_match`, and
`s0fix5_count_break` packages now reject the later push as an unhandled
`Result<(), Full>`. The cases cover a zero-iteration loop, an unselected match
arm, and a `break` path before a clear.

`s0fix5_count_valid` covers if/else-if/else and match joins, paths where every
arm clears before pushing, exact zero- and one-iteration loops, and an
unhandled push inside a loop known to run zero times. Rust Stage 0 accepts and
prints `[10, 40]`, `[2, 3]`, `[6]`, `[8]`, `[4]`, `[12]`, and `[9]` on separate
lines. Its `expected` classification records the current selfhost output,
which omits the first push in the conditional and match examples.

## `grow` width equality

In `compiler/src/checker.rs`, `grow_width_matches` and `grow_width_error` are
used at both `grow` call paths: `check_direct_function_call` and
`check_indirect_call`. The argument must have exactly the parameter's declared
maximum: bytes for `Ascii` and `Bytes`, and both bytes and code points for
`Text`. `string_width_fits` remains unchanged for assignments and stores.

Before the fix, the inverted `actual <= expected` check accepted smaller
arguments, allowing the callee to write past their reservation, and refused
larger arguments. `s0fix5_grow_ascii_small`, `s0fix5_grow_bytes_small`,
`s0fix5_grow_text_codepoints`, `s0fix5_grow_text_bytes`, `s0fix5_grow_field`,
and `s0fix5_grow_indirect` now reject mismatched maxima. The field case, which
previously could segfault, is rejected at the call. `s0fix5_grow_ascii_large`
pins refusal of a larger argument. The errors say `exactly` and include the
expected Text code-point maximum. `s0fix5_grow_valid` verifies equal-width
direct and indirect calls and an equal-width struct field; it prints `ab`,
`abb`, `ab`, `9`, `aé`, and `255`.

## Byte literal range

In `compiler/src/checker.rs`, `byte_literal_out_of_range` checks unsuffixed
integer literals in the `Bytes.push` path before lowering. It rejects literals
outside 0 through 255 and includes the value in the existing checked-cast
diagnostic shape.

Before the fix, `discard raw.push(300)` built and stored 44. The new
`s0fix5_byte_invalid` and `s0fix5_byte_negative` packages reject 300 and -1
with diagnostics naming those values. `s0fix5_byte_valid` still builds and
prints 0 and 255.

## Packages and classifications

The 15 new packages are `s0fix5_count_loop`, `s0fix5_count_match`,
`s0fix5_count_break`, `s0fix5_count_valid`, `s0fix5_grow_ascii_small`,
`s0fix5_grow_ascii_large`, `s0fix5_grow_bytes_small`,
`s0fix5_grow_text_codepoints`, `s0fix5_grow_text_bytes`, `s0fix5_grow_field`,
`s0fix5_grow_indirect`, `s0fix5_grow_valid`, `s0fix5_byte_invalid`,
`s0fix5_byte_negative`, and `s0fix5_byte_valid`. Their rows were appended to
`tests/e1/classification.tsv` according to current selfhost behavior:
11 `unsupported` and 4 `expected`.

No existing package's result changed, and no existing package was edited.

## Verification

- `scripts/compare-selfhost.sh --build --only 'tests/e3/s0fix5_*'` — passed:
  11 unsupported, 4 expected-output packages, 0 mismatches.
- `NLC_FRONTEND=rust cargo test --offline --release -q` — passed.
- `NLC_FRONTEND=selfhost cargo test --offline --release -q --test '*'` — passed.
- `cargo fmt --all -- --check` — passed.
- `git diff --check` — passed.
