# T11 implementation report: function values

## Delivered

- Added function types with exact parameter types and modes, exact result types, and `print`, `reads`, and `writes` effect bounds. Global effect paths accept struct fields. Pure functions fit wider effect bounds; assigning a function with an unallowed effect reports that effect.
- Named top-level functions are pointer-sized values. They can be inferred into locals, passed as parameters, returned, stored in struct fields, arrays, lists, maps and globals, and called through those values. Function fields have no default and are required in struct literals. Closures and anonymous functions produce build errors.
- Indirect calls carry edges to every address-taken function with matching parameters, modes and result whose inferred effects fit the call type. Those edges feed recursion detection, constant cacheability, transitive global effect checks and write/view overlap checks.
- Function equality compares identity, and printing a function emits its top-level name. Concrete owner-typed signatures such as `fn(Id<app.nodes>) -> long` work. Owner- and capacity-generic functions are rejected as values. Suspension, append mode and data-stack contracts remain deferred to M3 and later; sorting remains T12.
- Added T11 run fixtures for storage and calls across the required value locations, effect bounds, indirect recursion, constant effects, global writes, generic function rejection, anonymous functions, identity/printing, and missing function fields.

## Decisions

- Function values use LLVM function pointers and globals can hold static function-pointer relocations. The emitted function type occupies one pointer-sized slot.
- `reads app` and `writes app` cover matching nested paths such as `app.score`; a more specific bound does not cover its parent or a sibling field.
- Enum constructor syntax remains distinguished by type-style uppercase names; lowercase value receivers can call function fields even when the field name overlaps a built-in method name.
- No task requirement was impossible or contradictory. No external crates were added.

## Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — passed: 6 unit tests, 2 collection IR tests, 3 globals tests, 3 language integration tests (including all run and test fixtures), 1 pool IR test, and doc tests.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt -- --check` — passed.

## Fix round 1

- Function types may omit `-> result`; this means `()`, including when an `effects` clause follows. Explicit `-> ()` remains supported. Incompatible parameter modes now report the parameter number and expected and actual mode.
- A `writes P` effect bound covers reads of `P` and descendant paths as well as writes; `reads P` still does not cover writes. Updated the Functions as values section in `docs/DESIGN.md` to state this rule.
- Added run fixtures for no-result function values called through a list and a struct field, a write-mode callback that changes its caller's variable, a writes bound that covers compound-assignment reads, and a reads-only bound that rejects writes.

### Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — passed: 6 unit tests, 2 collection IR tests, 3 globals tests, 3 language integration tests (including all run and test fixtures), 1 pool IR test, and doc tests.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt -- --check` — passed.
