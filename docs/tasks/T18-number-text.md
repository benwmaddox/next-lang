# T18: integer parsing and formatting, abs/min/max (milestone M3 follow-up)

Same rules (docs/PLAN.md). Depends on T14 to T16 (Ascii, Text, Bytes). From PLAN.md's M3 follow-up and the self-hosting prerequisites. `double`/`float` don't exist yet (a separate float task, DESIGN.md "Floats" and "Deterministic by default"), so `str_fixed` for doubles is out of scope here.

## Formatting

- `str(n)` exists for `int` and `long` (T14). Add `str_hex(n)` (lowercase, no prefix, two's complement not used: negative values print with `-`), and `str_bin(n)` for completeness; maxima from the type's range as for `str`.
- `pad(s, width)` (pad on the left with spaces to at least `width` code points; a longer `s` is unchanged) and `pad_right(s, width)`, for `Ascii` and `Text`; `width` a constant or a refined `long` so the result's maximum is known (max(len, width)). `pad_zero(n, width)` for integers (`-0042` style: sign first).
- All results stream into a destination in append mode like `str` (T15), so `out += pad(str(x), 10)` writes straight into `out`.

## Parsing

- `s.parse_int() -> Option<int>` and `s.parse_long() -> Option<long>` on `Ascii`, `Text` and `Bytes` (and their slices): optional `+` or `-`, decimal digits, optional `_` between digits (as in source literals), nothing else (no surrounding spaces); overflow or any other character is `none`. Also `parse_int_radix(16)` style for 2, 8, 10 and 16 (accepting `0x`/`0b` prefixes only through a separate `parse_int_literal` that follows the language's own literal rules, without suffixes).
- `byte` values: `b.is_digit()`, `b.is_alpha()`, `b.is_space()`, `b.to_lower()`, `b.to_upper()` (ASCII only), useful for hand-written lexers.

## Numbers

- `abs(x)` (or `x.abs()`; pick one, matching how `str(x)` is called, and say why), `min(a, b)`, `max(a, b)`, `clamp(x, lo, hi)` for `int` and `long`, keeping refinements: `abs` of `int -5..=3` is `int 0..=5`; `abs` of the type's minimum is an overflow (fails the job, as `-x` does), unless the range excludes it.

## Acceptance

- Formatting and parsing round-trip for `int` and `long` extremes, zero, negative zero input (`-0` parses to 0), every radix, underscores in the right and wrong places (`1__0`, `_1`, `1_`), leading `+`, empty input, a lone sign, overflow by one in each direction, non-ASCII digits in Text (refused).
- `pad` with a value longer than the width, exactly the width, and a Text value with multi-byte code points (padding counts code points).
- Refinement results: `abs`, `min`, `max`, `clamp` keep the narrowest provable range (show with a refinement that needs it).
- The logsum example's `report` line from docs/EXAMPLES.md (`pad(str(rank + 1), 3) + " " + pad(str(top.value), 10) + " " + top.key`) compiles (with a concrete stand-in for `top_by_value`) and prints aligned columns.
- Time a large generated input (1,000 chained `pad(str(...))` concatenations) to keep checking linear.
- Report: docs/tasks/T18-report.md.
