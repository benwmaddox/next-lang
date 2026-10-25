# E1: the self-hosted compiler, end to end, for a small subset

This spec incorporates docs/reviews/sol-E1-r1.md.

Ben (2026-10-25): after H1b, focus on the self-hosted compiler getting all the way to a correct executable. This is the first step of the E-track (PLAN.md, Order of work item 5): every stage in next-lang, for a small part of the language, then widen it task by task.

Depends on H1b item 1 (one input policy for every command). Read docs/PLAN.md items 3 and 5, DESIGN.md "The theory being tested" and "The job's data stack", and docs/research/selfhost-architecture.md sections 5.2 to 5.4 first.

## Scope

- Rust nlc is stage 0 and the reference. The self-hosted compiler (selfhost/) is its own implementation. The two share only the language, the C runtime and the test suite, and are compared by behaviour. Exact IR equality with Rust nlc is not required.
- E1 adds a checker and a code generator after the existing self-hosted lexer and parser, for the subset below. The result is LLVM IR text that clang builds against runtime/nl_runtime.c.
- The self-hosted compiler is built by the Rust nlc of the same commit, always with `--frontend=rust`. Self-compilation and the stage 2 and stage 3 stability check belong later (research section 5.4).
- Recursion is out of E1: no `recursive` functions, and no call cycles in accepted packages.

## Commands

**The self-hosted compiler** gets one new command:

```
nlc --frontend=rust run selfhost -- build <package> -o <file.ll> [--test]
```

- Without `--test` it builds a program and requires `main`, like `nlc build` and `nlc run`.
- With `--test` it builds a test program and does not require `main`, like `nlc test`.
- Both forms check every function and every test, as Rust does.
- The IR is the same in both forms except for the build kind in the metadata header (below). That matches Rust, which emits the same module for `build` and `test` and only links it differently.

**Rust nlc** gets two small commands, the driver seam:

- `nlc link-ir <file.ll> -o <exe>` links the IR into an executable.
- `nlc test-ir <file.ll>` runs the tests of a test build.

Both live in compiler/src/driver.rs and share its toolchain code with `nlc build` and `nlc test`. They do not have a second clang command line.

- **One clang path.** `run_clang` and `clang_internal` stop taking a whole `CompileOutput`. They take the IR path and a small link description instead: build kind, stack mode, optimisation level and recursion data. The package path builds that description from `CompileOutput`, and `link-ir` builds it from the IR's metadata header. Everything else is shared:
  - the runtime source path and its missing-file error;
  - `NLC_OPT_LEVEL` (1 by default, 3 allowed, any other value the same tool error);
  - `-DNLC_TEST_BUILD=1` for test builds;
  - `-DNLC_STACK_MODE_OFFSET=1` for offset IR;
  - the "clang failed" error.
- **Host target.** Like `run_clang` today, `link-ir` passes no `-target`, and neither compiler writes a target triple or data layout into its IR. Both build for clang's default target on the WSL host, with the pinned clang 18.1.3. The report records `clang -print-target-triple`.
- **Recursion.** `link-ir` refuses, with status 3, IR whose header declares recursion other than `none`. It also refuses IR that contains `nlc.recursion.targets=`. Under E1's checked acyclic rule, skipping T19's probe build is therefore safe. The header is versioned, so a later E-task can add a call-graph and recursive-flags record. That record would feed the existing probe, read, patch and rebuild-until-stable loop, and later T17 native-frame checks, through the same link description.
- **Test runner.** `test-ir` requires a test build. With zero tests it prints `0 passed, 0 failed` and exits 0 without linking, as `nlc test` does. Otherwise it links into a temporary directory and runs the test runner that `nlc test` uses. That loop is extracted from `test_package` into one function that both commands call. It does the following:
  - starts one child per test with `NLC_TEST_INDEX`;
  - prints `ok   <name>` or `FAIL <name>`, plus the exit-code lines for status 70, other codes and abnormal termination;
  - forwards each child's stdout, then its stderr;
  - prints the `N passed, M failed` summary;
  - exits 0 if every test passed, otherwise 1.

  The loop needs only the binary and the ordered test names, which the header carries. Stack-peak budgets are not part of E1.
