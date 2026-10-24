# T04: structs, refinements and constants (milestone M1, part 2)

Depends on T03. Same rules (docs/PLAN.md, T01's Architecture section).

## Structs

- `struct Ship { pos_x: int = 0, lives: Lives = 3, ... }`: fields with optional defaults (DESIGN.md, "Initialised before use"). A literal `Ship { lives: 2 }` gives the named fields and takes defaults for the rest; a field with no default must be given, or it's a build error naming it. Field shorthand `Ship { lives }` uses a variable of that name.
- Structs are values: `let b = a` copies. Fields are read `s.f` and written `s.f = v` (on a `var`). Nested structs.
- Parameters take modes (DESIGN.md: written before the type): plain is read-only; `write T` lets the function change the caller's value in place (pass it by reference under the hood). The call site passes a `var` (or a `write` parameter), never a `let`. Two arguments that could overlap when either is `write` are a build error (DESIGN.md, "No overlapping arguments"): for this task, refuse passing the same variable twice when either use is `write`, and passing a variable and one of its own fields when either is `write`; two different fields of one struct are allowed.
- `print` and `expect ==` work on structs.

## Refinements (DESIGN.md, "The refinement contract")

- Range refinements on integer types: `int 0..=100`, `int 1..=3`, `long 0..=500`, using `..` (end excluded) and `..=` (end included). Named refinements: `type Size = int 1..=3` (the same type, with a name).
- **The contract:** storing into a refined type (assign, argument, return, field, struct literal) is free when the checker proves the value fits, and otherwise a build error asking for `(Size)(x)` (a checked cast: fails the program if it doesn't fit) or `x.fit<Size>()` (returns `Option<Size>`). Literals are checked at compile time. Arithmetic on refined values gives the plain base type.
- **What the checker proves, for this task:** a simple interval analysis (each integer expression gets a range: literals, refined variables, `+ - *` of ranges, `min`/`max`, and narrowing by an enclosing `if` on a comparison with a constant, including early `return`/`continue`/`break` in an `if`). Anything it can't prove needs the explicit form. Keep this in one module, since M4 will extend it and hand its results to LLVM.
- **`wrap` and `clamp`:** `int 0..=359 wrap`, `int 0..=100 clamp`. Storing any value of the base type wraps (`lo + (x − lo) mod (hi − lo + 1)`) or clamps; this applies to `=`, `+=` and the rest. Input conversions (casts, `fit`) are still checked, never wrapped or clamped.
- `bool`-style refinements, `Text` lengths and float ranges come later.

## Constants

- `const NAME: T = expr` at the top level. `expr` is evaluated at compile time: literals, arithmetic, calls to functions with no effects (`print` is an effect, so a const can't call it, and the error says so), `if`, `for`, structs and enums. A failure during compile-time evaluation (an overflow, say) is a build error at the line that failed, showing the chain of calls.

## Tests

- Structs: defaults, a missing required field (build error), copies are independent, `write` parameters change the caller, `write` on a `let` (build error), the overlap cases (each a build error, and the allowed two-fields case).
- Refinements: a proven store with no cast; an unproven one (build error with both suggestions); a checked cast failing at run time with its line; `fit` giving `none`; narrowing by `if` and by an early `return`; `wrap` and `clamp` with `+=`, including values far outside the range and negative ones.
- Constants: a computed constant; a constant calling a pure function; a constant calling `print` (build error); an overflow during evaluation (build error with the line).

## Report

docs/tasks/T04-report.md.

## Changes from Sol's review (docs/reviews/sol-T03-T04-r1.md), all binding

- **Constants move to their own task, T05.** Remove them from this task's scope and tests. Order inside this task: structs and modes first, then the refinement analysis. Extend `Option`/`Result` payloads to structs and refinements here.
- **Modes:** a `write` argument must be an assignable place (a `var`, a field of one, or another `write` parameter); a plain parameter can't be assigned or passed on as `write`. A `write` argument's type must match exactly, including its refinement and its `wrap`/`clamp` policy: a `Size` can't be passed to `write int`, since the callee could store a value outside `Size`. `grow` is deferred until growing values exist (M3). Test: writing a field, passing a `write` parameter on, a scalar `write`, a temporary or a read parameter passed as `write` (build errors), a refined `write` mismatch (build error).
- **Overlap by place paths:** places are compared by owner and full field path. `s.a` and `s.a.b` overlap; `s.a.b` and `s.a.c` don't. Passing the same place twice, or a place and something inside it, is a build error when either argument is `write`; repeated reads are fine. Track through `write` parameters passed on; never decide from spelling alone. Test each case in both argument orders, including nested calls with side effects (left-to-right evaluation kept).
- **Initialisation (a stricter subset of DESIGN.md for M1):** every field without a default must be given in the literal. Duplicate and unknown fields are build errors; a default or initialiser can't read a field of the value being built, but may read ordinary locals. Given fields are evaluated in source order, then omitted defaults in declaration order, each once. Test: an override skipping a default's evaluation, nested required fields, a refined default that doesn't fit (build error), writing a field of a nested `let` struct (build error). Globals, restored state and whole-value invariants are later.
- **Proofs stay sound under change:** facts about a variable end when it's assigned or passed as `write`; branch joins keep only what both sides prove; loops account for the back edge (what's true on entry must still hold after an iteration). Ranges from checked arithmetic hold only on the path where it succeeded; wrapping arithmetic gets the full range of its type. Add built-in two-argument `min(a, b)` and `max(a, b)` with matching base types. Test: a fact made stale by an assignment, narrowing by an early `continue`/`break`, a refined loop bound with T02's counter typing, and every place a value is stored (assignment, argument, return, field, enum payload).
- **Range edges:** an empty, reversed or out-of-base-type range in a refinement is a build error; named refinements are aliases. `..` is normalised to its inclusive form before `wrap`/`clamp` (so `int 0..360 wrap` is `0..=359`). Wrapping uses widened arithmetic, including a full-width `long` range. Test endpoints, negative values in `wrap`, a one-value range, stores through arguments and returns, a cast and a `fit` succeeding and failing, an invalid constant refinement, and arithmetic overflow happening before clamping.
- **Wording:** the contract is DESIGN.md's "The refinement contract": an unproven plain store is a build error, and only a written cast or `fit` adds a runtime check. LLVM facts from the analysis are M4, not this task.
