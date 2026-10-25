# Claude: S1a-1 review (the self-hosted lexer)

**Verdict:** approved, no fix round. The first compiler component written in next-lang.

What it is: selfhost/ (946 lines of next-lang: source loading in driver order, a flat counted-loop lexer with a 2,048-entry delimiter stack, a token dump with its own JSON escaping, limits in one file, a small CLI), plus scripts/compare-selfhost.sh, a deterministic adversarial-case generator, a fixed benchmark manifest and generator, and compiler/tests/selfhost.rs (builds the lexer once and runs the comparison inside `cargo test`; about 65 s).

Checked:

- `cargo test --test selfhost` passes: 360 corpus packages, 42 directed and limit cases (N and N+1 for files, bytes, tokens and delimiters; check order; no partial stdout), 300 seeded mutations, the 54,145-line benchmark, CLI flag cases.
- My own probes (~/nlprobe: z1 with CRLF, a bad escape, `..=`, `0x_ff`, `>>=`, `?.`, `??`, a tab and a control byte; plus t1, a1, g1, k1, n2, x1, y1/pkg): identical stdout, stderr and exit status between `nlc lex` and the self-hosted lexer.
- Speed and memory on the benchmark: self-hosted 0.14 s and 13.9 MB against the (debug) Rust `nlc lex` at 0.21 s and 23.1 MB. 270 MB reserved, about 12.8 MB touched (T17 and T23 doing their job).
- Absolute package paths are refused (rooted I/O), as documented; the harness runs from the repository root.

Language findings from the report and my checks:

1. No user-declared never-returning functions: `fn fail(env: Env, code: int 0..=125) -> never { env.exit(code) }` is "unknown type 'never'". CLI error helpers need a redundant `env.exit` after the call. Small task before S1a-2.
2. No `while`: cursor scans are `for step in 0L..length { ... break }`. Works, and doubles as a step budget; leave it, as DESIGN intends.
3. Splitting the output escaper into helpers once produced multi-gigabyte stack contracts (copy-down of a large `Bytes`). My probe of the plain pattern (helpers taking `grow Bytes max 1 MiB` and pushing) shows byte requirement 0, so it was a specific shape in the first draft; worth reproducing in S1a-2 when the tree printer needs helpers.
4. `fs.list_with_extension` returns at most its list's capacity of matches (4,096 here); fine for 256-source packages.
