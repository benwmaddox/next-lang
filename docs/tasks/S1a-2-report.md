# S1a-2 implementation report

## Implementation

Added the parser and tree dumper in `selfhost/parser.nl` and `selfhost/parse_output.nl`. `ParseTables` holds one package-wide postorder node list, extra-data and four-limb literal tables, parser state, and caller-owned nesting, match, `if`, `for`, and scratch frames. Each node stores a subtree size instead of child edges. `append_node` verifies that child subtrees are contiguous; bare names are delayed until postfix parsing resolves them, and replacement postfix forms remove their provisional node subtree before appending the parent.

The parser mirrors the Rust recursive-descent paths, including its error order, 1,000-level counters, expression-tree nesting walk, and diagnostic anchors. Large traversal and chain state stays in `ParseTables`, with checkpoints for iterative `else if`, nested `match` arms, and nested `for` bodies. A parser cursor represents `>` pieces from `>>` and `>>=` without modifying lexer tokens or token counts. Integer magnitudes use four nonnegative 32-bit limbs.

`load_and_parse` reads, validates, lexes, token-checks, parses, and counts each file before reading the next one. It applies per-file and cumulative node, edge, and work checks in driver order, retaining successful data for the final output. The tree printer walks postorder nodes with an explicit stack and writes through its 1 MiB buffer. Token-bearing diagnostics and reconstructed fields stream from source slices, including long duplicate-generic and unknown-effect names. The `ByteString` encoding retains the non-ASCII-hex-escape flag for S2.

The CLI now accepts `parse <package> [--tokens] [--tree]`. Updated `docs/syntax-tree-format.md` with `Take`, `grow`, exceptional-field reconstruction recipes, and the node/edge invariant. The harness covers all four parse flag combinations, and `compiler/tests/selfhost.rs` runs both the existing lexer comparison and the new parser comparison.

## Comparison and validation

`CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test --test selfhost -- --nocapture` passed. The integration test built the self-hosted executable and compared status, stdout, and stderr against Rust for:

- 366 packages from `tests/run`, `tests/test`, and `tests/parse/cases`.
- 103 directed and limit packages, including all 75 tree node kinds and every dumped operator, mode, policy, and effect alternative.
- 300 legacy byte mutations with seed `0x51a1a`, in all four parse modes; and 300 parser mutations with seed `0x51a2a`, under `--tree`.
- The 54,145-line parser benchmark under all four modes. The parse benchmark wraps its assignment filler in a test body so it is valid source; the lexer benchmark retains its original input.

Directed cases cover exact 1,000/1,001 boundaries for parentheses, unary and binary chains, calls, casts, blocks, types, `if`, `match`, and `else if`; mixed recursive paths; tree-walk branch order and diagnostic spans; root `print` versus ordinary roots; capacity and function-type expressions; virtual generic closers and shifts; integer/range/`stack_peak` edges; synthetic nodes; decoded byte and string output; long diagnostic names; and error-order pairs. The type-error package confirms that parsing and dumping skip the checker. Syntax errors before tree counting and node overflow before work overflow are also compared without dump flags.

Node and work N/N+1 cases matched Rust. The 2,000,001-node plus 72-million-work case reports the node error first. The per-file node check remains before the cumulative check, but cannot overflow independently: the 1,000,000-token per-file limit is lower than the 2,000,000-node limit. The multi-file node boundary exercises cumulative counting with every individual file below its node limit. Child edges equal nodes minus source files, so an edge-only overflow is unreachable; this invariant is documented in the format file. An earlier syntax error against a later byte-limit error is covered; a deterministic later read failure is not available through the static filesystem fixtures.

`CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt --all -- --check`, Python syntax validation, both shell syntax checks, and `git diff --check` passed.

## Timing and memory

The parser benchmark contains 13 files, 54,145 lines, and 1,152,008 bytes. Its token dump has 510,003 token rows (plus 13 file headers). One WSL run of `parse --tokens --tree` measured:

| Executable | Elapsed | Process max RSS |
| --- | ---: | ---: |
| Rust `nlc` | 0.76 s | 63,172 KiB |
| Self-hosted parser, `-O1` | 0.68 s | 60,016 KiB |

For the self-hosted `main`, `nlc inspect stacks selfhost` reports a data-stack worst case of 192,745,324,820 bytes and a virtual reservation of 192,745,328,640 bytes. The 60,016 KiB process RSS is the observed resident high-water for the benchmark run; the ordinary CLI build does not include the test-only per-mapping touched-page hook, so RSS and virtual reservation are separate measurements. The harness's logical live-data estimate for this benchmark is 12,808,475 bytes.

Native-stack bounds from the optimized frames were 4,060,656 bytes at `NLC_OPT_LEVEL=1` and 4,060,592 bytes at `NLC_OPT_LEVEL=3`. Twice the larger bound is 8,121,312 bytes, 185,376 bytes below T19's default effective budget of 8,306,688 bytes. Mixed 1,000-level call/parenthesis and block/call inputs succeeded under both optimization levels; their 1,001-level counterparts produced Rust's nesting diagnostic without exhausting the runtime recursion budget. The package uses a 3,900 KiB recursion-budget override.

## Hard or awkward patterns in next-lang

### Forced boilerplate

- `NodeKind`, `TokenKind`, and `ParseProblemKind` need exhaustive spellings and messages to preserve the reference dump and diagnostics.
- The parser cursor must split `>>` and `>>=` virtually while preserving references to original tokens.
- Decimal formatting for unsigned 128-bit magnitudes requires limb-by-limb division; signed `long` parsing cannot hold the full range.
- Tree JSON and long diagnostics are streamed byte by byte through bounded output rather than assembled in an unbounded string.

### Awkward patterns

- Without `while`, cursor scans and tree walks use bounded `for` loops with `break` at their explicit end conditions.
- Large frame and scratch lists cannot live across recursive calls, so the parser keeps them in caller-owned `ParseTables` and unwinds them with checkpoints.
- Postfix parsing has to delay or roll back provisional nodes so replacement forms keep a contiguous postorder tree without ghost nodes.

## Compiler fixes

None. The direct-call cursor-offset bug and two diagnostic wording mismatches found by mutation comparison were fixed in `selfhost/`; no Rust compiler or runtime code changed.

## Wanted language and runtime features

- A `while` loop would simplify cursor-driven scans, though bounded loops are sufficient here.
- Paginated filesystem listing remains useful for packages with more than the current directory-entry bound; it was not needed for this task.
- No new core language feature was needed or added.
