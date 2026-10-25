# S1a-1 implementation report

## Implementation

Added `selfhost/` as a next-lang package with separate source loading, lexer, token dump, limits, and CLI files. The lexer has a `TokenKind` enum and compact token records containing kind, file-relative start, and length. It uses one flat counted scan per file, with a 2,048-entry delimiter stack.

Package handling follows the reference order: sorted `.nl` entries from `fs.list_with_extension`; regular files only; the 256-file check; then, per file, the 16 MiB read bound, package 64 MiB bound, UTF-8 validation and position, lexing (including per-file token and delimiter checks), and finally the 4 million package-token check. Tokens and source are retained until every file succeeds, so a later error cannot leave partial stdout. The token table has capacity for 5 million tokens.

The CLI accepts `lex <package>`, optional `--tokens`, and temporary `--tree` rejection. Duplicate or unknown flags produce the specified usage response. `--tree` exits 3 with `nlc: tool failure: not implemented yet`.

Added a deterministic comparison harness, adversarial case generator, fixed benchmark manifest and generator, and a Cargo integration test that builds the self-hosted executable once and runs the comparison harness against Cargo's `nlc`.

## Comparison and validation

The direct comparison harness passed:

- 360 packages from `tests/run`, `tests/test`, and `tests/parse/cases`.
- 42 directed and limit cases covering operator prefixes, newline behavior, strings and byte strings, Unicode and invalid UTF-8, file selection, check ordering, no partial output, and the exact N/N+1 file, byte, token, package, and delimiter boundaries.
- 300 deterministic byte mutations with seed `0x51a1a`.
- The 54,145-line benchmark: 13 files, 1,152,008 source bytes, and 510,185 tokens.
- Duplicate and unknown CLI flags and both temporary `--tree` forms.

The harness compares exit status and stdout exactly. It compares stderr exactly except that tool failures are considered equivalent when both have the tool-failure prefix and status, as required for OS error text differences. It also checks that a later-file lexer failure leaves stdout empty. A separate invocation through `nlc run selfhost -- lex tests/run/arithmetic` matched `nlc lex tests/run/arithmetic` byte for byte.

`CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt --all -- --check` passed. The full `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` suite passed, including `selfhosted_lexer_matches_the_rust_lexer`.

## Timing and memory

Measurements were taken in WSL with the default build settings. The harness timed one full lexer-only run per executable, including directory listing, file reads, token output, and output writes redirected to `/dev/null`:

| Executable | Elapsed | Process max RSS |
| --- | ---: | ---: |
| Rust `nlc lex` | 0.21 s | 23,128 KiB |
| Self-hosted lexer | 0.14 s | 13,904 KiB |

`nlc inspect stacks selfhost` reports a 270,041,644-byte data-stack worst case and a 270,045,184-byte reservation. Its native-stack worst case is 68,736 bytes and nonrecursive.

The test-only stack residency hook measured a benchmark-shaped probe at 270,589,952 bytes reserved, 12,771,328 bytes touched, and a 254,518,812-byte `peak_used` high-water. The probe used 13 files with the benchmark's exact per-file byte count, line count, and token count; its token spellings were synthetic, and its fixture builder used an additional 88,616-byte `Bytes` value. Treat touched pages as a close runtime measurement of the table and I/O path, rather than an exact run over the benchmark's original bytes.

The harness also estimates 12,812,115 bytes of logical live data for the actual benchmark. That estimate includes the full package source, one-file read staging, live token records, file and directory entries, and the 1 MiB output buffer. The stack reservation, test-hook touched pages, logical live-data estimate, and process RSS are separate measurements.

## Hard or awkward patterns in next-lang

### Forced boilerplate

- The explicit `TokenKind` cases and exhaustive spelling match in `dump.nl` are required to keep token names and lexer output aligned. Operator matching in `lexer.nl` checks every ambiguous spelling from longest to shortest.
- Error text and JSON escaping are assembled byte by byte. The writer handles quote, backslash, control-byte, and lowercase hex escapes directly, and flushes its local 1 MiB `Bytes` buffer before a write could exceed capacity.
- The lexer tracks byte offsets, line, and column explicitly. This preserves Rust's byte-column behavior and the first-byte diagnostic for an unexpected non-ASCII character.

### Awkward patterns

- There is no `while` loop, so cursor-driven scans use a bounded `for step in 0L..length` with `break` once the cursor reaches the end. This appears in identifier, number, string, comment, whitespace, and output scans in `lexer.nl` and `dump.nl`.
- There is no dynamic formatting builder for mixed token fields. `dump.nl` converts each numeric field with `str()` and copies its bytes into the output buffer.
- `env.exit` is treated as returning `unit`, so CLI rejection paths explicitly follow helper calls that exit with another `env.exit` to make control flow terminate for the checker.
- Initially, splitting output escaping into helper functions caused large `Bytes` copy-down stack contracts. Keeping the byte-writing loop in `output_token_dump` reduced the reported stack bound from the multi-gigabyte helper chain to 270 MB. The capacity remains reserved, while runtime touched pages stay close to the live data.

## Compiler fixes

None. No Rust compiler or runtime source was changed.

## Wanted language and runtime features

- A paginated or iterator-based `fs.list_with_extension` API would remove the fixed 4,096-entry listing bound. The current package has at most 256 regular sources, and the harness covers 10,000 irrelevant `.txt` entries, but more than 4,096 matching `.nl` entries can still exhaust the bounded result list before kinds are filtered.
- A diverging return type for `env.exit` would remove the explicit follow-up exits needed to satisfy control-flow checking.
