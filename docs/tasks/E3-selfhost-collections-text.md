# E3: the self-hosted compiler gains collections, text, `write` parameters and a growing data stack

This spec incorporates the peer review docs/reviews/sol-E3-r1.md.

Depends on E2a (layout, structs, shared helpers, the single addressing function) and on E2i, the shared-interfaces step specified below, which runs right after E2a. Later parts also depend on E2b and E2c (see "Parts and order"). Read docs/PLAN.md "Stage 0 freeze" and Order of work items 4 and 5, DESIGN.md "The theory being tested", "Collections", "Layout", "The job's data stack" (offsets, starting size, growth, measures kept apart, unbounded collections at the tail, the rows layout), "How the compiler places values", "Loops can't quietly fill a stack", "Text, ASCII and bytes" and the Decided list, docs/design/core-library.md (the retirement table, "Retiring the hook ABI", "The data stack in E1c", "Output buffering and flush points", "File I/O in the core library", "UTF-8 in the core library", "The stack is pinned while the kernel holds an address into it"), E1's and E2's specs, reports and reviews, docs/reviews/sol-E1-r1.md, sol-E2-r1.md and sol-E3-r1.md, and the stage-0 task reports T05, T06, T08, T13 to T17, T20, T23 to T25, T29 to T31 and O1.

E1's and E2's specs hold for everything this file does not change: the harness protocol, the classes, unsupported-before-checker-error precedence with typed events, the compiler's own budget, and the report shape. E2's contracts stay as built: inferred oversized sums, memoised cycle and unknown handling, active-payload copies, unit erasure, declaration-scoped defaults, shared helpers, evaluation snapshots, the `i32` tag at offset 0 with payloads at aligned offsets at or after 4, fresh destinations, byte-stored bools, no LLVM struct types and no emitted `memcpy`, with their adversarial fixtures. Sizing is never declaration-only: `some(s)` and `.ok()` instantiate types during checking. E2's native-path budget remains a documented partial bound, not a stack-safety proof. E2's two reference fixes (default scope, unit erasure) keep their fixtures as regression tests.

Rust code is cited by function name. Line numbers drift.

## Scope

- Rust nlc is stage 0 and the behavioural reference. The two compilers are compared by stdout, stderr and exit status, never by IR or internal layout. For a feature stage 0 lacks (unbounded collections, the starting-size estimate, the atomic write, the streaming writer), the reference is the fixture's checked-in `expected.*` files (see "Harness").
- E3 widens the self-hosted subset to: fixed arrays and lists; `byte`; `Ascii`, `Text` and `Bytes` values and builders; `const`; `write` and `grow` parameters with the overlap check; data-stack regions with the core library's moving stack; unbounded local collections and builders at the stack's tail; the typical-run starting size; `Full` and capacity results, `discard` and `?.`; file I/O through the core library; nested collections in the flattened target layout. Mutable user globals are removed (decided 2026-10-26); program and shared state use parameters instead.
- The core library moves up with it: the hook ABI becomes context-passing (E3a1), the core library gains stack growth, UTF-8 and file I/O routines, the state block becomes a struct reached through the job context, and buffers become `Bytes`.
- The subset stays closed. Everything a part doesn't build fails closed as unsupported, with one fixed construct-table string each, until the part that builds it.
- "No `Option` or `Result`" in the worktree parts means no new dependency in target programs or in core-library code that the self-hosted compiler compiles. The compiler's own source is compiled by stage 0 and already uses both.

## Parts and order

E3 is split into steps. Each is sized for about one session, but a step is done when its acceptance holds, not when a session ends. A step that isn't finished continues in the next session. Every step ends with both full suites passing (`NLC_FRONTEND=rust` and `selfhost`), the default and long comparison modes at zero mismatches, `cargo fmt --all -- --check`, the measurements its section asks for, and its own report (docs/tasks/E2i-report.md, E3a1-report.md and so on). Each step leaves everything not yet built failing closed.

| Step | Contents | Starts after |
| --- | --- | --- |
| **E2i** | the shared interfaces: one type-kind classification, the storage-location interface, the helper-emission interface, the exit and cleanup interface, ownership of shared functions; the stage-0 audit of argument evaluation (see "Evaluation of arguments and operands") | E2a lands. Main checkout |
| **E3a1** | the region runtime: the context record with a C-compatible prefix in a stable header page; the core library's stack growth (offsets, `mremap`, guard page, the pin count, `NLC_STACK_VERIFY` with non-heap poison records, `NLC_STACK_STATS` with `clock_gettime`); the context-passing hook ABI; region planning, the inline bump, growth points, base reload and scope resets in the compiler; the data-stack origin of the location descriptor; the stack-address `sys` operations with offset-taking stack-buffer functions; the two-phase relocation test; the region-threshold test option and positive relocation evidence | E2i lands. Worktree, in parallel with E2b and E2c |
| **E3a2** | fixed arrays and `list` of scalars and structs (no `byte`, text, sum-typed or nested elements); indexing, element assignment, `len`/`count`, literals and `fill`; `for` over collections and writable views; `discard` on `push` and `insert`; `remove` and `clear`; collection helpers; exact layout arithmetic; the location descriptor's lane geometry; `write` parameters with the overlap check; values over 4,096 bytes in regions | E3a1. Worktree |
| **merge** | E3a1 and E3a2 rebased onto main and merged under the merge contract (see "Parallel work and the merge") | E3a2, E2b and E2c land |
| **E3b** | `Full`, capacity results as `Result<(), Full>`, `pop`, proven pushes, `discard` in full, `?.`; sum-typed collection elements; sum types over 4,096 bytes in regions; the `write` store-back fixtures on `?` | the merge |
| **E3c** | `byte`; `Ascii`, `Text` and `Bytes` as stored values in locals, struct fields and payloads; literals, `len`, byte access, slicing (with the inclusive-range fix), comparisons, `print`, `str` and the formatting functions, conversions with `Utf8Error` and `TextError`, `fit<Ascii max N>()`; fresh-result destinations; `Text` validated once, with the test-build assertion | E3b |
| **E3d1** | builders: append transactions with checkpoints, `+=`, `try_append`, `Bytes.push`, `take`; `grow` parameters (with the width fix); iteration scopes and the loop-growth bound rule; the in-place reassignment rule (T30) | E3c |
| **E3d2** | unbounded local collections and builders at the stack's tail (rows layout for structs); the typical-run starting size; the `expected` harness class | E3d1 |
| **E3d3** | interpolated strings `$"..."` (DESIGN "Interpolated strings"): lexing and parsing, bounds from the holes, one-pass lowering into the destination and straight into builders, format options | E3d2 |
| **E3e** | `const` and constant arrays; retiring the core state block (into the job context) and constants-as-functions; nested collections in the flattened layout; text and byte fields in collection lanes; emitting only reachable functions | E3d2 |
| **E3f1** | `Env`, `Fs` and `Out` as far as file I/O needs them; `Path`, `DirEntry`, `IoError` and `FileKind`; `main` and tests returning `Result`; file reads, writes, listings and joins in the core library; the atomic write; the test-build temporary root; the Bytes-only read fix and the zero-byte-write fix; core memory-function speed | E3e |
| **E3f2** | the streaming file writer, with its uniqueness, borrowing, exit and fault-plan rules | E3f1 |

