# T22: parser nesting limits (fix before S1)

Same rules (docs/PLAN.md). From docs/research/selfhost-architecture.md (revision 2) and PLAN.md's "Parser nesting fixes". The Rust parser is the reference S1 must match byte for byte, so its limits must be exactly what docs/syntax-tree-format.md says.

- **`else if` chains:** the parser recurses once per `else if` with no counter. A 124,000-link chain parsed (1.34 GB peak memory) before the finished-tree check reported "expression nesting limit of 1000 exceeded". Parse `else if` chains iteratively (a loop building the chain, no Rust recursion per link), and decide how links count: each `else if` link counts as one level of construct nesting toward the 1,000 limit, as the finished-tree check already treats it, so the 1,001st link is reported at that link while parsing, before memory grows.
- **The expression-depth counter** trips at 2,048 while its message says 1,000 (2,049 nested `!` or `-` are rejected at the 2,049th operator). Make every counted path (parentheses, unary operators, binary chains, calls, blocks, types, `if`/`match`, `else if`) agree with the documented 1,000, with one message per kind of limit naming it.
- List every recursive path in parser.rs and the finished-tree walk with its counter; any recursion without a counter either gets one or becomes a loop. State the list in the report.
- Update docs/syntax-tree-format.md's limits paragraph to describe exactly which constructs count and where the error is reported (byte position of the token that passes the limit).
- Tests: for each counted kind, N = 1,000 builds and N + 1 gives the limit error at the right position, with the debug nlc; a 100,000-link `else if` chain fails quickly (state the time and peak memory) at link 1,001; the parse corpus and run fixtures still pass (regenerate dumps only where messages changed, and list them).
- Report: docs/tasks/T22-report.md.
