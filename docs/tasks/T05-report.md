# T05 report: compile-time constants

Top-level `const NAME: T = expr` declarations are parsed and typechecked with the package. Constant names are registered before expressions are checked, so forward references work. A typed compile-time evaluator handles checked integer operations and casts, `if`, `match`, loops, structs, enums, `Option`/`Result`, and calls to cacheable functions. It rejects transitive `print` effects and `write` parameters with the function path, and detects constant cycles, including dependencies reached through called functions. Evaluated values are emitted as immutable LLVM globals; references load that data.

The evaluator enforces a deterministic budget of 10 million steps per constant. I count each evaluated expression and statement, plus one step for each loop iteration. A budget failure points to the constant declaration. Unit constants need no LLVM global because they carry no runtime data. No external crates were added.

The new run fixtures cover computed and forward-referenced constants, pure calls, struct and enum values, `Option` and `Result`, loops and matches, call-chain agreement between compile-time and runtime evaluation, effect and write-parameter rejection, cycles, failed casts, overflow locations, and the step limit.

Verification passed:

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build`
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — 4 unit tests and all 3 integration tests passed; the integration tests checked every run and test fixture.

Fixed-size arrays are not part of the current type system, so array-valued constants such as the CRC table in `docs/EXAMPLES.md` remain for the arrays task (T06). The constant evaluator and LLVM data emission will need array support then.
