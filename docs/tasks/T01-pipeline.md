# T01: the pipeline, part 1 (milestone M0)

Read docs/PLAN.md (roles, layout, rules) and the parts of docs/DESIGN.md it points to. You are the implementer: build this task in the repository, run its tests, and write docs/tasks/T01-report.md. Never commit; never create or switch git branches. Peer review of this task is in docs/reviews/sol-plan-r1.md; its answers are folded in below.

## Goal

The smallest whole path from source to a running native program: functions, scalar values, checked arithmetic, calls, `print`, build errors. Control flow beyond `if` and the `test` harness come in T02.

## Build environment

Everything runs in WSL (Ubuntu): `wsl -e bash -lc '...'` from Windows, with the repository at `/mnt/d/code/next-lang`. Use `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target`. clang 18 and lld are installed (`/usr/bin/clang`). Rust is 1.93 in WSL.

## Architecture (required, because later milestones build on it)

- Lexer → parser (an AST with a source span on every node) → **checker** that resolves names and types into a **typed representation** (resolved symbols, types on every expression, lexical scopes, the call graph, explicit control-flow exits such as `return`) → LLVM IR text emitter → clang. The emitter works from the typed representation, never from the AST or source text.
- **One place lowers function signatures** (how a language function becomes an LLVM function), so later milestones can add hidden arguments (a context pointer, result destinations) by changing that one place.
- **Runtime failures are structured:** generated code calls one runtime function, `nl_fail(kind, file_id, line, col)`, with a failure kind (overflow, divide by zero, bad cast, bad shift). The runtime (a small C file under `runtime/`) formats the message and exits. Generated code never formats messages or calls `exit` itself.
- Builtins (here just `print`) are marked in the checker as having an effect, so later compile-time evaluation can't run them.

## Language subset

Syntax as in DESIGN.md and EXAMPLES.md. Where those don't say, use these (decided for this task):

- **Statements:** a newline ends a complete statement, except inside parentheses or after an operator or comma; semicolons are optional. Shadowing in an inner scope is allowed; declaring the same name twice in one scope is an error.
- **Functions:** `fn name(a: int, b: long) -> int { ... }`. An omitted return type means `()` (nothing). `fn main()` takes nothing and returns `()`. A function with a result must produce one on every path; a block's last expression is its value; `return e` also works.
- **Bindings:** `let` (immutable) and `var` (mutable), with optional type annotations; `x = e`; `+= -= *= /= %=` mean exactly `x = x op e`, with the same checks.
- **Types:** `int` (32-bit), `long` (64-bit), `bool`. No implicit conversions: `int + long` is a build error naming which side to cast. Casts: `(long)x` widens; `(int)x` narrows, checked (a value that doesn't fit fails). Widening methods: `x.to_long()` on `int`.
- **Literals:** decimal, `1_000_000`, `0xFF`, `0b1010`; the `L` suffix makes a `long`. An unsuffixed literal takes the type its context needs, else `int`; one that doesn't fit its type is a build error. The most negative value is written `-2147483648` and must not overflow on the way (parse `-` with a literal as one negative literal).
- **Operators and evaluation:** operands and arguments are evaluated left to right; `&&` and `||` short-circuit. `+ - *` and unary `-` are checked: overflow fails. `/` and `%` fail on a zero divisor; `MIN / -1` fails (it overflows); `MIN % -1` is `0` (guard it before LLVM's `srem`, which would trap). Wrapping `+% -% *%` never fail. Comparisons, `! && ||`, bitwise `& | ^`; `<<` and `>>` need `0 <= n < width` (else fail); `<<` discards bits shifted out; `>>` on signed types is arithmetic (keeps the sign).
- **`if c { } else if c { } else { }`**, as a statement and as an expression (both branches' types must match).
- **`print(x)`** for `int`, `long` and `bool`: writes the value and a newline to stdout.
- **No loops yet** (T02). **No recursion:** a call cycle is a build error saying recursion is opt-in with `recursive` and not supported yet.

## Commands

- `nlc run <package-dir>`: compile every `.nl` file in the directory (one package; no imports), build with `clang -O1` into a temporary directory, run `main`, and pass through its stdout, stderr and exit code.
- `nlc build <package-dir> -o <file>`: the same without running.
- Exit codes: 0 success; 1 a runtime failure in the program; 2 a build error (lexing, parsing, checking); 3 a tool failure (clang missing, can't write files).

## Errors

Lexing, parsing and checking errors report `file:line:col: error: <what's wrong>` and, where possible, what to do (for an unknown name close to a known one: `did you mean 'count'?`). The first error per file is enough for now. A runtime failure prints `file:line:col: <kind>` to stderr, for example `main.nl:7:13: overflow in int addition`.

## Tests (all must pass with `cargo test`)

- Unit tests in the compiler where useful (lexer, parser).
- A Cargo integration test that runs every directory under `tests/run/`. Each has `main.nl` (or several `.nl` files), `expected.stdout`, `expected.stderr` (with the temporary directory and repository root normalised away) and `expected.exit` (one number). Build-error cases are directories too, with exit 2.
- At least these cases:
  - arithmetic and precedence; `long` arithmetic past 2^31; casts both ways; widening with `.to_long()`; `+=` and the other compound forms; wrapping ops; bit operations;
  - failures, each with the right `file:line:col`: `int` overflow in `+`, `*` and unary `-`; divide by zero; `MIN / -1`; `MIN % -1 == 0` (not a failure); `(int)` of a too-large `long`; a shift by 32 on an `int`; the most negative literal;
  - `if` as a statement and as an expression; `&&` short-circuit (the right side would fail if evaluated);
  - build errors: unknown name with a "did you mean"; `int + long`; assigning to a `let`; a function missing its result on one path; wrong argument count; a literal too big for `int`; a call cycle; a duplicate name in one scope.

## Report (docs/tasks/T01-report.md)

What you built, the commands that build and test it, the test results (counts), every choice you made that this task or DESIGN.md didn't settle, and anything you'd change about the plan or T02.
