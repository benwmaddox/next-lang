# T14 report: ASCII values in regions

Implemented bounded `Ascii max N` values across parsing, checking, typed IR, LLVM emission, and the C runtime. ASCII literals are compile-time checked and use their exact length; concatenation, bytewise comparisons, NUL handling, uppercase conversion, integer formatting, `fit`, checked casts, printing, and `expect` are covered by fixtures.

The checker tracks ASCII length ranges and growth through direct and indirect calls, including `grow` parameter forwarding. It requires proof for plain append, reports `Full` from `try_append` without changing the builder, restricts `write` to length-preserving replacement, and rejects invalid `take` use, branch-dependent moves, use after move, moves beyond a reserved region, and widening a moved builder beyond its reservation. It reserves maximum-sized regions for values that may grow later, including values reachable through `take` and function values. Finished values use their actual byte length. Copies of ASCII values nested in `Option` and `Result` rebase their descriptors into the destination region.

LLVM `noalias` is emitted only for parameter ranges proven disjoint; calls with hidden result destinations do not claim `noalias` when the destination may overlap an argument. Appending writes into the existing reserved region without allocating a second stack region. Self-concatenation builds in scratch storage before replacing the original bytes.

## Acceptance coverage

- `tests/run/t14_ascii_values` covers read parameters and results, local returns and copies, `take`, `grow` forwarding, bounded concatenation, `try_append` failure preservation, `fit`, checked casts, integer and long extremes, NUL bytes, bytewise ordering, self-concatenation, nested `Option`/`Result` values, and three live builders.
- `tests/run/t14_ascii_move_escape` checks that a moved builder cannot escape through an `Option` result; `t14_ascii_move_branch`, `t14_ascii_use_after_take`, and `t14_ascii_take_widen` cover the other move errors.
- `tests/run/t14_ascii_loops` runs 100,000 iterations with 1 KB temporaries, including `break`, `continue`, nested-loop `return`, and `?` cleanup.
- `tests/run/t14_ascii_cast_failure`, `t14_ascii_non_ascii`, and `t14_ascii_write_append` cover the required runtime and build errors.
- `tests/run/t14_ascii_packed` and `compiler/tests/ascii_values.rs` check exact-size finished reservations, hidden-result alias claims, and the absence of per-append stack allocation. `tests/test/t14_ascii_expect` covers ASCII comparisons and uppercase handling in `expect`.

The grammar has no standalone block expression that can be bound outside its inner scope. The escaping-move rejection is therefore exercised with a function result, while the separate branch-dependent move fixture checks the conditional case.

## Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — passed (31 tests across the unit and integration suites; doc-tests also passed).
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target scripts/update-parse-dumps.sh --update` — refreshed parse snapshots for the new fixtures.

## Fix round 1

The LLVM emitter now maps every `Ascii max N` descriptor to the shared `%nl.ascii` layout. This lets the six bytewise comparison operators use operands with different maxima, including literals, without emitting mismatched named aggregate types. `Option<Ascii max N>` variants also share one LLVM representation so structural equality can compare options with different maxima.

The checker now joins `if` branches with different Ascii maxima and accepts an Ascii-returning function with a smaller result maximum where a wider callback result is expected. ASCII values are supported as map and set keys; each slot has backing bytes for a stable key copy, and hashing includes its length and bytes. Compaction and value copies rebase those key descriptors into their destination storage.

`tests/run/t14_ascii_mixed_max` prints results for `==`, `!=`, `<`, `<=`, `>`, and `>=` across different maxima, as well as read arguments, function returns and callback values, mixed-max branches, assignment, concatenation, match comparisons, `Option` equality, and map/set keys. `tests/test/t14_ascii_expect` also checks mixed-max expectation comparisons.

### Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — passed (31 unit and integration tests; doc-tests also passed).
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt -- --check` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target scripts/update-parse-dumps.sh --update` — refreshed the mixed-max run fixture and Ascii expectation snapshots.

## Fix round 2

ASCII widening during a store now changes the typed expression to the expected maximum. Constructors therefore carry payloads with the exact type declared by their `Option`, `Result`, or enum case, instead of passing a smaller `Ascii max N` payload through to the emitter. Equality operand checking also uses a known sum type on the right to type a context-sensitive constructor on the left; the existing independent comparison path remains in place for `Option<Ascii>` values with different maxima.

`tests/run/t14_ascii_mixed_max` now covers both operand orders for `some` equality and inequality, as well as `none`, `ok` and `err`, enum payloads, smaller-maximum payloads, a struct literal with an Ascii field, and nested `some(some("ab"))`. `tests/test/t14_ascii_expect` checks `expect o == some("ab")`.

### Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — passed (31 unit and integration tests; doc-tests also passed).
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt -- --check` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target scripts/update-parse-dumps.sh --update` — refreshed the mixed-max run and Ascii expectation snapshots.
