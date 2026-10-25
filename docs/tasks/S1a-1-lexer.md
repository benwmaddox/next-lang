# S1a-1: the self-hosted lexer and token dump (self-hosting step S1a, part 1)

Depends on M3 (T13 to T18, T22, T23) and T24. Read docs/PLAN.md "Self-hosting track", docs/research/selfhost-architecture.md sections 4 and 5.1 (revision 2; where it describes the Rust parser's limits before T22, T22's behaviour wins: every counted path is limited to 1,000 and `else if` is iterative), docs/reviews/sol-selfhost-arch-r1.md, docs/syntax-tree-format.md and compiler/src/lexer.rs and driver.rs.

The first program written in next-lang that the project depends on: a lexer that reproduces `nlc parse <package> --tokens` **byte for byte** (stdout, stderr and exit status).

## Where it lives

- `selfhost/` at the repository root, a next-lang package (`selfhost/package.toml` granting `fs`, `out`, `env`), split into files by role (`main.nl`, `source.nl`, `lexer.nl`, `dump.nl`, `limits.nl`). It's built by the Rust `nlc` like any package.
- Run as `nlc run selfhost -- parse <package> --tokens` (arguments mirror `nlc parse`). Also accept `--tree` and both flags, reporting "not implemented yet" with exit 3 for `--tree` until S1a-2.

## Design (binding)

- **Memory:** no globals for compiler data. Tables are locals on `main`'s data stack, reserved at their limits and touched only as used (T17, T23): one package source buffer (`Bytes`, 64 MiB, the package limit), a file table (name, base offset, length), and a token list per package. Token records: kind, file-relative start, length (the research report's `Token`). Check `nlc inspect stacks selfhost` and report reserved vs touched for the 54,145-line benchmark.
- **Package flow in driver.rs's order:** list the package directory and keep entries exactly as Rust does (extension exactly `nl`, regular files after following symlinks, sorted); read each file; check per-file bytes, package bytes, UTF-8 (with Rust's column for the first invalid byte), then lex, then the per-file and package token limits, in Rust's order, so the first error reported is the same error Rust reports for every input. Write that order down in a comment block at the top of `source.nl`.
- **Lexer:** one flat loop per file, no recursion, with a bounded delimiter stack (2,048). Reproduce lexer.rs exactly: token kinds and spellings, newline coalescing and suppression inside brackets, string and byte-string escapes (including T24's `\xNN`), number token spans, error messages and positions.
- **Output:** a byte buffer flushed through `out.write` (1 MiB chunks); JSON escaping exactly as syntax-tree-format.md says. Nothing on stdout unless every file succeeds; errors go to stderr as `file:line:col: error: ...`, exit 2; tool failures as `nlc: tool failure: ...`, exit 3 (compare tool failures by exit status and prefix only, since OS error texts differ).
- **Limits** in one place (`limits.nl`), each with the exact message Rust prints.

## Comparison harness

- `scripts/compare-selfhost.sh --tokens`: for every package under tests/run, tests/test and tests/parse/cases, run both `nlc parse --tokens` and the self-hosted lexer and compare stdout, stderr and exit status byte for byte; print a summary and the first difference. It's run by a cargo integration test (compiler/tests/selfhost.rs) so `cargo test` covers it.
- Also: every lexer limit at N and N+1, in each position of the check order (a package-byte overflow in a file that also has a lexing error, and so on); a byte-level fuzz pass (mutate corpus files deterministically from a fixed seed, a few hundred cases, compare both); the 54,145-line benchmark (generate it as the research report did) with both lexers' times and peak memory.

## Report

docs/tasks/S1a-1-report.md: what was hard to express in next-lang (each missing feature or awkward pattern, with the code it forced; this is the main input for language changes), timings and memory against Rust, and the comparison summary.

## Corrections from Sol's review (docs/reviews/sol-S1a-r1.md), binding; they override the text above where they differ

Read the review for the evidence. Depends on T25 as well as T24.

1. **Oracle:** compare against `nlc lex <package>` (T25), the lexer-only reference, for every package including syntactically invalid ones; `nlc parse` equivalence (no flags, `--tree`, both) is S1a-2's. The self-hosted command is `nlc run selfhost -- lex <package>`.
2. **Buffers:** use T25's `Bytes` builder for the package source and the output buffer, and `validate_utf8` for the UTF-8 check.
3. **Listing:** use T25's `fs.list_with_extension` and keep kind == File; package paths are relative to the working directory (run the harness from the repository root).
4. **Limit points, exactly as Rust:** the per-file token limit is checked as each token is emitted (Newline and Eof included; suppressed newlines never count); delimiter errors come before the token push; unclosed delimiters before Eof; the package token limit only after a file lexes completely. Token storage: a per-file scratch of 1,000,000 tokens plus the package list (record each file's token start and count), or one list of 5,000,000; say which. The 16 MiB read temporary's overflow maps to the per-file source-limit diagnostic. Tests: paired errors within one file and across sorted files, and every file/source/token/delimiter boundary at N and N+1 (counting Eof).
5. **Directed newline and operator matrix** (lexer-only inputs, so parser rejection can't hide differences): leading and trailing LF, LF after whitespace or a comment, CRLF and a lone CR, semicolon runs, LF inside `()`/`[]` (suppressed) and `{}` (not), nested and mismatched delimiters, EOF without LF; every operator, each ambiguous prefix (`.`/`..`/`..=`, `?`/`?.`/`??`, `-`/`-%`/`->`, `>`/`>>`/`>>=`/`>=` and so on) and truncated suffix.
6. **Spellings and Unicode:** number spans for `0x`, `1__0`, `123abc`, suffixes and `1..=2`; valid, invalid and truncated escapes, a trailing backslash, the opening-quote error anchor; byte strings as T24 left them (freeze the post-T24 reference); JSON control bytes (`\u0000`, lowercase hex), raw Unicode, and quoting across output chunk boundaries; byte columns after multi-byte characters, tabs and CRLF; invalid UTF-8 at the sequence start (overlong, surrogate, truncated); the quirk that an unexpected non-ASCII character is reported by its first UTF-8 byte (lexer.rs:249-252). Decoded string values are compared in S1a-2.
7. **Language use:** a `TokenKind` enum with exhaustive matches, concrete capacities, explicit spelling matches; function tables optional; use the lexer's own whitespace rule, not `is_space()`. In the report, separate forced boilerplate from missing features.
8. **Harness and measurement:** build the self-hosted lexer once (`nlc build selfhost -o ...`) and Cargo's `nlc` once, outside timed runs; the harness takes both executables, keeps exact stderr and status, records the mutation seed and the failing input, and normalises only OS error texts in tool failures. Check empty stdout after a later-file failure, duplicate and unknown flags, and the temporary `--tree` rejection. Commit a deterministic benchmark generator (scripts/gen-bench-corpus.sh, fixed input selection), time equivalent lexer-only work (`nlc lex` vs the self-hosted lexer), and report runtime touched/high-water data and process RSS separately, including I/O staging.
