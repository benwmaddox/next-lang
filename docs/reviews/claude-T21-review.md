# Claude: T21 review (parse-only command and stable dump format)

**Verdict:** approved after one fix round. With T19 and T20 this completes S0.

Checked: cargo build and test pass; `nlc parse --tree` dumps a package with a type error (the checker never runs); docs/syntax-tree-format.md documents token kinds, tree node kinds and fields, JSON escaping, 128-bit integer magnitudes and the parser's limits.

Fix round 1 (prompt-T21-fix1.md):

1. Spans were operator-local: `-0x10` covered only the `-`, and the outer node of a 1,000-term sum started near its end. Now every node spans its whole construct (my probe: `f(a) * -(2) + a.x` gives nested spans that each cover their operands), documented as a rule with its exceptions, and a structural test checks containment, ordering and token alignment across the corpus.
2. The corpus was 9.9 MB: two-space indentation makes the 1,000-deep stress dumps quadratic (2 MB each). Dumps over 100 KB are no longer stored; those packages are checked live (two identical runs plus the structural test). tests/parse is now 1.4 MB of content.

Notes for S1: parentheses have no node of their own, so a parenthesised operand's span includes its parentheses (`-(2)`: the `Integer` spans `(2)`). S1 compares against live `nlc parse` output, not only the stored snapshots.
