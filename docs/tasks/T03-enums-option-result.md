# T03: enums, match, Option and Result (milestone M1, part 1)

Depends on T01 and T02. Same rules (docs/PLAN.md, T01's Architecture section).

## Language

- **`enum`** with and without payloads: `enum Shape { Circle(int), Rect(int, int), Empty }`, `enum PostError { Empty, Full }`. Cases are written `Shape.Circle(3)` or, where the expected type is known, just `Circle(3)`. Enums are values (copied), laid out as a tag plus the largest payload.
- **`match e { pattern => expr, ... }`**, as an expression and a statement. Patterns: a case with bindings (`Circle(r) => …`), a case with `_` for unused payload parts, a literal (`0 => …`) for integer and bool matches, `_` as a catch-all. **Exhaustive:** a match that misses a case is a build error listing the missing cases; an unreachable arm is a build error too. Arms are separated by newlines or commas.
- **`Option<T>`** (`some(x)`, `none`) and **`Result<T, E>`** (`ok(x)`, `err(e)`), as ordinary generic enums in a small built-in prelude. `T` and `E` may be any type T01–T03 support (scalars, enums, `()`). Generics here mean only these two prelude types; user-written generics come later.
- **Operators** (DESIGN.md, "`?.` and `??`" and Effects/Result rules):
  - `x?` on a `Result` returns the error from the enclosing function, which must return a `Result` with the same error type (no conversion yet); on an `Option` it returns `none` from a function returning an `Option`.
  - `x?.f()`: if `x` is `none` the result is `none`, otherwise `some(x.f())`. If `f` itself returns an `Option`, the result is that `Option` (flattened, not nested): decided here, as most languages with `?.` do.
  - `x ?? d`: `x`'s value if present, else `d`, evaluated only then. `d` may be a value, `return …`, `continue` or `break`. `??` works on `Option` only; using it on a `Result` is a build error suggesting `match` or `.ok()`.
  - `.ok()` turns a `Result` into an `Option`; `.unwrap()` on an `Option` or `Result` fails the program (a structured failure, like overflow) if it's `none` or `err`; `.is_none()`, `.is_some()`, `.is_ok()`, `.is_err()`.
- `print` works on enums for testing (`Circle(3)`, `none`, `ok(5)`), and `expect a == b` compares and shows them.

## Tests

- `tests/run/` and `tests/test/` cases for: payload and no-payload enums; nested matches; match as an expression; literal patterns; `?` on Result and Option; `?.` with a plain and an `Option`-returning method; `??` with a value, `return`, `continue`, `break`; `.unwrap()` failing with its line.
- Build errors: a non-exhaustive match (listing the missing cases); an unreachable arm; `??` on a `Result`; `?` in a function whose result type doesn't match; an unknown case name with a "did you mean".

## Report

docs/tasks/T03-report.md.

## Decisions from Sol's review (docs/reviews/sol-T03-T04-r1.md), all binding

- **`?.` flattens** (Ben, 2026-10-24; DESIGN.md updated): `x?.f()` on `none` gives `none`; otherwise the call's result, wrapped in `some` unless it's already an `Option`. `x?.f(a)` calls a named function as `f(value, a)` (there are no user methods yet: a name after `.` resolves to a function whose first parameter takes the value). `?.` on a `Result` receiver is a build error. Test: the receiver evaluated once; arguments not evaluated when it's `none`; a flattened and a plain result; precedence with `?` and `??`.
- **Exits:** `?` and `?? return` leave through every enclosing loop's cleanup hook (T02); `?? break`/`?? continue` target the nearest loop, and outside a loop they're build errors. `?` and `?? return` directly in a test body are build errors, as `return` is (T02). An alternative that leaves (`return`, `break`, `continue`) counts as diverging when the expression's type is checked. Test: different success types with the same error type; a mismatched error type (build error); a present value skipping the fallback; exits from nested loops.
- **Constructors and patterns:** `none` and `err(e)` get their missing type parameters from the expected type; with nothing to infer from, it's a build error asking for a type, never a guess. Unqualified cases resolve from context; an ambiguous one needs qualifying. The scrutinee is evaluated once. Payload bindings are immutable copies scoped to their arm. Reachable arms must have compatible types; diverging arms are allowed. A `bool` match needs both `true` and `false` or `_`; an integer match needs `_`. Duplicate or already-covered arms, and the wrong number of payload bindings, are build errors. Test: qualified patterns, shadowing in arms, a match with no arms on an enum that has cases (build error), case-name collisions across files, arms that are blocks with statements.
- **Representation:** a value type that contains itself, directly or through another enum, `Option` or `Result`, is a build error (it would have infinite size). Equality is structural: same case, equal payloads, never comparing padding or unused payload bytes. No ordering yet. `print` format: `Circle(3)`, `Rect(2, 3)`, `Empty`, `some(ok(5))`, nested the same way. Aggregates go through T01's shared signature-lowering path.
