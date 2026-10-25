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
