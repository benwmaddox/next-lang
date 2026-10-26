# E1 report: self-hosted compiler end-to-end slice

## Result

The self-hosted compiler now checks the E1 subset and emits one offset-mode LLVM module. The Rust driver provides `link-ir` and `test-ir`; both use the existing clang/runtime path, validate the versioned metadata header, and reject recursive IR. The selfhost command reads the package under H1b's limits, parses every source file before reading the manifest, rejects unsupported syntax before checking, and writes IR once only after a successful compile.

The stage-zero compiler is built from `selfhost/` with Rust nlc. It remains a separate implementation from the Rust checker/emitter. The program IR it emits declares `nlc.stack offset` and is linked by `link-ir` with the offset runtime.

## Comparison results

The checked-in classification table covers **482 packages** under `tests/run`, `tests/test` and `tests/e1`:

| Class | Count | Result at O1 and O3 |
| --- | ---: | --- |
| Build | 34 | All outputs, diagnostics and statuses matched |
| Diagnose | 39 | All diagnostic bytes and statuses matched |
| Unsupported | 409 | All were rejected with the specified one-line diagnostic and no IR file |
| Mismatches | 0 | Both optimization levels |

The seeded comparison added 8 valid and 8 invalid packages at each optimization level; all matched at O1 and O3. `scripts/compare-selfhost.sh --build` verifies every reference result against checked-in `expected.*` files before comparing the selfhost path.

The table includes 121 directed E1 packages. Coverage includes checked arithmetic at both widths, overflow and division failures, short-circuiting, operand and argument order, extreme inclusive ranges, nested loop control, if expressions, block tails and scopes, expectation reports, test-runner runtime failures, manifest behavior, a quoted multi-file runtime path, literal-range contexts, checker phase order, and unsupported operators/types in unused functions, unreachable statements and tests. Existing run/test fixtures cover the other unsupported node categories; the E1 matrix also includes each listed non-scalar built-in type and all out-of-subset arithmetic operators.

## Checker order and eligibility

The implementation order matches `checker.rs` for the supported subset:

1. Load and parse every sorted file under the shared input policy.
2. Read the manifest and build immutable-node child links, interned names and line indexes.
3. Run eligibility over all nodes, including unused functions, unreachable statements and tests. Select the first sorted file and source offset, preferring the outer node at a shared offset.
4. Register functions and tests file by file. Within each file, function built-in-name and duplicate checks precede its parameter/result type checks; tests are then checked for duplicate names.
5. Check the entry point.
6. Check function bodies in declaration order, followed by tests in declaration order.
7. Check whole-program call cycles after every body has been checked.

Within a body, the explicit checker frames carry expected types and fall-through facts. Operand pairs reverse their visit order when the left is an unsuffixed literal and there is no expected type. Loop counter constraints are combined from the annotation, bound types and body uses before checking the bounds. Literal range errors are delayed until their type context is known. The E1 directed cases and generated diagnostics pin these ordering rules. No mismatch with the current Rust checker was found.

The fail-closed eligibility table is:

| Area | Accepted | Rejected as unsupported |
| --- | --- | --- |
| Declarations | Non-generic, non-recursive functions; zero-parameter tests | Enums, structs, aliases, constants, globals, generic/recursive functions, write/grow parameters and test parameters |
| Statements | Let/var, local assignment (`=`, `+=`, `-=`, `*=`, `/=`, `%=`), return, range loops, break/continue, blocks, test expectations | For-each, discard and other compound assignments (including `>>=`) |
| Expressions | Unit/integer/bool literals, local names, direct package calls, `print`, checked scalar operators, short-circuit booleans, if/else, block tails and parentheses | Match, cast, fit, `?`, method/indirect/optional calls, function values, indexing, fields, qualified cases, struct initialization, arrays and collection literals, grid indexing, and other node kinds |
| Operators | `+ - * / %`, comparisons, `&&`, `||`, unary `-` and `!` | `+% -% *%`, `& | ^`, `<< >>`, `??`, and operators outside the table |
| Types | `int`, `long`, `bool`, `()` | `Env`, `Fs`, `Out`, `Ascii`, `Text`, `Bytes`, `byte`, `Id`, `Option`, `Result`, `list`, `map`, `set`, `pool`, `queue`, `ring`, `grid`, `Path`, `DirEntry`, `FileKind`, `IoError`, `Full`, and generic/array/refined type forms |
| Built-ins | Direct package functions and `print` | Other built-in calls (including `min`, `max`, `abs`, `sort`, `sort_by`, `binary_search` and `stack_peak`) and built-in enum cases (`some`, `none`, `ok`, `err`, `FileKind`, `IoError`, `Full`) |