**Nested collections belong in E3 (E3e), not E4.** The self-hosted compiler has its own layout, and the location descriptor (E3a2) already carries lane geometry. Building nested collections inline per element first (stage 0's T06 form) would be rewritten one task later. E3e is the first step with every element kind nested collections need. Until then, a collection type inside a collection element, directly or through a struct field, is unsupported (`nested collections`).

**Text lanes over 64 bytes** (size classes, T31) are in E3e. If E3e runs out of room, size-class lanes may fail closed (`text fields over 64 bytes in collections`) and move to E4; the E3e report says so. Inline lanes up to 64 bytes are not optional in E3e.

## E2i: shared interfaces (before the split)

E2b, E2c and the worktree parts all change the same parts of selfhost/compiler.nl. Today the compiler identifies aggregates by `ty >= TY_STRUCT_BASE` and indexes `struct_types` directly, and signatures, helper emission and exit lowering are written for structs only. E2i replaces those assumptions with four small interfaces and an ownership table, so each later part adds branches instead of rewriting shared code. The self-hosted compiler's accepted behavior does not change; E2i's separate stage-0 argument-timing audit fixes the reference behavior described below.

Size: small, one session. It runs in the main checkout right after E2a, before E2b and E3a1 start.

1. **Type kinds.** The type record gains a kind field: scalar, unit, never, struct, enum, option, result, array, list, ascii, text, bytes, and the core-only address type. One classification function answers every kind question (`type_kind(ty)`, and predicates such as `is_aggregate_type` built on it). It replaces each `>= TY_STRUCT_BASE` test, in `value_type_size`, `value_type_align`, `size_package_structs`, `type_node_is_oversized`, the unsupported-category branches, `is_aggregate_type` and elsewhere, and each direct `struct_types[ty - TY_STRUCT_BASE]` index outside the type module. Type ids come from one table: E2b's enums and the worktree's collections append records and never renumber the `TY_*` constants.
2. **Storage locations.** The emitter's compile-time location record: an origin (native slot now; data-stack offset and fixed address for `const` data later), a constant byte offset, and lane geometry (copies and index, see "The location descriptor"). E2i implements only the native-slot origin with one copy and index 0, which is E2a's slot-plus-offset form. `emit_layout_address` takes the record. The interface also owns the two ends of every by-reference pass: passing a location as a call argument or hidden destination, and receiving a parameter as a location. Every aggregate parameter, result and helper operand goes through them, whatever its kind, so when E3a2 changes the runtime form to the descriptor, E2b's and E2c's sum parameters and results change with it. The other origins and lane geometry are an internal compiler error until E3a1 and E3a2 add them.
3. **Helper emission.** One registry keyed by type id and operation (copy, eq, print, fill, default), dispatching by kind to one emitter per kind. E2a's struct helpers become the struct entry. E2b registers enum, `Option` and `Result` emitters; E3a2 registers collection emitters. Helpers take locations as operands, so later parts can copy, compare and print values in place.
4. **Exits and cleanup.** One function lowers every exit from a scope: `return`, the fall-through end, `break`, `continue`, and later `?`, `?? return`, `?? break` and `?? continue`. It runs the pending cleanups of each scope left, innermost first. E2i registers none. E3a1 registers region top resets, E3a2 registers `write` store-backs and view ends, E2c's `?` and `??` call it, and E3f2 registers writer aborts.
5. **Ownership.** E2i writes the ownership table into a comment at the top of selfhost/compiler.nl and into its report. After E2i, only a function's owner changes its body; other parts add one delimited branch through the interfaces.

   | Shared code | Owner after E2i | Others may |
   | --- | --- | --- |
   | type table, kind classification, `value_type_size`/`_align`, `resolve_value_type`, `known_non_scalar_type`, `is_builtin_type_name` | E2i (interface frozen) | append a kind and its branches |
   | `emit_layout_address` and the location record | E3a1 (origins), E3a2 (lane geometry) | nothing; sum layouts reach it only through the layout table |
   | passing a location as an argument or destination, receiving a parameter as a location | E3a2 (the descriptor ABI) | nothing; E2b and E2c call them for sum parameters and results |
   | helper registry | E2i | register an emitter for their kind |
   | exit and cleanup function | E2i | register a cleanup; call it from a new exit |
   | `register_package_declarations`, signatures | E3a2 (parameter modes) | E2b: enums; E2c: result types |
   | `natural_node_type`, `check_one_body`, `emit_expr_linear`, `emit_function_body` | none | one dispatch branch per new node kind |
   | `unsupported_category_for_node`, `unsupported_node_message` | none | remove their nodes, append their rows |
   | `core_sys_*`, the hook table, the frame-budget walk | E3a1 | E2b and E2c add hooks only when unavoidable, each with a contract fixture recorded against C |
   | limits.nl | none | append one delimited block with derivations |

6. **The stage-0 argument audit** (see "Evaluation of arguments and operands"). It runs here, in the main checkout, so stage 0 is final for argument evaluation before the worktree starts and the worktree never edits stage 0.

**Acceptance.** No behaviour change: both suites pass, both comparison modes at zero mismatches, no classification movement except from the audit's fixtures. A source-scan test finds no `TY_STRUCT_BASE` comparison and no `struct_types` index outside the type module. The audit fixtures and any stage-0 fix are listed in the report.

## Parallel work and the merge

E3a1 and E3a2 run in their own git worktree while E2b (enums, `match`) and E2c (`Option`, `Result`, `?`, `??`, the core error wrappers) continue in the main checkout. The rules:

1. **Starting point.** The worktree branches from main after E2i's commit and builds on the interfaces as they landed.
2. **No dependency on E2b or E2c.** The worktree adds no enum, `match`, `Option`, `Result`, `?` or `??` path in target programs or in core-library code. `pop`, and `push` or `insert` used other than under `discard`, stay unsupported (see "Arrays and lists"). `discard xs.push(v)` and `discard xs.insert(i, v)` lower straight to capacity branches without making a `Result` value. Core-library code the worktree adds (core/stack.nl and the stack-buffer functions) uses the E1c raw-result convention (`sys.is_error` at the call site).
3. **New files.** selfhost/regions.nl (region planning, top and base caches, growth points, scope resets) and core/stack.nl (growth, verification, statistics, pinning) in E3a1; selfhost/collections.nl (collection types, checking, emission, helpers) and selfhost/params.nl (`write` checking and lowering, the overlap check) in E3a2.
4. **Shared code.** Edits to selfhost/compiler.nl, limits.nl and main.nl go through E2i's interfaces, follow its ownership table, and are marked with `// E3a1 begin`/`// E3a1 end` or `// E3a2 begin`/`// E3a2 end`. A shared function changed outside the table is listed in the step's report with the reason.
5. **Generated and shared data files.** selfhost/core_files.nl is never merged by hand: regenerate it with scripts/embed-core.sh. tests/e1/classification.tsv gets the worktree's fixtures in one block at the end between `# E3a begin` and `# E3a end`. A row moves only for a package the worktree alone makes buildable or diagnosable. Harness edits are limited to E3a1's removal of the C leg (one delimited hunk in scripts/compare-selfhost-build.py) and new scripts and test files (scripts/check-selfhost-relocation.py, compiler/tests/selfhost_relocation.rs).
6. **Separate build state.** `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target-e3a` for the worktree. Benchmarks take the WSL bench lock as always.
7. **Stage 0 is untouched in the worktree.** E2i's audit settled argument evaluation in stage 0 beforehand, and no other reference fix is needed for the worktree's features.
8. **The C leg.** E3a1 switches the hook ABI and removes the C-runtime third leg in the worktree. Main keeps the C leg until the merge. E2b and E2c add hooks only when unavoidable, each with a contract fixture recorded against C.

**The merge contract.** The merge depends on E2i's interfaces: hunks that follow the ownership table merge as separate branches, and any conflict outside them is resolved by the table's owner. The steps, in order:

1. On main, before rebasing, record a contract fixture against the C runtime for every hook E2b or E2c added after the branch point.
2. Rebase the worktree onto main. Resolve the delimited hunks. Regenerate core_files.nl.
3. Convert the hooks E2b and E2c added to the context-passing ABI. Remove the C leg from main's harness.
4. Convert core/stack.nl's raw results and the stack-buffer functions to E2c's wrappers (see "Core library: stack-buffer functions"). Extend E2c's wrapper audit to them. The audit test, injected `EINTR` and short writes, and the later-argument relocation test pass together.
5. Reclassify by hand the packages that need features from both sides (each stays `unsupported` on each branch alone), listing each movement.
6. Validate with merge fixtures that neither side alone can build:
   - an enum whose payload holds a collection (copy, compare, print, `match` bindings);
   - a struct default that builds a collection (`items: list<int, 4> = [1, 2]`), used, overridden and omitted;
   - `?` and `?? return` propagating out of a `for` loop over a collection with a writable view live and a data-stack region live, and from a callee with a `write` parameter (the caller sees the stored-back value, and the top is reset);
   - `?? break` and `?? continue` inside such a loop.
7. Rerun both full suites, both comparison modes and the relocation check. Rerun the measurements of E2b, E2c and E3a2 on the merged tree and report them.

E3b starts only after the merge.

## Reference fixes in stage 0

Stage 0 takes a fix only where its observable behaviour contradicts DESIGN.md and the self-hosted compiler can't be tested without it. Each fix lands with fixtures and updated `expected.*` files, in the step named, and that step's report lists it.

1. **E2i: argument evaluation.** The audit and fixes in "Evaluation of arguments and operands".
2. **E3c: `slice(a..=b)`.** Stage 0 accepts `s.slice(a..=b)` but treats the end as exclusive, because both parsers discard the `RangeInclusive` token in that position, so a fix in the emitter alone can't work. Carry inclusivity through the Rust parser, the self-hosted parser and typed lowering, keeping the parse-dump comparison byte for byte (both dumps gain the flag in the same change). An inclusive end that overflows when made exclusive fails with kind 16. Fixtures: `..=` at the last code point, one past it (kind 16), and at the largest `long` (kind 16).
3. **E3c, if needed: `sys` names in user code.** If E3c's method calls make a user `sys.write(...)` reach the self-hosted checker, add `sys operations are available only to the core library` to stage 0 at its name resolution and to the self-hosted checker, with the privilege fixtures.
4. **E3d1: the `grow` width check.** See "`grow` parameters".
5. **E3f1: one byte-buffer read form.** DESIGN.md makes `Bytes` the one byte-buffer I/O form (O5). Stage 0 still reads files into `list<byte, N>`. Remove the form entirely: the checker overload in `fs.read`, the emitter branch choosing `nl_fs_read`, its declaration, and `nl_fs_read` in runtime/nl_runtime.c. Migrate the fixtures that read into `list<byte, N>` to `Bytes`. A `list<byte, N>` buffer becomes the checker error `read files into Bytes; list<byte, N> is not a file buffer`, with a fixture. The two existing texts that promise a byte list (`fs.read(path, buffer) takes a path and a write byte list`, `fs.read buffer must be a bounded byte list`) are reworded to name `Bytes` or `Text`, and the report lists the new texts. Reads into `Text` stay. Reads into `Ascii` stay what stage 0 makes them, a checker error.
6. **E3f1: a zero-byte write is `EIO`.** Both `nl_write_all` and `nl_output_flush_index` use `errno ? errno : EIO` when `write` returns 0 or less. Split the cases in both: a return of 0 is `EIO`; a negative return keeps `errno`. Fixtures through the fault plan for `Out` and `Fs` writes.

Not fixes (unobservable, so stage 0 keeps them): stage 0's pointer mode and its up-front reservation; its re-validation of `Text`; its inline nested lanes; its 256 KiB offset-mode start. If an implementer finds another observable contradiction with DESIGN.md, they fix it in stage 0 with a fixture and list it, or, if it is unclear, keep stage 0's behaviour and list it as a question.

## Layout and residence

**Two sizing functions, kept apart.** E2's capped eligibility sizing (saturating at 4,097, with unknown and cycle results) stays for the unsupported gates that remain: sum types over 4,096 bytes until E3b, transitively through structs, including instances E2c infers after the merge. A struct containing an oversized sum is gated too. Unknown and cycle results still never gate; those packages reach the checker and get stage 0's errors. A second function, **exact layout**, computes every size, alignment and offset that storage uses, with checked 64-bit arithmetic: lane products (copies times size), alignment round-ups, list counts and other metadata, and nesting products. It runs only on types that have passed checking. Overflow is stage 0's `collection size overflows long; reduce a capacity`, where stage 0 reports it (`check_all_type_sizes`). Region and top additions at run time are checked in the bump; overflow fails with kind 18. A test confirms that, for every directed fixture type, the two functions agree wherever eligibility sizing is below its cap.

**Residence is by exact size alone** (DESIGN "The job's data stack"): a value of 4,096 bytes or less, whatever its kind, lives in a native-stack slot (scalars in SSA values); a larger value gets a data-stack region. The rule is transitive by construction, because exact size includes embedded collections at full capacity and text at full maximum. So a small struct holding a `list<int, 4>` stays native, and a `list<int, 4>` local is native too. Unbounded values are the exception: they live at the stack's top (see "Unbounded collections"). E2's `value types larger than 4096 bytes` entry leaves the construct table for structs and collections in E3a2, and for sum types in E3b.

**The layout of N copies.** Every value's storage follows one recursive rule, "N copies of T", with offsets measured from the start of the group:

- a scalar: one lane of N elements of its size (a `bool` is one byte);
- a struct: for each field in declaration order, the group of N copies of the field's type, placed at the next offset aligned to that type's alignment; the group's size is rounded up to the struct's alignment;
- an array `T[M]`: N times M copies of T, element `j` of copy `i` at copy index `i * M + j`;
- a list `list<T, M>`: a count lane of N `long` counts, then N times M copies of T;
- a sum type (from E3b): one lane of N whole values, each with its tag and payload together and its size rounded to its alignment, because cases overlap;
- `Ascii`, `Text`, `Bytes` of maximum M bytes (from E3c): a length lane, a code-point count lane for `Text`, and a byte lane of N times M bytes, so each value's bytes are contiguous.

A standalone value is one copy, so a struct's layout is exactly E2's: each field at an aligned offset, the size rounded to the alignment. The address of field `f` of copy `i` is `group + lane_offset(f, N) + i * size(f)`. Lane offsets are computed level by level from per-type tables (each field's alignment and its size per copy), never from a table indexed by flattened leaves, so the work and the IR stay linear in the declared fields and the written path even for a type DAG. Copies, equality and printing touch only live elements (`0 <= i < count`, T23), so bytes past a count are never read.

**Rows** (unbounded collections, DESIGN "Unbounded collections grow at the stack's tail"): after the count, element `i` is one copy of T at `i * size(T)`, so each element is a contiguous standalone value. Bounded collections keep split fields.

## The location descriptor

One descriptor says where a value is, for read parameters, `write` and `grow` parameters, hidden results, helper operands, element references and views.

- **Origin.** A native slot (an address on the native stack, which never moves), a data-stack offset (from the job's stack base, which moves), or a fixed address (which never moves, used by `const` data from E3e).
- **Offset.** A byte offset from the origin to the start of the group.
- **Lane geometry.** The copy count N of the group's layout, and the copy index i. A standalone value has N = 1 and i = 0. Inner strides are not passed: they follow from the static type (inner capacities), as in the layout rule above.

At run time a descriptor is passed as `(ptr anchor, i64 offset)` for a scalar location (the caller folds lane arithmetic into the offset) and `(ptr anchor, i64 offset, i64 copies, i64 index)` for an aggregate location. The anchor is null for the data-stack origin; the address is then derived from the current cached base, at the access. A native or fixed anchor is used as is. LLVM hoists the choice out of loops. The callee's code depends only on the parameter's static type, so there is one callee form.

Uses:

- An element `xs[i]` of a split-field collection is passed in place as the collection's group with N = capacity and index i. A rows element is a standalone value at its own offset.
- A nested subcollection `units[i].inventory` is passed as the inventory group inside `units`'s layout, with N = `units`'s capacity and index i. The callee, expecting `list<Item, 8>`, finds its count at count-lane index i and its items at copy indexes `i * 8 + j`.
- An embedded collection in a native struct has a native anchor; in a large struct or an element, a data-stack anchor.
- A hidden result destination is a fresh standalone value (N = 1), native or in a region by size.
- Helpers take descriptors, so a collection's helper calls its element type's helper on `(group, N, i)` without copying.
- **Gathering is the fallback** where a callee needs contiguous storage that the descriptor can't name: core hooks and memory functions with fixed C signatures, and later foreign calls. The caller gathers into a fresh contiguous value, passes that, and for `write` copies it back after the call, after reloading the base.

Relocation pins (each callee forces a stack move, then reads and writes through the descriptor): a large struct element of a list (E3a2); an embedded collection in a native struct and in a large struct (E3a2); a nested subcollection (E3e).

## Evaluation of arguments and operands

The target is stage 0's reference semantics for `write` and E2's evaluation-point snapshots for reads.

- **Indexes are captured once.** An index or field path in an argument or operand is evaluated, and bounds-checked, once, where the argument is evaluated. Later effects don't re-evaluate it: in `f(xs[i], { i = 5; 0 })` the reference is to the old `xs[i]`.
- **`write` and `grow` arguments are references.** The callee sees the place's contents when it runs, after every later argument has been evaluated. In `f(xs[0], { xs[0] = 9; 0 })` with a `write int` first parameter, the callee sees 9, as stage 0's element pointer gives. The self-hosted compiler passes a descriptor, so it gets this by construction. Where it gathers (the fallback above), it gathers after the last argument is evaluated, just before the call.
- **Read arguments and operands are snapshots taken where they are evaluated** (E2's rule). The emitter may skip the copy only when no operand evaluated after it, up to the value's use, can change it. E2's skip rule assumed calls can't change a caller's locals, which no longer holds. From E3a2 the threats are assignment, compound assignment, a mutating method (`push`, `insert`, `remove`, `clear`, later `try_append`, `+=`, `Bytes.push`), and any call that passes a `write` or `grow` argument. So in `f(s, mutate(s))`, with `f`'s first parameter read and `mutate` taking `write`, `f` sees the old `s`.
- **The overlap check doesn't cover these cases.** A block or call argument is not a place, so `places_overlap` never sees it. That is why evaluation order, not exclusivity, decides them.

**The stage-0 audit (E2i).** Stage 0's `emit_call_argument` gathers a struct element passed `write` (`emit_gather_collection_element`) inside the argument loop, before later arguments are evaluated, and scatters it back after the call. So `g(units[0], { units[0].hp = 9; 0 })` with a `write Unit` first parameter probably shows the callee the old `hp`, and the scatter then overwrites the 9. Its large-value read path passes the place's pointer or offset without a snapshot, so a later `mutate(big)` may be visible to the callee. Both contradict the rules above. E2i writes fixtures for each, at both optimisation levels, and runs them through stage 0. A mismatch is a stage-0 fix: gather after the last argument; snapshot a large read argument when a later operand may change it. These fixtures are classed `unsupported` for the self-hosted compiler until E3a2.

Fixtures (E2i for stage 0, run through the self-hosted compiler from E3a2):

- `f(xs[0], { xs[0] = 9; 0 })` with `write int`, and its struct-element form, both printing what the callee sees and the element afterwards;
- `f(n, { n = 9; 0 })` with `write int` on a scalar local;
- `f(s, mutate(s))` for a small struct, a struct over 4,096 bytes and a list;
- `f(xs[i], { i = 5; 0 })`;
- equality: `xs == { xs[0] = 9; xs }` and `s == mutate_then_copy(s)`;
- `expect` with the same operands, failing, so the left value prints as it was.

## `write` parameters

A `write` parameter is a reference to the caller's storage, for every type, scalars included: `fn bump(x: write int) { x += 1 }` changes the caller's `n` in `bump(n)`. That matches stage 0 (the T04 and T11 fixtures). Read is the default and unwritten; `write` comes before the type (`g: write Game`).

**What may be passed.** The argument must be a place (stage 0's `resolve_place`): a name, a `.field` path, or `xs[i]` on an array or list, rooted at something `place_is_mutable` accepts: a `var` local, a `write` or `grow` parameter, or a writable loop view. It is written bare. Stage 0's texts, all pinned by its fixtures:

- a temporary or literal: `a write argument must be an assignable place` (t04_write_temporary, t16_bytes_view_write);
- a `let`, a read parameter or a constant: `a write argument must be a var, a field of a var, or another write parameter` (t04_write_let, t04_read_forward);
- a different type, including a different refinement or `wrap`/`clamp` policy: `write argument needs exactly {param}; found {arg}` (t04_write_policy_mismatch, t04_write_refined_mismatch, t16_text_write_ascii);
- storage under a live view: `cannot pass storage containing a live collection view as write` (t06_view_write_collection, t06_nested_write_element);
- inside the callee, assigning to a read parameter: `cannot assign to read parameter '{}'; pass it as 'write' to allow mutation`;
- a `write` text may not grow: `appending through a parameter requires 'grow' mode; 'write' cannot increase its length` and the `try_append`/`push` variants (E3c, E3d1).

**Exclusivity.** No argument passed `write` or `grow` may overlap another argument of the same call (stage 0: `places_overlap`, `places_proven_prefix`, `canonical_place`, checked against every earlier argument when either mode is not read). Places overlap only with the same root after view expansion, when one path is a prefix of the other: two different fields are apart; two constant indexes that differ are apart; any other pair of indexes overlaps. The text is `arguments overlap, and at least one is passed as write; pass separate fields or a copy` (t04_overlap_same, t04_overlap_same_reverse, t04_overlap_child_first, t04_overlap_parent_first, t06_overlap_child_first, t06_overlap_parent_first, t06_overlap_unknown_indexes, t06_overlap_params_unknown). The emitter may give `noalias` only where this proof holds and the callee has no hidden result destination.

**Passing.** A `write` argument is passed as its location descriptor (see "The location descriptor"). A scalar local that is passed `write` anywhere in its scope lives in a native cell for its whole scope, not in an SSA value, so a later argument that assigns to it (`f(n, { n = 9; 0 })`) changes the cell the callee reads, and the callee sees 9, as in stage 0.

**Register caching and store-back.** Because no other argument aliases a `write` argument, the callee may load a scalar `write` value into an SSA register at entry, work on it, and store it back before it leaves. The store-back is a cleanup registered with E2i's exit function, so it runs on every exit: each `return`, the fall-through end, and from the merge each `?` that propagates and each `?? return`. A runtime failure needs none: the job ends. A call that passes the cached value on stores it first, and reloads it after a `write` pass. The emitter may instead keep every access in memory; the choice must not be observable.

**Function values.** A parameter's mode is part of a function type (`fn(write int) -> ()`), so an indirect call uses the same ABI and the place, overlap and view rules apply at the indirect call site (`check_indirect_call`). A mismatch is `function parameter {n} mode mismatch: expected {read|write|grow}, found {...}` (t11_mode_mismatch). Function values are E4; E3 writes the fixtures now, classed `unsupported` (`function values`). The descriptor ABI is the contract E4 follows.

**Fixtures** (tests/e3/a2_write_*), each at both optimisation levels:

- scalar `write` parameters of `int`, `long` and `bool`, printed in the caller after the call;
- repeated calls on the same variable, and a call inside a loop;
- a `write` parameter forwarded to another `write` parameter and to a read parameter;
- a field path (`bump(s.inner.count)`) on a native struct and on a struct element of a list (`bump(units[i].hp)`), with the stack forced to move inside the callee;
- a collection element of scalar type (`bump(xs[2])`), a whole collection (`fill_all(xs)`), and a struct element passed whole;
- an overflow failure inside the callee after earlier writes (output before the failure shows);
- aliasing refused: the same place twice, an element and its collection, a field and its struct, two unproven indexes; allowed: two different fields, two different constant indexes;
- each refused argument form (`let`, read parameter, loop counter, literal, call result);
- the evaluation fixtures in "Evaluation of arguments and operands";
- through a function value (classed `unsupported` until E4);
- store-back on `?` and `?? return` (E3b): the callee changes the value, then propagates; the caller sees the change.

## `grow` parameters and append transactions (E3d1)

A `grow` parameter is a builder in its caller's region; the callee appends within it (DESIGN "How the compiler places values"). Stage 0 allows `grow` only on `Ascii`, `Text` and `Bytes` (`grow parameters are for Ascii, Text, and Bytes builders; use read or write for other types`), with the argument the same kind as the parameter. The self-hosted compiler passes the builder's descriptor. The callee publishes the new length only on success.

**Reference fix: the width check.** Stage 0's message is `grow argument needs an {Ascii|Text|Bytes} builder with at least {param max} bytes reserved; found {arg type}`, but its test, `string_width_fits(place.ty, param.ty)`, accepts `actual <= expected`: a caller builder smaller than the parameter's maximum. The callee then bounds appends by the larger maximum and writes past the caller's region. The same predicate serves assignments and stores, where `actual <= expected` is right, so it is not changed. The two `grow` sites (the direct call in `check_direct_function_call` and the indirect call path) get their own check: the argument's maximum must be at least the parameter's, in bytes, and for `Text` also in code points. Same-kind restrictions stay. E3d1 also audits the general call path for branches that test only `Write` where `Grow` must be covered too (mode and overlap), and fixes them with fixtures. Fixtures, direct and indirect, per kind: a smaller argument (refused), an equal one and a larger one (accepted); `Text` with enough bytes but too few code points, and the reverse.

**Append transactions.** A checkpoint (the builder's length, code-point count and the stack top) is saved before each append (`+=`, `try_append`, `Bytes.push`, and a call running in append mode) and restored when that append fails: `Full`, or an error from a fallible producer. Nested appends each restore their own. Rollback covers one append, never a whole call: a `grow` callee that appends successfully and then returns an error leaves its earlier appends published, as stage 0's `emit_ascii_try_append` does. A fixture pins that, so no part of E3 promises call-wide rollback.

Fixtures: a helper that appends twice; nested `grow` forwarding; a failure inside an append that restores the checkpoint; the published-then-error helper; and the T30 in-place reassignment (`buffer = f(buffer)`), which updates in place exactly when T30's rule says.

## Data-stack regions, growth and offsets (E3a1)

**The context record.** `nl_context_create` today maps a header page but returns the stack base and leaves no usable record. E3a1 puts the context in the header page, which never moves. Only the stack mapping moves, so the context pointer is valid for the whole run. The record is declared once, as a struct in core, and the compiler takes the offsets of the fields generated code reads and writes from that declaration, never from a second copy. Its prefix matches stage 0's `nl_data_stack_context` as compiled in offset mode (`-DNLC_STACK_MODE_OFFSET=1`, which `link-ir` passes for offset-mode IR), in order and types: header mapping and size, mapping and size, reservation bytes, peak used bytes, entry name, base, top, limit, top offset, growth count, relocation count, growth nanoseconds, poison records. Fields after the prefix (pin count, initial size, the poison table) are core-only. The prefix matters while the C leg still links the same IR, and lets that leg cross-check the inline bump and the growth path against C's `nl_stack_alloc_offset` before the switch. A test compares the core declaration's offsets with `offsetof` from a small C file compiled against runtime/nl_runtime.c's definition. Failure cleanup: startup failures keep the E1c messages; a growth failure unmaps the new target range before failing.

**Growth** (core/stack.nl), with the C runtime's behaviour: double until the request fits (or take the request), round to pages, map a new `PROT_NONE` range with room for the new guard page, `mremap` with `MREMAP_MAYMOVE | MREMAP_FIXED` into it, unmap the old guard page, and fail with kind 18 and the same message on any failure. The guard page belongs to the stack mapping: the page after the reservation, moved with it. The growth routine refuses to grow while the context's pin count is above zero (no E3a1 code pins; a core test covers the refusal). `clock_gettime` (`sys.clock_gettime`, `CLOCK_MONOTONIC`) times each move for the statistics.

**`NLC_STACK_VERIFY=1`** poisons each old mapping as the C runtime does. The C runtime keeps poison records with `malloc`; the core library has no heap, so they live in a fixed table of 64 records in the context's header page. Each growth at least doubles a size below 2^63, so 64 records are enough; a full table fails with kind 18 anyway.

**`NLC_STACK_STATS=1`** prints, after the final flush, `nl offset stack entry '<name>': initial=<n> reserved=<n> peak_used=<n> growths=<n> relocations=<n> growth_ns=<n>`. That is C's line with `initial` added. The two lines differ only under this variable, which the harness leaves unset. `initial` is the starting reservation, `reserved` the final one, and `peak_used` the allocation high-water. Inline bumps update the peak: a function keeps a running maximum of its top beside the cached top and folds it into the context whenever it writes the top back (before a call that can reach the stack, and at exits). Written pages and resident pages are separate measures (DESIGN "Measures kept apart"): E3 doesn't track written pages (the scheduler milestone does), and resident memory is measured outside the program, labelled as such.

**The `sys` additions.** `sys.remap`, `sys.unmap`, `sys.clock_gettime`, and the data-stack operations `sys.stack_addr`, `sys.stack_load8` and `sys.stack_store8`, with the syntax rule (`sys.stack_addr` only as a direct argument of a system-call operation) and the two-phase lowering of core-library.md "The stack is pinned while the kernel holds an address into it": evaluate every argument, then load the base, derive each address, and make the call with nothing in between.

**Core library: stack-buffer functions.** E2c lets only wrappers taking `sys.Addr` make raw fallible calls, while `sys.stack_addr` may appear only directly inside a raw call, so a stack-buffer call can't be passed through an address-taking wrapper. Each system call that takes a data-stack buffer therefore gets an offset-taking function (`stack_write(ctx, fd, offset, count)`, and from E3f1 `stack_read` and the others) whose body is the single raw call with `sys.stack_addr` as the direct argument. Stable-address callers keep the address-taking wrappers. In the worktree these functions return raw results; the merge makes them E2c wrappers returning `Result<long, Errno>` and adds them to the wrapper audit. The memory functions keep their fixed C signatures, and their closure keeps its guard: no growth code enters it.

**The context-passing hook ABI** (in E3a1 because core/stack.nl is the first core code that needs the context). As core-library.md "Retiring the hook ABI" says: first, while the old ABI still links against C, record one contract fixture per hook (edge-case arguments; expected stdout, stderr and status). Then switch every hook to take the context pointer, replace the NUL-terminated `ptr` strings with compiler-emitted static tables (files, entries), delete `--runtime=c` and the third leg in the worktree, and keep the contract fixtures and the core library's own tests as the replacement. The E1c output, startup and test-index scripts keep passing.

**Region planning** (selfhost/regions.nl). A function plans the regions of each block's locals at block entry, as T30 orders them: regions of 64 KiB or less first, then the larger ones. Each loop iteration is a scope. Leaving a scope resets the top to the scope's entry top, through E2i's exit function, on every exit kind. The hidden result destination of a large result is a region the caller reserves, passed as a descriptor.

**Allocation.** Taking a region is an inline bump of the cached top: align, add (checked), compare with the cached limit. Only the slow path calls the growth routine.

**Offsets and growth points.** Every reference generated code keeps into the data stack is an `i64` offset. The function caches the base and the limit in SSA values.

- A **growth point** is any call that may grow the stack: the slow path, and any call except to functions the compiler proves place no regions (and the core hooks that don't).
- After a growth point the base and limit are reloaded from the context. The emitter never holds a derived address across a growth point. Addresses come only from the addressing function, at the access.
- The top is written back to the context before a call that can reach the stack and at exits.
- The frame-budget walk (`populate_frame_slot_bytes` and its callers) counts native slots only; region bytes are not native bytes.

**The region-threshold test option.** The self-hosted compiler accepts a test-only option, `--test-region-threshold=<bytes>`, that lowers the 4,096-byte residence threshold. At 0, every aggregate local, temporary, snapshot and destination of E1 and E2 goes into a region. It is never used in a comparison against stage 0 except by the relocation check (below). It gives E3a1 real region users before E3a2 adds collections.

**Starting size.** Until E3d2, the core library starts at 256 KiB, as stage 0's offset mode does.

## Forced relocation and growth evidence

- **The two-phase core test** (mandatory, deferred from E1c): a system-call operation whose later argument grows the stack by a forced move. The kernel sees the new range, and the old range, unmapped by the move, is never touched.
- **`NLC_TEST_STACK_FORCE_MOVE=1`**, read in test builds by the growth routine, makes every growth move to a fresh range and the stack start at one page.
- **The relocation check** (scripts/check-selfhost-relocation.py, run by compiler/tests/selfhost_relocation.rs) builds each selected package with the self-hosted compiler, core library only, at -O1 and -O3, and runs it with `NLC_TEST_STACK_FORCE_MOVE=1`, `NLC_STACK_VERIFY=1` and `NLC_STACK_STATS=1`. It removes the stats line and compares stdout, stderr and status with the ordinary run. It needs positive evidence: in every run, relocations equal growths, and every directed relocation fixture shows at least one relocation. The report gives the number of packages that relocated at least once.
  - E3a1 selects every `build` and test package under tests/run, tests/test, tests/e1 and tests/e2 that the self-hosted compiler builds, compiled with `--test-region-threshold=0`.
  - E3a2 onwards adds every package that allocates regions at the normal threshold.
  - From E3d2 it also selects `expected`-class packages, compared with their `expected.*` files.
- **Directed relocation fixtures:** a `write` element argument whose callee forces growth; a collection read parameter used after a callee grows; a loop over a list whose body calls a growing function; a large result destination filled after growth; the descriptor pins in "The location descriptor"; from E3d2 an unbounded list grown across moves.

## Starting size (E3d2)

DESIGN "Starting size": per entry point, a typical-run estimate from the same analysis as the worst case, with every loop counted at most 5 times and recursion at most 5 levels. Values not built in a loop count at their computed size. The first stack starts at the estimate rounded up to a power of two, at least one page, plus the guard page. `NLC_STACK_PREALLOC=1` still starts at the worst case.

- The self-hosted compiler computes both the worst case (extended to regions) and the estimate, and passes both through the context-passing ABI.
- An unbounded collection or builder counts at 5 elements in the estimate and makes the worst case "unbounded".
- Not observable in the comparison. A core test and directed fixtures check the stats line's `initial` field against estimates worked out by hand in each fixture's comment, including a loop of 1,000 pushes (counted 5 times) and a single large region. `initial` and `reserved` are reported separately.

## Unbounded collections and builders (E3d2)

DESIGN "Unbounded collections grow at the stack's tail". Stage 0 doesn't have them, so their fixtures are `expected` class.

- **Types.** `list<T, unbounded>`, `Text max unbounded`, `Ascii max unbounded` and `Bytes max unbounded`, for locals, parameters and results. In a struct field, a collection element or a sum payload it is a build error naming the place. A manifest key forbidding `unbounded` and `strict_stack` stay rejected until their tasks.
- **Layout.** A list of structs uses rows: a count, then whole elements, each a standalone value with the element's own layout, contiguous at the tail. A list of scalars is one lane, the same thing. A builder is its length (and code-point count for `Text`), then its bytes.
- **Growth.** A growth point (`push`, `try_append`, `+=`, `Bytes.push`) writes the new element or bytes at the top and bumps the top inline, with the usual slow path. It is allowed only while the value is the topmost live region: no region created after it is still alive. A violation is a build error naming both values and suggesting finishing the collection first or creating the other value earlier. Temporaries don't count: a call's regions are gone when it returns, and a pushed element is built straight into the next slot.
- **Freezing.** Opening a second unbounded value while the first is alive freezes the first until the second's scope ends. Growing a frozen value is the same build error.
- **Top ownership and scope resets.** The value's end is always its start plus its header plus its contents, so it never needs a separate record. A scope exit resets the top to the larger of the scope's entry top and the end of the innermost open unbounded value created outside that scope. So a loop that pushes onto an outer unbounded list keeps it, while each iteration's own regions are freed.
- **Return hand-off.** A function returning an unbounded value builds it as the first region it places, at its incoming top, so nothing is trapped beneath it. A region placed before it is a build error naming both values. The callee returns normally; the caller's top after the call is the value's end, and the value belongs to the local it is bound to. The result must be bound directly by `let` or `var`, or returned again; any other use is a build error. When the binding's scope ends, the top resets below it as usual.
- **Growth through a parameter.** An unbounded list passed `write`, or a builder passed `grow`, may be grown by the callee only while the callee has no live region of its own. At the call it must be the caller's topmost live region, and no other argument of the call may use a region. After the call, the caller's top is the value's new end.
- **Bounds and failures.** A `push` onto an unbounded list has no `Full` and returns `()`. Unbounded values are exempt from the loop-growth bound rule; instead the entry point's worst case reads "unbounded". The cap (`data stack range exhausted`) is a later task; until then, growth that can't be mapped fails with kind 18.
- **Messages** are new texts, written in this step and pinned by fixtures.
- **Fixtures:** a 1,000,000-element push loop of scalars; a list of a three-field struct (`int`, `long`, `bool`) pushed, indexed, field-assigned, passed `write` element by element, printed and compared; builder appends of mixed sizes; a function returning an unbounded list, and one returning another function's result through two levels, with further growth in the caller; a helper pushing through a `write` parameter, nested two calls deep; a temporary call between pushes; each build error; the starting-size fixtures; the relocation fixtures.

## Arrays and lists

**E3a2: types and operations.**

| Form | Notes |
| --- | --- |
| `T[N]`, `list<T, N>` | `T` is `int`, `long`, `bool`, or a struct whose fields are, recursively, those. A struct with a collection field is fine as a standalone value or as a field, but not as an element (`nested collections`, until E3e). `N` is a constant expression (`capacity_value`: literals, unary `-`, `+ - * / %`; `const` names from E3e). Zero is allowed. Stage 0's texts: `collection capacity must be a constant integer expression; use a literal or const value`, `list capacity cannot be negative; use zero or a positive constant` (and the array form), `collection size overflows long; reduce a capacity` |
| `[a, b, c]` literals | need an expected type (`cannot infer whether this literal is an array or list; add a T[N] or list<T, N> annotation`); an array literal has exactly N elements, a list literal at most N, with stage 0's texts |
| `list {}` | the bare form only, with an expected list type (`cannot infer the capacity for 'list {}'; add a list<T, N> type annotation`) |
| `fill(v)` | arrays only, one argument, evaluated once, stage 0's texts |
| an omitted initialiser (`let x: T`) | stage 0's `default_typed_value`: an empty list, an array of the element's default |
| `a[i]`, `a[i] = v`, `a[i].f = v`, compound assignment on elements | indexes are `long` (`collection indexes are long; cast an int index with .to_long()`; an unsuffixed literal is fine); a bad index fails with kind 16, `index out of range`, at the index expression, before any store; stage 0's proven-index elision is not observable and may be skipped |
| `a.len()` on arrays, `xs.count()` on lists | `len` is a constant `long`; `count` is `long 0..=N` (the refinement matters only from E4) |
| `discard xs.push(v)`, `discard xs.insert(i, v)` | on a full list nothing changes and nothing fails; `insert` checks `0 <= i <= count` first (kind 16 at the index argument) |
| `xs.remove(i)` (returns the element; kind 16 outside `0 <= i < count`; shifts down) and `xs.clear()` | refused under a live view: `cannot call '{T}.{m}' while a collection view is live; move the operation after the loop` |
| `for x in coll`, `for x, i in coll` | the length is snapshotted at entry; over a mutable place, `x` is a writable view aliasing `coll[i]` (a descriptor); stage 0's view and loop texts (`cannot replace or modify storage that contains a live collection view`, `cannot assign to loop counter 'index'; loop counters are immutable`, `collection iteration needs a local, parameter, or field place; bind the value to a local first`) |
| `print`, `==`, `!=`, copies, read and `write` parameters, results | equality needs identical types; no ordering on collections |

Lists have exactly `push`, `pop`, `insert`, `remove`, `count` and `clear` in stage 0 (no `get`, no `len`); an unknown method is stage 0's `no method` text. Arrays of arrays (`int[3][4]`) are nested collections and wait for E3e.

A use of `push` or `insert` other than under `discard`, and `pop`, is the typed unsupported event `collection operations with Option or Result results` until E3b, reached where the checker resolves the method. A package where stage 0 accepts an unused proven push is `unsupported` until E3b.

**E3b** adds `Result<(), Full>` values (`?`, `match`, `unwrap`, `is_ok` and the rest E2c provides), `pop` (`Option<T>`), proven pushes, `discard`'s full rules, `Full` printing (`Full`, `err(Full)`, `ok(())`), `?.` (DESIGN "`?.` and `??`"), and sum-typed elements and struct fields of elements (one lane of whole values, see "Layout and residence"):

- **Proven pushes** are stage 0's count facts (`collection_counts`, `proven_success`, `collect_loop_pushes`, `prepare_loop_push_proofs`, `finish_loop_push_proofs`, `invalidate_collection_counts`): a fact starts at 0 from `list {}` or a default; a push outside loops is proven while the count is below N; a loop's pushes are proven when start plus pushes per iteration (if and match take the larger) times iterations fits N, with iterations from the counted range, the list's count fact, or the array's N; any nested loop disables the proof; `clear` resets it; `pop`, `insert`, `remove`, other writes and passing the list as `write` end it; branches join to the larger count; `insert` is never proven. A proven push keeps its `Result` type but may be left unused. Fixtures: t06_core's `[1, 3]`, t06_helper_ends_push_proof, t06_push_unhandled.
- **`discard`** accepts only a `Result<_, Full>` from a built-in capacity operation (push, insert, and later `try_append`, `Bytes.push`); anything else is `discard accepts only built-in operations whose Result error is capacity Full`.
- **Unused results:** `this collection operation returns a Result with error type Full; handle it with '?', 'match', or '??' where supported, or write 'discard' when dropping Full is intended`, at stage 0's text when E3b runs (PLAN's small fix to the `??` wording may land first; the self-hosted text follows it).

**Behaviour.** Printing, equality and failure messages are stage 0's bytes (`emit_print_collection_storage`, `emit_equal_sequence_storage`): `[`, the elements joined by `, `, then `]`; `[]` when empty; elements printed as E2 prints them (`[Cell { value: 0, active: false }]`, `[[4], [5, 6]]`). Lists compare counts, then live elements; arrays compare all N. Copies, equality and printing touch only live elements (T23), and the T23 dirtied-page fixtures run through the self-hosted compiler too. Helpers are per type: a collection's helper loops over its live elements and calls the element type's helper on a descriptor, so the IR stays linear in the type graph.

**E3e: nested collections, flattened.** A collection inside a collection element (directly or through a struct field) follows the layout rule: `inventory: list<Item, 8>` inside `units: list<Unit, 4096>` becomes one count lane of 4096 counts and, per `Item` field, one lane of 4096 times 8 items. The address of `units[i].inventory[j].f` is `group + lane_offset(f) + (i * 8 + j) * size(f)`. Capacity products are checked by exact layout. Copying, comparing and printing a nested value walks only live outer elements and, for each, its live inner elements. Element references are descriptors, so no gather is needed. E3e measures descriptor arithmetic on a nested-loop benchmark.

**E3e: text lanes.** A text or byte field of 64 bytes or less in an element follows the layout rule (length lane, count lane for `Text`, byte lane at full maximum). A larger one uses size classes in one flat region after the collection's metadata, with per-class free lists and handles that are a class plus a byte offset from the collection's group, never an address (T31). Stage 0's T31 fixtures are the behavioural check.

## `Ascii`, `Text` and `Bytes`

**E3c: values.**

- **`byte`.** Stage 0 defines `byte` as a built-in refinement, `int 0..=255` checked (`Checker::new`). E3c admits that one named refinement where stage 0 uses it: `Bytes` elements, `b[i]` results, `Bytes.push` arguments (E3d1), and stores, casts and proofs into `byte` with stage 0's texts and failure kinds. General refinements, `type` aliases and `fit` on refinements stay E4. Until E3c, `byte` stays in E2's unsupported type-name table.
- `Ascii max N`, `Text max N` and `Bytes max N` with stage 0's maximum rules, in locals, struct fields and payloads. A stored value holds its length, its code-point count for `Text`, and its bytes inline at full maximum (T29). Reading one gives a transient descriptor (location, length, count) that borrows the bytes.
- A collection whose element type contains text or bytes, directly or through a struct field or payload, is unsupported (`text in collections`, syntactic, from the declarations) until E3e.
- String literals and `b"..."` literals with stage 0's escape rules (`\xNN` refused above 0x7F in text). Literal bytes are constant data, copied into their destination.
- Stage 0's forms as its checker types them: `Text max N` (bytes default to 4N), `Text max N bytes max M`, `Text bytes max M`; `Ascii.empty()`, `Text.empty()`, `Bytes.empty()` taking their maximum from the destination; untyped string literals typed `Ascii max len` when all ASCII, else `Text`; `b"..."` typed `Bytes max len`.
- `len()` (`Ascii` bytes, `Text` code points), `Text.byte_len()`, `Bytes.len()`/`count()`; `b[i]` on `Bytes` only (kind 16 out of range); `.bytes()` as a temporary read-only view; `s.slice(a..b)` and `s.slice(a..=b)` (kind 16 outside the bounds; code-point positions for `Text`; see the reference fix); all six comparisons, bytewise, within one kind with any maxima and between `Text` and `Ascii`; `+` with stage 0's result maxima and its "cannot prove this concatenation fits" errors; `print`; `str`, `str_hex`, `str_bin`, `pad`, `pad_right`, `pad_zero`; `ascii_upper`; `Text.upper()` (unsupported, `upper on Text`, until E3e brings the Unicode table as constant data); the checked `(Ascii max N)(x)` cast (kind 10) and `fit<Ascii max N>()` returning `Option`; `Ascii` to a read `Text` parameter, comparison or concatenation without a copy; `validate_utf8()` (`Result<(), Utf8Error>`); `to_text()` and `to_ascii()` (`Result<_, TextError>`); number parsing (`parse_int`, `parse_long`, the radix and literal forms) returning `Option`.
- **Built-in types.** E3c adds `Utf8Error` (a struct with `valid_up_to: long`) and `TextError` (`InvalidUtf8`, `NonAscii`) as stage 0 declares them. Their cases leave E2's typed event for built-in cases; `Full` leaves it in E3b; `IoError` and `FileKind` in E3f1.
- Functions returning a growing value build into a destination the caller reserves (the fresh-result contract). Concatenation with `+` streams into its destination.
- Failure kinds and messages are stage 0's: kind 16 for slices and byte indexes, kind 10 for casts; capacity is a build error or a `Result`, never a failure.

**`Text` is validated once** (DESIGN's Decided list, core-library.md "UTF-8 in the core library"):

- validation happens only where bytes become `Text`: `Bytes`-to-`Text` conversion, `validate_utf8`, a file read into `Text` (E3f1), and literals (checked at build time);
- building `Text` from `Text` or `Ascii` pieces sums their code-point counts; code-point positions count lead bytes; printing, comparing, copying and writing check nothing;
- the core library keeps boundary validators (core/utf8_validate.nl) and trusting helpers (core/utf8_trusted.nl) in separate files;
- in test builds (`; nlc.build test`), every core routine and generated path that constructs a `Text` re-validates it and fails with kind 22, `invalid Text constructed (compiler or core library bug)` (status 70 in a test child). Program builds never run it. Stage 0 keeps its re-validation (not observable); the C runtime doesn't get the assertion, because no valid program reaches it and the C leg is gone;
- a Text-heavy benchmark (concatenating, slicing and printing) is measured for the report, against stage 0.

**E3d1: builders.** Stage 0's surface: `+=` on `Ascii` only (on `Text` and `Bytes` it is stage 0's numeric-operator error), `try_append` on all three (`Result<(), Full>`), `Bytes.push(byte)`, `take` with its move rules and texts, and append-mode variants only for functions returning `Ascii` or `Result<Ascii, E>`. The self-hosted compiler matches that surface. It builds them with append transactions (see "`grow` parameters and append transactions"), reserve-ahead regions for builders over the residence threshold, tight packing of temporaries finished before anything is placed above them, iteration scopes, and the loop-growth bound rule: a value a loop keeps growing must have a bound from its type or from a counted loop over bounded input, else stage 0's error naming the value and the loop. The DESIGN worked example (`render` and `line`) is a fixture with its output.

## Interpolated strings (E3d3)

As DESIGN "Interpolated strings" says. A new step because stage 0 has no interpolation: every fixture is `expected` class (hand-written expected output, reviewed), and the self-hosted compiler's own source keeps using concatenation until B1.

- **Syntax:** `$"..."` with `{expr}` holes and `{{`/`}}` for literal braces; holes may hold any expression of a printable type; format options `{e:N}`, `{e:0N}`, `{e:x}`, `{e:b}` on integers only (others are a build error).
- **Type:** `Ascii max N` when every literal piece and every hole is ASCII-only (numbers, bools, `Ascii`, structs and enums whose printed form is ASCII), else `Text` with the summed code-point maximum; N is the sum of the literal lengths and each hole's maximum (with its width option). Overflow of the sum is a build error.
- **Lowering:** exactly the concatenation path from E3c and E3d1, with no intermediate values: a fresh result built in its destination region; `x += $"..."` in append mode straight into the builder, with E3d1's checkpoint and rollback if a later piece fails; the `Text` code-point count summed as pieces are written. Holes use the existing formatters and print helpers, so `$"{s}"` prints exactly what `print(s)` prints.
- **Evaluation:** holes are evaluated once, left to right, under "Evaluation of arguments and operands".
- **Fixtures:** every hole type; each format option, including a width wider than the type's maximum; `{{` and `}}`; an empty `$""`; the bound exactly fitting and one over (build error); `+=` into a builder near capacity (the `try_append` failure leaves the builder unchanged); `Text` holes with four-byte characters; holes with side effects in order; a struct and an enum hole matching `print`.
- **Measurement:** the `text_format` pair in bench/vs-rust rewritten with `$"..."` (as a second next-lang version) must be no slower than the concatenation version.

## `const` (E3e)

- `const` with compile-time evaluation and constant arrays, with stage 0's rules and texts (T05): what an initialiser may use, evaluation errors at build time. Evaluated constant data isn't bounded by source bytes (`fill(7)` over a million elements is one node), so the emitter writes runs of one value as `zeroinitializer` or a startup fill, and element-by-element data only for written elements. The IR bound gains a term for written constant elements (bounded by nodes). No compiler limit is added below stage 0's accepted input policy.
- **Retiring the core library's bootstrap mechanisms** (core-library.md's retirement table): the bootstrap state block becomes a struct reached through the job context record (not by name, and not a `const`, since it changes), holding the output buffers, the file table and the scratch areas; constants-as-functions become `const`; the state-offset functions disappear. The poison table and other header-page fields stay in the context. The harness compares before and after. The same step updates the retirement table in docs/design/core-library.md.
- **Emitting only reachable functions** (PLAN small fixes): the emitter emits a user function, helper or core function only if it is reachable from `main`, a test, a hook the IR calls, or the core library's roots (`nl_core_start`, the memory functions). Unreachable functions are still checked. A fixture with an unused function and the IR-size measurement show the effect.
- **Mutable globals are removed from the language** (decided 2026-10-26): the self-hosted compiler never accepts user `global` declarations. Stage 0 still accepts them (for reference), but test packages using `global` are classified unsupported in the self-hosted comparison. Program state is now declared as a local in `main` and passed as a `write` parameter; shared state is passed to jobs as a `shared` parameter. Both state kinds stay in the design (see DESIGN.md "Mutable globals are removed"); the language now builds them differently. The core library's own constants become `const` in this step.

## File I/O and capabilities

**E3f1.** As far as file I/O needs them: the capabilities `Env`, `Fs` and `Out`; `main(env: Env)`; `main` and tests returning `Result` (an `err` prints the error and exits 1, stage 0's bytes); the built-in types `Path`, `DirEntry`, `IoError` and `FileKind` and their cases. Every existing `Fs` operation keeps stage 0's behaviour exactly; core-library.md "File I/O in the core library" is the design:

- reads into `Bytes` and `Text`, straight into the destination's bytes through the offset-taking `stack_read` function, with the probe for `TooLarge`, `EINTR` and short reads, and in-place validation for `Text`; after the reference fix, `list<byte, N>` is not a file buffer;
- `list`, `list_with_extension` and `join`, with their different rules kept;
- the plain write, with the zero-byte-write fix;
- the atomic write (`Fs.write_atomic`), with its error type and the fault-plan tests listed there; stage 0 has none, so its fixtures are `expected` class;
- the test-build temporary root (`mkdirat` with a random name from `getrandom`, removed with `getdents64` and `unlinkat`);
- the system-call context in error text;
- the `sys` operations this needs (`openat2`, `read`, `getdents64`, `fsync`, `renameat2`, `unlinkat`, `mkdirat`, `getrandom`), each with its E2c wrapper, or its offset-taking stack-buffer function where it takes a data-stack buffer.

**Core memory-function speed** (PLAN small fixes, E3f1): tune `memcpy` and `memset` (wider moves, function multiversioning for x86-64-v3 and v4 where it pays) and measure against the 1.25x bar with bench/memfn. The closure rules and the post-link call-graph test stay. Also block-wise `copy_backward` and an overlapping tail in place of the byte loops.

**Specialised copies** (E3a2 for collections and structs, E3c for text, E3e for nested lanes). Where the code generator knows a copy's facts, it emits the copy inline instead of calling `memcpy`, `memmove` or `memset`. The generic functions remain for copies of unknown shape and for LLVM's own calls. The facts and what each allows:

- **Fixed or bounded size.** A copy whose size is a compile-time constant of at most 64 bytes is straight-line loads and stores with no size test. A bounded copy (a lane's live part, a text's live bytes) uses only the tiers its maximum can reach.
- **Alignment.** Native slots, region starts and lanes have the alignment the layout section gives them; the emitted moves declare it.
- **No overlap.** A copy between two places the checker proved distinct (separate values, `write` arguments after the overlap check, a fresh hidden result) is a forward copy with no direction test. Copies between places it hasn't proved distinct keep `memmove`.
- **Padded copies.** When both the source and destination slots have room, a live length is rounded up to the move width and copied without a tail. The rounding never reads or writes past either slot's capacity (not just past the live data), and the bytes beyond the live length are never observed: equality, printing, hashing and writes use live lengths only. A fixture fills a slot, shrinks it, copies it and checks that equality, printing and a file write show no stale bytes.
- **Collections copy as one loop over their lanes** (each lane's live part, same count), not one call per lane.
- **Zeroing fresh memory.** A fill to zero is skipped only for bytes above the data stack's high-water mark, which the operating system gave zeroed and nothing has written since. Memory below the mark has been used and reused by earlier scopes, so it is filled as normal. If the high-water mark isn't tracked exactly, this item is skipped, not approximated.

Acceptance: the comparison and relocation checks unchanged; a bench/memfn variant timing each specialised form against the generic call at sizes 8, 40, 64, 256 and 4,096 bytes and on a list copy of a three-field struct (8, 64 and 1,024 elements); the report lists each form, how often the self-hosted compiler's own build emits it, and its speed-up. A form that isn't faster than the generic call is dropped.

**E3f2: the streaming file writer.** Its own step, because it is a unique resource with borrowing and exit rules no other feature has. It follows core-library.md: what the writer holds, `write`, uniqueness (no copy, no store, no return, moves only by `take`), the exclusive borrow of its buffer, `close` as the commit and `abort` that never publishes, an `abort` cleanup registered with E2i's exit function on every early exit, the failed state, and the per-job list of open writers linked by offsets. Its fixtures are `expected` class. The control-flow fixtures (each exit kind, nested scopes, loops, `?` inside a callee taking `write FileWriter`), the lifetime fixtures (a copy, a store, a use of the borrowed buffer, a buffer with a shorter scope, a second `close`, each refused at build time) and the fault-plan runtime fixtures must all pass. The self-hosted compiler's own IR output keeps its single `Bytes` write until B1: its source may use only what stage 0 accepts, and stage 0 has no streaming writer.

## Eligibility and precedence

E2's stages and precedence stay. Each step removes its constructs from the syntactic construct table and adds the events it needs:

- **E3a2:** syntactic `nested collections` (a collection type inside an element type, directly or through struct fields), `sum types in collections` (until E3b), `byte` (in E2's type-name table until E3c), `Ascii, Text and Bytes` (until E3c); the typed event `collection operations with Option or Result results`; E2's oversized-sum event, unchanged until E3b.
- **E3b:** `sum types in collections` leaves.
- **E3c:** `text in collections` (until E3e), `upper on Text` (until E3e); `byte`, text types, `Utf8Error` and `TextError` leave.
- **E3d1, E3d2, E3e, E3f1, E3f2:** the not-yet-built features keep or gain one fixed string each (`builders`, `grow parameters`, `unbounded collections`, `const declarations`, `capabilities`, `file writers`, `function values`, and so on). `global declarations` stays unsupported permanently (removed from the language, 2026-10-26).
- Typed events for built-in cases narrow as above: `TextError` in E3c, `Full` in E3b, `IoError` and `FileKind` in E3f1.

Each entry has a test in an unused function, an unreachable statement and a test block, as in E1. 

## Checker order

Errors don't have to match stage 0's order or wording (Ben, 2026-10-26). A program stage 0 rejects must be rejected with the same status, no IR written, and an error message with real text (`file:line:col: error: ...`); which error is reported first, and its exact text, may differ. The harness checks exactly that (`same_rejection` in scripts/compare-selfhost-build.py). An `unsupported` diagnostic never counts as a rejection. Each new rule (overlap, `write` and `grow` place checks, views, capacities, the loop-growth rule, `const` evaluation) has at least one fixture stage 0 rejects that the self-hosted compiler must reject too.

## The compiler's own budget

New tables (collection types, per-type lane tables, regions per function, write-parameter facts, overlap work, literal data, constants, reachable-function marks) take their capacities from the input policy's limits, listed in limits.nl with derivations, with N and N+1 tests for every limit the policy can reach. No limit is added below stage 0's accepted input policy. The IR bound gains per-entry terms for collection, lane and constant tables, the bytes of string literals (bounded by source bytes) and written constant elements. Lane offsets come from per-type tables and helpers loop at run time, so neither flattened leaves nor element counts enter the bound. A bound test sizes a nested struct-and-collection DAG far past what leaf expansion allows and checks the IR grows linearly.

## Harness

E2's protocol is unchanged, with these changes:

- **E3a1** adds the relocation check as its own script and test file, and removes the C-runtime third leg (main removes it at the merge).
- **E3d2** adds one class, `expected`: the reference compiler isn't run; the self-hosted result is compared with the package's checked-in `expected.stdout`, `expected.stderr` and `expected.status` (or `expected.diagnostic`), written by hand and reviewed. Only packages using a feature stage 0 lacks may be `expected`, and the classification file names the feature in a comment. The relocation check covers them.
- The default mode is -O1 and the core leg; `NLC_LONG_TESTS=1` adds -O3, and on main until the merge the C leg. Every step's acceptance needs both modes at zero mismatches.

## Classification

Each step reclassifies by hand, from this file, the packages it makes buildable or diagnosable, and only those, under tests/run, tests/test, tests/e1, tests/e2 and tests/e3. It lists every movement with old and new class, and every expected-output change from a reference fix. The report gives counts per class before and after. New directed fixtures go under tests/e3/, grouped by step (tests/e3/a1_*, a2_*, merge_*, b_*, ...), and are classified when added.

## Directed fixtures

Beyond those named in the sections above, each step covers, with exact output at both optimisation levels:

- **E2i:** the evaluation audit fixtures.
- **E3a1:** the core tests for growth, verification, the pin refusal, the poison table and statistics; the two-phase relocation test; the context-offset test; one contract fixture per hook; the E1 and E2 suites through the relocation check at threshold 0; regions freed at block exit, `break`, `continue` and `return` (a loop allocating a large region a million times stays bounded, under the threshold option).
- **E3a2:** every array and list form in the table; index failures at both ends, with output before; element and field assignment and compound assignment with overflow at the operator; evaluation order of receiver, index and arguments (each once, in source order); copies independent of their source; equality and printing including empty lists and lists that held more elements earlier (no stale element shows); writable views changing fields; each view refusal; values just under and just over 4,096 bytes (native slot versus region) and one over 64 KiB; a small struct holding a list (native) and a large one (region); a list of structs with a `bool` field (one-byte lanes); the `write`, evaluation and relocation fixtures.
- **merge:** the merge validation fixtures.
- **E3b:** `Full` from `push` and `insert` at capacity, with the list unchanged; `?` on a push inside a function returning `Result`; `pop` with `??` and `match`; proven pushes accepted and unproven ones refused, as stage 0 decides; `discard` refusals; `?.` flattening; lists of enums and of structs with `Option` fields; the `write` store-back fixtures on `?`.
- **E3c:** literals with every escape; a four-byte character at the declared maximum; slicing on code-point boundaries, inclusive and exclusive; comparisons; conversions succeeding and failing; `validate_utf8` on invalid input; `byte` stores and casts in and out of range; fresh results returned and nested; text fields in structs and payloads; the kind-22 assertion with an injected bad construction (a core test only).
- **E3d1:** the render example; three builders open at once; a failed append leaving no partial result, and the checkpoint restored in nested appends; the published-then-error `grow` helper; `continue` and `break` discarding iteration scratch while keeping the outer builder; the loop-growth error; `s = s + s`; `out.append(f(out))` as DESIGN's step 2 cases say; the `grow` width fixtures.
- **E3d2:** the unbounded and starting-size fixtures.
- **E3e:** `const` arrays, including a large `fill`; shared state with constant and startup initialisers passed as a `shared` parameter; program state written through `write` parameters (passed from `main`); nested lists of structs (counts per outer element, independent; a loop over all nested items); a nested subcollection passed as a parameter; text lanes at 64 and 65 bytes, and a text moving between classes at capacity (T31's cases); the reachable-function fixture; the core library unchanged in behaviour after the state-block retirement.
- **E3f1:** stage 0's T20 fixtures and the T24 and T25 file cases; the fault-plan cases for reads, writes and the atomic write; `main` returning `err`; the two fixes' fixtures.
- **E3f2:** the writer's control-flow, lifetime and fault-plan fixtures.

Generated cases: the E1/E2 generator gains arrays, lists, element writes and `write` arguments (with seeded overlap errors and later-argument effects) in E3a2, and text in E3c. `cargo test` runs a fixed seed set; each report covers a larger run.

## Measurements

As E2's rules (release builds, `ulimit -v 8000000`, the bench lock, best of five with the spread and conditions). Per step, as it applies:

- scalar and aggregate regression: E1's and E2's benchmarks against the previous step's baseline; for E3a2, E2's struct-parameter benchmark under the descriptor ABI;
- E3a1: growth cost (moves and microseconds per move) from the stats line, and the cost of the threshold-0 build of the E2 aggregate benchmark against the normal build;
- E3a2: a tight list loop, a struct-of-arrays loop over two fields, and a `write`-parameter call loop, each built by both compilers, run for at least a second with a checksum, output to a file, with an empty program's time beside them;
- the merge: E2b's, E2c's and E3a2's measurements again on the merged tree;
- E3c and E3d1: the Text-heavy benchmark and a builder benchmark, both compilers;
- E3d2: a large unbounded push loop: wall time, `initial`, `reserved` and `peak_used` from the stats line, and peak RSS, each labelled with its measure;
- E3e: IR bytes per source byte before and after reachable-only emission, on the self-hosted compiler's own source compiled as a package if the subset allows it by then, else on the generated benchmark; the nested-loop benchmark with descriptor arithmetic;
- E3a2, E3c and E3e: the specialised-copy benchmark (see "Specialised copies"), for the forms each step adds;
- E3f1: bench/memfn before and after; a file-heavy program, both compilers;
- every step: bootstrap time and `nlc inspect stacks selfhost` (what its tables add).

## Not part of E3

- Maps, sets, pools, queues, rings, grids and ids; refinements other than `byte`, `type` aliases, `fit` on int and long refinements, `wrap`, `clamp`; generics; function values (the fixtures are written, classed `unsupported`); `recursive` functions and the native-stack budget; sorting; number parsing beyond what E3c's conversions need (E4 and later).
- The cap as a growth limit, `stack_reserve`, `strict_stack`, pooling, trimming, written-page tracking, admission, jobs and asynchronous I/O pinning (later tasks; manifest keys for them stay rejected).
- The rows layout as a per-collection opt-out for bounded collections (PLAN item 7); E3 uses rows only for unbounded collections.
- Self-compilation, the stage 2 and stage 3 check, per-file IR modules and parallel clang.
- String-literal patterns in `match`.

## Report

docs/tasks/E2i-report.md, E3a1-report.md, E3a2-report.md (which also covers the merge), E3b-report.md, E3c-report.md, E3d1-report.md, E3d2-report.md, E3e-report.md, E3f1-report.md and E3f2-report.md, each covering: the counts per class before and after, movements and expected-output changes; reference fixes and their fixtures; the checker order as extended and any difference from this file; the construct table as it now stands; the interfaces and ABI as built (type kinds, the location descriptor, region planning, growth points, the exit function and its cleanups); shared functions edited outside the ownership table, with reasons; the merge's steps and movements; the relocation check's positive evidence; the measurements, each labelled with its measure; what was awkward to write in next-lang; and the plan for the next step.
