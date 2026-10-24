# T04 report: structs, refinements and writable parameters

## Built

Structs now support required fields, defaults, shorthand initializers, nested values, independent copies, field reads and writes, structural equality, and recursive printing. Initializers evaluate supplied fields in source order, followed by omitted defaults in declaration order; an overridden default is skipped.

Function parameters are read-only by default. `write T` passes an assignable place by reference, with exact type and refinement-policy matching. The checker rejects immutable or temporary write arguments and overlapping places by owner and complete field path, while allowing sibling fields and repeated reads. Call arguments keep left-to-right evaluation order.

Integer refinements support aliases, inclusive and exclusive bounds, checked stores, `wrap`, and `clamp`. The interval analysis tracks literals, refinements, arithmetic, `min`/`max`, comparison narrowing, branch joins, assignments, write calls, and loop back edges. It checks stores into assignments, arguments, returns, struct fields, and enum payloads. Explicit casts add runtime checks; `fit<T>()` returns `Option<T>`. `Option` and `Result` payloads accept structs and refinements. The T03 follow-up `x?.to_long()` works for `Option<int>`.

Constants are excluded from T04 as directed by the binding review and remain in T05. No external crates were added.

## Build and test

```sh
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build
cargo test
```

Both commands pass. `cargo test` reports 4 unit tests and 3 integration tests passing. The integration tests check all 91 `tests/run/` packages and all 7 `tests/test/` packages, including 36 new T04 run fixtures and one T04 test package.

## Choices for details left open

- Struct printing uses `Type { field: value, ... }` in declaration order. Tests cover nested output and structural comparison.
- Exclusive bounds are normalized to inclusive bounds before policy handling. Wrapping uses widened arithmetic, including a full-width `long` range.
- Globals, restored state, whole-value invariants, and `grow` parameters remain deferred as specified by T04 and its review.

## Remaining work

T04 is complete. Compile-time constants move to T05; later milestones retain the deferred features described in `docs/PLAN.md`.

## Fix 1

Equality branches now narrow to the compared constant; inequality branches exclude it when it is an interval endpoint. This also applies to supported `&&` and `||` paths and `continue` branches. Added run fixtures for endpoint narrowing, an unprovable interior case, and loop flow. `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` and `cargo test` pass.
