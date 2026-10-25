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

## Corrections from Sol's review (docs/reviews/sol-H1-r1.md), binding; they override the text above where they differ

Read the review for the evidence behind each point.

1. **Every span, explicitly:** write an AST-field-to-wire table in docs/tree-binary-format.md covering every field of ast.rs, including all diagnostic spans (operator, call including the whole grouped callee, case, method, field, index, cast, range, effect root, pattern name, binding) and synthetic nodes (`default` with its zero-width expression span and its call span at `let`). Each is either stored or reconstructed losslessly by a stated rule. Add grouped and multiline callees, ignored bindings, effects and synthetic-node diagnostic cases.
2. **Store what the self-hosted parser now computes only on output or discards:** child roles and counts (type constant arguments and array capacities kept separately, as `TypeAst` does), synthesised names, decoded strings with byte lengths and hex-origin flags, test names, `expect` sources, signed range bounds and four-limb magnitudes, and both `StmtKind::Block` and its `Block` where one syntax node yields two. The wire carries lengths, bytes and indexes, never T29's in-memory layout or descriptors.
3. **Acceptance is differential AST equality:** derive or write equality for the AST types and compare the ordered programs plus file identities, every variant, value and span, for every syntactically valid package (checker-invalid ones included), and the first diagnostic and status for syntax failures; extend S1a's generated, mutation and boundary cases, not just repository fixtures. Don't normalise spans away.
4. **Driver semantics:** the compile path (driver.rs 360-411) and the parse path (182-310) apply different file, byte, node and work policies and report invalid UTF-8 differently; the self-hosted front end follows the parse path today. Reconcile: preserve each command's existing behaviour, or make and document one intentional change with tests. Rebuild the per-file declaration vectors in original order with stable file ids, so the checker visits declarations exactly as now; test several checker errors across categories and files, an earlier syntax error against a later input failure, byte columns, and duplicate-declaration "first line" messages.
5. **Bootstrap:** building the self-hosted front end always uses an internal Rust-only path that ignores `--frontend` and `NLC_FRONTEND` (and the S1a comparison pins the Rust reference the same way). CLI flags override the environment; `--frontend` goes before `run`'s `--`. Locate selfhost/ independently of the caller's working directory. Test an empty cache with `NLC_FRONTEND=selfhost`.
6. **Cache key:** the sorted selfhost source paths and contents, its package.toml, the nlc build identity (a hash of the binary or a build id, not the crate version), the runtime's content, target, optimisation level and toolchain, and the wire version. Cache under the target directory; serialise concurrent builders with a lock and publish atomically; test each invalidation, missing and corrupt artifacts, and simultaneous cold starts; use a unique tree file per invocation.
7. **Transport:** the self-hosted parser writes the binary tree to stdout (`parse <package> --binary`), and nlc redirects that into a unique temporary file (or reads the pipe), since `fs.write` truncates on every call and can't stream. Define the child's working directory and the package-root mapping (rooted I/O refuses absolute paths; fixtures pass absolute paths, so nlc runs the child from the package's parent or passes a relative path) and the symlink policy. Syntax errors: forward the child's stderr once, status 2. Launch failures, signals, write and protocol errors are tool failures; a partial tree is never used.
8. **Reader validation before allocation:** check arithmetic overflow, section extents, tags and flags, child counts and roles, subtree partitioning, roots and file ownership, UTF-8 names versus raw byte strings, span bounds; cap allocations and depth and work before rebuilding; no recursion in the reader or in dropping a deep tree. Malformed fixtures for each, including valid-size headers with impossible trees. Include what's needed to turn spans into line and column (a line-start index per file, or the source) and define how `parse --tokens` still gets raw spellings without Rust relexing.
9. **Measure after T29:** use a line-start index (not prefix rescans) for positions; measure warm subprocess plus write plus read plus rebuild time, parent and child memory, cold bootstrap separately, repeated small packages and the benchmark; report wire size, RSS, reservation and stack bounds. The default stays `rust` in H1; switching is a separate decision after the report.
10. **H2 is narrowed** (PLAN updated): an ordered top-level declaration index with stable file and node ids and exact duplicate and error precedence, consumed through an explicit seam in the Rust checker, compared both ways. Name resolution, type elaboration, constant evaluation and typed output are later, separately specified steps.
