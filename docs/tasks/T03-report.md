# T03 report: enums, match, Option and Result

## Built

Enums now support payload and no-payload cases, qualified and context-resolved constructors, copied values, structural equality, and recursive printing. The compiler rejects infinite-size enum cycles, including cycles through `Option` and `Result`. `match` works as an expression or statement, evaluates its scrutinee once, scopes immutable payload copies to each arm, and checks exhaustiveness, duplicate or covered patterns, payload arity, and compatible arm types. Integer and boolean literals and catch-all patterns are supported.

The built-in generic `Option<T>` and `Result<T, E>` support all T03 payload types, including unit. The implementation adds `some`/`none`, `ok`/`err`, the requested query and unwrap methods, and `.ok()`. `?` propagates matching errors or `none`; `?.` skips argument evaluation for `none`, evaluates the receiver once, and flattens an Option-returning function call; `??` evaluates its fallback only when needed and supports value and control-flow exits. Propagation and exits preserve T02 loop cleanup edges. Runtime unwrap failures report their source location. No external Rust crates were added.

## Build and test

```sh
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build
cargo test
```

Both commands pass. `cargo test` reports 4 unit tests and 3 integration tests passing. The integration tests check all 55 `tests/run/` packages and all 6 `tests/test/` packages, including T03 success, type-error, exhaustiveness, reachability, propagation, optional-call, structural-equality, and runtime-unwrap cases.

## Choices for details left open

- Optional chaining follows the binding T03 review decision: `x?.f()` flattens an Option result. It resolves `f` as a function whose first parameter accepts `x`; T03 does not introduce user-defined methods.
- The prelude provides generic `Option` and `Result`; user-written generic declarations remain deferred. Enum values use a tag and byte storage sized for the largest payload. Structural equality reads only the active case and its payload, so padding and inactive payload bytes do not affect equality.
- Match arms may be comma or newline separated. Diverging arms are accepted alongside arms that produce values.

## Remaining work

T03 is complete. User-defined generics, structs, writable parameters, refinements, and the other later milestones remain as described in `docs/PLAN.md`.
