# T18 report: integer parsing, formatting, and text helpers

Implemented T18 across checking, typed IR, LLVM emission, and the C runtime. `str`, `str_hex`, and `str_bin` format signed `int` and `long` values with conservative maxima from their ranges. `pad` and `pad_right` work on Ascii and Text; Text padding counts code points. `pad_zero` keeps a negative sign before its zero fill. These expressions stream into append destinations, including `out += pad(str(x), width)`.

Added `parse_int`, `parse_long`, `parse_int_radix`, `parse_long_radix`, and `parse_int_literal` for Ascii, Text, Bytes, and their slices. Parsing checks signs, radix digits, digit separators, and overflow and returns `none` for malformed input. Added ASCII-only byte classification and case conversion methods, plus `abs`, `min`, `max`, and `clamp` with range propagation. `abs` reports overflow for the numeric minimum.

## Acceptance coverage

- `tests/test/t18_number_text` covers signed extrema, radices, zero, malformed and overflowing input, Text non-ASCII digits, slices, mixed string maxima, multi-byte Text padding, byte helpers, and refined numeric ranges.
- `tests/run/t18_logsum_alignment` compiles the report expression with a concrete `top_by_value` stand-in and prints aligned columns. Other run fixtures cover minimum-value `abs` overflow, unbounded padding width, invalid radix, and invalid clamp bounds.
- Parse snapshots cover the new fixtures and malformed source integer separators.
- The checker performance test compiles 1,000 `joined += pad(str(42), 3)` statements. With `NLC_TIMING=1`, this generated package compiled in **25.0 ms**, below the two-second bound.

The task asks for 1,000 chained formatting concatenations. A single expression exceeds the parser's 1,000-level expression nesting limit because each `pad(str(...))` call adds nesting. I used 1,000 append statements instead, which exercises the requested destination append path in a valid package.

## Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt -- --check` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — passed, including all language fixtures and parser snapshots.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target scripts/update-parse-dumps.sh --update` — passed.
- `git diff --check` — passed.

## Running and remaining work

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` runs all compiler and language tests.
- `nlc test tests/test/t18_number_text` runs the T18 test blocks; `nlc run tests/run/t18_logsum_alignment` runs the aligned report example.
- No T18 acceptance work remains. `str_fixed` stays with the later floating-point task, as specified.

## Choices

- I chose the global `abs(x)` form to match the existing `str(x)` call style.
- `parse_int_literal()` returns `Option<long>` so it covers the language's long literal range. It accepts the language's decimal, `0x`, and `0b` forms without suffixes. Signs are unary operators in source syntax, so this method parses the unsigned literal text; `parse_int()` and `parse_long()` accept explicit signs.
- `parse_int_radix` takes a constant radix restricted to 2, 8, 10, or 16, matching the task's `parse_int_radix(16)` form.
- Added the corresponding `parse_long_radix` form so formatted long extrema can round-trip in the non-decimal bases too.
- No external crates were added. Floating-point formatting remains outside T18, as specified by the task.
