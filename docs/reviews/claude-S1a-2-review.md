# Claude: S1a-2 review (the self-hosted parser and tree dump)

**Verdict:** approved, no fix round, with one follow-up (T27). With S1a-1 this completes S1a: the lexer and parser in next-lang reproduce `nlc parse` byte for byte.

What it is: selfhost/parser.nl and parse_output.nl (selfhost/ is now about 5,100 lines of next-lang): a postorder node list with subtree sizes, extra-data and four-limb literal tables, recursive descent mirroring parser.rs along counted paths only, explicit frames for `else if`, `match` arms and `for` bodies, virtual `>>` splitting in a parser cursor, the completed-tree walk ported task for task, per-file load/lex/parse/count in driver order, an explicit-stack preorder printer. No Rust compiler changes.

Checked: the full cargo test suite passes (17 groups, including the selfhost comparison: 366 corpus packages in all four flag combinations, 103 directed and limit packages covering all 75 node kinds and every field alternative, 600 mutations, the 54,145-line benchmark). Native stack: 4.06 MB bound with a 2x margin under the budget, at -O1 and -O3.

Throughput (my measurement, best of 5, WSL, the 54,145-line / 1.15 MB benchmark, output to /dev/null):

| Work | Rust nlc debug | Rust nlc release | self-hosted -O1 | self-hosted -O3 |
|---|---|---|---|---|
| `lex` (token dump) | 0.187 s | 0.089 s | 0.135 s | 0.134 s |
| `parse --tokens --tree` | 0.512 s | 0.234 s | 0.489 s | 0.444 s |
| `parse` (no dump) | | 0.233 s | | 0.152 s |

So against the release Rust compiler the self-hosted lexer is about 1.5x slower and the full dump about 1.9x slower; parsing without a dump is faster than Rust's `nlc parse`, which seems to do most of the dump work regardless. The dumps are about 20 MB of text, so byte-by-byte output formatting is the main cost.

Finding for T27: `inspect stacks selfhost` reports a 192,745,324,820-byte data-stack worst case (and reserves that address space), while its listed regions total about 100 MB, the tables about 550 MB by hand, and the process touches about 60 MB. Either the analysis overcounts or something is really copied; `inspect stacks` also doesn't attribute its total. Also five 1 MiB copy-down temporaries for the output buffer in dump.nl.

Housekeeping: deleted Luna's .s1a2-stack-* probe folders and /tmp/s1a2-generated (483 MB) after review.
