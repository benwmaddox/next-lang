# T13: data stacks and Ascii values (milestone M3, part 1)

Depends on M2 (T06 to T12). Same rules. This is DESIGN.md's second step, first slice. Read DESIGN.md "Stacks" (in Memory), "Copies and moves of growing values", "N stacks per job", "How the compiler assigns stacks" (the stack contract and the worked example), "Keeping it fast", and the step 2 acceptance cases under "First steps".

## What a growing value is

`Ascii max N` (DESIGN.md "Text, ASCII and bytes") is the first growing value: its length changes, up to a declared maximum in bytes. In this task: `Ascii max N` values as locals, parameters (read, `write`, and `grow` mode) and results; string literals (`"hello"`, checked ASCII at compile time); `+` (concatenation) and `+=` (append); `str(n)` for integers; `len()` (a refined `long`); comparison `==`, `!=`, `<`; `print`; and `expect`. Not yet: `Text` and `Bytes` (T15), growing values inside collections (T15), append mode across calls (T14).

## Data stacks

- **The runtime keeps, per job (here: per program run and per test child), N data stacks**, each a reserved address range with a bump pointer and a guard page at the end (DESIGN.md "N stacks per job"). The reservation per stack is 64 MB in this task (DESIGN.md's default for unbounded entry points; per-entry-point sizing from bounds is T16). Pages are committed on first touch.
- **The stack contract** (DESIGN.md "How the compiler assigns stacks"): every function gets, computed by the compiler from its body and callees, a window size `k` (consecutive stacks for its own growing locals and its callees'), a mode per reference parameter, and, for a function returning a growing value, a destination stack the caller names. A caller passes the base (the first free stack index) as a hidden argument through T01's single signature-lowering function, together with a hidden context pointer to the job's stack table. Each growing local takes the lowest free stack in its window (Goose's rule: at most one growing value per stack, always on top), and gives it back at its scope's end.
- **Freeing a scope** sets its stacks' tops back, at the scope's end and on every exit: `return`, `break`, `continue`, `?`, and T02's cleanup hooks (which this task fills in). A failed job resets everything (that's just exiting the child here).
- **Growing past the reservation** fails the job through `nl_fail` (`data stack exhausted`), checked with one compare before each growth.
- **Fixed-size locals** stay in registers or on the native stack as before. T06's 64 KB limit on local collections moves to: collections over 4 KB go on a "fixed scratch" data stack (DESIGN.md), so the 64 KB build error goes away; add a test with a 1 MB local list.

## Copies, moves and results (DESIGN.md "Copies and moves of growing values")

- `let b = a` copies `a`'s bytes; `let b = take a` moves (no copy; `a` can't be used after: a build error if it is). Passing to a read parameter neither copies nor moves.
- Returning a local moves it: when it was built on the caller's destination (the usual case, arranged when the compiler can prove it safe) it's free; otherwise it's copied from scratch to the destination, with both counted while the copy runs.
- Returning a read parameter copies it.
- `s = s + s` takes a safe path (build the result on scratch, then copy over `s`) or is refused; it must never read bytes it's overwriting.
- **Bounds:** every `Ascii` has a maximum; `+` of `Ascii max A` and `Ascii max B` is `Ascii max (A+B)`; storing into a smaller maximum follows the refinement contract (prove it fits, or a checked cast `(Ascii max 80)(s)`, or `s.fit<Ascii max 80>()`). A loop that grows a value kept outside it is T14; in this task a loop body may only grow values local to the body.

## Acceptance cases (DESIGN.md step 2, the parts this task owns)

- `fn f(s: Ascii max 80) -> Ascii max 80 { s }` returns equal bytes and `s` stays usable; returning a local after reading it; a forced copy from scratch to the destination; `take` making the source unusable (build error on later use), the destination taking over, and the bytes alive until the destination's scope ends.
- Concatenation results at their maximum; one byte past a declared maximum through a checked cast (fails) and through `fit` (`none`); a non-ASCII literal (build error).
- `s = s + s` correct, or refused.
- A nested call while live values occupy separated stacks gets a window that avoids them, and N is one more than the highest index used (check with an IR test or a debug dump of each function's contract).
- Scope reset on every exit form, including `?` and a `break` out of two loops (a test that loops a million times building a temporary `Ascii` each iteration and doesn't exhaust the stack).
- A data stack exhausted by deliberately unbounded growth (an artificially small reservation set by an environment variable the runtime reads only in test builds) fails with `data stack exhausted`.
- A 1 MB local list now works (fixed scratch stack).

## Report

docs/tasks/T13-report.md. Include each function's computed stack contract for the worked example in DESIGN.md (`render`/`line`), so the review can compare it with the doc.
