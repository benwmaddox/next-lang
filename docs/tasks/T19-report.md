# T19 report: recursive functions

## Implemented

- Added `recursive fn` and call-cycle validation over direct calls and possible function-value targets. Every function in a cycle must be marked; diagnostics name each unmarked function and say to mark every function `recursive`.
- Added native stack checks before calls into recursive functions. The compiler first builds optimized code with clang's `.stack_sizes` data, reads the resulting ELF frame sizes, and patches the checks with the callee frame plus the deepest reachable nonrecursive call chain, alignment/call allowance, and the fixed 64 KiB foreign-call margin. It rebuilds and confirms frame sizes stabilize after inserting checks. This also handles the largest target of an indirect call.
- Added runtime checks against the current stack pointer and the usable native stack limit obtained from pthread stack bounds. The default recursion budget leaves an 80 KiB safety margin; `recursion_budget` in `package.toml` can lower it, with units such as `256KiB`. Exhaustion calls `nl_fail` with `recursion budget exhausted` at the recursive call location. The runtime reserves 16 KiB for reporting and 512 bytes for its helper path.
- Added recursive-cycle region checks for large locals, hidden large-result destinations, and large temporary argument copies. Caller-owned large values borrowed through parameters remain valid across recursive calls.
- Updated constant evaluation to account for calls as steps and compute cacheability/effects across entire call cycles. Constant evaluation has a checked call-depth cap of 64 so deep recursion returns a build error instead of exhausting the compiler's Rust stack. The infinite-recursion fixture covers this guard; ordinary call and expression steps continue to use the existing step limit.
- Added fixtures for factorial, Fibonacci, mutual and function-value recursion, recursive descent through a caller-owned pool, default and lowered budgets, indirect recursion, a large native frame, a foreign call near exhaustion, direct/mutual/indirect region violations, hidden results and temporary copies, recursive constants, const effects, and test-child failure status. Updated expected diagnostics for existing unmarked cycles.

## Verification

Ran from WSL:

```text
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt --all -- --check
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test
NLC_OPT_LEVEL=3 CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test
```

All commands passed. Both complete test runs include the run and test fixture suites, including the T19 acceptance cases. Focused runs also confirmed the budget and large-frame failures report the source call location and exit 1, the near-exhaustion foreign-call fixture completes, and the recursion-budget test child exits with status 70.

## Scope and implementation choices

Native frame extraction currently supports 64-bit little-endian ELF, and stack-bound discovery uses Linux pthread APIs, matching the requested WSL/Linux environment. The compiler uses a checked const-call depth limit, which is the bounded-depth option allowed by the task; it reports this limit distinctly from the ordinary evaluator step limit. No external crates were added.

## Fix round 1

- Raised the compile-time function call limit from 64 to 10,000 and kept the 10,000,000-step limit. Constant and global-initializer evaluation run on a scoped Rust thread with a 4 GiB stack; the thread returns a normal build diagnostic if it cannot start or panics.
- Measured the stack pointer distance while evaluating `depth(9999L)` (10,000 language-level calls). The debug `nlc` built by `cargo build` used 2,503,017,024 bytes, about 250,302 bytes per call; the release `nlc` used 188,946,112 bytes, about 18,895 bytes per call. The debug run's maximum RSS was about 2.36 GiB. A 512 MiB stack would not be sufficient for the observed debug frame size, so the evaluator reserves 4 GiB and touches pages only as recursion needs them.
- Added a fixture that succeeds at exactly 10,000 calls and changed the over-limit fixture to check that the 10,001st call fails with the named 10,000-call limit. Added stress fixtures for 2,000 nested parentheses and a 2,000-term addition chain. The parser now rejects expression nesting beyond 64 with a source diagnostic; a 64-term chain succeeds, while a 96-term chain overflowed the checker before this guard was added.
- Verification passed:

  ```text
  CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build
  CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test
  NLC_OPT_LEVEL=3 CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test
  CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt -- --check
  ```

  `cargo build --release` was also used for the release stack measurement. The debug fixture runner verified both the 10,000-call success and 10,001-call limit error.

