# H1: the self-hosted front end feeding the Rust compiler (hybrid track, step 1)

Depends on S1a and T29. Read docs/PLAN.md "Hybrid track", docs/syntax-tree-format.md, docs/tasks/S1a-2-report.md (the self-hosted parser's postorder encoding), compiler/src/ast.rs, parser.rs and driver.rs.

The self-hosted lexer and parser reproduce `nlc parse` byte for byte. This step makes them `nlc`'s actual front end: the Rust compiler runs the self-hosted parser, reads its tree, and continues with the Rust checker and code generator.

## The tree format

- A compact binary format (documented in docs/tree-binary-format.md, versioned) holding exactly what `ast.rs` holds for a package: files (names, sizes), the postorder node list (kind, flags, main token, span, subtree size), extra data, literal values (four-limb magnitudes), decoded strings and byte strings, and every field the text dump omits (such as the byte-string hex-origin flag). Little-endian fixed-width integers; offsets into the file rather than pointers; a header with a magic number, the format version and the counts, so a reader checks sizes before reading.
- `nlc run selfhost -- parse <package> --binary <out-file>` writes it (the self-hosted parser already holds this data). The writer streams through its output buffer.
- A Rust reader, `compiler/src/tree_reader.rs`, rebuilds `ast.rs` values from it, validating every index and count (a malformed file is a tool failure naming the problem, never a panic).

## Wiring into nlc

- `--frontend=rust|selfhost` on `nlc run`, `build`, `test`, `check` (if it exists) and `parse` (default `rust` in this task). With `selfhost`, nlc builds the self-hosted front end once (cached under the target directory, keyed by a hash of selfhost/ sources and the compiler version), runs it on the package, reads the tree and continues. Syntax errors come from the self-hosted parser's stderr and exit status unchanged.
- An environment variable `NLC_FRONTEND` sets the default, so the whole test suite can run either way.
- Timing: report the front-end time both ways on the 54,145-line benchmark (self-hosted parse plus write plus read, against the Rust parser).

## Acceptance

- **Round-trip equality:** for every package under tests/run, tests/test and tests/parse/cases, the `ast.rs` value rebuilt from the binary tree equals the one the Rust parser builds (a structural comparison in a cargo test, not just matching dumps).
- **Whole suite both ways:** `cargo test` with `NLC_FRONTEND=selfhost` passes everything that passes with `rust` (run, test and parse fixtures, compiler tests), with identical stdout, stderr and exit statuses.
- Malformed binary files (truncated, wrong version, an index out of range) give clear tool failures.
- The S1a comparisons keep passing.
- Report: docs/tasks/H1-report.md, with the timings and a recommendation on making `selfhost` the default.
