# E2: the self-hosted compiler gains structs, enums, `match`, `Option`, `Result` and `?`

This spec incorporates the peer review docs/reviews/sol-E2-r1.md.

Depends on E1 and E1c, and on the small-fixes task S2 (docs/tasks/S2-small-fixes-build-and-suite.md), which changes the harness's default and long modes. Read docs/PLAN.md items 3 and 5, DESIGN.md "The theory being tested", "The job's data stack", "The standard library needs no C library" and "Types, and refinement types", docs/design/core-library.md, and E1's spec, report and review first. E1's spec holds for everything this file does not change.

Rust code is cited by function name. Line numbers drift while compiler/ is being edited.

## Scope

- Rust nlc stays stage 0 and the reference. The two compilers are compared by behaviour: stdout, stderr and exit status. IR equality is not required, and neither is Rust's internal layout.
- E2 widens the closed E1 subset (with E1c's casts and `-> never`) to user structs, user enums with payloads, `match`, the built-in `Option<T>` and `Result<T, E>`, `?`, `??` on `Option`, and a short list of methods on them.
- The subset stays closed. The stages in "Eligibility and precedence" decide when an unsupported construct is reported.
- The core library moves to `Result` for its system-call errors (see "The core library").
- E2 adds no `write` parameters. No E2 construct needs one: values are copied, fields are assigned on `var` locals, and a function that changes a struct returns the new value. `write` parameters arrive with E3's collections, where copying is no longer cheap.

## Reference fixes in Rust nlc

Under the split-compiler rule (PLAN.md Order of work item 3) the reference is fixed, not copied, where it is wrong. E2 makes two fixes in Rust nlc first, each with fixtures and updated `expected.*` files. The self-hosted compiler then implements the fixed behaviour, and the comparison runs against the fixed Rust. Both fixes are part of the language rules below, not exceptions to them.

1. **Struct field defaults are checked once, in the declaration's scope** (see "Struct field defaults"). Today `check_struct_init` and `default_typed_value` check each default with `check_store` in the environment of every literal that omits it. So a default can name a local that happens to be visible where the literal is written.
2. **Unit values are erased everywhere** (see "Unit values"). Today stored unit printing reaches `emit_print_value_storage`'s generic load, and `llvm_type(Unit)` is `void`, so Rust emits an invalid `load void`. Named unit payload bindings are recorded as slots: `record_slot` and the function prologue don't erase unit storage. Unit parameters lower to `void` parameters.

The report records both fixes, with the fixtures that pin them.

## The E2 subset

Everything in E1's subset stays, with the same rules. The additions follow.

**Declarations.**

- `struct Name { field: Type [= default], ... }` with no generic parameters. Fields are separated by commas or newlines. A field type is a supported type other than `()`. Rust rejects `()` fields with its own error, and E2 matches it. An empty struct, `struct Name {}`, is allowed.
- `enum Name { Case, Case(Type, ...), ... }`. Payload parts are supported types, including `()`.
- Declarations may come in any order and in any file. Rust's two-phase registration applies (see "Checker order").
- Still out: `type` aliases, `const`, `global`, generic structs, and refinements anywhere.

**Types.** In every type position:

- `int`, `long`, `bool` and `()` as in E1, and `never` as a result type as in E1c;
- a declared struct or enum name;
- `Option<T>` and `Result<T, E>`, with `T` and `E` any supported type, nested to any depth (`Option<Result<int, Failure>>`).

Every other type name stays unsupported (E1's table less `Option` and `Result`), and so does any other type with arguments, any array form and any range. A value type over 4096 bytes is unsupported, written or inferred (see "Size eligibility").

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

**Patterns.** Exactly what the parser produces (ast.rs `Pattern`, and the parser's pattern function):

- `_`, the wildcard;
- an integer literal, negative or not, for an `int` or `long` scrutinee;
- `true` and `false`, for a `bool` scrutinee;
- a case, `Circle(r, _)` or `Shape.Circle(r, _)`, for an enum, `Option` or `Result` scrutinee (`some(x)`, `none`, `ok(v)`, `err(e)`, also qualified as `Option.some`). Each payload position is a binding name or `_`.

There are no nested patterns, no literals inside a payload and no guards. The parser rejects them, so they are syntax errors in both compilers. A binding is an immutable copy scoped to its arm and shadows outer names. The scrutinee is evaluated once. Arms are separated by commas or newlines. An arm body is an expression or a block.

**Entry and tests.**

- `main` stays `fn main()` returning `()`. `main` returning `Result` stays unsupported (it needs Rust's error-printing entry path).
- A test whose body ends in a `Result` stays unsupported. With `Result` values in the subset this is found by the checker (see "Eligibility and precedence").
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
| the built-in enum `Full` and its case | E3, with list pushes |
| the built-in enums `FileKind` and `IoError`, and their cases | the task that brings capabilities |
| `main` or a test returning `Result`, `Env`, `Fs`, `Out` | the task that brings capabilities |
| aggregate locals over the native-path budget | the native-stack task (see "Native frames") |
| `recursive` functions, function values, generics | later E-tasks |

The unsupported diagnostic keeps E1's form. The construct table gains entries for what E2 newly splits: `optional calls`, `method calls` (any method outside the list above), `type aliases`, `struct literals without an initialiser` for a `let` with no value, `generic structs`, `value types larger than 4096 bytes`, `cases of FileKind, IoError or Full`, and `aggregate locals over 1 MiB on one call path`. Each entry is one fixed string in one table, and a test reports each.

## Eligibility and precedence

E2 keeps E1's rule that an unsupported construct beats a checker error, with two stated exceptions: facts that only typing can reveal, and the native-path budget. The pipeline runs these stages in order, and the first stage that rejects decides the result:

1. **Front end:** input policy, lexing and parsing of every file (status 2).
2. **Manifest** (status 3).
3. **Syntactic eligibility:** one deterministic pass over every node of every file, as in E1. It covers node kinds, operators, written type names and the size of every declared and written type. A package rejected here is unsupported, whatever checker errors it also has.
4. **Checker,** in Rust's order (see "Checker order"), with **typed unsupported events** at fixed points:
   - the checker interns an `Option` or `Result` instance whose size exceeds 4096 bytes (see "Size eligibility");
   - the checker resolves a name or constructor to a case of `FileKind`, `IoError` or `Full`;
   - the checker finishes a test body whose tail has a `Result` type.

   Each event stops the checker with the unsupported diagnostic, anchored at the node that caused it. The event and Rust's checker errors are ordered by Rust's traversal. A checker error that Rust's order reaches first wins over a later event, and an event reached first wins over every later checker error.
5. **Native-path check,** after a successful check and before emission (see "Native frames").
6. **Emission** and the single write.

Hand classification follows these stages. Fixtures pin both orders for each typed event: an event before a checker error (`unsupported`) and one after it (`diagnose`).

**The syntactic pass** is E1's pass, unchanged in form, with these changes:

- `Enum`, `Struct` (without generics), `StructField`, `EnumCase`, `FieldType`, `PayloadType`, `StructInit`, `InitializerField`, `Field`, `QualifiedCase`, `Match`, `MatchArm`, the pattern nodes, `Try` and `ToLong` become supported.
- `MethodCall` is supported only for the method names in the expression table. Whether the receiver type fits is the checker's job, with Rust's `no method` error.
- `Binary coalesce` (`??`) is supported.
- `TypeArgument` is supported only under `Option` (one argument) and `Result` (two).
- `Name` and `Call` of `some`, `none`, `ok` and `err` are supported.
- Other names and calls are no longer judged by spelling. A name that Rust resolves to a local or a user enum case, and a call that it resolves to a package function or a user case, are supported, even when spelled like a built-in case. A bare name that resolves to a package function is a function value and stays unsupported, as in E1. Rust's unqualified-constructor candidates (`check_unqualified_constructor`, and the bare-name path in `check_expr`) include the built-in enums `FileKind`, `IoError` and `Full`. So a user case spelled like one of their cases is Rust's ambiguity error, not unsupported. Only resolution to a built-in case is unsupported, and that is a typed event.
- `Assign` with a `Field` target is supported for `=` and E1's compound forms.
- The size check over declared and written types runs in the same pass.
- **Order fix.** The first unsupported node is chosen by file, then start offset, then outermost, as E1's spec says. Today `check_package_eligibility` in selfhost/compiler.nl compares start offsets without comparing file ids first. E2 compares `file` before `offset`. A two-file fixture puts the later file's unsupported node at a smaller offset than the earlier file's, and the earlier file's node must win.

## Layout

The self-hosted compiler has its own layout. It must give Rust's observable behaviour and nothing more. Rust's sizes (emit.rs `type_size`: a 4-byte tag plus the largest payload, rounded to 4) are not a contract, and neither is Rust's packing.

**The rule.** Each value type has a size and an alignment, stored in a layout table indexed by type id:

- `bool` is 1 byte, `int` 4, `long` 8, `()` 0. Each is aligned to its size, and `()` to 1.
- A struct lays out its fields in declaration order, each at the next offset aligned to the field's alignment. Its alignment is the largest field alignment, and its size is rounded up to it. An empty struct has size 0 and alignment 1.
- An enum, `Option` or `Result` has an `i32` tag at offset 0. The tag is the case index in declaration order: `some` 0 and `none` 1, `ok` 0 and `err` 1, as typed.rs `cases()` orders them. Each case lays out its payload parts like a struct's fields, starting at offset 4 (aligned up). Cases overlap. The size is the largest case's end, rounded to the alignment, which is at least 4.
- The table stores, for every field and every payload part, its byte offset.
- A `bool` in storage is one byte holding 0 or 1. A store writes `zext i1 to i8`, and a load reads `trunc i8 to i1`. Scalars in SSA form stay `i1`.

**When layouts are made.** Declared structs and enums, and every `Option` or `Result` instance interned during registration and signatures, get layouts once, after the infinite-size phase. Every instance interned later (by inference in a body or a default) gets its layout at the moment it is interned. Its arguments are interned first, so their layouts already exist. At most one new instance is interned per expression node, so the instance table's capacity is the node limit, and the input policy can't exhaust it on a package Rust builds.

**Addressing.** All aggregate access in the self-hosted emitter goes through one addressing function: a slot (base) plus a constant byte offset from the layout table, through `getelementptr i8`. There are no LLVM struct types. No other emitter code computes an aggregate address. E3 then changes this one function: a data-stack value is held as an offset, the base is reloaded after any possible growth, and an address is derived only for each access. DESIGN "The job's data stack" puts read references and hidden destinations under that offset rule, so E3 must not keep E2's native-stack pointers across growth. The constant field offsets carry over unchanged.

**Where values live.**

- Scalars stay SSA values, as in E1.
- An aggregate local, binding, temporary or snapshot is an `alloca [size x i8], align A` in the function's entry block, from the locals-per-function table. These are native-stack slots, not data-stack regions, so DESIGN's offset rule for data-stack references is untouched in E2.
- A read parameter of aggregate type is passed as a `ptr` to a caller-owned snapshot slot (see "Evaluation points"). The callee only reads it.
- An aggregate result goes into a hidden destination `ptr`, the first argument after `%nl.ctx` and `%nl.top`. The caller always passes a fresh temporary slot and copies it into the target after the call. So `s = f(s)` never writes into a slot the callee is still reading.
- A copy moves the scalar leaves of the active layout with loads and stores. For an enum that is the tag, then the active case's parts, chosen by a switch. Bytes that the value doesn't define are never read: unused payload bytes and padding are never copied, compared or printed. That matches DESIGN's "the language never reads memory it hasn't written".
- The self-hosted compiler emits no `llvm.memcpy`. That rule constrains the emitted IR only. LLVM may still turn load and store sequences into library calls, which the core library's memory functions serve, except inside the protected memory-function closure, which keeps its existing guard.
- Core-library functions follow the same rules. The memory-function closure uses no aggregates, and a test checks that on the transitive calls after linking, not only in the source.

**No data-stack regions in E2.** DESIGN places fixed-size values over 4 KB in data-stack regions. E2 instead makes any value type over 4096 bytes unsupported. So E2 allocates no regions and does not bring in the core library's stack growth (`mremap`, the guard-page move, `NLC_STACK_VERIFY`), which stays in E3 with the first region user.

**The entry reservation** stays E1's rule over the self-hosted compiler's own data-stack bound, which is still zero regions plus the helper margin. Rust's bound for an aggregate package may differ, because Rust's stack contracts count its own aggregate temporaries. The reservation is not observable under the harness's documented fixed environment, and only there, so it isn't compared for aggregate packages. The E1 scalar comparison test stays, and the report lists both values for the directed aggregate fixtures.

## Size eligibility

One sizing function serves both stages that check size. It uses E2's layout above, never Rust's sizes. Its result is a size and alignment, or `unknown`.

- **Saturation.** Every addition and every alignment round-up saturates at 4,097. So a chain of structs that each hold two copies of the previous one stays finite and cheap to size.
- **Unknown.** A type is `unknown` if its walk meets a name that resolves to nothing, a name with more than one declaration (a duplicate type, a struct and an enum of one name, or a declaration that shadows a built-in), or a cycle. A type that contains an `unknown` part is `unknown` too. `unknown` is not zero. It is never oversized, so it never produces an unsupported result. Those packages reach the checker and get Rust's errors (unknown type, duplicate type, infinite size).
- **The walk** is iterative and memoised over the declarations: each type is unvisited, in progress or done. Meeting an in-progress type is a cycle. Each type is sized once, so the work is linear in fields, payload parts and type arguments.
- **Oversized** means a known size of 4,097 (more than 4096 bytes).

**The syntactic stage** sizes every struct and enum declaration and every type written in a type position, resolving names against the package's declarations and the scalars. The first declaration or type node that is oversized is unsupported, anchored at its start, in the pass's first-node order.

**The typed stage** sizes each `Option` or `Result` instance when the checker interns it. This covers types no declaration writes: `some(x)` with no expected type (`check_builtin_constructor`), `ok(x)` and `err(x)` inferred from their arguments, the `Option` that `.ok()` synthesises, and intermediates such as `some(some(s))`. An oversized instance is a typed unsupported event at the expression that interned it. Written types never reach this event, because the syntactic stage has sized them already (or found them `unknown`, which is a checker error first).

A test confirms that, for every directed fixture type, the syntactic stage's size equals the layout table's size.

The threshold is the one Rust uses to decide what is "large" (emit.rs `is_large_type`, `type_size > 4096`), applied to E2's layout. Rust passes those values by address and puts them in data-stack regions, but it still builds them. A package that Rust builds with a value over 4096 bytes is therefore `unsupported` in E2. Rust's sizes and E2's differ near the threshold, so classification uses E2's layout.

## Native frames

E1 relied on the kernel's main-thread stack (8 MiB `RLIMIT_STACK` by default) because it had no recursion and small frames (docs/design/core-library.md, "The native stack"). Aggregate slots weaken that assumption: many 4 KB locals along one acyclic call chain can exhaust the stack. E2 therefore adds a checked budget for aggregate slots.

- **Counted bytes.** For each function, the slot bytes are the sum of the sizes of its aggregate locals, bindings and aggregate-typed expression nodes. The emitter allocates at most one slot per aggregate-typed node, so this is an upper bound on its entry allocas, and it can be counted by hand from the source.
- **The graph** has a node for each package function, each default helper and each fill helper (see "Shared helpers"), each with its own slot bytes. A default helper's slot bytes come from its default expression; a fill helper has none. Edges run from a function to each function it calls, from a function whose literal omits a defaulted field to that struct's fill helper, from a fill helper to its default helpers, and from a default helper to the functions it calls and the fill helpers of the literals it contains.
- **Paths.** The graph is acyclic in E2 (a call cycle or a default cycle is a checker error). A memoised walk in reverse topological order gives, for each node, its slot bytes plus the largest total of any successor.
- **The budget** is 1 MiB of slot bytes on any path from an entry the command builds: `main` for `build`, and each test for `test`. An entry over budget is the unsupported construct `aggregate locals over 1 MiB on one call path`, anchored at its `fn` or `test` keyword. Entries are checked in Rust's check order, and the first one over budget is reported.
- **The rest is a recorded limitation.** Scalar frames, spills, LLVM inlining (which can copy a callee's slots into a caller more than once) and the core library's fixed frames are not counted. They share the remaining 7 MiB. The implementer confirms that the harness's fixed environment leaves `RLIMIT_STACK` at its default. The report records the limitation and proposes a PLAN follow-up item for the native-stack task: a computed native bound from `-fstack-size-section` frames, as docs/design/core-library.md sketches.

Fixtures: one entry at exactly 1 MiB (`build`) and one just over (`unsupported`), a many-live-values function, and a long call chain of aggregate-heavy functions. The measurements report computed slot bytes, the frames `-fstack-size-section` gives at -O1 and -O3, and observed peak RSS, as three separate figures.

## Evaluation points

An aggregate value is taken at the point where it is evaluated. Later code in the same expression must not change what an earlier operand passes on. Rust gets this by loading small aggregate operands as values before later operands are evaluated.

- **Snapshot sites:** call arguments, both operands of `==` and `!=` (including in `expect`), constructor payload arguments, struct-literal field values, and the right side of every aggregate assignment (`x = e`, `x.f = e`).
- **The rule.** A site whose operand is a fresh temporary (a call result, literal, constructor or match result) uses that temporary. A site whose operand is a place (a local, field path, binding or parameter) copies it into a fresh slot at the moment it is evaluated. The emitter may skip that copy only when no operand evaluated after it, up to the value's use, contains an assignment or compound assignment. Calls can't change a caller's locals in E2, so assignments are the only threat.
- **Literals and constructors** build into a fresh temporary, never straight into the assignment's target, then copy into the target. So `s = S { a: s.b, b: s.a }` reads the old `s` for both fields.
- **`match`** needs no snapshot of a place scrutinee: the tag is read and the bindings are copied at arm entry, before the arm body runs.
- The fresh hidden result destination stays (see "Where values live").

Fixtures: `f(s, { s.x = 9; 0 })` must pass the old `s`; `s == { s.x = 9; s }` must compare the old left operand; `s = S { a: s.b, b: s.a }`; a constructor whose later argument changes an earlier one's source; and an `expect` failure whose left value is changed by its right operand and must print as it was.

## Shared helpers

Copying, equality and printing are emitted as one internal helper per type and operation, only for types that need it: `copy`, `eq` (returns `i1`) and `print`. A helper handles its own fields, cases and parts. Each aggregate child calls the child type's helper, and each scalar leaf is inline. A use site emits one call.

Struct defaults follow the same rule. Each default is emitted once as a helper that writes its value into a destination. Each struct that has defaults gets one fill helper. It takes the destination and a pointer to a constant, sorted list of the field indices that the literal gave. It walks the fields in declaration order and calls the default helper of each field not on the list. A literal stores its given fields in source order, then makes one call to the fill helper. So a literal costs bytes in proportion to its own written fields, not to the struct's field count.

Helpers call only helpers of strictly smaller types, or default helpers along the acyclic default graph (see "Struct field defaults"). So the emitted call graph stays acyclic, the module's recursion header stays `none`, and `link-ir` still accepts it.

**The IR bound** (in limits.nl, with its derivation) becomes:

- a per-node constant times the node limit, since every node emits a constant number of bytes, including one helper call or one constant index per written field;
- plus a per-entry constant times the entries of the field, case, payload-part and type-instance tables, which covers every helper body, label and metadata line, since they are named by ids;
- plus the package's source bytes, which cover the printed names of types, fields and cases and the expectation sources;
- plus the fixed sections.

The tables are bounded by the node limit (each field, case and part is a node, and each instance comes from a node), so the bound is linear in the input. Raising the per-node constant alone would not be enough.

Adversarial fixtures:

- **A sum-type DAG:** `E0 { A(int), B(int) }`, then `En { A(En-1), B(En-1) }`. Storage grows linearly, but full expansion would grow exponentially. Copy, compare and print values of the deepest type. The depth is chosen so the reference still builds in the harness's timeout (Rust's printing and equality emitters expand the type recursively, `emit_print_value` and the equality emitter). The report notes Rust's expansion cost.
- **A struct DAG** of the same shape, and **a default DAG**, where each struct's defaults build two literals of the previous struct.
- **Zero-size leaves:** a struct with many empty-struct fields, and enums with many `()` payloads.
- **A bound test** that runs only the self-hosted compiler to IR, with no reference comparison, at a depth far beyond what full expansion allows (40 levels). It checks the IR stays under the derived bound and grows linearly with depth.

## Behaviour

**Printing.** Exactly the fixed Rust's bytes (emit.rs `emit_print_value` and `emit_print_value_storage`). `print` writes the value, then `\n`:

- a struct: `Name { f: v, g: w }`, fields in declaration order, `", "` between them, one space inside each brace. An empty struct prints `Name {  }`, the two spaces with nothing between;
- an enum case without a payload: its case name alone, never qualified (`Empty`);
- a case with a payload: `Name(p1, p2)`, so `Rect(2, 3)` and `Wrap(())`;
- `some(5)`, `none`, `ok(7)`, `err(Empty)`, `ok(())`;
- nesting composes: `some(ok(5))`, `ok(Core { size: 3, child: Child { value: 9 } })`;
- `()` inside a value prints `()`, whether the value is printed directly or reached through storage (a field, a payload inside `some(...)`); scalars print as in E1.

Rust composes these from small hooks: `nl_print_int_raw`, `nl_print_long_raw`, `nl_print_bool_raw` (no newline), `nl_print_text` (a NUL-terminated constant) and `nl_print_newline`. The self-hosted compiler calls the same hooks. The core library adds them to its hook table with the C signatures, so the third leg still links the same program IR against the C runtime.

**Expectation failures on aggregates.** A top-level `==` or `!=` between aggregates keeps both operands, as Rust's `TExpectKind::Compare` does. On failure, Rust calls `nl_expect_fail_header(file, line, col, source)`, then `nl_expect_fail_left()`, prints the left value, `nl_print_newline()`, then `nl_expect_fail_right()`, the right value and a newline (emit.rs, the expect-compare lowering; nl_runtime.c's expectation hooks). The output is:

```
  main.nl:29:5: expect Shape.Rect(2, 3) == Shape.Rect(2, 4)
    left:  Rect(2, 3)
    right: Rect(2, 4)
```

The header and labels flush the buffered output and write directly. The values go through the buffer. The core library adds the three hooks with exactly that flush behaviour.

**Unit values.** A unit value has no storage in either compiler. A unit expression is evaluated for its effects, and nothing is loaded or stored:

- a unit local, a unit payload binding (named or `_`) and a unit parameter get no slot and no LLVM parameter; a call with a unit argument evaluates the argument and passes nothing;
- a unit payload part takes no bytes in the layout;
- printing a unit, directly or from storage, writes `()`;
- equality of unit payload parts is true; copying them does nothing.

**Equality.**

- `==` and `!=` need two operands of the same type, and that type is not `()` or `never`. Otherwise it's Rust's error (`mixed_types_error`, or `equality requires values other than ()`).
- Equality is structural: structs field by field in declaration order; sum types equal when the tags are equal and the active case's parts are equal, part by part. Padding and inactive payload bytes are never read.
- Both operands are evaluated once, left then right, each snapshotted at its evaluation point.
- Comparison short-circuits on the first difference. That is not observable, because evaluation finished before the comparison.
- Ordering (`<` and the rest) on aggregates is Rust's error, `ordered comparisons require int or long values`.

**Struct literals.**

- The given fields are evaluated in source order, then the omitted defaults in declaration order, each once. An overridden default is never evaluated.
- The errors are Rust's, in Rust's order: unknown struct, not a struct, unknown field (with did-you-mean), duplicate field, then missing required field anchored at the whole literal.

**`match`.**

- The scrutinee is evaluated once. If it is an aggregate result it lives in a temporary; a place is read in place (see "Evaluation points").
- Cases dispatch with a `switch` on the tag. Integer and bool patterns dispatch with a `switch` on the value, or a compare chain, in arm order.
- Bindings are copies of the payload parts, made at arm entry.
- A scalar match result joins with a phi over real predecessors only. An aggregate match result has a destination slot: each arm that reaches the end copies its value into it, then branches to the join.
- Arms of type `never` don't join. If every arm is `never`, the match is `never`: there is no join block, no phi, and nothing is emitted after it.
- A match whose scrutinee value isn't any case (impossible in a well-formed program) goes to `unreachable`, as Rust's print switch does.

**`?` and `??`.**

- `e?` on `Option` gives the payload on `some`. On `none` it returns `none` of the enclosing function's result type. On `Result` it gives the payload on `ok`. On `err` it returns `err` of the enclosing result type, with the same error value.
- The return uses the enclosing result type's layout, which differs from the operand's when the success types differ. The emitter writes the enclosing type's tag into the hidden destination and, for `Result`, copies only the error payload into the enclosing layout's `err` part. Unit errors copy nothing.
- The rules and messages are Rust's (`check_expr`, `ExprKind::Try`): `Option` needs an `Option` result and `Result` needs a `Result` result with exactly the same error type. `?` in a test is an error.
- `e ?? d` evaluates `d` only on `none`. A `never` fallback leaves through the innermost loop for `break` and `continue`, or the function for `return`. `??` on a `Result` is Rust's crossed diagnostic, and outside a loop `?? break` is Rust's error.
- With no data-stack regions there is no cleanup on these exits, but the generator keeps E1's terminator tracking. Nothing is emitted after a `ret` or `br`.

**`unwrap`.** It fails through `nl_fail` with kind 14 (`unwrap called on none`) or 15 (`unwrap called on err`), at the position Rust reports.

**Unused `Result`.** An expression statement, a unit block tail, a loop body tail, a bare block or an `if` used as a statement whose value is a `Result` is Rust's `require_handled_result` error, with Rust's exact text at the time. A `let` binding of a `Result` is not an error. The PLAN small fix that drops `'??'` from that message may land in Rust first, and the self-hosted text follows it in the same commit.

## Struct field defaults

A default is part of its struct's declaration. Both compilers check it once, in the declaration's scope, and evaluate it at each literal that omits the field.

**The phase.** Defaults are checked after function signatures and tests are registered and after the entry check, before function bodies. Structs go in file order, then declaration order within a file, and fields in declaration order. So a default may call any package function, including one declared later or in another file. A fixture pins the phase: a bad default against a bad `main` signature (the entry error wins) and against a bad function body (the default error wins).

**Eager checking.** Every default is checked, whether any literal uses it, overrides it, or never names the struct. An invalid unused default is an error.

**The environment.** The default is checked with `check_store` against the field type, in an environment set up like `check_constant_expr`'s: no locals, loop depth 0, not a test, no enclosing function result. A block inside a default may declare its own locals. Every error found while checking a default names its field: it is the ordinary message followed by the fixed suffix ` (in the default for field 'S.x')`, anchored inside the default in the struct's file. In particular:

- a name that would only be visible at a literal (a local of the caller) is Rust's unknown-name error at the name, with the suffix: so a default that names a local is a build error naming the field;
- `break` and `continue` are Rust's outside-a-loop errors;
- `expect` is Rust's `'expect' is only valid inside a test block`;
- `return`, including `?? return`, is `return is not allowed in a field default`;
- `?` is `'?' is not allowed in a field default`.

The last two are new texts. They, the suffix and the cycle message below are added to Rust in the same fix.

**Defaults that depend on defaults.** A default depends on another default when it contains a literal that omits that field. A cycle in that graph would never finish evaluating, so it is an error in the defaults phase: `field defaults form a cycle through S.x; give one of these fields an explicit value`, anchored at the default of the first field on the cycle in check order, which is the `S.x` the message names. The message already names the field, so it takes no suffix. The cycle check runs after every default's expression has been checked.

**Uses.** A literal that omits a field runs its default there, at runtime, after the given fields (see "Struct literals"). The default's calls and effects are attributed to the function that contains the literal, transitively through defaults it depends on. So a function that builds `S {}` where `S.x = f()` calls `f`, and if `f` builds `S {}` the whole-program phase reports Rust's `call cycle contains unmarked function(s)` error.

**In Rust nlc** the typed default is stored once with the struct, and each use refers to it. Local ids inside a default's own blocks must not clash with the using function's locals.

Fixtures, run in both compilers: a default calling a function declared later in another file; a default that names a caller's local (an error now, with the full suffixed message pinned); a local that shadows a function a default calls (the default still calls the function); an invalid default that no literal uses; an overridden default with a print (not run); each of the error texts above; a default cycle, direct and through two structs; a call cycle through a default.

## Checker order

The first error must equal Rust's, as in E1. Rust's `run` adds these phases before E1's:

1. **Type names**, for every file: enums, then structs (`register_type_names`). Errors: a duplicate type, or one that shadows a built-in.
2. **Enum payloads** across all files, then **struct fields** across all files (`fill_enum_cases`, `fill_struct_fields`). Errors: duplicate cases and fields (with "first on line N"), unknown payload and field types, and `()` fields.
3. **Infinite size** (`check_recursive_value_types`), anchored at the declaration.
4. Function signatures and tests file by file, then the entry check, as in E1.
5. **Struct field defaults** (see "Struct field defaults").
6. Then E1's order: function bodies, test bodies and the whole-program phase.

Rust's `check_all_type_sizes` runs between 3 and 4. It reports nothing reachable in the E2 subset (its errors involve collections, pools and capabilities). The implementer confirms that and pins it with a comment, not a test.

Inside bodies, the order rules come from Rust's traversal:

- **Constructors:** expected-type resolution first, then the single matching enum, then the ambiguity error (`case 'X' belongs to more than one enum; qualify it with the enum name`), then the unknown-case or unknown-name error. Arity errors come after resolution. The candidates include the built-in enums, so resolution to one of their cases is the typed unsupported event, reached at that point.
- **Names:** a bare name resolves in the order of the `ExprKind::Name` path in `check_expr`: locals first, then package functions (a function value, which stays unsupported as in E1), then a case of the expected sum type, then `none`. With an expected type and no such case, the name is Rust's unknown-name error. Only with no expected type does Rust search every enum, built-ins included, for the single matching case. A call `Name(...)` resolves package functions before cases. Fixtures pin each collision: a local named like a case, a function named like a case, a case in two enums, a user case spelled like a built-in case (ambiguity with no expected type, the user's case with one), and a local spelled like a built-in case (the local wins).
- **`match`:** arms in source order. For each arm: its pattern errors (type of pattern against scrutinee, qualifier, arity, unreachable or duplicate), then its bindings, declared in payload order (a duplicate binding name fails here, before the body), then its body, then the arm-type check against earlier reachable arms. Exhaustiveness comes last, anchored at the `match` keyword:
  - sum types: `non-exhaustive match; missing Color.Blue`, missing cases as `Type.case` in declaration order joined by `", "`;
  - bool: `non-exhaustive bool match; missing ...`, true then false, joined by `" and "`;
  - integers: `integer matches need a '_' catch-all arm`.

  So an unreachable arm beats a missing case, and a bad binding beats an error in its arm's body.
- **Struct literals:** fields in written order, each checked as it is met, then the missing-field check over declaration order.
- **`?`:** the test check first (`a test cannot use '?'`, before the operand is visited), then the operand, then the operator's own rule.
- **`??`:** the operand first, then the operator's own rule, then the fallback.

The implementer extends E1's documented order in the checker's source and pins each non-obvious step with a fixture. Where this file and checker.rs disagree, checker.rs wins (after the reference fixes) and the report says so.

**Structure.** The type table gets struct, enum, `Option` and `Result` entries. `Option<T>` and `Result<T, E>` are interned by their arguments, so each instance has one id. Fields and cases live in their own ordered tables keyed by type id, with name ids. Typed defaults live with their fields. The checker stays a flat, frame-driven walk with no `recursive` functions, as in E1.

## The core library

The design note's retirement table gives E2 two rows. E2 does one and moves the other.

**Raw results become `Result`.**

- Each fallible system call the core library uses gets one wrapper, in core/linux or the file that uses it: `fn write(fd: int, data: sys.Addr, count: long) -> Result<long, Errno>`, and the same for `map`, `protect`, `ioctl`, `statx`, `sigaction`, `openat` and `close`.
- `Errno` is `struct Errno { number: int }`, holding the positive error number: the raw result `-4` becomes `Errno { number: 4 }`. Error numbers are preserved exactly, and the interrupted-call checks compare `number == 4`.
- Only the wrappers make raw fallible calls. That covers `sys.is_error` and also raw success tests such as `sys.ioctl(...) == 0L` and `sys.statx(...) == 0L` in output.nl, and the ignored `sys.close` in environment.nl. A test scans the core sources and fails on any raw fallible `sys.<call>` outside its wrapper. `sys.exit_group` is not fallible and stays raw.
- The `write` wrapper sits above the test-mode fault injection (`nl_core_sys_write` in output.nl), so injected faults reach callers as `Errno` values. The interrupted-call retry and the short-write loops in output.nl and format.nl keep their behaviour.
- Existing ignored-error policies stay. The ignored `close` in environment.nl stays ignored, written as a `let` binding of the `Result` (which the unused-`Result` rule allows).
- The existing fault-sequence, output and startup tests run again unchanged, and pass.

**The state-block layout struct moves to E3.** The block's layout is mostly byte areas: two 64 KiB buffers, the file table and scratch. E2 can't describe those without arrays. E3 replaces the block with an ordinary `global` struct anyway (the table's proposed E3 row). A layout struct in E2 would be rewritten one task later. E2 updates the table in docs/design/core-library.md to say so.

**New hooks:** the raw print hooks, `nl_print_text`, `nl_print_newline` and the three expectation hooks, with the C runtime's signatures and behaviour.

- Exported hooks keep their fixed C signatures, with scalar arguments and results. `Result`-returning functions are internal to the core library and never hooks.
- The hook table's check (each hook exists with its signature) covers the new hooks.
- Each new hook has a fixture comparing its bytes, flush order and failure status against the C leg: output to a terminal-like stream and redirected to a file and a pipe, and buffered values printed between the expectation labels.

The core library is still compiled with the privileged flag, after the user package, and a core diagnostic is still an internal error.

## Runtime checklist

Each item has a directed fixture comparing exact stdout, stderr and status, at both optimisation levels:

- **Copies are independent:** change a `var` copy's field, then print both values.
- **Evaluation order:** struct-literal fields in source order, then defaults in declaration order; an overridden default with a print is not run; constructor arguments left to right; the `match` scrutinee once; both `==` operands once.
- **Evaluation points:** the snapshot fixtures in "Evaluation points".
- **Payload placement:** cases of different sizes and alignments (`bool`, `int`, `long`, `()`, nested structs, empty structs) written, copied, matched and printed after the value has held another case. Stale bytes must never show.
- **Equality:** equal and unequal on every case pair of an enum, nested `Option<Result<...>>`, a struct whose padding differs, and unit payloads.
- **`match`:** an aggregate-valued match, a match with some `never` arms, and one where every arm is `never`.
- **`?`:** `Option` and `Result`, with different success types and one error type, from inside nested loops, the `none` and `err` paths returning the right value, and both a unit error and an aggregate error.
- **`??`:** a value fallback that prints (run only on `none`), `?? return`, `?? break` and `?? continue` in nested loops.
- **`unwrap`:** both failures with their messages, line and column, after earlier output, in a program and in a test child (status 1 and 70).
- **Printing:** every form in "Printing", including deep nesting, an empty struct, and aggregate expectation failures with output before and after.
- **Unit values:** `Wrap(())` printed directly, nested in a struct field and inside `some(...)`; `some(())` matched with a named binding and with `_`; a unit local; a function with unit parameters called with unit arguments that have effects.
- **Calls:** aggregates as parameters and results, `s = f(s)`, a result passed straight into another call, and an aggregate parameter used after the callee builds its result.
- **Defaults:** the fixtures in "Struct field defaults".

## Directed fixtures (tests/e2/)

Grouped like tests/e1, each classified by hand:

- **Structs:** defaults and overrides, shorthand, nested literals, field read and write paths, compound assignment on fields with overflow at the operator, copies, equality and printing, empty structs.
- **Enums:** payload and payload-free cases, qualified and unqualified constructors, cases of the same name in two enums (ambiguity), resolution from expected type, `Option` and `Result` nesting.
- **Match:** every pattern form; shadowing; block arms; `never` arms; match as statement and expression; integer matches on both widths with negative literals; bool matches.
- **Diagnostics, in Rust's order:** each checker message named in this file, at least once; competing errors across the new registration phases and files (a duplicate case in `b.nl` against a bad parameter type in `a.nl`); an unreachable arm against a missing case; each missing-case order; duplicate payload binding names; struct-literal errors in competition; `?` in a test with a bad operand; other `?` errors; `??` on a `Result`; unused `Result`; infinite size directly and through `Option`; the name-collision fixtures in "Checker order"; the default-phase fixtures.
- **Runtime:** the checklist above.
- **Core library:** a fixture per new hook, and the wrapper test.
- **Size:** at exactly 4096 bytes (`build`) and just over (`unsupported`); a threshold crossed only by alignment padding; a size where Rust's layout and E2's fall on different sides of 4096; a doubling chain of structs far past the threshold; direct, mutual and `Option`/`Result` cycles; forward references across files; an unresolved field type next to a large known part (`diagnose`); an oversized `some(s)` with no annotation, before and after a checker error; an oversized `.ok()`; an oversized intermediate in `some(some(s))`.
- **Unsupported:** each new construct-table entry, in an unused function, an unreachable statement and a test; a package with an E2 checker error and a syntactic unsupported construct (unsupported wins); a syntax error with an unsupported construct (`diagnose`); each typed event before and after a checker error; a test ending in an inferred `Result`; the two-file first-node order fixture; the native-path budget fixtures.
- **Helpers:** the adversarial fixtures and the bound test in "Shared helpers".

**Generated cases.** The E1 generator gains structs, enums, matches, `?` and `??` in valid packages, and seeded errors from the new phases (including defaults) in invalid ones. `cargo test` runs a fixed seed set, and the report covers a larger run.

## Classification update

- Re-classify every package under tests/run, tests/test, tests/e1 and tests/e2 by hand from this file, never by running the self-hosted compiler. No package keeps its class by default: each is judged afresh, including newly valid struct and enum programs and tests.
- The reference fixes may change `expected.*` files. Each change is listed.
- The report gives the counts before and after per class, lists every package that moved with its old and new class, and lists every expected-output change.

## Harness

E1's protocol is unchanged: the reference first, checked against its class and the `expected.*` files, then the self-hosted compiler, with the same comparisons, fixed environment, timeouts and the no-IR-after-rejection check. After S2:

- the default run (`cargo test`) uses -O1 and the core leg;
- `NLC_LONG_TESTS=1` runs both -O1 and `NLC_OPT_LEVEL=3`, and the C-runtime third leg.

E2's acceptance needs both modes passing with zero mismatches, including the long mode's -O1 and -O3 runs and the C leg. The report gives the counts from the long mode.

## The compiler's own budget

- New tables (types, fields, cases, payload parts, layouts, interned `Option`/`Result` instances, typed defaults, helper ids, per-function aggregate slots and slot bytes) take their capacities from the input policy's limits, as in E1. Each is listed in limits.nl with its derivation.
- Exhaustion is a named limit diagnostic, with tests at N and N+1 for every limit the input policy can reach. On a package Rust builds, a limit diagnostic is a failure, so every capacity must follow from the input policy.
- The IR bound is the one in "Shared helpers".

## Measurements

Release builds under `ulimit -v 8000000` and the WSL bench lock. Each figure is the best of five, reported with the spread (minimum, median, maximum) and the conditions: machine, pinned cores, optimisation level and harness mode.

- **Scalar regression:** the E1 benchmark, both compilers, against the same S2 baseline on the same machine and conditions, to show E2 cost nothing on scalar code.
- **Aggregate compile cost:** a new generated aggregate benchmark (structs, enums, matches, `?`), valid and uniquely named, within the input policy. Wall time and peak RSS for the whole self-hosted build, the self-hosted compile alone, `link-ir` alone, and Rust's whole build, each measured directly from its own process. No figure is derived by subtracting independent timings.
- **IR size:** IR bytes per source byte for both benchmarks, and the bound test's growth with depth.
- **Bootstrap:** the bootstrap time, and `nlc inspect stacks selfhost` (E1 reported 3.48 GB; say how much E2's tables add).
- **Native frames:** for the native-path fixtures, the computed slot bytes, the `-fstack-size-section` frames at -O1 and -O3, and observed peak RSS, kept as separate figures and separate from the compiler's own computed stack bound.
- **Run time:** one aggregate-heavy program built by each compiler, to show the offset-and-slot layout is not slower than Rust's LLVM aggregates. It runs for at least a second, prints only a checksum of its work (so nothing is optimised away), and output is redirected to a file. An empty program's run time is reported next to it, for process overhead. Report it; don't gate on it.

## Not part of E2

- `write` parameters, collections, strings, `const`, globals, refinements, aliases, user generics, `?.`, other methods, `discard`, function values, `recursive`.
- Data-stack regions and the core library's stack growth (E3).
- A computed native-stack bound covering scalar frames (the native-stack task; see "Native frames").
- The hook ABI change to context passing (E3, before the first region-using core function).
- Per-file IR modules, parallel clang, or any build-speed work (PLAN small fixes).
- A typed dump format, self-compilation, the stage 2 and stage 3 check.
- Language changes beyond the two reference fixes. If other Rust behaviour clearly contradicts DESIGN.md, fix it in Rust nlc (with a fixture) and list the fix in the report; if it is unclear whether Rust is wrong, keep Rust's behaviour, match it, and list it in the report as a question for Claude and Ben.

## Report

docs/tasks/E2-report.md. It covers:

- the counts per class, before and after, the packages that moved and the expected-output changes;
- the two reference fixes and their fixtures;
- the extended checker order and any place it differs from this file;
- the construct table as it now stands;
- the layout rule as built, with one worked enum;
- the shared helpers and the IR bound as built;
- the native-path budget, its fixtures and the recorded limitation;
- the core library changes, including the wrappers and hooks added;
- the measurements;
- what was awkward to write in next-lang;
- the plan for E3, including the switch of the addressing function to offsets.
