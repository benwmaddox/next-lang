You are implementing next-lang, task T14 (Ascii values), fix round 1. Repo: /mnt/d/code/next-lang. Read docs/tasks/T14-ascii-values.md and docs/tasks/T14-report.md. Same rules: do not commit, do not create, switch or stash branches, do not edit docs/DESIGN.md, docs/PLAN.md, docs/EXAMPLES.md, docs/reviews/ or docs/research/, use CARGO_TARGET_DIR=$HOME/.cache/next-lang/target, no external crates.

Reviewer finding: comparing two Ascii values whose maxima differ produces invalid LLVM IR (clang: "'%t24' defined with type '%nl.ty.22 = type <{ ptr, i64 }>' but expected '%nl.ty.17 = type <{ ptr, i64 }>'"). Each failing case is the whole body of `fn main() -> Result<(), Full> { ...; ok(()) }` with `fn label(n: int 0..=999) -> Ascii max 10 { "#" + str(n) }` above it:

    let x: Ascii max 10 = "ab"; print(x == "ab")
    let x = label(4); print(x == "#4")
    let x: Ascii max 10 = label(4); let y: Ascii max 20 = "#4"; print(x == y); print(x < y)
    print(label(42) == "#42")

(`label(4) < label(5)`, same maximum, works.) Fix the emitter so `==`, `!=`, `<`, `<=`, `>`, `>=` accept Ascii operands of any two maxima (and literals), comparing bytes and lengths; ideally descriptors of different maxima share one LLVM type, since the maximum is a checker fact, not a layout difference. Then look for the same mismatch everywhere else two Ascii values of different maxima meet: `match`/`expect` comparisons, map/set keys, `Option<Ascii max N>` equality, passing a smaller-max value to a larger-max read parameter (stated as free in the task), returning one through a function type, `if` branches yielding different maxima, assigning a proven-fitting smaller max into a larger var, concatenation of mixed maxima. Add a fixture covering every one of these, printing results.

Also a gap in your fixtures: they evidently never compare values of different maxima. Add a short test that builds one program exercising each Ascii operation with mixed maxima.

Run cargo build, cargo test and cargo fmt -- --check (and the parse-dump update script if new fixtures need dumps). Append a "Fix round 1" section to docs/tasks/T14-report.md.
