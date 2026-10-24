# T05: compile-time constants (milestone M1, part 3)

Depends on T04. Same rules (docs/PLAN.md, T01's Architecture section). Split out of T04 after Sol's review (docs/reviews/sol-T03-T04-r1.md).

- `const NAME: T = expr` at the top level, evaluated at compile time; the value is data in the program.
- What `expr` may use: literals, arithmetic, `if`, `match`, `for` loops, structs and enums, other constants (forward references allowed), and calls to **cacheable** functions only (DESIGN.md, Effects and capabilities): no effects, transitively (`print` anywhere down the call chain is refused), and no `write` parameters. The error names the call chain that reaches the effect.
- A cycle between constants is a build error naming the cycle. Evaluation has a step limit (10 million steps); passing it is a build error at the constant.
- Evaluation uses the same checked semantics as running code: an overflow or a failed cast during evaluation is a build error at the failing line, with the chain of calls that led there.
- Tests: a computed constant; one calling a pure function; a forward reference; a cycle (build error); `print` reached indirectly (build error with the chain); an overflow during evaluation (build error with the line and chain); the step limit; loops and `match` in a constant; and a check that compile-time and run-time evaluation agree (the same function run both ways on several inputs gives the same results).
- Report: docs/tasks/T05-report.md.
