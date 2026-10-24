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
