# T14: Ascii values on data stacks (milestone M3, part 2)

Depends on T13. Same rules. Binding points from docs/reviews/sol-T13-T14-r1.md. Read DESIGN.md "Copies and moves of growing values", "Text, ASCII and bytes", the step 2 acceptance cases.

## Ascii values

- `Ascii max N` values as locals, parameters and results, and inside `Option`/`Result`. Literals (`"hello"`, checked ASCII at compile time; a literal's maximum is its exact length); `+` concatenation; `str(n)` for integers (its maximum from the proven range: 6 digits for `int 0..=999999`, 11 for any `int` with its sign, 20 for `long`); `len()` (a refined `long`); `==`, `!=` and `<` (bytewise dictionary order); `print`; `expect`; `ascii_upper(s)` (same length); `Ascii.empty()` (its maximum comes from an annotation, its destination, or a counted loop, never "max 0").
- Each growing value is the one value on top of its own stack (T13's assignment). Concatenation **streams its pieces into the destination**, never materialising a piece first when it can write straight through.
- Maxima: `A + B` is `max (A+B)`, checked for overflow of the maximum itself; storing into a smaller maximum follows the refinement contract (prove it, cast `(Ascii max 80)(s)`, or `fit`). Embedded NUL bytes are allowed and print and compare correctly.

## Modes, copies and moves

- Parameter modes: read (no copy); `write` changes bytes in place without increasing the length; `grow` may also extend it (the value must be at its stack's top, as the stack contract says). A `grow` parameter can be passed on as `grow`.
- `let b = a` copies; `let b = take a` moves (no copy; `a` unusable after, a build error if used; the destination takes over the stack slot and the cleanup). Moves the compiler can't make safe (a branch-dependent move, a move out of a loop) are refused for now. Returning a local moves it (free when built on the destination); returning a read parameter copies.
- `s = s + s` builds on scratch then copies over `s`; it must never read bytes it's overwriting.

## Capacity versus reservation

- Going past a value's **declared maximum** is never a job failure: a plain `+=` must be proven to fit; otherwise the code uses `s.try_append(x) -> Result<(), Full>`, and a failure leaves the bytes, length and stack top unchanged (also when a helper failed after writing part of its output).
- Running out of the **reservation** (the 64 MB stack) is the only job failure here (`data stack exhausted`).
- In this task, a loop body may only grow values local to the body; growing an outer value in a loop is T15.

## Acceptance cases

- `fn f(s: Ascii max 80) -> Ascii max 80 { s }` returns equal bytes and `s` stays usable; returning a local after reading it; a forced copy from scratch; `take` (source unusable, slot transferred, alive to the destination's end); a refused branch-dependent move.
- Concatenation at the maximum; `try_append` past it gives `Full` with everything unchanged; a cast past it fails at its line; `fit` gives `none`; a non-ASCII literal (build error); `str` of `int` and `long` extremes; NUL bytes; bytewise ordering; `s = s + s`.
- A `grow` parameter passed on; overlap of a hidden destination with an argument (build error or safe path).
- A loop running 100,000 iterations, each building a 1 KB temporary `Ascii` (100 MB in all, more than the reservation): it must not exhaust the stack, which shows per-iteration cleanup; the same with `break` and `continue`, and with `return` and `?` from inside two nested loops.
- IR: appending a byte in a loop has no stack-table traffic.

## Report

docs/tasks/T14-report.md.

## Corrections from Sol's second M3 review (docs/reviews/sol-M3-r2.md), binding

- In T14, `try_append`'s argument is evaluated into scratch first and then appended, so rollback is simple; rollback after a producer has already written part of its output is T15's append mode.
- Widening a maximum (`Ascii max 60` passed where `Ascii max 80` is expected) is free and implicit for read parameters and copies, since it can't lose anything; it's not a numeric conversion.
- Job failures in this task are reservation exhaustion and the explicit failing forms already in the language (a failing checked cast, `unwrap`, overflow); exceeding a declared maximum never is.
- Gap tests: a callee's window above a caller's growing values with a gap below them (moved from T13).

## Ben's stack-count decision (2026-10-24), overrides anything above

DESIGN.md "Few stacks, used well": **one data stack per job by default, at most two.** Where this task says "N data stacks", "fixed scratch stack", "window k = 1 on stack 1" or "N = 2", read it under these rules:

- Finished values share the current stack in last-in-first-out order; only a value still growing while something above it is alive must be on top.
- There is **no separate fixed-scratch stack**: a large fixed-size temporary goes on top of the current data stack when nothing below it will grow during its lifetime, otherwise on the native stack.
- **Build above, then slide down:** something built while a value below it is still growing is built just past that value's end, then moved down onto it. A second data stack is very rare: used only when such a piece could exceed 64 KB (Ben, 2026-10-24), flagged as a warning in `inspect stacks`; never more than two. Append mode writes straight onto the growing value's end and needs no temporary at all.
- The worked example (`render`/`line`) runs on **one stack, N = 1**: `name` and `line`'s result are built above `out`'s end and the result slides down. Its worst case is 40,000 + 60 + 80 = 40,140 bytes plus page rounding (T17's numbers).
- `inspect contracts` / `inspect stacks` list every slide-down site and its worst-case copy size.
