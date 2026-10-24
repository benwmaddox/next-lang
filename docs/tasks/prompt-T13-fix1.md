You are implementing next-lang, task T13 (data stack, regions, destination emission), fix round 1. Repo: /mnt/d/code/next-lang. Read docs/tasks/T13-stack-contracts.md and docs/tasks/T13-report.md. Same rules: do not commit, do not create or switch branches, do not edit docs/DESIGN.md, docs/PLAN.md, docs/EXAMPLES.md or docs/reviews/, use CARGO_TARGET_DIR=$HOME/.cache/next-lang/target, no external crates.

Reviewer finding: the compiler panics (emit.rs:4597 "a whole structure-of-arrays element has no single address") whenever an element of a collection whose element type is over 4,096 bytes is passed to a function by pointer. Reproductions (all panic today):

    struct Big { xs: long[1000], n: int }
    fn first(b: Big) -> long { b.xs[0] + b.n.to_long() }
    fn bump(b: write Big) { b.n += 1 }
    fn pick(c: bool, a: Big, b: Big) -> Big { if c { a } else { b } }
    fn mk(v: long) -> Big { Big { xs: fill(v), n: 0 } }

    var l: list<Big, 3> = list {}; discard l.push(mk(4L)); print(first(l[0]))            // read param from a list element
    var l: list<Big, 3> = list {}; discard l.push(mk(4L)); bump(l[0]); print(l[0].n)      // write param on a list element
    var l: list<Big, 3> = list {}; discard l.push(mk(4L)); for b in l { print(first(b)) } // loop element
    var arr: Big[3] = fill(mk(7L)); let d = mk(3L); arr[1] = pick(true, arr[0], d)        // array element as argument

Fix: when the argument is a structure-of-arrays element (array, list, pool slot, map value, queue/ring/grid element, loop element, `write` loop view), gather it into a temporary data-stack region and pass that region's address; for a `write` parameter, copy the region back into the element's lanes after the call (copy-in, copy-out; the checker's exclusivity rules already ensure nothing else sees the element during the call), on every exit path of the call including a failed `?` in the callee. Count the temporary in the caller's byte requirement. Free it right after the call. A better zero-copy scheme can come later; correctness first. Also check that the same gathering is done everywhere else a single address of a large element is needed (equality, printing, `?.`, returning `l[0]` from a function, storing `l[0]` into a struct field or another collection, matching on it), and that nothing else in emit.rs can hit the same panic.

Add run fixtures for every reproduction above plus: a pool slot and a map value passed by read; a `write` element param inside a loop; an element of exactly 4,096 bytes and one of 4,104 bytes; returning a large element from a function; a nested large collection element of an outer list. Each must print correct values.

Run cargo build, cargo test and cargo fmt -- --check. Append a "Fix round 1" section to docs/tasks/T13-report.md.