Unknown names and types stay checker errors. A syntax error or manifest failure takes precedence because it occurs before eligibility. Cycles of unmarked functions are checker errors after function and test bodies.

## Benchmark and memory

The release benchmark package contains 10,000 uniquely named helper functions and one call from `main`: 500,042 source bytes. Every timing below is the best of five, measured under the 8,000,000 KiB virtual-memory limit. Peak RSS is `/usr/bin/time`'s maximum resident set size.

| Path/phase | Best wall time | Peak RSS |
| --- | ---: | ---: |
| Rust release nlc bootstraps selfhost (stage zero, pointer mode) | 13.017 s | 162,160 KiB |
| Rust nlc full build including clang | 5.671 s | 186,140 KiB |
| Rust `inspect stacks` (compile/check/emit without clang) | 5.642 s | 187,552 KiB |
| Rust clang/link estimate (difference of independent bests) | 0.029 s | — |
| Selfhost load/parse, eligibility/check, emission and one IR write | 1.622 s | 174,768 KiB |
| Selfhost `link-ir` / clang | 4.881 s | 173,468 KiB |
| Selfhost compiler plus `link-ir` | 6.503 s | 174,768 KiB |

Rust nlc does not expose its generated IR as a file, so the Rust clang value is an estimate from subtracting the best `inspect stacks` time from the best full-build time; those two best samples are independent. The E1 selfhost language has no clock/timer primitive, so load/parse, eligibility, checking, emission and writing cannot be timed separately from inside the compiler. The combined compiler time and separate `link-ir` time are reported instead.

The benchmark IR is 6,153,426 bytes, or 12.31 IR bytes per source byte. For `nlc inspect stacks selfhost`, the computed data-stack worst case is **3,478,494,879 bytes**, with a rounded reservation of **3,478,495,232 bytes**. The report gives a native-stack worst case of **8,054,176 bytes** and a recursion budget of **7,987,200 bytes**. The stage-zero executable is built in pointer mode; `NLC_STACK_STATS=1` emits no high-water statistic in that mode. Building the compiler package itself with `NLC_STACK_MODE=offset` is rejected by Rust nlc because `empty_compiler_tables` uses a large `CompilerTables` type outside its offset slice. Thus the allocation high-water is unavailable for the mode in which stage zero is built. The measured compiler-process peak RSS above is not a data-stack high-water measurement.

The existing stack-contract test now pins the exact attribution for the E1 tables and allows the measured compiler frame below 4 GiB. Its previous 1 GiB ceiling predates the checker/emitter tables.

## What was awkward

The hardest part was keeping large compiler tables caller-owned while the next-lang functions pass them through parsing support, eligibility, checking and emission. The checker and emitter use explicit work frames, and LLVM CFGs must preserve only real predecessors for phi nodes. Diagnostics and runtime failures also need byte-exact source positions, so file-relative line indexes and explicit operator anchors have to stay alive through emission. Finally, LLVM IR is built as one bounded `Bytes` value because `Fs.write` truncates on each call.

## E2 plan

Follow E1 with E1c from `docs/PLAN.md`: move the E1 program path to the next-lang core library and freestanding runtime. E2 then adds structs, enums, `match`, `Option`/`Result` and `?`, extending the type table, eligibility, checker and emitter while retaining the Rust behavior comparison. E3 adds arrays, lists, `Ascii`/`Text`/`Bytes` and builders, constants and globals; E4 adds refinements and the remaining collections.

## Final validation

- `scripts/compare-selfhost.sh --build`: passed, 34 builds, 39 diagnostics and 409 unsupported packages at both O1 and O3; zero mismatches.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` with `NLC_FRONTEND=rust`: passed.
- The same full `cargo test` suite with `NLC_FRONTEND=selfhost`: passed.
- Debug and release `cargo build`, with the target directory outside the repository: passed.
- `git diff --check`: passed.
