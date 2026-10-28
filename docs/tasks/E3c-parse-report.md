# E3c integer parsing report

This slice adds the five integer parsing methods required by the T18 parsing
contract to the self-hosted compiler: `parse_int()`, `parse_long()`,
`parse_int_radix(radix)`, `parse_long_radix(radix)`, and
`parse_int_literal()`. No `parse_long_literal()` API was introduced.

## Semantics and implementation

`parse_int()` returns `Option<int>` and `parse_long()` returns `Option<long>`.
Both parse decimal text and accept an optional leading `+` or `-`.
`parse_int_radix(radix)` and `parse_long_radix(radix)` have the same sign and
separator rules, with a constant radix of 2, 8, 10, or 16. Radix methods do
not recognize prefixes. All four methods accept `Ascii`, `Text`, and `Bytes`
values, including slices.

`parse_int_literal()` returns `Option<long>`. It accepts unsigned decimal,
`0x`/`0X` hexadecimal, and `0b`/`0B` binary input, with no sign or source
literal suffix. Its hexadecimal and binary forms parse as positive `long`
magnitudes: `0x80000000` yields `2147483648`, and `0xffffffff` yields
`4294967295`; they are not reinterpreted as signed 32-bit patterns.

Digits are ASCII-only. Underscores are accepted only between valid digits;
whitespace, malformed separators, invalid digits, prefixes in radix methods,
and overflow return `none`. The implementation scans the input using its
address and byte length, accumulates negatively to represent the signed
minimum safely, and writes the `Option` directly into its destination. It
does not call the C runtime or allocate a parsing buffer. The checker rejects
nonconstant or unsupported radices at the radix expression's source position.

The implementation is in `selfhost/parse_number.nl` and
`core/parse_number.nl`; the normal core embedding step includes the helper in
`selfhost/core_files.nl`.

## Directed fixtures

| Package | Class | Coverage |
| --- | --- | --- |
| `e3c_parse_valid` | `build` | Decimal and radix parsing, signs and separators, int/long minima and maxima in bases 2, 8, 10, and 16, literal prefixes and high-bit values, and parsing `Ascii`, `Text`, and `Bytes` slices. |
| `e3c_parse_invalid` | `build` | Empty input, lone and repeated signs, whitespace, malformed separators, forbidden prefixes and suffixes, invalid/non-ASCII digits, int/long overflow by one, and `parse_int_literal()` overflow. It prints `true` only when every malformed value is `none`. |
| `e3c_parse_bad_radix` | `diagnose` | Compile-time rejection of radix 3. Its Stage0 oracle is status 2, empty stdout, and `main.nl:2:32: error: parse_int_radix supports only 2, 8, 10, or 16`. |

## Stage0 probes

The frozen Stage0 executable used was
`/home/ben/.cache/next-lang/target/release/nlc`, not the repository's
potentially stale `target/release/nlc`. `e3c_parse_valid` ran with exit status
0 and its output matched the checked-in 35-line oracle, including the four
signed extrema in each supported radix. `e3c_parse_invalid` ran with exit
status 0 and printed `true`. The Stage0 build diagnostic for
`e3c_parse_bad_radix` matched its checked-in real-error oracle.

The parser helper source passed a fresh Stage0 selfhost-source build. The
final integrated comparison below also performed a fresh current-source
selfhost build.

## Focused selfhost comparison

The final focused comparison used:

```sh
scripts/compare-selfhost.sh --build --only "tests/e3/e3c_*" \
  --only "tests/e1/unsupported_type_ascii_*" \
  --only "tests/e1/unsupported_type_bytes_*" \
  --only "tests/run/t14_ascii_cast_failure" \
  --only "tests/run/t14_ascii_expect" \
  --only "tests/run/t16_bytes_view_return" \
  --only "tests/run/t16_bytes_view_store"
```

It ran with `CARGO_TARGET_DIR=/home/ben/.cache/next-lang/target`,
`NLC_TEST_JOBS=1`, and `ulimit -v 8000000`. All 35 selected E3c packages
matched at O1: 15 build, 10 diagnose, 1 intentional rejection, 8 expected
outputs, 1 expected rejection, and 0 mismatches or unsupported packages. All
three parsing fixtures passed.

The first integrated parse run exposed a missing closing parenthesis in the
generated LLVM core call; the emitter was corrected. The next run exposed a
region-offset collision when an aggregate receiver was AST node 0. The shared
region planner was corrected by moving the total-region size out of the
per-node offset table. The final 35-package run includes that shared fix.

## Scope and limits

Stage0 and Rust frontend code were not changed. This adds only the parsing
methods listed above; other numeric APIs remain outside this slice.
