You are implementing next-lang, task T12 (sorting), fix round 1. Repo: /mnt/d/code/next-lang. Read docs/tasks/T12-sorting.md and docs/tasks/T12-report.md. Same rules: do not commit, do not create or switch branches, do not edit docs/DESIGN.md, docs/PLAN.md, docs/EXAMPLES.md or docs/reviews/, use CARGO_TARGET_DIR=$HOME/.cache/next-lang/target, no external crates.

Reviewer finding: the comparator's type is `fn(C, T, T) -> bool` with no effects bound, so under T11's rules it must be pure, but `sort_by` accepts comparators that print or write globals:

    fn noisy(c: int, a: int, b: int) -> bool { print(a); a < b }        // accepted today
    fn less(c: int, a: int, b: int) -> bool { app.k += 1; a < b }       // accepted today

Fix: check the comparator (named function or function value) against the pure type `fn(C, T, T) -> bool` exactly as T11's assignment rule does, so any effect (print, reads or writes of a global) is a build error naming the effect and saying a sort comparator must be pure. A comparator that only reads its ctx and elements stays fine. A function value whose declared type has an effects bound is refused too. Since comparators are now pure, simplify any overlap checks that only existed for comparator global access, but keep the ctx/xs overlap checks.

Add fixtures: printing comparator refused; global-writing comparator refused; global-reading comparator refused; a function value with an effects bound refused; a pure comparator through a function value accepted.

Run cargo build, cargo test and cargo fmt -- --check. Append a "Fix round 1" section to docs/tasks/T12-report.md.
