You are the implementer (Luna) for next-lang. T07 is implemented and its tests pass, but Claude's review found a parser bug. Fix it, add tests, keep everything passing, and append a short "Fix 1" section to docs/tasks/T07-report.md. Same rules as before (never commit or touch branches; build and test in WSL with CARGO_TARGET_DIR=$HOME/.cache/next-lang/target).

The bug: nested generic closers lex as a shift operator. DESIGN.md's own example fails:

    struct Node<P> { parent: Option<Id<P>>, value: int }

gives "expected a comma or newline between struct fields" at the `>>`. It only parses with a space (`Option<Id<P> >`). Fix it the usual way: in a type context, split a `>>` token (and `>>=`, and `>>>` if the lexer has it) into separate closing `>`s, so any depth of nesting works (`list<list<Option<int>, 4>, 3>`, `map<Key, list<Id<P>, 8>, 64>`), while `a >> b` in expressions stays a shift. Add run cases for two- and three-deep nesting in struct fields, local declarations, parameters and return types, and one checking that `x >> 1` and `x >>= 1` in an expression still shift.
