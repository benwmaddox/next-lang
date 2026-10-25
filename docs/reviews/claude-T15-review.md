# Claude: T15 review (append mode and loop growth)

**Verdict:** approved after one fix round.

Checked: cargo build and test pass. Probe ~/nlprobe/g1:

- A row builder appending `cell(x)?` (a `Result<Ascii max 12, Bad>` producer) in a loop over a list gives `ok([1][22][333])`, and `err(Neg)` with the partial row rolled back when one cell fails.
- `try_append(str(i))` in a loop with `match ... err(_) => break` stops exactly at the maximum (`ab01234567`).
- 100 plain `+=` appends of `str(i) + ","` into `Ascii max 2000`: proven to fit with no `try_append` (length 290, correct).
- t15_append_growth: 2.5 MB peak for the million-iteration case.

Fix round 1: Luna had extended `??` to `Result<Ascii, E>` because my correction example in the task used it; DESIGN.md says `??` is for `Option` only. The extension is gone (`??` on a `Result` is a build error pointing to `match` or `?`), and the task's example now uses `match`.

Note: `match` over a `Result<Ascii, E>` materialises the value before choosing an arm, so `match producer() { ok(f) => buf.try_append(f), ... }` copies once; `out += producer()?` and `buf.try_append(producer()?)` stream. Fine for now.
