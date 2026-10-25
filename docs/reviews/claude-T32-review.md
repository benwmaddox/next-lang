# Claude: T32 review (operator matching and number output)

**Verdict:** approved, no fix round.

Checked: cargo test passes (the selfhost lex and parse comparisons over 374 packages, directed, limit and mutation cases, and the benchmark, all byte-identical). The self-hosted lexer dispatches on the operator's first byte (`matches_ascii` no longer appears in the profile); decimal `str`, `print` and `out` integer writes use a two-digits-at-a-time formatter, written straight into Ascii, Text and Bytes builders without a staging copy (an IR test checks), checked against every digit boundary to 10^18, the extremes and three million random values.

Luna's interleaved best-of-5: self-hosted lexer 0.10 to 0.08 s (level with release Rust's 0.08 s in my earlier run), parser with full dump 0.28 to 0.24 s, printing ten million longs 1.15 to 0.90 s.

From the new profile, logged in PLAN's small fixes: `print` spends 64% in `write` (stdout is unbuffered), and `match` doesn't accept a `byte` (the lexer casts to `int`).
