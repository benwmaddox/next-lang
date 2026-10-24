# T21: a parse-only command and a stable tree format (self-hosting step S0, part 3)

Depends on T20. Same rules. From docs/reviews/sol-S0-r1.md point 7: the self-hosted lexer and parser (S1) need a reference to compare against, and today the driver goes straight from parsing to checking.

- **`nlc parse <package> [--tree] [--tokens]`:** lex and parse only, no checking. `--tokens` prints one token per line (`kind start_byte length line col text`); `--tree` prints the syntax tree in a stable, documented text format (one node per line, indented by depth, with its kind, its byte span and its literal or name; children in source order). Without either flag, it prints only syntax errors.
- **Syntax errors only:** errors from lexing and parsing, in the existing `file:line:col: error: ...` format, separate from checker errors. Columns count bytes, as `lexer.rs` does today; that's the contract S1 must match.
- **The format is a contract:** write it down in docs/syntax-tree-format.md (node kinds, fields, escaping of literals, how integer literals are printed after decoding, including their 128-bit magnitudes before range checking), so S1 can produce byte-identical output.
- **Corpus:** a directory `tests/parse/` of inputs with their expected token and tree dumps: every existing `tests/run` and `tests/test` package, plus malformed inputs (an unterminated string, a bad escape, mismatched brackets, a non-UTF-8 byte, a literal too large for 128 bits) with their expected syntax errors, plus boundary inputs (an empty file, a very long line, deeply nested brackets).
- Acceptance: the corpus passes; the dump of a package is identical across runs; `nlc parse` never runs the checker (a package with type errors still dumps).
- Report: docs/tasks/T21-report.md.
