# E2: the self-hosted compiler gains structs, enums, `match`, `Option`, `Result` and `?`

Depends on E1 and E1c, and on the small-fixes task S2 (docs/tasks/S2-small-fixes-build-and-suite.md), which changes the harness's default and long modes. Read docs/PLAN.md items 3 and 5, DESIGN.md "The theory being tested", "The job's data stack", "The standard library needs no C library" and "Types, and refinement types", docs/design/core-library.md, and E1's spec, report and review first. E1's spec holds for everything this file does not change.

## Scope

- Rust nlc stays stage 0 and the reference. The two compilers are compared by behaviour: stdout, stderr and exit status. IR equality is not required, and neither is Rust's internal layout.
- E2 widens the closed E1 subset (with E1c's casts and `-> never`) to user structs, user enums with payloads, `match`, the built-in `Option<T>` and `Result<T, E>`, `?`, `??` on `Option`, and a short list of methods on them.
- The subset stays closed. Anything outside it rejects the whole package with E1's unsupported diagnostic, before checking.
- The core library moves to `Result` for its system-call errors (see "The core library").
- E2 adds no `write` parameters. No E2 construct needs one: values are copied, fields are assigned on `var` locals, and a function that changes a struct returns the new value. `write` parameters arrive with E3's collections, where copying is no longer cheap.

## The E2 subset

Everything in E1's subset stays, with the same rules. The additions follow.

**Declarations.**

- `struct Name { field: Type [= default], ... }` with no generic parameters. Fields are separated by commas or newlines. A field type is a supported type other than `()`. Rust rejects `()` fields with its own error, and E2 matches it.
- `enum Name { Case, Case(Type, ...), ... }`. Payload parts are supported types, including `()`.
- Declarations may come in any order and in any file. Rust's two-phase registration applies (see "Checker order").
- Still out: `type` aliases, `const`, `global`, generic structs, and refinements anywhere.

**Types.** In every type position:

- `int`, `long`, `bool` and `()` as in E1, and `never` as a result type as in E1c;
- a declared struct or enum name;
- `Option<T>` and `Result<T, E>`, with `T` and `E` any supported type, nested to any depth (`Option<Result<int, Failure>>`).

Every other type name stays unsupported (E1's table less `Option` and `Result`), and so does any other type with arguments, any array form and any range. A value type over 4096 bytes is unsupported (see "Layout").

**Expressions** (added to E1's table):

| Form | Notes |
| --- | --- |
| `S { f: e, g }` | struct literal; `g` alone is field shorthand (the parser turns it into the name `g`) |
| `e.f` | field read on any struct value |
| `Shape.Circle(e, ...)`, `Shape.Empty` | qualified constructors; `Shape.Empty` parses as a field on a type name and the checker resolves it |
| `Circle(e)`, `Empty` | unqualified constructors, resolved as Rust resolves them |
| `some(e)`, `none`, `ok(e)`, `err(e)` | built-in constructors, with Rust's inference from the expected type |
| `match e { arms }` | as an expression and as a statement |
| `e?` | on `Option` and `Result` |
| `e ?? d` | on `Option` only; `d` may be a value or a `never` expression (`return`, `break`, `continue`) |
| `e.is_some()`, `e.is_none()` | on `Option` |
| `e.is_ok()`, `e.is_err()`, `e.ok()` | on `Result` |
| `e.unwrap()` | on both; kinds 14 and 15 |
| `n.to_long()` | on `int`; the same value as `(long)n` |
| `==`, `!=` | on any two values of the same type other than `()` (see "Equality") |
| `print(e)` | on every supported type except `()` and `never`, as Rust allows |

Still out: `?.` (optional calls), every other method call, indexing, function values, collection and string literals, `take`, `fit`, `discard`.

**Statements.**

- Assignment `=` to a struct-typed or enum-typed `var` local, and to a field path of a `var` local (`p.x = 1`, `o.inner.value = 9`).
- E1's compound forms (`+= -= *= /= %=`) on an integer field path of a `var` local, failing at the operator as for locals.
- A `let` without an initialiser (a synthesised `default` call) stays unsupported.

**Patterns.** Exactly what the parser produces (ast.rs `Pattern`, parser.rs about lines 2028 to 2096):

- `_`, the wildcard;
- an integer literal, negative or not, for an `int` or `long` scrutinee;
- `true` and `false`, for a `bool` scrutinee;
- a case, `Circle(r, _)` or `Shape.Circle(r, _)`, for an enum, `Option` or `Result` scrutinee (`some(x)`, `none`, `ok(v)`, `err(e)`, also qualified as `Option.some`). Each payload position is a binding name or `_`.

There are no nested patterns, no literals inside a payload and no guards. The parser rejects them, so they are syntax errors in both compilers. A binding is an immutable copy scoped to its arm and shadows outer names. The scrutinee is evaluated once. Arms are separated by commas or newlines. An arm body is an expression or a block.

**Entry and tests.**

- `main` stays `fn main()` returning `()`. `main` returning `Result` stays unsupported (it needs Rust's error-printing entry path), and so do tests that end in a `Result`.
- `expect a == b` on aggregates is supported (see "Printing").

## What stays unsupported, and where it goes

| Construct | Goes to |
| --- | --- |
| arrays, lists, `Ascii`, `Text`, `Bytes`, builders, string and byte literals in user code | E3 |
| `const`, `global`, the core state block's retirement | E3 |
| `write` and `grow` parameters, overlap checks | E3 |
| `?.`, other methods, `discard`, `for` over collections | E3 |
| `type` aliases, refinements, `fit`, `wrap`, `clamp` | E4 |
| maps, sets, pools, queues, rings, grids, ids | E4 |
| `main` or a test returning `Result`, `Env`, `Fs`, `Out` | the task that brings capabilities |
| `recursive` functions, function values, generics | later E-tasks |

The unsupported diagnostic keeps E1's form. The construct table gains entries for what E2 newly splits: `optional calls`, `method calls` (any method outside the list above), `type aliases`, `struct literals without an initialiser` for a `let` with no value, `generic structs`, and `value types larger than 4096 bytes`. Each entry is one fixed string in one table, and a test reports each.

## Layout

The self-hosted compiler has its own layout. It must give Rust's observable behaviour and nothing more. Rust's sizes (emit.rs `type_size`: a 4-byte tag plus the largest payload, rounded to 4) are not a contract.

**The rule.** Each value type gets a size and an alignment, computed once after registration into a layout table indexed by type id:

- `bool` is 1 byte, `int` 4, `long` 8, `()` 0, each aligned to its size (`()` to 1).
- A struct lays out its fields in declaration order, each at the next offset aligned to the field's alignment. Its alignment is the largest field alignment, and its size is rounded up to it.
- An enum, `Option` or `Result` has an `i32` tag at offset 0. The tag is the case index in declaration order: `some` 0 and `none` 1, `ok` 0 and `err` 1, as typed.rs `cases()` orders them. Each case lays out its payload parts like a struct's fields, starting at offset 4 (aligned up). Cases overlap. The size is the largest case's end, rounded to the alignment, which is at least 4.
- The table stores, for every field and every payload part, its byte offset. Every access in the generated code is "slot plus constant offset" through `getelementptr i8`. There are no LLVM struct types.

**Where values live.**

- Scalars stay SSA values, as in E1.
- An aggregate local, binding, temporary or parameter copy is an `alloca [size x i8], align A` in the function's entry block, from the locals-per-function table. These are native-stack slots, not data-stack regions, so DESIGN's offset rule for data-stack references is untouched.
- A read parameter of aggregate type is passed as a `ptr` to a caller-owned slot that nothing writes during the call. The callee only reads it.
- An aggregate result goes into a hidden destination `ptr`, the first argument after `%nl.ctx` and `%nl.top`. The caller always passes a fresh temporary slot and copies it into the target after the call. So `s = f(s)` never writes into a slot the callee is still reading.
- A copy is a sequence of loads and stores of the scalar leaves of the active layout. For an enum that is the tag, then the active case's parts, chosen by a switch. No `llvm.memcpy` is emitted. Bytes that the value doesn't define are never read: unused payload bytes and padding are never copied, compared or printed. That matches DESIGN's "the language never reads memory it hasn't written".
- Core-library functions follow the same rules. The memory-function closure uses no aggregates, and a test checks that.

**No data-stack regions in E2.** DESIGN places fixed-size values over 4 KB in data-stack regions. E2 instead makes any value type over 4096 bytes unsupported, so E2 allocates no regions and does not bring in the core library's stack growth (`mremap`, the guard-page move, `NLC_STACK_VERIFY`), which stays in E3 with the first region user. The check runs in the eligibility pass, from declarations alone:

- It sizes every struct and enum declaration, and every `Option` or `Result` written in a type position, by resolving type names against the package's declarations and the scalars.
- A name that doesn't resolve, or a cycle, contributes nothing. Those become Rust's checker errors later (unknown type, infinite size).
- The first declaration or type node whose size exceeds 4096 bytes is unsupported, anchored at its start, in E1's first-node order.

The threshold is the same one Rust uses to decide what is "large" (emit.rs `is_large_type`, `type_size > 4096`): Rust passes those values by address and puts them in data-stack regions. Rust still builds them, though. A package that Rust builds with a value over 4096 bytes is therefore `unsupported` in E2, and a directed fixture pins it.

**The entry reservation** stays E1's rule over the self-hosted compiler's own data-stack bound, which is still zero regions plus the helper margin. Rust's bound for an aggregate package may differ, because Rust's stack contracts count its own aggregate temporaries. The reservation isn't observable under the harness's fixed environment, so it isn't compared for aggregate packages. The E1 scalar comparison test stays, and the report lists both values for the directed aggregate fixtures.

## Behaviour

**Printing.** Exactly Rust's bytes (emit.rs `emit_print_value` and `emit_print_value_storage`). `print` writes the value, then `\n`:

- a struct: `Name { f: v, g: w }`, fields in declaration order, `", "` between them, one space inside each brace;
- an enum case without a payload: its case name alone, never qualified (`Empty`);
- a case with a payload: `Name(p1, p2)`, so `Rect(2, 3)` and `Wrap(())`;
- `some(5)`, `none`, `ok(7)`, `err(Empty)`, `ok(())`;
- nesting composes: `some(ok(5))`, `ok(Core { size: 3, child: Child { value: 9 } })`;
- `()` inside a value prints `()`; scalars print as in E1.

Rust composes these from small hooks: `nl_print_int_raw`, `nl_print_long_raw`, `nl_print_bool_raw` (no newline), `nl_print_text` (a NUL-terminated constant) and `nl_print_newline`. The self-hosted compiler calls the same hooks. The core library adds them to its hook table with the C signatures, so the third leg still links the same program IR against the C runtime.

**Expectation failures on aggregates.** A top-level `==` or `!=` between aggregates keeps both operands, as Rust's `TExpectKind::Compare` does. On failure, Rust calls `nl_expect_fail_header(file, line, col, source)`, then `nl_expect_fail_left()`, prints the left value, `nl_print_newline()`, then `nl_expect_fail_right()`, the right value and a newline (emit.rs about line 16295; nl_runtime.c 1420 to 1439). The output is:

```
  main.nl:29:5: expect Shape.Rect(2, 3) == Shape.Rect(2, 4)
    left:  Rect(2, 3)
    right: Rect(2, 4)
```

The header and labels flush the buffered output and write directly. The values go through the buffer. The core library adds the three hooks with exactly that flush behaviour, and a fixture with output before and after the failure pins the order.

**Equality.**

- `==` and `!=` need two operands of the same type, and that type is not `()` or `never`. Otherwise it's Rust's error (`mixed_types_error`, or `equality requires values other than ()`).
- Equality is structural: structs field by field in declaration order; sum types equal when the tags are equal and the active case's parts are equal, part by part. Padding and inactive payload bytes are never read.
- Both operands are evaluated once, left then right.
- Comparison short-circuits on the first difference. That is not observable, because evaluation finished before the comparison.
- Ordering (`<` and the rest) on aggregates is Rust's error, `ordered comparisons require int or long values`.

**Struct literals.**

- The given fields are evaluated in source order, then the omitted defaults in declaration order, each once. An overridden default is never evaluated.
- Defaults are checked at each use, in the literal's own scope, as Rust does (checker.rs about lines 10789 and 8404). So a default may name a local that is visible where the literal is written. That looks like a Rust gap. E2 matches it, and the report lists it for a later language decision.
- The errors are Rust's, in Rust's order: unknown struct, not a struct, unknown field (with did-you-mean), duplicate field, then missing required field anchored at the whole literal.

**`match`.**

- The scrutinee is evaluated once, into a slot if it's an aggregate.
- Cases dispatch with a `switch` on the tag. Integer and bool patterns dispatch with a `switch` on the value, or a compare chain, in arm order.
- Bindings are copies of the payload parts. Arms of type `never` don't join, and the join's phi uses only real predecessors.
- A match whose scrutinee value isn't any case (impossible in a well-formed program) goes to `unreachable`, as Rust's print switch does.

**`?` and `??`.**

- `e?` on `Option` gives the payload on `some`. On `none` it returns `none` of the enclosing function's result type. On `Result` it gives the payload on `ok`, and on `err` it returns `err` with the same error value (copied into the result destination). The rules and messages are Rust's (checker.rs 11000 to 11058): `Option` needs an `Option` result and `Result` needs a `Result` result with exactly the same error type. `?` in a test is an error.
- `e ?? d` evaluates `d` only on `none`. A `never` fallback leaves through the innermost loop for `break` and `continue`, or the function for `return`. `??` on a `Result` is Rust's crossed diagnostic, and outside a loop `?? break` is Rust's error.
- With no data-stack regions there is no cleanup on these exits, but the generator keeps E1's terminator tracking. Nothing is emitted after a `ret` or `br`.

**`unwrap`.** It fails through `nl_fail` with kind 14 (`unwrap called on none`) or 15 (`unwrap called on err`), at the position Rust reports. A directed fixture pins both messages, the line and column, and output printed before the failure.

**Unused `Result`.** An expression statement, a unit block tail, a loop body tail, a bare block or an `if` used as a statement whose value is a `Result` is Rust's `require_handled_result` error (checker.rs 3672 to 3724), with Rust's exact text at the time. The PLAN small fix that drops `'??'` from that message may land in Rust first, and the self-hosted text follows it in the same commit.

## Checker order

The first error must equal Rust's, as in E1. Rust's `run` (checker.rs 460 to 666) adds these phases before E1's:

1. **Type names**, for every file: enums, then structs (checker.rs 700 to 746). Errors: a duplicate type, or one that shadows a built-in.
2. **Enum payloads** across all files, then **struct fields** across all files. Errors: duplicate cases and fields (with "first on line N"), unknown payload and field types, and `()` fields.
3. **Infinite size** (3548 to 3609), anchored at the declaration.
4. Then E1's order: function signatures and tests file by file, the entry, function bodies, test bodies and the whole-program phase.

Rust's `check_all_type_sizes` runs between 3 and 4. It reports nothing reachable in the E2 subset (its errors involve collections, pools and capabilities). The implementer confirms that and pins it with a comment, not a test.

Inside bodies, the new order rules come from Rust's traversal:

- **Constructors:** expected-type resolution first, then the single matching enum, then the ambiguity error (`case 'X' belongs to more than one enum; qualify it with the enum name`), then the unknown-case or unknown-name error. Arity errors come after resolution.
- **`match`:** arms in source order. For each arm: its pattern errors (type of pattern against scrutinee, qualifier, arity, unreachable or duplicate), then its body, then the arm-type check against earlier reachable arms. Exhaustiveness comes last, anchored at the `match` keyword:
  - sum types: `non-exhaustive match; missing Color.Blue`, missing cases as `Type.case` in declaration order joined by `", "`;
  - bool: `non-exhaustive bool match; missing ...`, true then false, joined by `" and "`;
  - integers: `integer matches need a '_' catch-all arm`.

  So an unreachable arm beats a missing case.
- **Struct literals:** fields in written order, each checked as it is met, then the missing-field check over declaration order.
- **`?` and `??`:** the operand first, then the operator's own rule.

The implementer extends E1's documented order in the checker's source and pins each non-obvious step with a fixture. Where this file and checker.rs disagree, checker.rs wins and the report says so.

**Structure.** The type table gets struct, enum, `Option` and `Result` entries. `Option<T>` and `Result<T, E>` are interned by their arguments, so each instance has one id. Fields and cases live in their own ordered tables keyed by type id, with name ids. The layout table is built once, after phase 3. The checker stays a flat, frame-driven walk with no `recursive` functions, as in E1.

## The core library

The design note's retirement table gives E2 two rows. E2 does one and moves the other:

- **Raw results become `Result`.** Each system call the core library uses gets one wrapper in core/linux or the file that uses it: `fn write(fd: int, data: sys.Addr, count: long) -> Result<long, Errno>`, and the same for `map`, `protect`, `ioctl`, `statx`, `sigaction`, `openat` and `close`. `Errno` is `struct Errno { number: int }`. Only the wrappers use `sys.is_error`. The seven call sites today (context.nl 2, environment.nl 1, format.nl 1, output.nl 1, start.nl 1, plus any added) use `match` or `?`. A test greps the core sources so `sys.is_error` appears only inside wrappers.
- **The state-block layout struct moves to E3.** The block's layout is mostly byte areas: two 64 KiB buffers, the file table and scratch. E2 can't describe those without arrays. E3 replaces the block with an ordinary `global` struct anyway (the table's proposed E3 row). A layout struct in E2 would be rewritten one task later. E2 updates the table in docs/design/core-library.md to say so.
- **New hooks:** the raw print hooks, `nl_print_text`, `nl_print_newline` and the three expectation hooks, with the C runtime's signatures and behaviour. The hook table's check (each hook exists with its signature) covers them.
- The core library is still compiled with the privileged flag, after the user package, and a core diagnostic is still an internal error.

## Eligibility

E1's pass is unchanged in form: one deterministic pass over every node of every file, the first unsupported node by file, then offset, then outermost. It changes as follows:

- `Enum`, `Struct` (without generics), `StructField`, `EnumCase`, `FieldType`, `PayloadType`, `StructInit`, `InitializerField`, `Field`, `QualifiedCase`, `Match`, `MatchArm`, the pattern nodes, `Try` and `ToLong` become supported.
- `MethodCall` is supported only for the six method names above. Whether the receiver type fits is the checker's job, with Rust's `no method` error.
- `Binary coalesce` (`??`) is supported.
- `TypeArgument` is supported only under `Option` (one argument) and `Result` (two).
- `Name` and `Call` of `some`, `none`, `ok` and `err` are supported. Built-in cases of the still-unsupported enums (`FileKind`, `IoError`, `Full`) stay unsupported, by name.
- `Assign` with a `Field` target is supported for `=` and E1's compound forms.
- The 4096-byte size check (see "Layout") runs in the same pass.

## Runtime checklist additions

Each item has a directed fixture comparing exact stdout, stderr and status, at both optimisation levels:

- **Copies are independent:** change a `var` copy's field, then print both values.
- **Evaluation order:** struct-literal fields in source order, then defaults in declaration order; an overridden default with a print is not run; constructor arguments left to right; the `match` scrutinee once; both `==` operands once.
- **Payload placement:** cases of different sizes and alignments (`bool`, `int`, `long`, `()`, nested structs) written, copied, matched and printed after the value has held another case. Stale bytes must never show.
- **Equality:** equal and unequal on every case pair of an enum, nested `Option<Result<...>>`, and a struct whose padding differs.
- **`?`:** `Option` and `Result`, with different success types and one error type, from inside nested loops, and the `none` and `err` paths returning the right value.
- **`??`:** a value fallback that prints (run only on `none`), `?? return`, `?? break` and `?? continue` in nested loops.
- **`unwrap`:** both failures, after earlier output, in a program and in a test child (status 1 and 70).
- **Printing:** every form in "Printing", including deep nesting and aggregate expectation failures with output before and after. Include a `()` payload printed directly (`Wrap(())`) and one reached through stored values (a field of a struct, a payload inside `some(...)`). Rust's storage printing path (emit.rs about line 16798) treats a unit payload differently from its by-value path. Whatever Rust prints there is the reference, and the report notes it if it looks wrong.
- **Calls:** aggregates as parameters and results, `s = f(s)`, a result passed straight into another call, and an aggregate parameter used after the callee builds its result.

## Directed fixtures (tests/e2/)

Grouped like tests/e1, each classified by hand:

- **Structs:** defaults and overrides, shorthand, nested literals, field read and write paths, compound assignment on fields with overflow at the operator, copies, equality and printing.
- **Enums:** payload and payload-free cases, qualified and unqualified constructors, cases of the same name in two enums (ambiguity), resolution from expected type, `Option` and `Result` nesting.
- **Match:** every pattern form; shadowing; block arms; `never` arms; match as statement and expression; integer matches on both widths with negative literals; bool matches.
- **Diagnostics, in Rust's order:** each checker message named in this file, at least once; competing errors across the new registration phases and files (a duplicate case in `b.nl` against a bad parameter type in `a.nl`); an unreachable arm against a missing case; struct-literal errors in competition; `?` errors; `??` on a `Result`; unused `Result`; infinite size directly and through `Option`.
- **Runtime:** the checklist above.
- **Core library:** a fixture per new hook, and the wrapper test.
- **Unsupported:** each new construct-table entry, in an unused function, an unreachable statement and a test; a value just over 4096 bytes (unsupported) and one at exactly 4096 (`build`); a package with an E2 checker error and an unsupported construct (unsupported wins); a syntax error with an unsupported construct (`diagnose`).

**Generated cases.** The E1 generator gains structs, enums, matches, `?` and `??` in valid packages, and seeded errors from the new phases in invalid ones. `cargo test` runs a fixed seed set, and the report covers a larger run.

## Classification update

- Re-classify every package under tests/run, tests/test, tests/e1 and tests/e2 by hand from this file, never by running the self-hosted compiler.
- E1 packages keep their classes, except E1's unsupported fixtures for `Option`, `Result`, `match` and `??`, which move to `build` or `diagnose` where they now fit, or stay unsupported for another construct, with a note.
- The report gives the counts before and after per class, and lists every package that moved.

## Harness

E1's protocol is unchanged: the reference first, checked against its class and the `expected.*` files, then the self-hosted compiler, with the same comparisons, fixed environment, timeouts and the no-IR-after-rejection check. After S2:

- the default run (`cargo test`) uses -O1 and the core leg;
- `NLC_LONG_TESTS=1` runs both -O1 and `NLC_OPT_LEVEL=3`, and the C-runtime third leg.

E2's acceptance needs both modes passing with zero mismatches. The report gives the counts from the long mode.

## The compiler's own budget

- New tables (types, fields, cases, layouts, interned `Option`/`Result` instances, per-function aggregate slots) take their capacities from the input policy's limits, as in E1. Each is listed in limits.nl with its derivation.
- Exhaustion is a named limit diagnostic, with tests at N and N+1 for every limit the input policy can reach.
- The IR bound's per-node constant is restated. Aggregate copies, equality and printing emit code proportional to the type's leaf count, so the derivation must cover that. One option: bound it by the 4096-byte cap times the node count, since each leaf is at least one byte except `()`.

## Measurements

Release builds, best of 5, under `ulimit -v 8000000` and the WSL bench lock:

- The E1 benchmark, both compilers, to show E2 cost nothing on scalar code.
- A new generated aggregate benchmark (structs, enums, matches, `?`), valid and uniquely named, within the input policy: wall time and peak RSS for the whole build, the self-hosted compile alone, `link-ir`, and Rust's build.
- The bootstrap time, and `nlc inspect stacks selfhost` (E1 reported 3.48 GB; say how much E2's tables add).
- IR bytes per source byte for both benchmarks.
- The run time of one aggregate-heavy program built by each compiler, to show the offset-and-slot layout is not slower than Rust's LLVM aggregates. Report it; don't gate on it.

## Not part of E2

- `write` parameters, collections, strings, `const`, globals, refinements, aliases, user generics, `?.`, other methods, `discard`, function values, `recursive`.
- Data-stack regions and the core library's stack growth (E3).
- The hook ABI change to context passing (E3, before the first region-using core function).
- Per-file IR modules, parallel clang, or any build-speed work (PLAN small fixes).
- A typed dump format, self-compilation, the stage 2 and stage 3 check.
- Language changes. If Rust's behaviour looks wrong (the struct-default scope above, say), match it and list it in the report.

## Report

docs/tasks/E2-report.md. It covers:

- the counts per class, before and after, and the packages that moved;
- the extended checker order and any place it differs from this file;
- the construct table as it now stands;
- the layout rule as built, with one worked enum;
- the core library changes, including the hooks added;
- the measurements;
- what was awkward to write in next-lang;
- the plan for E3.

## Reference fixes before comparing (Claude, 2026-10-26)

Under the split-compiler rule (PLAN.md Order of work item 3) the reference is fixed rather than copied when it is wrong. Two places in Rust nlc look wrong; E2 fixes them in Rust first, with fixtures, then compares:

1. **Struct field defaults are checked in the struct declaration's scope**, where only constants, literals and other declarations are visible, not in the scope of each struct literal (today a default can name a local that happens to be visible where the literal is written). Both compilers implement the declaration-scope rule; a default that names a local is a build error naming the field.
2. **One printing format for `()` payloads:** if Rust's by-value and storage printing paths print a `()` payload differently, make them print the same way (the by-value form), and pin it with a fixture.

Record both in the report.
