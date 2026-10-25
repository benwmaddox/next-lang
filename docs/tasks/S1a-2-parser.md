# S1a-2: the self-hosted parser and tree dump (self-hosting step S1a, part 2)

Depends on S1a-1 and T26. Read docs/PLAN.md "Self-hosting track", docs/research/selfhost-architecture.md section 5.1 (revision 2; where it describes the Rust parser before T22, the current parser.rs wins: every counted path is limited to 1,000 and `else if` chains are parsed iteratively), docs/reviews/sol-selfhost-arch-r1.md points 5 to 9, docs/syntax-tree-format.md, compiler/src/parser.rs, ast.rs, syntax_dump.rs and driver.rs, and S1a-1's code and report.

Extend `selfhost/` so `nlc run selfhost -- parse <package> [--tokens] [--tree]` reproduces `nlc parse` **byte for byte** (stdout, stderr, exit status) for every flag combination: none (syntax errors only), `--tokens`, `--tree`, both (with the `== tokens ==` / `== tree ==` headers).

## Design (binding)

- **Node storage:** one postorder node list per package on `main`'s data stack (children before their parent; every subtree contiguous; a subtree size per node, so no child-edge array), plus an extra-data list and a literal-value list, as the research report's node-encoding table describes (main token for names; flags for booleans and small enums; extra data for second names, generic and index lists, ranges, byte strings, effect paths and `expect` sources; synthetic nodes with explicit spans). Spans and token starts are file-relative. Nothing is added that would change the reference's node, edge or work counts.
- **Parser:** recursive descent mirroring parser.rs function by function, so tokens are consumed and errors raised in the same order. Recursion only along paths parser.rs counts (each limited to 1,000 now); mark those functions `recursive`. `else if` chains with explicit frames, as parser.rs now does. Port the completed-tree nesting walk (`expression_nesting_exceeded`) task for task over each outermost expression's postorder range, pushing children in the same order and running it at the same moment, with the same diagnostic span rule.
- **Native stack:** measure the recursion budget each counted path needs at its 1,000 limit (T19's report gives the method) and show at least a 2x margin under the default budget; any path that misses it moves to explicit frames.
- **Integer literals:** decode magnitudes into four 32-bit limbs held in non-negative `long`s; detect overflow past 2^128 - 1 with Rust's exact message; range endpoints follow Rust's i128 rule; print magnitudes in decimal by dividing by 10^9 limb by limb.
- **Limits and order:** the package flow continues in driver.rs's order after lexing: per-file tree counting, then cumulative node, edge and work limits, each at the point Rust checks it, with Rust's messages (sol-selfhost-arch-r1.md point 5).
- **Printer:** preorder from postorder with an explicit `{node, depth}` stack (children found right to left by subtree sizes and pushed so the first child pops first); output streamed through the 1 MiB `Bytes` buffer; JSON escaping and field order exactly as syntax_dump.rs.
- **Decoded values:** byte-string and string values are printed decoded, so escape-decoding bugs that the token dump couldn't see are compared here.

## Comparison and acceptance

- Extend scripts/compare-selfhost.sh with `--parse` (all four flag combinations) over tests/run, tests/test and tests/parse/cases, and over S1a-1's directed and mutation cases; keep the `--tokens`/lex comparison.
- Parser-specific directed cases: every node kind and field in syntax-tree-format.md at least once; every counted nesting path at 1,000 and 1,001 (parentheses, unary, binary chains, calls, casts, blocks, types, `if`/`match`, `else if`); the completed-tree walk's error span for a binary chain; integer literals at 2^64 - 1, 2^64, 2^127, 2^128 - 1, 2^128 in decimal, hex and binary, with underscores, `L`/`l` suffixes, negative literals and refinement endpoints at the i128 edges; synthetic nodes (`default()`, match-arm blocks, `else if` blocks); `pool<T, N, Owner>` argument order; a type-error package (must still dump: the checker never runs); a package where a later file has a syntax error (no stdout); node, edge and work limits at N and N + 1.
- A mutation pass with a new fixed seed (a few hundred cases) under `--parse --tree`.
- The 54,145-line benchmark under `parse --tokens --tree`: time and peak memory for both, reserved versus touched for the self-hosted parser.
- Report: docs/tasks/S1a-2-report.md with the same sections as S1a-1's (implementation, comparison, timing and memory, forced boilerplate versus missing features, compiler fixes, wanted features).
