# Claude: E1 review (the self-hosted compiler end to end, first subset)

**Verdict:** approved, no fix round. The first next-lang code that compiles programs into working executables.

What it is: selfhost/compiler.nl (selfhost/ is now about 9,100 lines of next-lang) adds eligibility, a checker and an LLVM IR code generator (offset addressing only) after the existing lexer and parser; `nlc link-ir` and `nlc test-ir` in the Rust driver build and run the IR with the existing toolchain path. Packages with anything outside the subset are rejected whole, before checking, with one diagnostic and no IR.

Checked: Luna ran `scripts/compare-selfhost.sh --build` (482 classified packages: 34 build and match, 39 diagnose with identical bytes, 409 rejected as unsupported, zero mismatches at -O1 and -O3) and both full suites. My probe (a loop-based Fibonacci to fib(90), Collatz from 27, `continue` in an inclusive range, negative division and remainder, short-circuit booleans, an int overflow) built with the self-hosted compiler and `link-ir`: stdout, the overflow message, line, column and exit status identical to Rust nlc.

Notes for later:

- The self-hosted compiler's computed data-stack worst case grew to 3.48 GB with the checker and emitter tables (the stack-contract test ceiling went from 1 GiB to 4 GiB). That's reserved address range, not memory, and the offset milestone makes it a growth limit, but it's worth watching as E2-E4 add tables.
- Correction (2026-10-26, after profiling): the 5.6 s Rust figure for "check and emit" includes clang, because `inspect stacks` builds the optimised code to read native frame sizes; the time is LLVM's per-function passes, run twice by the frame-size step, and it grows linearly. Both compilers send every function through clang. Follow-ups are in PLAN's small fixes ("Build time on many functions").
