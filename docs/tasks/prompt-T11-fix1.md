You are implementing next-lang, task T11 (function values), fix round 1. Repo: /mnt/d/code/next-lang. Read docs/tasks/T11-function-values.md and docs/tasks/T11-report.md. Same rules as before: do not commit, do not create or switch branches, use CARGO_TARGET_DIR=$HOME/.cache/next-lang/target, no external crates.

Reviewer findings to fix:

1. A function type with no result must be writable without `->`, mirroring declarations: `fn bump(x: write int) { x += 1 }` then `let f: fn(write int) = bump` is currently "expected '->' and a result type in function type". Allow `fn(...)` (and `fn(...) effects ...`) to mean no result, and keep `-> ()` if it already parses. Then a mode mismatch (`let f: fn(int) = bump`) must give a clear error naming the parameter mode.
2. `effects writes P` must also cover reads of P and of paths under P (a function that does `app.score += x` should fit `fn(int) -> int effects writes app.score`; today it reports "extra effect 'reads app.score'"). `reads P` alone still does not cover writes. Update DESIGN.md's function-values section with one sentence stating this rule.
3. Add run fixtures for both (no-result function values called through a list and a struct field; a write-mode parameter function value that changes the caller's variable; writes-covers-reads accepted; reads-does-not-cover-writes refused).

Run cargo build, cargo test and cargo fmt -- --check. Append a "Fix round 1" section to docs/tasks/T11-report.md.
