You are implementing next-lang, task T19 (recursion), fix round 1. Repo: /mnt/d/code/next-lang. Read docs/tasks/T19-recursion.md and docs/tasks/T19-report.md. Same rules: do not commit, do not create, switch or stash branches, do not edit docs/DESIGN.md, docs/PLAN.md, docs/EXAMPLES.md or docs/reviews/, use CARGO_TARGET_DIR=$HOME/.cache/next-lang/target, no external crates.

Reviewer finding: constant evaluation of a recursive function overflows the compiler's own Rust stack well before the 64-call cap, in the debug build of nlc that `cargo build` produces:

    recursive fn depth(n: long) -> long { if n == 0L { 0L } else { 1L + depth(n - 1L) } }
    const X: long = depth(40L)     // "thread 'main' has overflowed its stack", abort (depth(10L) works)
    fn main() { print(X) }

A cap of 64 is also too low to be useful (a compile-time table built by recursion over 100 or 1,000 items is reasonable).

Fix, in this order of preference:
1. Make the evaluator's call stack explicit (a Vec of frames, no Rust recursion per language-level call), so depth is bounded only by a checked limit; or
2. If (1) is too invasive for expression evaluation, run the whole compile (or at least constant evaluation) on a thread spawned with a large stack (e.g. 512 MB via std::thread::Builder::stack_size; pages are only touched as used) and measure the actual Rust stack used per language-level call in both debug and release builds of nlc.

Either way, set the depth limit to 10,000 calls, prove it can't overflow in a debug build (a fixture recursing to exactly 10,000 succeeds, 10,001 is the build error naming the limit, both under the debug nlc used by cargo test), and keep the step limit. Also check expression nesting in the evaluator and checker (a deeply nested expression like 2,000 nested parentheses or a long `a + a + ... + a` chain) doesn't overflow the compiler; if it does, report what depth it does handle and give the parser a nesting limit with a clear error rather than a crash.

Add the fixtures, run cargo build, cargo test, NLC_OPT_LEVEL=3 cargo test, and cargo fmt -- --check. Append a "Fix round 1" section to docs/tasks/T19-report.md.
