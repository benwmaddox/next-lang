# T01 report: the pipeline

## Built

The repository now has the planned Cargo workspace, a Rust `nlc` compiler, and a small C runtime. The compiler lexes and parses package files into span-bearing AST nodes, checks them into a typed representation with resolved local/function IDs, scope IDs, call edges, builtin effects, and explicit returns, emits LLVM IR from that typed form, then invokes clang.

The T01 subset includes functions and calls, `int`/`long`/`bool`, contextual integer literals, immutable and mutable locals, assignments and compound assignments, checked and wrapping arithmetic, checked casts, bit operations and shifts, comparisons, short-circuit booleans, `if` statements and expressions, and `print`. Runtime failures go through `nl_fail(kind, file_id, line, col)`; the runtime owns their messages and exit status. `nlc run` and `nlc build -o` are implemented. No external Rust crates were added.

## Build and test

```sh
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test
```

Both commands pass. `cargo test` reports 4 unit tests and 2 integration tests passing. The package integration test runs all 20 directories under `tests/run/`, including the required success, runtime-failure, and build-error cases. The other integration test uses `nlc build` to produce and run a native executable.

The compiler commands are:

```sh
nlc run <package-dir>
nlc build <package-dir> -o <file>
```

## Choices for details T01 and DESIGN left open

- Source `.nl` files are compiled in filename order. Runtime diagnostics use the source basename and point at the operator (`+`, `*`, `+=`, and so on), unary operator, or cast opening parenthesis. Columns currently count UTF-8 bytes.
- An `L` or `l` suffix fixes a literal as `long`; otherwise a literal uses its expected numeric type, then defaults to `int`. A literal on one side of a numeric operation takes the other side's type when that supplies context.
- `print(bool)` writes lowercase `true` or `false`. Runtime messages are `divide by zero`, `bad cast`, and `bad shift`, with operation-specific overflow messages for int and long addition, subtraction, multiplication, negation, and division.
- A final `if` without `else` is a statement. An `if` used for a value needs an `else`; a branch that returns on every path acts as `never` when matching branch types.
- A unit function may end with a unit-valued expression such as `print(...)`; a reachable non-unit tail in a unit function is an error. `main` must exist, take no arguments, and return unit for `run` and `build`.

## Remaining work and T02 handoff

Loops, `break`/`continue`, language `test` blocks, and `nlc test` remain for T02. T02 should add source byte offsets (or retained source slices) to spans so failed `expect` steps can show the original comparison without reevaluating either side. It will also need a checker/driver mode that accepts a package without `main` for `nlc test`, while still checking `main` if present. Keep the loop latch and every `break`, `continue`, and `return` edge explicit so M3 cleanup has one place to attach.

No changes to the milestone order are needed. The typed form already gives T02 resolved locals, explicit scopes, call edges, and control-flow returns to extend.