## Fix round 2

- Raised the expression nesting limit to 1,000. Parentheses have an explicit parser depth check, while the parsed expression tree is checked iteratively so long binary chains and nested calls get a source diagnostic instead of overflowing during checking. An `if` or `match` plus its branch block counts as one construct level. A separate parser recursion guard catches malformed inputs before parser helper recursion grows too far.
- Reduced recursive frames by splitting parser prefix, postfix, and statement handling; dispatching checker calls, binary expressions, `if`, and `match` through smaller paths; splitting evaluator calls, collections, access expressions, conditionals, and statement loops; and splitting emitter call, binary, and `if` paths. The constant evaluator no longer adds a separate large-stack thread.
- Moved the full compile pipeline onto one named worker thread with a fixed 1 GiB stack. Parsing, checking, constant/global evaluation, and emission all run there. Linux reserves the mapping without touching its pages; the 10,000-call evaluator fixture reaches far less than the available stack.
- Stack-pointer probes measured the deepest downward extent in each phase. The parser, checker, and emitter before-values were measured on an instrumented snapshot of the original unsplit compiler at 64 nested levels; that depth stayed below the old 8 MiB main-thread limit. The evaluator before-values are the recorded round 1 run at 10,000 calls. Round 2 values are direct phase probes. The number per level divides the measured extent by the repeated source nesting in the fixture.

  | Phase and repeated construct | Before debug | Before release | Round 2 debug | Round 2 release |
  | --- | ---: | ---: | ---: | ---: |
  | Parser, nested parentheses | 61,200 B/level | 6,013 B/level | 12,370 B/level | 5,016 B/level |
  | Checker, nested direct calls | 79,692 B/call | 6,325 B/call | 14,725 B/call | 6,125 B/call |
  | Evaluator, 10,000 language calls | 250,302 B/call | 18,895 B/call | 26,176 B/call | 3,328 B/call |
  | Emitter, nested direct calls | 12,968 B/call | 2,377 B/call | 4,373 B/call | 1,811 B/call |

  Before totals at 64 levels were 3,916,768 / 384,816 bytes in the parser for parentheses, 5,100,288 / 404,816 bytes in the checker for nested calls, and 829,952 / 152,112 bytes in the emitter for nested calls (debug / release). Round 2 totals were 12,370,000 / 5,016,368 bytes for 1,000 nested parentheses; 23,623,888 / 8,504,368 bytes in the parser, 14,724,672 / 6,125,264 in the checker, and 4,372,832 / 1,811,376 in the emitter for 1,000 nested calls. For a 1,000-term addition chain, checker extent was 32,132,576 / 3,194,080 bytes and emitter extent was 532,304 / 514,864 bytes. A 300-level nested-if fixture measured 8,268,688 / 4,584,368 bytes in the parser, 6,107,296 / 1,323,664 in the checker, and 883,232 / 392,176 in the emitter.
- Added fixtures for 1,000 nested parentheses, a 1,000-term `+` chain, a 1,000-term `&&` chain, 300 nested `if` expressions, and 1,000 nested calls. The success fixtures print `7`, `1000`, `true`, `123`, and `7`, respectively. The 1,001-level parenthesis, binary-chain, and call fixtures report `expression nesting limit of 1000 exceeded`. Also manually built debug packages with 1,000 nested `if`, `match`, and block constructs; each printed `123`, while 1,001 nested blocks returned the same limit diagnostic.
- The existing 10,000-call constant fixture completed with stdout `9999`. Its debug stack extent was 261,764,896 bytes and peak RSS without probe instrumentation was 287,936 KiB (about 281 MiB). Release stack extent was 33,281,392 bytes and peak RSS was 99,088 KiB (about 97 MiB), keeping debug RSS below the 512 MiB target.
- Verification passed after the changes:

  ```text
  CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build
  CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test
  NLC_OPT_LEVEL=3 CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test
  CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt -- --check
  ```