- A later task gives next-lang a process capability, so the self-hosted compiler can run clang and the test children itself. Until then, these two commands are the bridge.

**The IR file contract.** The file starts with a metadata header in comment lines:

```
; nlc-link-ir 1
; nlc.build program            (or: test)
; nlc.stack offset
; nlc.recursion none
; nlc.test <index> <test name as lowercase hex of its UTF-8 bytes>   (one line per test, in order)
```

- Test names are the decoded string values, as Rust's checker holds them. Hex keeps any byte safe in a comment line.
- The file ends with the line `; nlc-link-ir end`.
- `link-ir` and `test-ir` refuse, with status 3, a file that has a missing or unknown header, an unknown version, a stack mode other than `offset`, or no end line. The end line means a truncated file can't be linked.

**Output and failure handling.**

- The self-hosted compiler builds the whole module in one caller-owned `Bytes` builder and writes it with one `Fs.write` call. `Fs.write` truncates on every call (nl_runtime.c, `nl_fs_write`), so writing in chunks is not streaming and is not allowed.
- `-o` is a relative path beneath the working directory, because `Fs` is rooted there and opens paths beneath it. An absolute path, an escaping path or a failed write is a tool failure: status 3, nothing claimed written.
- On any rejection (syntax, limit, unsupported, checker error) nothing is written. The harness deletes the output path before each build and checks that it is still absent after a rejection.

## The E1 subset

The subset is closed. Any node kind, flag, operator, type name or callee outside it is unsupported (see Package eligibility).

**Package and entry.**

