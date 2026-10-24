# T14: Ascii values in regions (milestone M3, part 2)

Depends on T13. Same rules. Rewritten for the reserve-ahead decision (DESIGN.md "The job's data stack", "How the compiler places values", "Copies and moves of growing values", "Text, ASCII and bytes"), folding in sol-T13-T14-r1, sol-M3-r2 and sol-fewstacks-r1.

## Ascii values

- `Ascii max N` values as locals, parameters and results, and inside `Option`/`Result`. Literals (checked ASCII at compile time; a literal's maximum is its exact length); `+` concatenation; `str(n)` for integers (its maximum from the proven range: 6 digits for `int 0..=999999`, 11 for any `int` with its sign, 20 for `long`); `len()` (a refined `long`); `==`, `!=`, `<` (bytewise order); `print`; `expect`; `ascii_upper(s)` (same length); `Ascii.empty()` (its maximum from an annotation or its destination, never "max 0"). Embedded NUL bytes are allowed and print and compare correctly.
- Widening a maximum (`Ascii max 60` passed where `Ascii max 80` is expected) is free for read parameters and copies.

## Placement (reserve ahead)

- A value that's built and finished before anything is placed above it is packed at the top, using only its actual length.
- A value that may keep growing while other values are placed above it gets a **reserved region of its declared maximum** when it's created; it grows inside that region, and later values go above it. Untouched pages of a reservation cost no memory (they're never committed).
- Concatenation **streams its pieces into the destination**, never materialising a piece first when it can write straight through.
- Maxima: `A + B` is `max (A+B)`, checked for overflow of the maximum itself; storing into a smaller maximum follows the refinement contract (prove it, cast `(Ascii max 80)(s)`, or `fit`).

## Modes, copies and moves

- Read mode copies nothing; `write` changes bytes in place without increasing the length; `grow` may extend it within the builder's reserved region. A `grow` parameter can be passed on as `grow`.
- `let b = a` copies; `let b = take a` moves ownership and cleanup (not position: the bytes stay in their region until `b`'s scope ends); `a` is unusable after (build error). A move that would outlive its region's enclosing scope, or one that depends on a branch, is refused for now. Returning a local built in the caller's destination is free; otherwise it's copied there. Returning a read parameter copies.
- `s = s + s` builds the new value in a temporary region and copies it into `s`'s region; it never reads bytes it's overwriting.

## Capacity versus reservation

- Going past a value's **declared maximum** is never a job failure: a plain `+=` must be proven to fit; otherwise `s.try_append(x) -> Result<(), Full>`. In this task `try_append`'s argument is evaluated into a temporary region first, then appended; a failure leaves the bytes, length and top unchanged.
- Job failures here: running out of the stack's reservation, and the explicit failing forms already in the language (a failing checked cast, `unwrap`, overflow).
- A loop body may grow only values local to the body in this task; growing an outer value in a loop is T15.

## Acceptance cases

- `fn f(s: Ascii max 80) -> Ascii max 80 { s }` returns equal bytes and `s` stays usable; returning a local after reading it; a forced copy into the destination; `take` (source unusable, cleanup transferred, alive to the destination's end); a refused escaping move; a refused branch-dependent move.
- Concatenation at the maximum; `try_append` past it gives `Full` with everything unchanged; a cast past it fails at its line; `fit` gives `none`; a non-ASCII literal (build error); `str` of `int` and `long` extremes; NUL bytes; bytewise ordering; `s = s + s`.
- A `grow` parameter passed on; a hidden destination overlapping an argument (build error or safe path).
- Three independent builders open at once, each in its own reserved region, appended to in turn (a fixture that slide-down alone couldn't handle).
- A loop running 100,000 iterations, each building a 1 KB temporary `Ascii` (100 MB in all, more than the reservation): no exhaustion, showing per-iteration cleanup; the same with `break` and `continue`, and with `return` and `?` from inside two nested loops.
- IR: appending a byte in a loop does no stack-table traffic.

## Report

docs/tasks/T14-report.md.
