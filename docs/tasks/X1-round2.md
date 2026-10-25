# X1 round 2: a working offset-mode vertical slice — done, historical record

**Done (2026-10-25); nothing below is to be built.** Results: docs/tasks/X1-report.md "Round 2"; round 3 (docs/tasks/X1-round3.md) followed, and O1 ports the slice onto main. The text below is the original round spec, kept only as a record.

Round 1 (docs/tasks/X1-report.md) built the runtime (mremap growth, guard page) and a fail-closed compiler mode, but no program that touches the data stack compiles in offset mode, so the per-access cost is still unmeasured. This round must produce **running offset-mode programs** for a narrow slice and measure them. Everything outside the slice keeps failing closed (a clear build error), never a miscompile.

## The slice (must work in offset mode, with relocations actually happening)

- Large local `list<long, N>` and `list<S, N>` for a small struct `S` of scalars (structure-of-arrays lanes) placed in data-stack regions: `list {}`, `push`, indexing (read and write), `count`, `for x in xs`, `for i in 0..n`, element field access and update.
- Passing such a list as a read parameter and as a `write` parameter (by offset), and returning one through a caller destination (by offset).
- A local `Ascii max N` builder: `+=` of literals and `str(n)` results, `try_append`, `len`, `print`, passing it as a `grow` parameter.
- Growth points: region creation and builder appends that don't fit grow the stack; after every call that may grow (any callee with a nonzero data-stack requirement), reload the base; no raw pointer derived from the base is held across such a call. A debug check (`NLC_STACK_VERIFY=1`) that, after each growth, poisons the old mapping (e.g. by moving to a fresh range every time and `mprotect`-ing the old one, or by always relocating) so a stale pointer faults instead of silently working: run the slice's fixtures under it.
- Tests: fixtures covering each slice feature, with growth triggered mid-append, inside a loop, inside a callee with a `write` parameter, with two lists and a builder alive at once, and under NLC_STACK_VERIFY=1. Pointer mode and the full existing suite stay unchanged.

## Measurements (release-built compiler; programs at -O1 and -O3; best of 5; pointer vs offset; offset both with growth and with NLC_STACK_PREALLOC=1)

1. **Per-access cost:** spike/tight-list (sum and indexed update over a large list, many rounds), plus a struct-list variant updating one field. Include the inner loop's IR for both modes in the report and say whether LLVM keeps the base in a register and hoists it out of the loop.
2. **Calls:** a loop calling a function that takes a list by `write` and one that returns a list through a destination (a call per iteration), to show the cost of passing offsets and reloading the base after calls.
3. **Builders:** an Ascii builder appending `str(i) + ","` up to tens of MB, with growth versus preallocated.
4. Peak RSS, data-stack reservation, number of relocations and total relocation time for each.

## Optional, only if 1-4 are done: 32-bit offsets

Repeat measurement 1 and the struct-list variant with offsets stored as 32-bit values scaled by 8 (regions 8-byte aligned, `base + off * 8` addressing), and report descriptor sizes and the difference.

## Report

Append "Round 2" to docs/tasks/X1-report.md: the tables, the IR excerpts, what broke and was fixed, a revised estimate of the full-adoption work, and a recommendation based on the numbers.