- Files are loaded under H1b's input policy: the same limits, messages and order as every other command, and invalid UTF-8 as a syntax diagnostic. File identities are the policy's sorted, package-relative names.
- The manifest is read the way Rust's `read_memory_config` reads it:
  - the same defaults with no `package.toml` (capabilities `["out"]`, recursion budget 0, Rust's headroom and globals budget);
  - the same keys: `capabilities`, `job_headroom`, `globals_budget`, `recursion_budget`;
  - the same handling of other keys and `[section]` lines;
  - the same tool-failure messages, with status 3 and the `nlc: tool failure: ` prefix.
- Granted capabilities set the environment mask (fs 1, out 2, env 4). `recursion_budget` is passed to `nl_context_create` as Rust passes it.
- When a key that Rust ignores today becomes an error (PLAN.md Small fixes), the self-hosted reader follows.
- `print` needs the `out` capability. Without it, the error is Rust's manifest-capability error at the call.
- `main` is `fn main()` returning `()`, checked when building a program or when the package declares `main`. A missing `main` and a wrong signature get Rust's entry errors and positions. `main(env: Env)` and `main` returning `Result` are unsupported, not entry errors.

**Declarations.**

- `fn name(params) -> result { body }` with no generic parameters and no `recursive` marker.
- Parameters are read mode only (no `write` or `grow`).
- Parameter, result and annotation types are `int`, `long`, `bool` and, where Rust accepts it, `()`. A missing result type means `()`.
- `test "name" { body }` with no parameters.
- Nothing else at top level: no `struct`, `enum`, `type`, `const` or `global`.

**Statements.**

- `let` and `var`, each with an optional annotation and a required initialiser.
- Assignment with `=`, `+=`, `-=`, `*=`, `/=` or `%=` to a local name. `>>=` and every other compound form are unsupported.
- `return`, with or without a value, as a statement and as an expression.
- Expression statements.
- `for name in a..b` and `for name in a..=b`, with an optional counter annotation.
- `break` and `continue`, as statements and as expressions.
- Standalone blocks `{ ... }`.
- `expect`, inside tests only.

**Expressions.**

| Form | Notes |
| --- | --- |
| `()` | the unit value |
| integer literals | every spelling the parser accepts, with or without `L`. A `-` directly before a literal is part of the literal (the parser folds it), so `-2147483648` is a valid `int` |
| `true`, `false` | |
| names | locals, parameters, loop counters |
| `f(args)` | direct calls to package functions, and `print(x)` for `int`, `long`, `bool` |
| unary `-`, `!` | `-` on anything but a literal is checked negation |
| `+ - * / %` | checked, on `int` and `long` |
| `== != < <= > >=` | on `int`, `long`, `bool`, as Rust allows |
| `&&`, `\|\|` | short-circuit |
| `if`/`else` | as statement and as expression, including `else if` chains |
| blocks with a tail | the block's value is its tail |
| parentheses | grouping only |

Out of the expression subset:
- the wrapping operators `+% -% *%`;
- the bit operators `& | ^`;
- the shifts `<< >>`;
- `??`, `?` and `?.`;
- casts, `.to_long()` and every other method call;
- `match`, indexing, fields, struct, array and collection literals, string and bytes literals, `take`, `fit`;
- indirect calls and function values.

**Facts the checker keeps.** These are internal, not syntax:
- `()` and `never` are types.
- `return`, `break` and `continue` have type `never`.
- Every block and statement records whether it falls through, as `statement_falls_through` and `check_block` do (checker.rs).

Rust's rules for an `if` whose branches are `never`, unreachable statements, and "can reach the end without a value" apply unchanged. A written `-> never` is unsupported.

**Tests.**

- `expect <bool expression>`, where a top-level comparison keeps its two operands for the failure report, as Rust's `TExpectKind::Compare` does.
- The expectation's source text is preserved byte for byte, including line breaks.
- Tests that take `Env`, `stack_peak` expectations, and tests ending in a `Result` are unsupported.
- `return` in a test and `expect` outside a test get Rust's errors.

## Package eligibility

Unsupported constructs reject the whole package before any artifact. The pipeline runs in this order, and the first stage that rejects decides the result:

1. **Front end:** input policy, lexing and parsing of every file, as `nlc parse` reports them (status 2).
2. **Manifest:** read after parsing, as Rust reads it after `load_package` (tool failure, status 3).
3. **Eligibility:** one deterministic pass over every node of every file. It covers unused functions, unreachable statements and every test, not just what `main` reaches.
4. **Checker:** in Rust's order (next section, status 2).
5. **Emission and the single write.**

A package with a syntax error and a `struct` therefore gets the syntax error. A package with a `struct` and an unknown name gets the unsupported diagnostic. Nothing runs after a rejection.

Rules of the eligibility pass:

- **Node kinds and flags.** Every node kind outside the subset is unsupported:
  - declarations: `Enum`, `Struct`, `TypeAlias`, `Const`, `Global`;
  - statements: `ForEach`, `Discard`;
  - expressions: `Match`, `Cast`, `Fit`, `Try`, `MethodCall`, `IndirectCall`, `Index`, literals other than unit, integer and bool, and the rest.

  So are a `Function` with generic parameters or the `recursive` flag, a parameter in `write` or `grow` mode, a `Test` with parameters, an operator outside the table, and a compound assignment outside the list.
- **Type names.** In a type position, `int`, `long`, `bool` and `()` are supported. Every other built-in type name the Rust checker knows is unsupported. That includes `Env`, `Fs`, `Out`, `Ascii`, `Text`, `Bytes`, `byte`, `Id`, `Option`, `Result`, `list`, `map`, `set`, `pool`, `queue`, `ring`, `grid`, `Path`, `DirEntry`, `FileKind`, `IoError` and `Full`, as well as any type with arguments, a range or a refinement. The list is taken from `parse_type` and `Checker::new` at E1's base commit and kept as one table. A test reports each entry as unsupported. A type name that nothing declares is not unsupported: it gets Rust's unknown-type error from the checker.
- **Callees and names.** Callee names resolve in Rust's order.
  - A call to a package function or to `print` is in the subset.
  - A name or call that Rust resolves to anything else is unsupported. That covers other built-in functions (`min`, `max`, `abs`, `sort`, `sort_by`, `binary_search`, `stack_peak` and the rest) and built-in enum cases (`some`, `none`, `ok`, `err`, and the `FileKind`, `IoError` and `Full` cases).
  - A name that resolves to nothing gets Rust's unknown-name or unknown-function error.
  - Redeclaring a built-in function name is a checker error, as in Rust.
- **Recursion.** The `recursive` marker is unsupported. A cycle of unmarked functions is not an eligibility matter. It reaches the checker's whole-program phase and gets Rust's "call cycle contains unmarked function(s)" error, after every body and test has been checked.
- **The diagnostic.** One line on stderr, `<file>:<line>:<col>: error: not supported by the self-hosted compiler yet: <construct>`, with status 2.
  - It names the first unsupported node: the first file in sorted order that has one, then the smallest start offset, then the outermost node at that offset.
  - `<construct>` comes from a fixed table of names, such as `struct declarations`, `match`, `the >>= operator` or `type Ascii`.
  - The harness recognises "unsupported" only by this exact one-line form with status 2.

## Checker

**Order.** The first error must equal Rust's: message, file, line, byte column, status 2, and the bytes `<file>:<line>:<col>: error: <message>\n` on stderr. Rust's order is its algorithm, not a postorder walk. For the subset, `Checker::run` (checker.rs) does the following:

1. **Registration**, file by file in sorted order. Within each file it registers the functions in source order, then that file's tests:
   - for functions: the built-in-name check, duplicate functions, then parameter types and the result type;
   - for tests: duplicate test names.

   An error in a test name in `a.nl` therefore comes before a bad parameter type in `z.nl`.
2. **Entry:** `check_entry`, when building a program or when `main` exists. A missing `main` is reported at line 1, column 1 of the first file.
3. **Bodies**, each function in declaration order, then each test in order, each stopping at its first error.
4. **Whole program:** effect paths, then the call graph and Rust's cycle check. The cycle check visits components in the order `strongly_connected_components` yields them, sorts each component's unmarked names, and reports at the first one's span.

Within a body, the order follows Rust's traversal, including the places where it is not left to right:
- `check_operand_pair` checks the right operand first when only the left is an unsuffixed literal. `print(2147483648 + missing)` reports `missing`, not the literal's range.
- `infer_loop_type` collects constraints from the annotation, the bounds' natural types and the body's uses of the counter, and reports conflicts, before the bounds are checked.
- Expected types flow from annotations, parameters, the function's result, `return` and the other operand into unsuffixed literals. Literal range errors are found only once that context is known.

The implementer documents the subset's full phase, category, file, function and expression order in the checker's source and pins each non-obvious step with a test. Where this spec and checker.rs disagree, checker.rs wins and the report says so.

**Structure.** The checker follows DESIGN.md "The theory being tested" and research section 5.2: flat tables, ids rather than pointers, and caller-owned scratch.

- The parser's tables stay immutable. One linear pass builds first-child and next-sibling links for every node (two longs per node). Checking and emission walk children through those links. They never rescan children or use the parser's shared `child_scratch`, which every `collect_children` call overwrites.
- Typed facts are node-indexed: a type id, a never or falls-through flag, and the resolved binding, function or literal value. The other tables are kept separate and ordered:
  - functions and tests, with their signatures and parameters;
  - scopes and bindings, with locals per function;
  - call edges;
  - types.
- `int`, `long`, `bool`, `()` and `never` are ids in an extensible type table, which E2 to E4 extend without changing the representation.
- Literal magnitudes stay in the parser's four limbs until contextual range checking finishes.
- Identifiers are interned to name ids once, in a caller-owned table sized from the token limit. Tables compare ids, not bytes.
- Each file gets one indexed line-start table, so the many runtime failure sites and the diagnostic get their line and column without rescanning.
- Each diagnostic has an explicit anchor node and offset. Unary and binary nodes anchor at the operator, as `expression_node_anchor` does.
- Checking uses an explicit work stack of enter and resume frames. Each frame holds a node, a step, the expected type and the scope state, and a value stack carries results. A frame resumes at its next child, so the stack's depth follows nesting, not the number of children.
- The checker and the code generator add no `recursive` functions.
- Parallel checking waves and a public typed dump format (`nlc check --dump`) are not part of E1.

## Code generator

**ABI and stack mode.**

- The self-hosted generator emits offset addressing only (DESIGN.md "The job's data stack"), so it is built for the final design from the start.
- Every generated function takes `ptr %nl.ctx, i64 %nl.top`, with the top from `nl_context_base_offset`, as Rust's offset mode does. The header says `nlc.stack offset`, and `link-ir` compiles the runtime with `-DNLC_STACK_MODE_OFFSET=1`.
- E1 allocates no data-stack regions. Any construct that would need one is outside the subset, which is PLAN's support-or-fail-closed rule.
- The comparison therefore crosses stack modes on purpose. The Rust reference runs in its default mode (pointer, until O7), and behaviour must not depend on the mode.

**Startup and cleanup.** The C `main` matches what Rust emits (emit.rs, the `define i32 @main` section):

- **Entry reservation.** `nl_context_create` gets the entry's reservation, the manifest's recursion budget and the entry name (`main`, or `test '<name>'` for a test).
  - The reservation follows Rust's rule: the entry's bound, plus `DATA_STACK_HELPER_MARGIN`, rounded up to a 4096-byte page, at least one page.
  - A test compares the value against Rust's (`nlc inspect stacks`) for a scalar package.
- **Startup.**
  - `nl_env_create` gets the capability mask.
  - `nl_register_file` registers every file in sorted order, with its name written as escaped LLVM bytes.
- **Program build.**
  - `main` runs.
  - Then `nl_env_destroy` and `nl_context_destroy`, which flushes buffered output and fails with kind 20 if the write fails.
  - Then `ret i32 0`.
- **Test build.**
  - The program picks the selected test's reservation and name through `nl_test_selected_index`.
  - It calls `nl_set_test_mode`, runs the test function (which returns `i32`: 0 on pass, 1 at the first failed expectation), destroys the environment and context, and returns the test's status.
  - With no test selected, it falls through to `main` if there is one.
  - A package without `main` uses its first test's reservation as the default and returns 0, as Rust does.

**Emission structure.**

- Typed facts are lowered through explicit emission frames, using function-local value and block ids.
- All of a function's local allocas are emitted in its entry block before the body. The checker's locals-per-function table makes that one pass.
- The generator tracks whether the current block is terminated, emits nothing after a terminator, and uses only real predecessors in a phi (short-circuit joins, `if` values, the remainder join).
- Type and ABI lowering, failure kinds, and runtime declarations each live in one table, ready for E2 to E4.
- The module has fixed sections in a fixed order:
  1. the metadata header and `source_filename = "next-lang"`;
  2. runtime declarations;
  3. functions in id order, then test functions;
  4. constant strings (file names, entry names, expectation sources);
  5. the C `main`;
  6. the end line.

  There are no temporary paths, process ids or times.
- E1 writes a single module. Per-file modules come later.

**Runtime semantics checklist.** Each item has a directed fixture that compares exact stdout, stderr and status:

- **Representation.** `int` is i32, `long` is i64, `bool` is i1.
- **`+ - *`.** These use `llvm.s{add,sub,mul}.with.overflow` and fail with kinds 1 to 3 (`int`) or 5 to 7 (`long`). The failure reports the operator's position, which for a compound assignment is the `+=`-style operator.
- **Negation.** Checked negation of a non-literal is `0 - x` with the overflow check and fails with kind 4 or 8. A negative literal has no runtime check.
- **`/` and `%`.**
  - A zero divisor fails first, with kind 9 `divide by zero`, for both operators.
  - Then minimum `/` -1 fails with kind 12 or 13.
  - Minimum `%` -1 is 0 and does not fail.
  - Both operators truncate toward zero, and the remainder takes the dividend's sign.
- **Evaluation order and short-circuit.** Operands and call arguments are evaluated left to right at runtime, whatever order the checker used. The right side of `&&` and `||` does not run (no output, no failure) when the left side decides.
- **Loops.**
  - Range bounds are evaluated once, start then end, before the loop.
  - `a..b` runs while the counter is `<` the end. `a..=b` runs while it is `<=` the end and exits when the counter equals the end, before incrementing, so a range ending at the type's maximum does not overflow.
  - Empty and reversed ranges run zero times.
  - `break` and `continue` act on the innermost loop, and `return` leaves nested loops.
- **`print`.** It writes decimal `int` and `long`, or `true`/`false`, each followed by a newline, through the runtime's buffered output.
- **Runtime failure.** It goes through `nl_fail` (nl_runtime.c):
  - it flushes all buffered output first, so earlier prints appear;
  - then it writes `<file>:<line>:<col>: <message>\n` to stderr, using the registered package-relative file name;
  - then it exits with 1, or with 70 in test mode.
- **Expectation failure.** A failed expectation prints through `nl_expect_fail_compare` (with left and right values, and the bool flag) or `nl_expect_fail_bool`, with the preserved source. The test returns 1 at once and runs nothing after it.

## The compiler's own budget

The self-hosted compiler's `main` (selfhost/main.nl) already owns large source, token and parse buffers sized by limits.nl, and the parser's manifest budgets 7800 KiB of recursion. E1's new tables live alongside them, so their sizes are stated up front:

- **Capacities.** Every new table's capacity comes from the H1b policy limits, never tighter, so no input that the policy accepts and Rust compiles hits a limit Rust doesn't have. The constants go in limits.nl:
  - typed facts and sibling links: one per node;
  - functions plus tests, bindings, scopes and call edges: each at most the node limit;
  - interned names: at most the token limit;
  - the work and value stacks: nesting-bounded.

  The IR buffer's maximum is a derived bound:
  - a per-node constant times the node limit, since every node emits at most a constant number of bytes because symbols and values are named by ids;
  - plus the package's source bytes, since expectation sources and file names are bounded by them;
  - plus the fixed sections.

  The bound is stated with its derivation in limits.nl. Pages are committed only as written, so a large maximum costs address space, not memory. The report gives the measured bytes of IR per source byte.
- **Exhaustion.** Exhausting any table is a named limit diagnostic, in the parse limits' form with status 2, never a truncated success. On a package the reference builds, a limit diagnostic is a failure, never "unsupported". Tests sit at N and N+1 for every limit that the input policy can reach.
- **Ownership.** All tables and scratch are caller-owned in `main`'s frame and passed down.
  - Lexer-only scratch (delimiters, file data) ends with parsing.
  - Source, tokens and parse tables live through emission, because interned names refer to source slices and diagnostics need offsets.
  - Typed tables live through emission.
  - The IR buffer lives until the single write.
- **Measurement** (report, separately): the computed data-stack bound (`nlc inspect stacks selfhost`) against the observed allocation high-water from the runtime's existing statistics, the reservation, and peak RSS. If no statistic reports the high-water in the mode the compiler is built in, the report says so.

## Acceptance

**Case sets.**

- A checked-in classification file lists every package under tests/run and tests/test, and every directed E1 fixture, as `build`, `diagnose` or `unsupported`.
- Packages are classified by hand from this spec, never by running the self-hosted compiler.
- A package without a class fails the harness, so new fixtures must be classified.
- Directed fixtures for supported features are `build` or `diagnose`. The directed unsupported-construct fixtures are `unsupported`.
- A `diagnose` case expects status 2, except manifest-error cases, which expect Rust's tool failure (status 3) and its exact bytes.

**The harness** is `scripts/compare-selfhost.sh --build`, run by `cargo test`.

1. It builds the self-hosted compiler once with `nlc --frontend=rust build selfhost -o <exe>`.
2. For every classified package it runs the reference first, `nlc --frontend=rust build` or `test`, and checks that its result fits the class:
   - `build`: the reference succeeds;
   - `diagnose`: status 2 (status 3 for manifest-error cases);
   - `unsupported`: either result.

   It also compares against the repository's `expected.*` files, the second oracle, after the normalisation documented in compiler/tests/language.rs (`<repo>`, `<package>`, temporary paths). A reference that disagrees with its class is a misclassification and fails the harness.
3. It then runs the self-hosted compiler and compares results:
   - **`build`:** for programs, `build` then `link-ir`; for test packages, `build --test` then `test-ir`. The executable's, or the runner's, stdout, stderr and status must equal the reference's raw bytes.
   - **`diagnose`:** stderr bytes and status equal the reference's.
   - **`unsupported`:** the result must be the unsupported diagnostic (eligibility leaks fail).
   - An unsupported result on a `build` or `diagnose` case fails.
4. Every run uses the same working directory, arguments and environment (a fixed environment, `NLC_TEST_INDEX` unset), with a per-run timeout.
   - Timeouts, signals, tool failures (status 3) and limit diagnostics are failures, never "unsupported". The only exception is a manifest-error case whose status-3 bytes equal the reference's.
   - The harness checks that no IR file is left after a rejection.
5. The whole comparison runs at the default `-O1` and again with `NLC_OPT_LEVEL=3`, for both compilers.
6. It reports counts per class and optimisation level: built and matching, diagnosed and matching, unsupported, mismatches (must be zero).

**Directed fixtures** (the Unsupported group is classed `unsupported`, except where noted; every other group is `build` or `diagnose`):

- **Arithmetic:**
  - every operator at both widths, at and next to the minimum and maximum;
  - each overflow failure (add, subtract, multiply, negate) at both widths;
  - both zero-divisor failures;
  - minimum `/` -1 failing and minimum `%` -1 giving 0;
  - every sign combination of `/` and `%`;
  - negative literals against dynamic negation of the minimum;
  - compound assignments failing at their operator.
- **Literals:** range rules at both widths in every typing context (annotation, parameter, result, `return`, other operand, no context), with and without `L`, including `-2147483648`, `2147483648`, `9223372036854775808L` and `-9223372036854775808L`.
- **Evaluation:**
  - short-circuit suppression of output and of a failure;
  - left-to-right order of operands and arguments shown by prints;
  - bounds evaluated once;
  - empty, reversed and extreme ranges (inclusive to both maximums);
  - nested loops with `break` and `continue`;
  - `return` from nested loops;
  - `if` as statement and expression;
  - block tails and standalone blocks with scoping;
  - `()` functions and value-less `return`;
  - never-typed branches;
  - a failure after earlier output.
- **Checker order:**
  - competing signature, body and test errors, across files;
  - an entry error against body errors;
  - operand reversal;
  - loop-inference conflicts against bound errors;
  - an unmarked cycle (two functions, and a self-call) losing to a test-body error;
  - duplicate functions, tests, parameters and locals;
  - unknown names and types;
  - assignment to `let`, to a parameter and to a loop counter;
  - a missing value on some path;
  - `break` outside a loop;
  - `expect` outside a test;
  - `return` in a test.
- **Package and entry:**
  - no manifest;
  - a manifest granting `fs` and `env`;
  - a manifest without `out`, with `print`;
  - a malformed manifest (tool failure, compared byte for byte);
  - missing `main`;
  - a bad `main` signature;
  - multi-file packages in sorted order, with file names that need escaping, as far as the input policy allows.
- **Tests:**
  - passing and failing (bool, and `int`, `long` and `bool` comparisons);
  - runtime-failing (status 70);
  - multi-line expectation source;
  - zero tests;
  - a test-only package;
  - a package with `main` and tests, whose `build` runs `main` only (tests/test/harness is the model).
- **Unsupported:**
  - one fixture per construct-table entry, each also placed in an unused function, an unreachable statement and a test;
  - the `recursive` marker;
  - packages that also contain a checker error, where unsupported wins;
  - a package with a syntax error and an unsupported construct, where the syntax error wins (classed `diagnose`).

**Generated cases.** A seeded generator writes:

- valid subset packages: nested expressions, branches, loops and calls at both widths and at boundary values;
- invalid packages with one or several seeded errors, chosen to compete across phases, files and operand order.

`cargo test` runs a fixed seed set. The report covers a larger run.

**Time and memory.** A new generator writes a valid, uniquely named, benchmark-sized subset package within the input policy. The existing scripts/gen-bench-corpus.sh repeats declarations and unresolved filler, so it is not usable here.

- Measure with release nlc, best of 5, for both compilers:
  - wall time and peak RSS for the whole build;
  - for the self-hosted path: load and parse, eligibility, checking, emission and the write, then `link-ir`'s clang time;
  - the bootstrap time to build the self-hosted compiler with stage 0;
  - Rust nlc's build, with its clang time separate.
- Report the compiler's own stack and memory measures as described in "The compiler's own budget".

**Report:** docs/tasks/E1-report.md. It covers:

- the counts;
- the measurements;
- the documented checker order and any place it differs from this spec;
- the eligibility construct table;
- what was awkward to write in next-lang;
- the plan for E2.
