# T26: never-returning functions

Same rules (docs/PLAN.md). From docs/reviews/claude-S1a-1-review.md finding 1.

- A function may declare `-> never`. The checker proves its body can't complete normally: every path ends in a `never` expression (`env.exit`, a call to another `-> never` function, `return` is refused in it, a failing `expect`... use the existing `never` type rules from T24). A body that can fall through or `return` is a build error naming the path.
- A call to a `-> never` function has type `never` and fits any expected type (T24's rule), in tails, branches, after `?`, as arguments.
- Function values: `fn(Env) -> never` is a function type; a `-> never` function fits a slot expecting `fn(...) -> T` for any `T`? No: keep it simple and exact; a `never` function fits only a `-> never` function type. Say so in the report.
- Recursion and contracts: a `-> never` function's stack contract and T19's recursion rules apply unchanged; T17's `inspect stacks` handles it.
- Acceptance: an error helper used in a value position (`let x = if ok { 1 } else { fail(env, 3) }`), in a `match` arm, as the tail of a `Result`-returning `main`; a body that can fall through refused; `return` inside refused; a function value of type `fn(Env, int 0..=125) -> never` called in a tail. Also update selfhost/main.nl to use a `-> never` helper instead of its follow-up exits, and keep the selfhost comparison passing.
- Report: docs/tasks/T26-report.md.
