# T26 report: never-returning functions

Implemented user-declared `-> never` functions and `fn(...) -> never` function types. The checker treats calls to them as `never`, so they work in value branches, match arms, function arguments, after `?`, and as tails. It rejects a never function that can complete normally, and rejects `return` in both statement and expression forms. The emitter lowers never calls as `void` calls followed by `unreachable`; direct and indirect calls are covered.

Updated the self-hosted CLI helpers (`usage`, `fail_tool`, `fail_diagnostic`, and `fail_lex`) to return `never`, removing the follow-up `env.exit` calls. Added run fixtures for the accepted positions, direct calls between never functions, a never callback called from a `Result`-returning `main`, fallthrough, both forms of `return`, and a function-value result mismatch. Added their frozen parse dumps.

`never` is accepted as a function result and function-type result only. This keeps it out of storable types and parameter positions. The callback that calls `Env.exit` uses `effects env`, since the existing full function contract records that effect; function result compatibility remains exact for `never`.

Validation passed:

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build`
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` (including the self-host comparison)
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt -- --check`
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target scripts/update-parse-dumps.sh --update`

No external crates were added. No T26 work remains; the next scheduled task can proceed.
