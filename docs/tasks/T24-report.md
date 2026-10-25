# T24 report

Implemented the pre-S1 language and CLI items.

- `Env.exit(code)` requires the `env` capability, checks `code` as `int 0..=125`, and has the existing `never` type. The runtime flushes stdout and stderr before exiting. In a test process it prints a failure message and exits with status 70; `nlc test` records that test as failed and continues with the remaining tests.
- `[ ... ]` literals take their array or list type from context. Arrays require exactly their declared length; lists may contain up to their capacity. Nested literals and trailing commas work. Const and global array/list values are evaluated and emitted as static data. Large constant reads use that static storage directly.
- String escapes now include `\xNN` with exactly two hex digits. High-byte escapes are rejected when a plain literal is used as `Text` or `Ascii`; byte strings retain the raw byte. The parse corpus and [syntax tree format](../syntax-tree-format.md) document the new literal and dump representation.
- Crossed `Option`/`Result` cases now report the value type and the valid case names.
- CLI stdout writes handle a closed pipe quietly. The integration test covers `run`, `build`, `test`, `parse`, and all three `inspect` commands. `nlc run` still returns the launched program's own exit status.

The 10,000-element `const TABLE: int[10000]` package built in **0.399 seconds** in this WSL workspace. Running the built program printed `9999`.

Validation passed:

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build`
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test`
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target scripts/update-parse-dumps.sh --update`

## Fix round 1

- `never` now passes store and expected-type checks without losing its bottom type. The `env.exit(2)` and `env.exit(3)` fixtures return `Result<(), IoError>` directly; additional fixtures cover an `if` value branch, a `match` arm, and an exit after `?`.
- Constant evaluation preserves string bytes as string values. The emitter writes deduplicated backing bytes and static descriptors for `Ascii`, `Text`, and `Bytes` elements in const and global arrays and lists. Const arrays can be iterated as read-only collections; the string-table fixture reads all three string types by index, in loops, and from match arms. Enum constants whose payload contains a growing string type are rejected by the checker with a specific message rather than reaching an emitter panic.
- `for` collection and range heads, `if` conditions, and `match` scrutinees now treat a capitalised name before `{` as the name. Parenthesized expressions enable struct literals in those heads. The rule is in [syntax tree format](../syntax-tree-format.md), and `control_flow_heads` is in the parse corpus.
- Chosen type spelling: parenthesized parameterised types are supported, including `(Ascii max 8)[3]`. The ambiguous `Ascii max 8[3]` form now reports the working spelling.

Validation passed:

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build`
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test`
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt -- --check`
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target scripts/update-parse-dumps.sh --update`
