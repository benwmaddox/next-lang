# E3c value fixture handoff

These packages cover stored text-like values, comparisons, slices, formatting,
and `Ascii` fitting. The accepted Stage0 cases were run with the frozen
`/home/ben/.cache/next-lang/target/release/nlc`; their `expected.*` files match
the output below.

| Package | Contract |
| --- | --- |
| `e3c_values_fields` | Construct empty `Ascii`, `Text`, and `Bytes` values from destination bounds; store each value kind in a struct; use `Text` in enum, `Option`, and `Result` payloads; pass an `Ascii` local to read `Text` parameters, return the value as owned `Text`, and print it with its code-point and byte lengths. |
| `e3c_values_compare` | All six comparisons for `Ascii`, `Text`, and `Bytes` across different maxima, mixed `Ascii`/`Text` comparisons, and `ascii_upper` across NUL and ASCII range boundaries. |
| `e3c_values_text_slices` | Exclusive `Text` slices on code-point boundaries, empty end slice, `len()` versus `byte_len()`, and `Ascii` slicing. |
| `e3c_values_str_bounds` | `str(int/long/byte)`, signed extrema, hexadecimal and binary formatting, and space/zero padding. |
| `e3c_values_conversions` | `Bytes.to_ascii()` distinguishes successful ASCII from `NonAscii`; invalid UTF-8 Bytes and valid non-ASCII Bytes both return `NonAscii` in Stage0. `Text.to_ascii()` returns `NonAscii` for non-ASCII Text; `validate_utf8()` and `to_text()` report the malformed sequence offset. |
| `e3c_values_str_bool` | Negative fixture: Stage0 rejects `str(bool)` with a real diagnostic. |
| `e3c_values_fit` | `fit<Ascii max N>()` returns `Some` when the value fits and `None` when it does not. |
| `e3c_values_inclusive_slices` | Inclusive `Text` and `Ascii` slices, including the final code point; the oracle uses the corrected inclusive behavior. |
| `e3c_values_slice_exclusive_bounds` | Exclusive `Text` slice with an end beyond the code-point length fails with `index out of range`. |
| `e3c_values_slice_inclusive_bounds` | Inclusive `Text` slice one past the final code point fails with `index out of range`. |
| `e3c_values_slice_overflow` | Inclusive end at `long` maximum fails with `index out of range`. |
| `e3c_values_const_bytes` | Reproduces `.bytes()` on a const `Ascii`; the intended selfhost error must identify both `SIGNATURE` and `.bytes()`. |

## Stage0 probes

Stage0 accepts and runs the six output packages (`fields`, `compare`,
`text_slices`, `str_bounds`, `fit`, and `conversions`), and their
checked-in stdout matches fresh runs byte-for-byte. The fields output starts
with five zero counts from the destination-bounded empty constructors.
The comparison fixture's matrix contains false results where lexical ordering
requires them; it is not an all-true matrix. The `ascii_upper` probe prints
`0, 64, 65, 90, 91, 96, 65, 90, 123, 127` for NUL, `@`, `A`, `Z`, `[`,
backtick, `a`, `z`, `{`, and DEL.
The formatting fixture constrains `str(-1)` to `Ascii max 2`, `str(1 + 2)`
to `Ascii max 1`, and `str(7)` to `Ascii max 1`; Stage0 accepts them and
prints `-1`, `3`, and `7`.

For `values_conversions`, Stage0 prints `0, 2, 2, 0, 2, 1, -1, 2, 2`.
`Bytes.to_ascii()` reports `NonAscii` for any byte above ASCII, including the
truncated UTF-8 input; it does not return `InvalidUtf8`. `Bytes.validate_utf8()`
and `Bytes.to_text()` both report `valid_up_to = 2` for that truncated input.
The fixture separately constructs `TextError.InvalidUtf8` to exercise that
built-in case.

Stage0 rejects `str(bool)` during compilation with status 2, empty stdout, and
`main.nl:2:15: error: str needs int or long; found bool`. This fixture is
classified as `diagnose`.

The source-order padding probe was not added: Stage0 first rejects a `byte`
width where `pad` expects `long`; an explicit cast then fails because the
width is not a nonnegative constant or refined `long`. That refinement is
outside E3c.

Stage0 treats `..=` as an exclusive end. For `values_inclusive_slices`, it
prints `é` followed by two empty lines. The expected-output oracle instead
asserts the E3c inclusive results `é😀`, `Z`, and `w`.

Stage0 accepts the exclusive out-of-range slice in `values_slice_exclusive_bounds`
as a run-time error (exit status 1, `main.nl:3:11: index out of range`). It
accepts the inclusive one-past-end slice in `values_slice_inclusive_bounds`
and prints the whole text because it treats the end as exclusive; the
expected-output oracle requires an out-of-range error.

The `long`-maximum inclusive slice in `values_slice_overflow` fails at runtime
with exit status 1 and `main.nl:3:11: index out of range`.

Stage0 rejects `SIGNATURE.bytes()` at compile time with exit status 1 and
`main.nl:4:15: error: unknown enum 'SIGNATURE'; declare it with enum`. The
known defect's required selfhost diagnostic is a real error naming the const
and the `.bytes()` method. The comparison uses the new `expected-reject` class: it checks an exact status-2 rejection with empty stdout and no IR, without a Stage0 reference result. The checked-in oracle expects `main.nl:4:25: error: const 'SIGNATURE' cannot
call '.bytes()'; const evaluation is not implemented yet`. The focused E3c
comparison matched this diagnostic.

## Focused selfhost comparison

The latest focused comparison over `tests/e3/e3c_*` passed all selected
packages with zero mismatches. It includes conversions, stored fields,
comparisons, formatting, fitting, slice bounds, inclusive slicing, `str(bool)`
rejection, and the const-bytes diagnostic, including the constant-narrowing
cases added to `values_str_bounds`.
