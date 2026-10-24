# T07 implementation report

Implemented the pool and owner-parameter milestone across parsing, type checking, compile-time evaluation, and native code generation.

## Delivered

- Added `pool<T, N>` declarations, empty pool literals, owner-qualified `Id` types, dotted owner paths, and owner/capacity parameters on reusable definitions.
- Lowered pools as fixed field lanes with occupied flags, generations, and a free-slot stack. `add`, `get`, `remove`, `contains`, and `count` use generation-checked 64-bit IDs; removal retires slots rather than wrapping the maximum generation.
- Added slot-ordered pool iteration over a snapshot of occupied slots, immutable ID bindings, and writable element views. Added pool printing and same-owner equality that ignores free-list order and vacant history.
- Added owner inference and capacity specialization for generic functions. Owners are erased from generated code; capacity specializations are limited to 10,000.
- Added owner and lifetime checks, including paths such as `state.nodes`, errors for IDs that escape a local pool, and recursive restrictions on copying, returning, or replacing values containing pools.
- Added pool operations and pool iteration to constant evaluation, with a fixture comparing compile-time and runtime scalar results.
- Added runtime fixtures for pool operations, snapshots, nested lists, ownership, views, capacity rules, and rejection cases, plus IR checks for layout, generation retirement, owner erasure, and nested list lanes.

## Decisions and boundaries

- Following the task and second review, a pool-valued constant is rejected; compile-time functions may use local pools and return ordinary values.
- Pools inside array or list elements, including through structs, are rejected because each repeated element would require a distinct owner. Pool elements that themselves contain pools are also rejected for the same owner/copy boundary.
- Pool copies, returns, and resets remain rejected, including when hidden inside an aggregate. Supporting copies with owner rebinding remains later work.
- Pool capacities above 2^32 and allocations exceeding the task's 64 KB temporary stack limit are rejected. Capacity zero remains supported.

## Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `cargo test` — passed: 6 unit tests, 1 collection IR test, 3 language test-harness tests (including all run fixtures), 1 pool IR test, and doc tests.
- `cargo fmt --all -- --check` and `git diff --check` — passed.

No external crates were added. No commits or branch changes were made.

## Fix 1

- Generic type parsing now splits `>>` and `>>=` into closing `>` tokens only in type contexts; three adjacent closers also parse correctly.
- Added `t07_nested_types` run coverage for nested fields, locals, parameters and return types, plus `>>` and `>>=` expressions.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` and `cargo test` passed.
