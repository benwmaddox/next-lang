# T21 report: parse-only command and stable dumps

Implemented `nlc parse <package> [--tree] [--tokens]`. It lexes and parses every package source file without invoking the checker. With no dump option, successful input prints nothing; syntax errors use the existing `file:line:col: error: ...` format and exit status 2. Token text, tree node kinds and fields, byte spans, JSON escaping, decoded `u128` integer magnitudes, and parser resource limits are specified in [syntax-tree-format.md](../syntax-tree-format.md).

Added frozen snapshots and comparison tests for all packages in `tests/run/` and `tests/test/`, plus malformed and boundary cases for invalid escapes, unterminated strings, mismatched delimiters, non-UTF-8 input, integers beyond 128 bits, an empty file, a 70,000-byte line, and excessive nesting. `unknown_name` verifies that parse output succeeds even when checking would reject the package. Repeated parses produce identical dumps.

Five existing run fixtures (`t08_locked_unsupported`, `t11_anonymous_function`, and three `t19_*_limit` cases) are intentionally rejected during parsing, so their corpus entries record the syntax diagnostic rather than token/tree snapshots. This is the simplest reading of the corpus requirement for inputs the parser cannot turn into an AST.

Regenerate snapshots only after reviewing a format change:

```sh
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target scripts/update-parse-dumps.sh --update
```

Build and verify:

```sh
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test
```

No external crates were added. T21 has no remaining implementation work; S1 must reproduce the documented output and limits byte for byte.

## Fix round 1

Corrected parser spans so syntax nodes cover their complete constructs. Binary nodes now begin at the left operand and end at the right; unary and negative literal spans include their operands; postfix calls and accesses include their arguments or closing delimiter; declarations, statements, types, blocks, initializers, `if`, and `match` nodes retain their full source extent. The tree dumper now prints those parser spans directly. The binary checker keeps the operator as its diagnostic anchor, and synthesized implicit `default()` calls retain the `let` keyword as their diagnostic anchor.

Documented the full-construct span rule and the synthetic-node exceptions in `syntax-tree-format.md`. Tests check parent containment, source-ordered non-overlapping siblings, token-boundary alignment, and each `Program` through EOF for every successful corpus dump. Parser regressions compare source slices for the reported negative literal and binary chain, declarations, statements, and postfix/control-flow forms.

Successful frozen token/tree output is combined into one `.dump` file per package, using the same headers as `nlc parse --tokens --tree`. No stored dump exceeds 100 KB. The expression nesting stress fixtures, `t12_sort_specialization_limit`, and the 70,000-byte line are live-only: tests require two identical parses and validate the live tree structure. `tests/parse` is **1.9 MB allocated** (`du -sh`; 1,395,926 bytes of file contents).

Verified with:

```sh
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt -- --check
```
