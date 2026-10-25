# Claude: T22 review (parser nesting limits) and the T14 checker regression

**Verdict:** approved after one fix round.

T22: `else if` chains are parsed with a loop and counted (clause 1,001 fails at its `if`; a 100,000-link chain fails in 0.14 s instead of parsing at 1.34 GB), the expression counter matches the documented 1,000, a cast path that bypassed the counter got its own, and docs/syntax-tree-format.md now lists what counts and where errors point. Probes: 999 `else if` links build and run (`f(998)` prints 998); 1,001 nested `!` are refused with status 2.

Regression found while probing: since T14, checking was cubic in expression size (a 1,000-term `long` sum took 47.7 s to build; bisected in a separate worktree to T14 at dc1acc8; 0.12 s at 7a48b01). Cause: the `+` checker re-inferred whether each operand could be Ascii for every subtree, and cloned the whole typed left subtree at each node; T15's loop-growth analyses also re-walked nested loop bodies. Now memoised per expression and moved rather than cloned: 1,000 terms in 0.03 s for `inspect contracts`, 0.32 s for a full build and run. compiler/tests/checker_performance.rs keeps 1,000-term `long`, Ascii, `&&` and nested-call expressions and 750 nested Ascii-growth loops under 2 s in debug.

Lesson for future reviews: time a few large generated inputs after every checker change, not only correctness probes.
