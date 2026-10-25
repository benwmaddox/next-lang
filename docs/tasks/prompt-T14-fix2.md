You are implementing next-lang, task T14 (Ascii values), fix round 2. Repo: /mnt/d/code/next-lang. Read docs/tasks/T14-report.md (including Fix round 1). Same rules: do not commit, do not create, switch or stash branches, do not edit docs/DESIGN.md, docs/PLAN.md, docs/EXAMPLES.md, docs/reviews/ or docs/research/, use CARGO_TARGET_DIR=$HOME/.cache/next-lang/target, no external crates.

Reviewer finding: the compiler panics (emit.rs:8081 "construction of Option<Ascii max 4> case 0 has incompatible payload type Ascii max 2 but expects Ascii max 4") on

    fn opt() -> Option<Ascii max 4> { some("ab") }
    fn main() { let o = opt(); print(o == some("ab")) }

(`let o: Option<Ascii max 4> = some("ab")`, returning `some("ab")`, and `ok("ab")` all work.) The right operand `some("ab")` is constructed as `Option<Ascii max 2>` and then forced into the left operand's type. Fix it so an `Option`/`Result`/enum constructor whose payload is a literal or a smaller maximum is typed from context when the other operand gives one (and otherwise compares correctly as is), and make sure no type mismatch reaches the emitter as a panic: the checker must either coerce explicitly (free widening, as the task says) or report an error. Check the same for `!=`, `expect o == some("ab")`, `o == none`, `r == ok("ab")`, `r == err(3)`, a struct literal with an Ascii field compared to a struct variable, and nested `some(some("ab"))`. Add these to the mixed-max fixture.

Run cargo build, cargo test and cargo fmt -- --check (and the parse-dump update script if needed). Append a "Fix round 2" section to docs/tasks/T14-report.md.
