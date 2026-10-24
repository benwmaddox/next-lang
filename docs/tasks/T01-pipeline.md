# T01: the pipeline (milestone M0)

Read docs/PLAN.md (roles, layout, rules) and the parts of docs/DESIGN.md it points to. You are the implementer: build this task in the repository, run its tests, and write docs/tasks/T01-report.md. Never commit; never create or switch git branches.

## Goal

The smallest whole path from source to a running native program, so every later milestone only adds features.

## Build environment

Everything runs in WSL (Ubuntu): `wsl -e bash -lc '...'` from Windows, with the repository at `/mnt/d/code/next-lang`. Use `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target`. clang 18 and lld are installed (`/usr/bin/clang`). Rust is 1.93 in WSL.

## What to build

1. A Cargo workspace at the repository root with one crate, `compiler/` (binary `nlc`, plus a library so tests can call it).
2. `nlc run <package-dir>`: compile every `.nl` file in the directory (one package; files read in name order; no imports), call `fn main()`, exit 0. `nlc test <package-dir>`: compile and run every `test "name" { ... }` block, print one line per test (`ok  name` or `FAIL name` with the failing `expect` and its line), exit non-zero if any fail.
3. The language subset (syntax as in DESIGN.md and EXAMPLES.md; where they don't say, choose the plainest option and record it in the report):
   - `fn name(a: int, b: long) -> int { ... }`; a block's last expression is its value; `return`.
   - `let` (immutable) and `var` (mutable) with optional type annotations; `x = e`; `+= -= *= /= %=` (same checks as the long form).
   - Types: `int` (32-bit), `long` (64-bit), `bool`. Integer literals take their type from context, defaulting to `int`; `5L` suffix. No implicit conversions: `int + long` is a build error naming which side to cast; casts `(long)x` (widening) and `(int)x` (narrowing, checked); widening methods `x.to_long()`.
   - Operators: `+ - * / %` (checked: overflow, divide by zero and the most-negative-divided-by-minus-one fail the program), `+% -% *%` (wrapping), comparisons, `&& || !`, bitwise `& | ^ << >>` (a shift by n needs `0 <= n < width`).
   - `if c { } else if c { } else { }`, also as an expression.
   - `for i in a..b { }` and `for i in a..=b { }`, with `break` and `continue`; the counter's type comes from its bounds (DESIGN.md, "Loop counters take their type from their bounds and use"). No other loops in this task.
   - `test "name" { ... }` blocks with `expect <bool>` steps (several per test, `let` between them; on failure show both sides of a `==` comparison).
   - A builtin `print(x)` for `int`, `long` and `bool`, for `nlc run` programs.
4. A runtime failure (overflow, divide by zero, bad cast, bad shift) stops the program with a message naming the file, line and what failed, and a non-zero exit. In a test run it fails that test only and the others still run.
5. Output: LLVM IR as text (look at how D:\code\burin\crates\burinc\src\helpers.rs emits checked arithmetic with LLVM's `llvm.sadd.with.overflow` intrinsics; copying ideas or code is fine, with a note). Build with `clang -O1` (development) into a temporary directory and run the result. Hand LLVM facts where they're free (`nsw` only where overflow is proven impossible: skip that for now; just emit the checks).
6. Errors: lexing, parsing and type errors report `file:line:col`, say what's wrong and, where possible, what to do ("did you mean `count`?" for an unknown name close to a known one). Stop at the first error per file is fine for now.

## Tests (all must pass with `cargo test`)

- Unit tests in the compiler where useful.
- Language tests under `tests/run/<name>/` (a package directory with `main.nl` and `expected.txt`, the program's exact output and exit code) and `tests/test/<name>/` (a package with `test` blocks and the expected `nlc test` output), run by a Cargo integration test. At least:
  - arithmetic and precedence; `long` arithmetic past 2^31; casts; `+=`; wrapping ops;
  - overflow failing with the right line; divide by zero; `(int)` of a too-large `long`; a shift of 32 on an `int`;
  - `if` as a statement and an expression; nested `for` with `break`/`continue`; `..` vs `..=` iteration counts;
  - recursion is **not** in this task (DESIGN.md makes it opt-in with `recursive`); a call cycle is a build error saying so;
  - a test file where one test fails and the rest pass, checking the output format and exit code;
  - build errors: unknown name with a "did you mean", `int + long`, assigning to a `let`, a missing return value, wrong argument count.
- A short `README` section (in the root README.md) saying how to build and run the tests.

## Report (docs/tasks/T01-report.md)

What you built, the commands that build and test it, the test results (counts), every choice you made that this task or DESIGN.md didn't settle, and anything you'd change about the plan.
