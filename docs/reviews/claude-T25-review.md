# Claude: T25 review (byte buffers, source listing, nlc lex)

**Verdict:** approved after one fix round.

Checked: cargo build and test pass (compiler/tests/t25_prerequisites.rs: 256/257 sources, 10,000 ignored entries, invalid-UTF-8 names, rooted symlinks, `lex` vs `parse --tokens`). Probe ~/nlprobe/y1: `fs.list_with_extension("pkg", "nl")` returns `a.nl`, the symlink `c.nl`, the directory `d.nl` and the dangling link `e.nl` (kinds for S1 to filter), excluding `.nl` and `b.NL`; `Bytes` indexing (97), `try_append` and `push`; `validate_utf8` on `ab\xc3` gives `valid_up_to: 2`. `nlc lex` on `fn main( { }` reports the unclosed `(` with status 2 without parsing; Luna measured a 64 MiB package lexed in 0.09 s.

Fix round 1: `discard` refused `Bytes.try_append` though its only error is `Full`; now `discard` accepts every built-in capacity operation (collection push/insert/add/set, Ascii/Text/Bytes `try_append`, `Bytes.push`) and nothing else. Luna also added the missing `Text.try_append`.
