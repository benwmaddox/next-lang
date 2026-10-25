# Claude: T14 review (Ascii values in regions)

**Verdict:** approved after two fix rounds.

Checked: cargo build and test pass. Probes in ~/nlprobe (a1, b*, c*):

- `"hello, " + name + "!"`, `str(n)` for `int 0..=999`, `str` of `int` and `long` extremes, `len()`, bytewise `<`, `ascii_upper`.
- `try_append` past the maximum gives `err(Full)` with the value unchanged; a plain `+=` that can't be proven to fit is refused with a hint to use `try_append`; a non-ASCII literal is refused.
- A `grow` parameter appended through `try_append`; three builders interleaved; `take` moves; returning through wider maxima.
- Growing an outer value inside a loop is refused with a pointer to T15 (as the task says).

Fix round 1: comparing values of different maxima (`x == "ab"` with `x: Ascii max 10`) produced invalid LLVM IR; Luna's fixtures only compared equal maxima. Now all Ascii descriptors share one LLVM layout (the maximum is a checker fact), and mixed maxima work in comparisons, branches, map and set keys (keys now own a stable byte copy), `Option` equality and callbacks.

Fix round 2: `o == some("ab")` panicked the emitter (the constructor was typed from its literal, `Option<Ascii max 2>`). Widening now rewrites the typed expression to the expected maximum, and constructors are typed from the other operand; covered for `!=`, `none`, `ok`/`err`, enum payloads, struct literals, nested `some(some(..))` and `expect`.

Note: the research report (docs/research/selfhost-architecture.md 2.3b) found that empty collections, construction, copies and returns still touch full capacity; that's now a PLAN follow-up before T17, not a T14 problem.
