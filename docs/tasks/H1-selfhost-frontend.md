# H1: the self-hosted front end feeding the Rust compiler (hybrid track, step 1)

Depends on S1a and T29; runs after O1 (docs/PLAN.md "Order of work"). Read docs/PLAN.md "Hybrid track", docs/syntax-tree-format.md, docs/tasks/S1a-2-report.md (the self-hosted parser's postorder encoding), compiler/src/ast.rs, parser.rs and driver.rs. This spec incorporates docs/reviews/sol-H1-r1.md; read it for the evidence behind each requirement.

The self-hosted lexer and parser reproduce `nlc parse` byte for byte. This step adds them to `nlc` as a selectable front end: the Rust compiler runs the self-hosted parser, reads its tree, and continues with the Rust checker and code generator. The Rust front end stays the default in H1 (see "The default", below).

## The tree format

- A compact binary format, documented in docs/tree-binary-format.md and versioned, holding exactly what `ast.rs` holds for a package. Little-endian fixed-width integers; offsets into the file rather than pointers; a header with a magic number, the format version and the counts, so a reader checks sizes before reading.
- **An AST-field-to-wire table** in docs/tree-binary-format.md covers every field of `ast.rs`. Each field is either stored or reconstructed losslessly by a stated rule. That includes:
  - files (names, sizes, stable file ids) and the postorder node list (kind, flags, main token, span, subtree size), extra data and literals;
  - every diagnostic span, not one span per node: operator, call (including the whole grouped callee, which Rust keeps as `Call.call_span`), case, method, field, index, cast, range, effect root, pattern name and binding;
  - synthetic nodes: `default` with its zero-width expression span and its call span at `let`;
  - what a line and column need: a line-start index per file (or the source), so spans turn into positions without prefix rescans.
- **Store what the self-hosted parser now computes only on output, or discards.** It doesn't hold all of this yet; add the parser metadata needed. Child roles and counts (type constant arguments and array capacities kept separately, as `TypeAst` does), synthesised names, decoded strings and byte strings with their byte lengths and hex-origin flags, test names, `expect` sources, signed range bounds and four-limb magnitudes, and both `StmtKind::Block` and its `Block` where one syntax node yields two.
- The wire carries lengths, bytes and indexes, never T29's in-memory layout or transient descriptors.

## Transport

- `nlc run selfhost -- parse <package> --binary` writes the binary tree to stdout through its output buffer. nlc redirects stdout into a unique temporary file per invocation (or reads the pipe), and uses the tree only after the child exits successfully. (`fs.write` truncates on every call, so the child can't stream into a named file.)
- **Working directory and paths:** rooted I/O refuses absolute paths, and fixtures pass absolute package paths, so nlc runs the child from the package's parent directory and passes a relative path. Locate selfhost/ independently of the caller's working directory. Define the symlink policy in docs/tree-binary-format.md and test it.
- **Failures:** a syntax error forwards the child's stderr once, with status 2. Launch failures, signals, write errors and protocol errors are tool failures. A partial tree is never used.
- **Tokens:** define how `parse --tokens` with `--frontend=selfhost` still prints raw spellings without the Rust lexer relexing the source (the child prints them, or the wire carries them).

## Command policy

The parse path and the compile path in driver.rs apply different file, byte, token, node and work limits, and report invalid UTF-8 differently (the parse path as a source diagnostic, the compile path as a tool failure). The self-hosted loader follows the parse path today. H1 preserves each command's current limits, error precedence and statuses: nlc passes the child an explicit command policy, and the Rust reference path uses that same policy. Unifying the commands' limits is a separate, separately tested change, not part of H1.

## The Rust reader

- `compiler/src/tree_reader.rs` rebuilds `ast.rs` values from the binary tree. A malformed file is a tool failure naming the problem, never a panic.
- **Validate before allocating or rebuilding:** arithmetic overflow, section extents, tags and flags, child counts and roles, subtree partitioning, roots and file ownership, UTF-8 names versus raw byte strings, and span bounds. Cap allocations, depth and work before rebuilding. No recursion in the reader, or in dropping a deep tree.
- Rebuild the per-file declaration vectors in original order with stable file ids, so the checker visits declarations exactly as it does with the Rust parser.

## Wiring into nlc

- `--frontend=rust|selfhost` on `nlc run`, `build`, `test`, `check` (if it exists) and `parse`. An environment variable `NLC_FRONTEND` sets the default, so the whole test suite can run either way. CLI flags override the environment; `--frontend` goes before `run`'s `--`.
- **Bootstrap:** building the self-hosted front end always uses an internal Rust-only path that ignores `--frontend` and `NLC_FRONTEND`; the S1a comparison pins the Rust reference the same way. Until O6 brings the self-hosted code to offset mode, that build uses pointer mode explicitly (`NLC_STACK_MODE=pointer`), whatever the caller's setting; O7 removes this exception with pointer mode.
- **Cache:** the built front end is cached under the target directory, keyed by the sorted selfhost source paths and contents, its package.toml, the nlc build identity (a hash of the binary or a build id, not the crate version), the runtime's content, the target, the effective optimisation level, stack mode and code-generation settings, the toolchain, and the wire version. A lock serialises concurrent cold builds, and a successful build is published atomically.

## The default

`rust` stays the default front end in H1. H1's report gives a recommendation; switching production parsing to `selfhost` is a separate, recorded decision after it. After that switch, the Rust parser stays selectable as the reference the comparisons use, with no automatic production fallback. Retiring the rest of the Rust compiler is a later, separate decision (PLAN "Self-hosting track").

## Acceptance

- **Differential AST equality:** derive or write equality for the AST types. For every syntactically valid package (checker-invalid ones included), the ordered programs plus file identities rebuilt from the binary tree equal those the Rust parser builds, in every variant, value and span; spans are not normalised away. For syntax failures, the first diagnostic and the status match. Inputs: every package under tests/run, tests/test and tests/parse/cases, plus S1a's generated, mutation and boundary cases, extended with grouped and multiline callees, ignored bindings, effects and synthetic-node diagnostic cases.
- **Whole suite both ways:** `cargo test` with `NLC_FRONTEND=selfhost` passes everything that passes with `rust` (run, test and parse fixtures, compiler tests), with identical stdout, stderr and exit statuses.
- **Checker order:** several checker errors across categories and files, an earlier syntax error against a later input failure, byte columns, and duplicate-declaration "first line" messages, all identical both ways.
- **Command policy:** each command's limits and invalid-UTF-8 behaviour identical both ways, at N and N+1 of each limit.
- **Malformed trees:** fixtures for each validation rule (truncated file, wrong version, an index out of range, overflowing extents, bad tags, impossible subtree partitions, valid-size headers with impossible trees, spans out of bounds), each a clear tool failure.
- **Cache and bootstrap:** an empty cache with `NLC_FRONTEND=selfhost`; each cache-key input invalidating the artifact; missing and corrupt artifacts; simultaneous cold starts.
- **Transport:** a syntax error forwarded once with status 2; a child killed by a signal and a truncated stdout are tool failures; the symlink policy.
- The S1a comparisons keep passing.
- **Measurements:** warm subprocess plus write plus read plus rebuild time against the Rust parser, on the 54,145-line benchmark and on repeated small packages; cold bootstrap separately; parent and child memory (RSS), wire size, reservation and stack bounds.
- Report: docs/tasks/H1-report.md, with the timings and a recommendation on making `selfhost` the default.

H2 (the next step) is an ordered top-level declaration index consumed through an explicit seam in the Rust checker, specified separately (PLAN "Hybrid track").
