# E3: the self-hosted compiler gains collections, text, `write` parameters and a growing data stack

Depends on E2a (layout, structs, shared helpers, the single addressing function). Parts after E3a also depend on E2b and E2c (see "Parts and order"). Read docs/PLAN.md "Stage 0 freeze" and Order of work items 4 and 5, DESIGN.md "The theory being tested", "Collections", "Layout", "The job's data stack" (offsets, starting size, growth, unbounded collections at the tail), "How the compiler places values", "Loops can't quietly fill a stack", "Text, ASCII and bytes" and the Decided list, docs/design/core-library.md (the retirement table, "Retiring the hook ABI", "File I/O in the core library", "UTF-8 in the core library", "The stack is pinned while the kernel holds an address into it"), E1's and E2's specs, reports and reviews, docs/reviews/sol-E1-r1.md and sol-E2-r1.md, and the stage-0 task reports T05, T06, T08, T13 to T17, T20, T23 to T25, T29 to T31 and O1.

E1's and E2's specs hold for everything this file does not change: the harness protocol, the classes, unsupported-before-checker-error precedence with typed events, exact first errors in Rust's order, the compiler's own budget, and the report shape.

Rust code is cited by function name. Line numbers drift.

## Scope

- Rust nlc is stage 0 and the behavioural reference. The two compilers are compared by stdout, stderr and exit status, never by IR or internal layout. For a feature stage 0 lacks (unbounded collections, the starting-size estimate, the atomic write, the streaming writer), the reference is the fixture's checked-in `expected.*` files (see "Harness").
- E3 widens the self-hosted subset to: fixed arrays and lists; `Ascii`, `Text` and `Bytes` values and builders; `const` and `global`; `write` and `grow` parameters with the overlap check; data-stack regions with the core library's moving stack; unbounded local collections and builders at the stack's tail; the typical-run starting size; `Full` and capacity results, `discard` and `?.`; file I/O through the core library; nested collections in the flattened target layout.
- The core library moves up with it: the state block becomes a `global`, constants become `const`, buffers become `Bytes`, the hook ABI becomes context-passing, and the core library gains the stack growth, UTF-8 and file I/O routines.
- The subset stays closed. Everything a part doesn't build fails closed as unsupported, with one fixed construct-table string each, until the part that builds it.

## Parts and order

E3 is too large for one session. It is split into six parts. Each part is one session, ends with both full suites passing (`NLC_FRONTEND=rust` and `selfhost`), the default and long comparison modes at zero mismatches, `cargo fmt --all -- --check`, and its own report (docs/tasks/E3a-report.md and so on). Each part leaves everything not yet built failing closed.

| Part | Contents | Starts after |
| --- | --- | --- |
| **E3a** | data-stack regions and the core library's stack growth (offsets, `mremap`, guard page, `NLC_STACK_VERIFY`, `NLC_STACK_STATS`), the forced-relocation tests deferred from E1c; the addressing function in offset form; fixed arrays and `list` of scalars and structs (no text elements, no nested collections); indexing, element assignment, `len`/`count`, literals and `fill`; `for` over collections and writable views; `discard` on `push` and `insert`; `remove` and `clear`; collection copy, equality and printing helpers; `write` parameters for every type E3a has, with the overlap check; values over 4096 bytes in regions | E2a lands. Runs in a worktree, in parallel with E2b and E2c |
| **E3b** | `Full`, capacity results as `Result<(), Full>` values, `pop` (the one `Option`-returning list method), proven pushes, `discard` in full, `?.`; sum types over 4096 bytes in regions; the `write` copy-back fixtures on `?` | E2c and E3a land |
| **E3c** | `Ascii`, `Text` and `Bytes` as stored values (inline at their maximum), string and byte literals, `len`, byte access, slicing, equality and comparisons, `print`, `str`, conversions and `validate_utf8`, fresh-result destinations for growing results, `Text` validated once and trusted after, the test-build re-validation assertion | E3b lands |
| **E3d** | the context-passing hook ABI (retiring the C-runtime third leg), builders: append mode with checkpoints, `+=`, `try_append`, `Bytes.push`, `grow` parameters, iteration scopes and the loop-growth bound rule, the in-place reassignment rule (T30), unbounded local collections and builders at the stack's tail, the typical-run starting size, the `expected`-only harness class | E3c lands |
| **E3e** | `const` and constant arrays, `global` with startup initialisation and the startup claim, retiring the core state block and constants-as-functions, nested collections in the flattened layout, text and byte fields in collection lanes, emitting only reachable functions | E3d lands |
| **E3f** | `Env`, `Fs` and `Out` as far as file I/O needs them, `main` and tests returning `Result`, `IoError` and `FileKind`, file reads, writes, listings and joins in the core library, the atomic write, the streaming file writer, the test-build temporary root, the `list<byte, N>` read reference fix, core memory-function speed | E3e lands |

**Nested collections belong in E3 (E3e), not E4.** The self-hosted compiler has its own layout, and E3a's addressing function already takes lanes. Building nested collections inline per element first (stage 0's T06 form) would be rewritten one task later, as E2 avoided for the state-block struct. E3e is the first part that has every element kind nested collections need (text lanes, collection fields in structs). Until E3e, a collection type inside a collection element or a struct field of a collection element is unsupported (`nested collections`).

**Text lanes over 64 bytes** (size classes, T31) are in E3e. If E3e runs out of room, size-class lanes may fail closed (`text fields over 64 bytes in collections`) and move to E4; the E3e report says so. Inline lanes up to 64 bytes are not optional in E3e.

## Parallel work

E3a runs in its own git worktree while E2b (enums, `match`) and E2c (`Option`, `Result`, `?`, `??`, the core error wrappers) continue in the main checkout. The rules:

1. **Starting point.** E3a branches from main after E2a's commit. It reads E2a's layout table, type table, shared helpers and addressing function as they landed, and builds on them.
2. **No dependency on E2b or E2c.** E3a uses no enum, `match`, `Option`, `Result`, `?` or `??` code paths, in the compiler or in the core library. Operations whose result is an `Option` or a `Result` (`pop`, and `push` or `insert` used other than under `discard`) stay unsupported in E3a (a typed event, see "E3a: lists"), except `discard xs.push(v)` and `discard xs.insert(i, v)`, which drop the result without making a `Result` value. Core-library code that E3a adds (core/stack.nl) uses the E1c raw-result convention (`sys.is_error` at the call site). The merge converts it to E2c's wrappers if E2c has landed by then (see 7).
3. **New files.** E3a's code goes in new files where it can:
   - selfhost/regions.nl: region planning, the top and base caches, growth points, offset addressing;
   - selfhost/collections.nl: array and list types, layout, checking and emission of collection expressions, statements and helpers;
   - selfhost/params.nl: `write` parameter checking (places, the overlap check) and lowering (passing, register caching, copy-back);
   - core/stack.nl: the core library's stack growth, verification and statistics.
4. **Shared code: small, additive and delimited.** Edits to selfhost/compiler.nl, selfhost/limits.nl and selfhost/main.nl are additive and marked with `// E3a begin` and `// E3a end` comment lines, so a merge sees small separate hunks. E3a must extend only these shared tables and functions, each with a one-branch hook into the new files:
   - the type table and its constants: new entries for array and list types, with a type-kind field. If E2a's type record has no kind field, E3a adds one; it never renumbers the existing `TY_*` constants;
   - `CompilerTables`, `empty_compiler_tables` and `reset_compiler_tables`: new tables (collection types, regions per function, write-parameter facts) appended at the end of the struct;
   - `value_type_size` and `value_type_align`, `resolve_value_type`, `known_non_scalar_type` and `is_builtin_type_name`: the collection types;
   - `unsupported_category_for_node` and `unsupported_node_message`: E3a's nodes leave the unsupported table, and E3a's new construct strings join it;
   - `natural_node_type` and `check_one_body`: one dispatch branch per new node kind, calling into collections.nl or params.nl;
   - `register_package_declarations`: parameter modes;
   - `emit_layout_address` (the single addressing function), `emit_aggregate_copy`, `emit_store_scalar` and `emit_load_scalar`: the offset form;
   - `emit_expr_linear`, `emit_function_body` and `emit_function_definition`: one dispatch branch per new node kind, region entry and exit, the `write` ABI;
   - `core_sys_operation`, `core_sys_argument_count`, `core_sys_argument_type` and `core_sys_result_type`: `sys.remap`, `sys.unmap`, `sys.stack_addr`, `sys.stack_load8`, `sys.stack_store8`;
   - the hook table: the stack-growth hook;
   - limits.nl: new capacities appended in one delimited block, each with its derivation;
   - the frame-budget walk (`populate_frame_slot_bytes` and its callers): region bytes are not native-slot bytes.

   If another shared function must change, the E3a report lists it with the reason.
5. **Generated and shared data files.** selfhost/core_files.nl is never merged by hand: after any merge, regenerate it with scripts/embed-core.sh. tests/e1/classification.tsv gets E3a's new fixtures in one block at the end, between `# E3a begin` and `# E3a end` comment lines. E3a moves an existing row only for a package that E3a alone makes buildable or diagnosable. scripts/compare-selfhost-build.py is not edited in E3a; new checks go in new scripts and new test files (scripts/check-selfhost-relocation.py, compiler/tests/selfhost_relocation.rs).
6. **Separate build state.** The worktree uses its own Cargo target directory (`CARGO_TARGET_DIR=$HOME/.cache/next-lang/target-e3a`) so its self-hosted build cache and its lock don't contend with the main checkout. Benchmarks take the WSL bench lock as always.
7. **The merge.** When E3a is done, it is rebased onto main as it then stands (with E2b, E2c or both). The merge step: resolve the delimited hunks; regenerate core_files.nl; convert core/stack.nl's raw results to E2c's wrappers if E2c has landed (E2c's wrapper test must pass); reclassify by hand the packages that need both E3a's and E2b/E2c's features (they stay `unsupported` on each branch alone), listing each movement; rerun both full suites and both comparison modes. E3b starts only after the merge.
8. **Stage 0 is untouched in E3a.** No reference fix is needed for E3a's features (see "Reference fixes"), so the worktree can't conflict with stage-0 edits in E2b or E2c.

## Reference fixes in stage 0

Stage 0 takes a fix only where its observable behaviour contradicts DESIGN.md and the self-hosted compiler can't be tested without it. Each fix lands with fixtures and updated `expected.*` files, in the part named, and the part's report lists it.

1. **E3f: one byte-buffer read form.** DESIGN.md says `Bytes` is the one byte-buffer I/O form (O5's planned change). Stage 0 still reads files into `list<byte, N>` (the `list<byte, N>` branch where emit.rs chooses between `nl_fs_read` and `nl_fs_read_string`). The self-hosted compiler doesn't build that form, so without the fix those fixtures stay unsupported forever and parity (PLAN item 5) can't be reached. Migrate the fixtures that read into `list<byte, N>` to `Bytes`, and make the form a checker error in stage 0 (`read files into Bytes; list<byte, N> is not a file buffer`), with a fixture. Remove `nl_fs_read` from runtime/nl_runtime.c.
2. **E3f: a zero-byte write is `EIO`.** The C runtime reports `errno ? errno : EIO` for a `write` that returns 0, which can pick up a stale `errno` (core-library.md, "Output buffering"). Once `Out` and `Fs` writes are in the self-hosted subset this is observable as `IoError.Other(n)`. Make the C runtime use `EIO`.
3. **E3c: `slice(a..=b)`.** Stage 0 accepts an inclusive range in `s.slice(a..=b)` but treats the end as exclusive. DESIGN says `..=` always includes its end. Fix stage 0 to include it, with a fixture at both ends (including `..=` at the last code point and one past it, kind 16).
4. **E3c, if needed: `sys` names in user code.** core-library.md recommends one message in both compilers, `sys operations are available only to the core library`, once method calls are in the self-hosted subset. If E3c's method calls make a user `sys.write(...)` reach the self-hosted checker, add that message to stage 0 at its name resolution, and to the self-hosted checker, with the privilege fixtures.

Not fixes (unobservable, so stage 0 keeps them): stage 0's pointer mode and its up-front reservation; its re-validation of `Text` (`emit_text_to_data`'s `nl_utf8_count`, `nl_utf8_offset`); its gather-and-scatter of collection elements passed as `write` (exclusivity makes copy-in, copy-out invisible); its inline nested lanes; its 256 KiB offset-mode start. If an implementer finds another place where stage 0 contradicts DESIGN.md observably, they fix it in stage 0 with a fixture and list it, or, if it is unclear, keep stage 0's behaviour and list it as a question.

## `write` parameters

A `write` parameter is a reference to the caller's storage, for every type, scalars included: `fn bump(x: write int) { x += 1 }` changes the caller's `n` in `bump(n)`. That matches stage 0 (the T04 and T11 fixtures). Read is the default and is unwritten; `write` is written before the type (`g: write Game`).

**What stage 0 does.** Stage 0 passes every `write` (and `grow`) argument as a pointer to the caller's storage (`lower_signature_mode`, `emit_call_argument`); the callee reads and writes through it (`local_pointer`), so there is no copy-in or copy-out for scalars or plain places. The only copy-back is T13's gather and scatter of a struct element of a collection (`emit_gather_collection_element`, `emit_scatter_collection_element`, `finish_call_argument_regions`): the scatter runs after the call returns, so also after the callee returned early through `?` (tests/run/t13_soa_gather, `bump_then_fail`); a `-> never` callee gets none. Because exclusivity holds, the self-hosted compiler may use either form; only behaviour is compared.

**What may be passed.** The argument must be a place (stage 0's `resolve_place`): a name, a `.field` path, `xs[i]` on an array or list (and later the other collections), rooted at something `place_is_mutable` accepts: a `var` local, a `write` or `grow` parameter, a writable loop view, and from E3e a `global`. The argument is written bare, as in stage 0. Stage 0's texts, all pinned by its fixtures:

- a temporary or literal: `a write argument must be an assignable place` (t04_write_temporary, t16_bytes_view_write);
- a `let`, a read parameter or a constant: `a write argument must be a var, a field of a var, or another write parameter` (t04_write_let, t04_read_forward);
- a different type, including a different refinement or `wrap`/`clamp` policy: `write argument needs exactly {param}; found {arg}` (t04_write_policy_mismatch, t04_write_refined_mismatch, t16_text_write_ascii);
- storage under a live view: `cannot pass storage containing a live collection view as write` (t06_view_write_collection, t06_nested_write_element);
- inside the callee, assigning to a read parameter: `cannot assign to read parameter '{}'; pass it as 'write' to allow mutation`;
- a `write` text may not grow: `appending through a parameter requires 'grow' mode; 'write' cannot increase its length` and the `try_append`/`push` variants (E3c, E3d).

**Exclusivity.** No argument passed `write` or `grow` may overlap another argument of the same call (stage 0: `places_overlap`, `places_proven_prefix`, `canonical_place`, checked against every earlier argument when either mode is not read). Places overlap only with the same root after view expansion, when one path is a prefix of the other: two different fields are apart; two constant indexes that differ are apart; any other pair of indexes (`values[i]` and `values[j]`) overlaps. The text is `arguments overlap, and at least one is passed as write; pass separate fields or a copy` (t04_overlap_same, t04_overlap_same_reverse, t04_overlap_child_first, t04_overlap_parent_first, t06_overlap_child_first, t06_overlap_parent_first, t06_overlap_unknown_indexes, t06_overlap_params_unknown). From E3e, stage 0's hidden-global check applies too (`check_global_access_contracts`: `write argument '{}' overlaps hidden global access in '{}'; pass separate fields or remove the by-name access`, t08_global_overlap). Stage 0 emits `noalias` only where this proof holds and the callee has no hidden result destination; the self-hosted compiler may do the same.

**How the self-hosted compiler passes it.** The ABI depends only on the parameter's type, so the callee has one form:

- **Native-resident types** (scalars, and aggregates of 4096 bytes or less, which live in native-stack slots, E2's rule): the caller passes the address (`ptr`) of a native-stack cell holding the value. The native stack never moves, so the address stays valid across every growth point.
  - When the argument's storage is a native-stack slot (a local, or a field path inside one), the caller passes that slot's address plus the field offset, from the addressing function.
  - When the argument's storage is not a native-stack slot (an element or lane of a collection on the data stack, a field of a data-stack value, a global), the caller copies the value into a fresh native cell, passes its address, and after the call copies the cell back to the place, re-deriving the place's address from its offset after the call (the call may have grown the stack). For a struct element of a collection that is a gather from the lanes into the cell and a scatter back, as stage 0 does. Exclusivity makes the copy invisible.
- **Data-stack-resident types** (collections, `Ascii`, `Text`, `Bytes`, and any value over 4096 bytes): the caller passes an `i64` offset from the job's stack base. The callee derives an address from the cached base only for each access and reloads the base after every growth point (see "Offsets and growth points").
- An element of a collection passed to a data-stack-resident parameter (a collection-typed or text-typed element, from E3c and E3e) is passed as an offset where its storage is contiguous. Where it isn't (lanes), see E3e: element references.

**Register caching and copy-back.** Because no other argument can alias a `write` argument, the callee may load a scalar `write` value into an SSA register at entry, work on the register, and store it back through the pointer before it leaves. The store happens on every exit: each `return`, the fall-through end, and (from E3b) each `?` that propagates an error and each `?? return`. A runtime failure needs no store: the job ends and nothing reads the caller's value after it. A call that passes the cached value on (as another `write` argument, or to a read parameter) stores it first and reloads it after a `write` pass. The emitter may instead keep every access in memory; the choice must not be observable.

**Function values.** A parameter's mode is part of a function type (`fn(write int) -> ()`, stage 0's `TFunctionTypeParam`), so an indirect call passes `write` arguments in the same ABI as a direct call, and the place, overlap and view rules apply at the indirect call site (`check_indirect_call`). A mismatch is `function parameter {n} mode mismatch: expected {read|write|grow}, found {...}` (t11_mode_mismatch); t11_write_function_value prints 41. Function values themselves are E4 (PLAN item 5); E3 writes the fixtures now, classed `unsupported` (`function values`), and E4 moves them to `build`. The ABI above is the contract E4 follows.

**Fixtures** (tests/e3/write_*), each at both optimisation levels:

- scalar `write` parameters of `int`, `long` and `bool`, printed in the caller after the call;
- repeated calls on the same variable, and a call inside a loop;
- a `write` parameter forwarded to another function's `write` parameter, and to a read parameter;
- a field path (`bump(s.inner.count)`), on a native struct and on a struct element of a list (`bump(units[i].hp)`), with the stack forced to move inside the callee;
- a collection element of scalar type (`bump(xs[2])`), and a whole collection (`fill_all(xs)`);
- an overflow failure inside the callee after earlier writes (the caller's value is not observed, the output before the failure is);
- aliasing refused: the same place twice, an element and its collection, a field and its struct, two elements with unproven indexes; allowed: two different fields, two constant different indexes;
- each refused argument form (`let`, read parameter, loop counter, literal, call result);
- through a function value (classed `unsupported` until E4);
- copy-back on a `?` failure and on `?? return` (E3b, when `?` is in the subset): the callee changes the value, then propagates; the caller sees the changed value.

## `grow` parameters (E3d)

A `grow` parameter is a builder in its caller's reserved region; the callee appends within the region (DESIGN "How the compiler places values"). Stage 0 allows it only on `Ascii`, `Text` and `Bytes` (`grow parameters are for Ascii, Text, and Bytes builders; use read or write for other types`) and passes it like `write`, a pointer to the inline storage, with appends bounded by the parameter's maximum. The self-hosted compiler passes the builder's offset; the callee publishes the new length only on success.

**Reference fix (E3d): the `grow` width check.** Stage 0's message is `grow argument needs an {Ascii|Text|Bytes} builder with at least {param max} bytes reserved; found {arg type}`, but its test (`string_width_fits(place.ty, param.ty)`) appears to accept a caller builder smaller than the parameter's maximum, while the callee bounds appends by the larger parameter maximum: a write past the caller's region. No fixture pins it. E3d confirms it with a fixture and, if confirmed, fixes stage 0 to require the argument's maximum to be at least the parameter's, as the message says. `Ascii` passed to a `grow Text` parameter needs stage 0's conversion rules (DESIGN "Text, ASCII and bytes"). The overlap check covers `grow` arguments like `write` ones. Fixtures: a helper that appends twice, nested `grow` forwarding, a failure inside the callee that restores the checkpoint, and the T30 in-place reassignment (`buffer = f(buffer)`), which updates in place exactly when T30's rule says.

## Data-stack regions, growth and offsets (E3a)

**Where values live.** E2's rule stays for values of 4096 bytes or less (native-stack slots). A local, temporary, snapshot or result of more than 4096 bytes, and every collection, `Ascii`, `Text` or `Bytes` local, gets a region on the job's data stack instead. E2's `value types larger than 4096 bytes` entry leaves the construct table for structs and collections in E3a, and for sum types in E3b.

**Region planning.** A function plans the regions of each block's locals at block entry, as T30 orders them: regions of 64 KiB or less first, then the larger ones. Leaving a block (fall-through, `break`, `continue`, `return`, later `?`) resets the top to the block's entry top. Each loop iteration is a scope. The hidden result destination of a large result is a region the caller reserves, passed as an offset.

**Allocation.** Taking a region is an inline bump of the cached top: align, add, compare with the cached limit. Only the slow path calls the growth hook. The hook keeps stage 0's offset-mode C signature (`nl_stack_alloc_offset(ctx, top, bytes, alignment, file, line, col) -> i64`, runtime/nl_runtime.c), so the third leg still links against the C runtime until E3d retires it. The core library implements it in core/stack.nl with the C runtime's behaviour: double until it fits (or take the request), round to pages, map a new range, `mremap` with `MREMAP_MAYMOVE | MREMAP_FIXED` into it, unmap the old guard page, and fail with kind 18 and the same message on any failure.

**Offsets and growth points.** Every reference generated code keeps into the data stack is an `i64` offset: regions, collection lanes, text payloads, views, data-stack-resident `write` and read arguments, hidden destinations and the top. The function caches the base and the limit in SSA values.

- A **growth point** is any call that may grow the stack: the growth hook's slow path and any call to a function whose stack contract can place regions (conservatively, every call except to functions the compiler proves place none, and the core hooks that don't).
- After a growth point the base and limit are reloaded from the context. The emitter never holds a derived address across a growth point. This is an emitter invariant, enforced by construction: addresses come only from the addressing function, at the access.
- **The addressing function changes in one place.** `emit_layout_address` takes a base form (a native slot pointer, or a data-stack offset with the current cached base) and a constant offset from the layout table, plus, for collections, a lane and an index (see "Arrays and lists: layout"). For an offset base it emits `getelementptr i8, ptr %base, i64 (offset + constant)` at the access. No other emitter code computes a data-stack address. E2's constant field offsets carry over unchanged.
- The top is written back to the context before a call that can reach the stack and at exits, as stage 0's offset mode does.

**Core library.** E3a adds `sys.remap` and `sys.unmap`, and the data-stack operations `sys.stack_addr`, `sys.stack_load8` and `sys.stack_store8` with the syntax rule and the two-phase lowering of core-library.md "The stack is pinned while the kernel holds an address into it". The context gains a pin count; the grow routine refuses growth while it is above zero (no E3a code pins; the count and the refusal are tested by a core test). `NLC_STACK_VERIFY=1` poisons each old mapping as the C runtime does; `NLC_STACK_STATS=1` prints the C runtime's line after the final flush. The core library's context layout becomes shared with generated code here (the inline bump reads the limit): declare it once in core and take field offsets from that declaration, never a second copy (core-library.md "The data stack in E1c").

**Forced-relocation tests** (deferred from E1c):

- the core test from core-library.md: a system-call operation whose later argument grows the stack by a forced move; the kernel sees the new range and the old range is never touched;
- a test-build-only switch, `NLC_TEST_STACK_FORCE_MOVE=1`, read by the core grow routine, that makes every growth move to a fresh range and start from one page. A new check (scripts/check-selfhost-relocation.py, run by compiler/tests/selfhost_relocation.rs) runs every `build` and test package that allocates regions through the self-hosted compiler, core leg only, with that switch and `NLC_STACK_VERIFY=1`, at -O1 and -O3, and compares stdout, stderr and status with the ordinary run. Every relocation must be invisible;
- directed fixtures: a `write` element argument whose callee forces growth; a collection read parameter used after a callee grows; a loop over a list whose body calls a growing function; a large result destination filled after growth.

**The C leg.** Stage 0's C runtime in offset mode starts at 256 KiB. The core library does the same in E3a (the starting-size estimate is E3d). Growth counts differ between legs only under `NLC_STACK_STATS`, which the harness leaves unset.

## Starting size (E3d)

DESIGN "Starting size": per entry point, a typical-run estimate from the same analysis as the worst case, with every loop counted at most 5 times and recursion at most 5 levels; values not built in a loop count at their computed size. The first stack starts at the estimate rounded up to a power of two, at least one page, plus the guard page. `NLC_STACK_PREALLOC=1` still starts at the worst case.

- The self-hosted compiler computes both the worst case (as the E1 reservation does now, extended to regions) and the estimate, and passes both to the core library through the context-passing ABI (E3d's first step), which is why the estimate waits for E3d.
- An unbounded collection or builder counts at 5 elements in the estimate and makes the worst case "unbounded".
- Not observable in the comparison. A core test and a directed fixture check it with `NLC_STACK_STATS=1` (the reported starting reservation equals the expected power of two) on packages whose estimates are worked out by hand in the fixture's comment, including one with a loop of 1000 pushes (estimate counts 5) and one with a single large region.

## Unbounded collections and builders at the stack's tail (E3d)

DESIGN "Unbounded collections grow at the stack's tail". Stage 0 doesn't have them, so their fixtures are `expected` class (see "Harness").

- `list<T, unbounded>`, `Text max unbounded`, `Ascii max unbounded` and `Bytes max unbounded` as locals only. In a global, a struct field, a collection element, a parameter type other than `write`/`grow`/read of a local, or a `strict_stack` entry point (rejected anyway until `strict_stack` exists), it is a build error naming the place.
- Storage is the top region; growth bumps the top, inline, with the usual slow path. A growth point (`push`, `try_append`, `+=`) is allowed only while the value is the topmost live region; growing after a longer-lived region was created above it is a build error naming both values and suggesting finishing the collection first or creating the other value earlier.
- Opening a second unbounded value while the first is alive freezes the first until the second's scope ends; a growth of the frozen one is the same build error.
- A function may build one at its top and return it: the region becomes the caller's top region without a copy.
- Messages are new texts, written in this task and pinned by fixtures. A `push` onto an unbounded list has no `Full` and returns `()`. The cap (`data stack range exhausted`) is a later self-hosted task; until it lands, growth that can't be mapped fails with kind 18, as other growth does.
- Fixtures: a 1,000,000-element push loop; builder appends of mixed sizes; a return to the caller and further growth there; each build error; a temporary call between pushes (allowed: its regions are gone when it returns).

## Arrays and lists

**E3a: types and operations.**

| Form | Notes |
| --- | --- |
| `T[N]`, `list<T, N>` | `T` a scalar or a struct whose fields are E3a types; `N` a constant expression (`capacity_value`: literals, unary `-`, `+ - * / %`; `const` names from E3e). Zero is allowed. Stage 0's texts: `collection capacity must be a constant integer expression; use a literal or const value`, `list capacity cannot be negative; use zero or a positive constant` (and the array form), `collection size overflows long; reduce a capacity` |
| `[a, b, c]` literals | need an expected type (`cannot infer whether this literal is an array or list; add a T[N] or list<T, N> annotation`); an array literal has exactly N elements, a list literal at most N, with stage 0's texts |
| `list {}` | the bare form only, with an expected list type (`cannot infer the capacity for 'list {}'; add a list<T, N> type annotation`) |
| `fill(v)` | arrays only (grids later), one argument, evaluated once, stage 0's texts |
| an omitted initialiser (`let x: T`) | stage 0's `default_typed_value` for collections: an empty list, an array of the element's default |
| `a[i]`, `a[i] = v`, `a[i].f = v`, compound assignment on elements | indexes are `long` (`collection indexes are long; cast an int index with .to_long()`; an unsuffixed literal is fine); a bad index fails with kind 16, `index out of range`, at the index expression's position, before any store; stage 0's proven-index elision is not observable and may be skipped |
| `a.len()` on arrays, `xs.count()` on lists | `len` is a constant `long`; `count` is `long 0..=N` (the refinement matters only from E4) |
| `discard xs.push(v)`, `discard xs.insert(i, v)` | on a full list nothing changes and nothing fails; `insert` checks `0 <= i <= count` first (kind 16 at the index argument) |
| `xs.remove(i)` (returns the element, kind 16 outside `0 <= i < count`, shifts down) and `xs.clear()` | refused under a live view: `cannot call '{T}.{m}' while a collection view is live; move the operation after the loop` |
| `for x in coll`, `for x, i in coll` | the length is snapshotted at entry (pushes inside the loop aren't visited); over a mutable place, `x` is a writable view aliasing `coll[i]`; stage 0's view and loop texts (`cannot replace or modify storage that contains a live collection view`, `cannot assign to loop counter 'index'; loop counters are immutable`, `collection iteration needs a local, parameter, or field place; bind the value to a local first`) |
| `print`, `==`, `!=`, copies, read and `write` parameters, results | equality needs identical types; no ordering on collections |

Lists have exactly `push`, `pop`, `insert`, `remove`, `count` and `clear` in stage 0 (no `get`, no `len`); an unknown method is stage 0's `no method` text. Arrays of arrays (`int[3][4]`, the first cap innermost) are nested collections and wait for E3e like other nesting.

A use of `push` or `insert` other than under `discard`, and every method whose result is an `Option` or a `Result`, is the typed unsupported event `collection operations with Option or Result results` in E3a, reached where the checker resolves the method. A package where stage 0 accepts an unused proven push is therefore `unsupported` in E3a and `build` in E3b.

**E3b** adds the `Result<(), Full>` values (`?`, `match`, `unwrap`, `is_ok` and the rest E2c provides), `pop` (`Option<T>`), proven pushes, `discard`'s full rules, `Full` printing (`Full`, `err(Full)`, `ok(())`), and `?.` (DESIGN "`?.` and `??`"):

- **Proven pushes** are stage 0's count facts (`collection_counts`, `proven_success`, `collect_loop_pushes`, `prepare_loop_push_proofs`, `finish_loop_push_proofs`, `invalidate_collection_counts`): a fact starts at 0 from `list {}` or a default; a push outside loops is proven while the count is below N; a loop's pushes are proven when start plus pushes per iteration (if and match take the larger) times iterations fits N, with iterations from the counted range, the list's count fact, or the array's N; any nested loop disables the proof; `clear` resets it; `pop`, `insert`, `remove`, other writes and passing the list as `write` end it; branches join to the larger count; `insert` is never proven. A proven push keeps its `Result` type but may be left unused. Fixtures: t06_core's `[1, 3]`, t06_helper_ends_push_proof, t06_push_unhandled.
- **`discard`** accepts only a `Result<_, Full>` from a built-in capacity operation (push, insert, and from later parts `try_append`, `Bytes.push`, pool, map and set adds); anything else is `discard accepts only built-in operations whose Result error is capacity Full`.
- **Unused results:** `this collection operation returns a Result with error type Full; handle it with '?', 'match', or '??' where supported, or write 'discard' when dropping Full is intended`, at the texts stage 0 has when E3b runs (PLAN's small fix to the `??` wording may land first; the self-hosted text follows it).

**Behaviour.** Printing, equality and failure messages are stage 0's bytes (`emit_print_collection_storage`, `emit_equal_sequence_storage`): `[`, the elements joined by `, `, then `]`; `[]` when empty; elements printed as E2 prints them (`[Cell { value: 0, active: false }]`, `[[4], [5, 6]]`). Lists compare counts, then live elements; arrays compare all N. Copies, equality and printing touch only live elements, `0 <= i < count` (T23): bytes past the count are never read, so a reused page's stale bytes can't show (the T23 dirtied-page fixtures run through the self-hosted compiler too). The helpers are per type, as E2a's: a collection's helper loops over its live elements and calls the element type's helper, so the IR stays linear in the type graph.

**Layout.** Structure of arrays: a collection of structs is one lane per scalar field; a list adds a count. Lane offsets come from the layout table: each lane starts at the previous lane's end aligned to its element alignment, so the address of field `f` of element `i` is `base + lane_offset(f) + i * size(f)`, through the addressing function. A struct of E2 is the same rule with capacity 1, so E2's offsets are unchanged. A `bool` element is one byte. The counts and lanes are all inside the collection's one region (or slot), so a collection is one contiguous block, copied lane by lane, live part only.

**E3e: nested collections, flattened.** A collection inside a collection element (directly, or through a struct field) is flattened, as DESIGN's Layout section says: `inventory: list<Item, 8>` inside `units: list<Unit, 4096>` becomes one lane per `Item` field of `4096 * 8` items, plus one count lane of 4096 counts. The address of `units[i].inventory[j].f` is `base + lane_offset(f) + (i * 8 + j) * size(f)`. Capacity products are computed in 64 bits and checked. Copying, comparing and printing a nested value walks only live outer elements and, for each, its live inner elements.

- **Element references.** An element of a collection passed to a parameter is passed as the collection's offset plus the element index, read in place through its lanes, wherever the parameter type is data-stack-resident. For a native-resident struct parameter, E3 keeps the gather into a native cell (and scatter back for `write`), because the callee's single form expects a contiguous value. E3e measures the gather cost on a nested-loop benchmark and the report proposes whether element-reference variants of callees (one variant per parameter that receives elements, emitted only when a call needs it) are worth adding in E4.
- **Text lanes.** A text or byte field of 64 bytes or less sits in its lane at full size with its length (and, for `Text`, its code-point count). A larger one uses size classes in one flat region after the collection's metadata, with per-class free lists and handles that are a class plus a byte offset from the collection's base, never an address (T31). Stage 0's T31 fixtures are the behavioural check.

## `Ascii`, `Text` and `Bytes`

**E3c: values.**

- `Ascii max N`, `Text max N` and `Bytes max N` with stage 0's maximum rules. A stored value (local, struct field, payload, from E3e a global) holds its length, its code-point count for `Text`, and its bytes inline at full maximum (T29). Reading one gives a transient descriptor (offset, length, count) that borrows the bytes.
- String literals and `b"..."` literals in user code, with stage 0's escape rules (`\xNN` refused above 0x7F in text). Literal bytes are constant data, copied into their destination.
- Stage 0's forms, as its checker types them: `Text max N` (bytes default to 4N), `Text max N bytes max M`, `Text bytes max M`; `Ascii.empty()`, `Text.empty()`, `Bytes.empty()` taking their maximum from the destination; untyped string literals typed `Ascii max len` when all ASCII, else `Text`; `b"..."` typed `Bytes max len`.
- `len()` (`Ascii` bytes, `Text` code points), `Text.byte_len()`, `Bytes.len()`/`count()`; `b[i]` on `Bytes` only (kind 16 when out of range), `.bytes()` as a temporary read-only view; `s.slice(a..b)` (kind 16 outside the bounds; code-point positions for `Text`); all six comparisons, bytewise, between one kind with any maxima and between `Text` and `Ascii`; `+` with stage 0's result maxima and its "cannot prove this concatenation fits" errors; `print`; `str`, `str_hex`, `str_bin`, `pad`, `pad_right`, `pad_zero`; `ascii_upper`; `Text.upper()` (the Unicode table becomes constant data in the core library when E3e brings constant arrays; until then it is unsupported, `Text.upper`); the checked `(Ascii max N)(x)` cast (kind 10) and `fit<Ascii max N>()`; conversions: `Ascii` to a read `Text` parameter, comparison or concatenation without a copy, `validate_utf8()` (`Result<(), Utf8Error>`), `to_text()`, `to_ascii()` (`Result<_, TextError>`); number parsing (`parse_int`, `parse_long`, the radix and literal forms) returning `Option`.
- Functions returning a growing value build into a destination region the caller reserves (the fresh-result contract). Concatenation with `+` streams into its destination.
- Failure kinds and messages are stage 0's: kind 16 for slices and byte indexes, kind 10 for casts; capacity is a build error or a `Result`, never a failure.

**`Text` is validated once.** DESIGN's Decided list and core-library.md "UTF-8 in the core library":

- validation happens only where bytes become `Text`: `Bytes`-to-`Text` conversion, `validate_utf8`, a file read into `Text` (E3f), and literals (checked at build time);
- building `Text` from `Text` or `Ascii` pieces sums their code-point counts; code-point positions count lead bytes; printing, comparing, copying and writing check nothing;
- the core library keeps boundary validators (core/utf8_validate.nl) and trusting helpers (core/utf8_trusted.nl) in separate files;
- in test builds (`; nlc.build test`), every core routine and generated path that constructs a `Text` re-validates it and fails with kind 22, `invalid Text constructed (compiler or core library bug)` (status 70 in a test child). Program builds never run it. Stage 0 keeps its re-validation (not observable); the assertion is not added to the C runtime, because no valid program reaches it, and the third leg is gone by E3d anyway;
- a Text-heavy benchmark (concatenating, slicing and printing) is measured for the report, against stage 0.

**E3d: builders.** Stage 0's surface: `+=` on `Ascii` only (on `Text` and `Bytes` it is stage 0's numeric-operator error), `try_append` on all three (`Result<(), Full>`), `Bytes.push(byte)`, `take` with its move rules and texts, and append-mode variants only for functions returning `Ascii` or `Result<Ascii, E>`. The self-hosted compiler matches that surface; how it builds them is its own. Append mode with checkpoints (DESIGN "How the compiler places values": length, code-point count and top saved before each append, restored on `Full` or on a fallible producer's error, nested appends each restoring their own), `+=`, `try_append` (a `Result` with `Full`), `Bytes.push`, reserve-ahead regions for builders, tight packing of temporaries finished before anything is placed above them, iteration scopes, and the loop-growth bound rule (a value a loop keeps growing must have a bound from its type or from a counted loop over bounded input, else stage 0's error naming the value and the loop). The DESIGN worked example (`render` and `line`) is a fixture with its output.

**E3d: the hook ABI.** The first core function that uses regions needs the context, so E3d starts by moving the hooks to a context-passing ABI and compiler-emitted static tables, as core-library.md "Retiring the hook ABI" says: first record, against the C runtime while the old ABI still links, one contract fixture per hook (edge-case arguments; expected stdout, stderr and status); then switch the ABI, delete `--runtime=c` and the third leg, and keep the contract fixtures and the core library's own tests as the replacement. The E1c output, startup and test-index scripts keep passing.

## `const` and globals (E3e)

- `const` with compile-time evaluation and constant arrays, with stage 0's rules and texts (T05): what an initialiser may use, evaluation errors at build time.
- `global NAME: T [prefault] = expr` (T08): sized by the compiler, emitted as one block of module data, never on a data stack. Stage 0's rule: an initialiser that reads no other global must evaluate at compile time and becomes data in the binary; one that reads other globals runs once at startup, after the context, environment and file registration and before `main` or the selected test, dependencies first. Stage 0's phase order (`register_globals` with the type phases, `check_global_initializer` after the struct defaults, constants checked after bodies, then evaluation, `finish_globals` and `global_initialization_order`) and texts (duplicates, name conflicts with constants and functions, capabilities in globals or constants, effects in initialisers, initialisers writing globals, initialisation cycles, non-constant initialisers, the compile-time step limit) apply. `locked` stays stage 0's parse error.
- The startup claim: stage 0's `nl_claim_memory` (overcommit mode, cgroup `memory.max` and swap limits, `job_headroom`, touching every page, the re-check after touching, `--allow-overcommit`) and its `nlc: startup memory guarantee failed: <reason>` messages, reproduced in the core library. They are observable only in constrained environments: a core test covers each reason by injection (stage 0's `NLC_TEST_MEMORY_POLICY` form), and the report lists any check that can't be run in the harness. `globals_budget` stays an `inspect memory` warning only, which the self-hosted compiler doesn't have yet.
- Globals are a growth-free place: a `write` argument naming a global's path is passed by address (globals never move).
- **Retiring the core library's bootstrap mechanisms** (the rows of core-library.md's retirement table): `sys.state()` and `state_bytes` give way to an ordinary `global` struct holding the output buffers (as `byte[65536]` arrays or `Bytes max 65536`, whichever E3e has), the file table and the scratch areas; constants-as-functions become `const`; the state-offset functions disappear. The harness compares before and after. The same task updates the retirement table in docs/design/core-library.md.
- **Emitting only reachable functions** (PLAN small fixes): the emitter emits a user function, helper or core function only if it is reachable from `main`, a test, a hook the IR calls, or the core library's roots (`nl_core_start`, the memory functions). Unreachable functions are still checked. A fixture with an unused function and the IR-size measurement show the effect.

## File I/O and capabilities (E3f)

As far as file I/O needs them, the capabilities `Env`, `Fs` and `Out`, `main(env: Env)`, `main` and tests returning `Result` (an `err` prints the error and exits 1, stage 0's bytes), `IoError` and `FileKind` and their cases. Every existing `Fs` operation keeps stage 0's behaviour exactly; core-library.md "File I/O in the core library" is the design:

- reads into `Bytes`, `Text` and `Ascii`, straight into the destination's bytes through an address formed immediately before the system call (`sys.stack_addr`), with the probe for `TooLarge`, `EINTR` and short reads, and in-place validation for `Text`;
- `list`, `list_with_extension` and `join`, with their different rules kept;
- the plain write, with the reference fix for a zero-byte write;
- the atomic write (`Fs.write_atomic`) and the streaming file writer, with their error types, the exit rules, the uniqueness and borrowing rules, and the fault-plan tests listed there. Stage 0 has neither, so their fixtures are `expected` class;
- the test-build temporary root (`mkdirat` with a random name from `getrandom`, removed with `getdents64` and `unlinkat`);
- the system-call context in error text, the same in both runtimes;
- the `sys` operations this needs (`openat2`, `read`, `getdents64`, `fsync`, `renameat2`, `unlinkat`, `mkdirat`, `getrandom`), each with its E2c wrapper.

The self-hosted compiler's own IR output keeps its single `Bytes` write until B1: its source may use only what stage 0 accepts, and stage 0 has no streaming writer.

**Core memory-function speed** (PLAN small fixes): tune `memcpy` and `memset` (wider moves, function multiversioning for x86-64-v3 and v4 where it pays) and measure against the 1.25x bar with bench/memfn; the closure rules and the post-link call-graph test stay.

## Eligibility and precedence

E2's stages and precedence stay. Each part removes its constructs from the syntactic construct table and adds the typed events it needs:

- E3a: `collection operations with Option or Result results` (a method resolved to one of them), `nested collections` (a collection type inside a collection element, in the syntactic pass), sum types over 4096 bytes (E2's size event, unchanged until E3b);
- E3c: `upper on Text` until E3e;
- every part: the not-yet-built features keep or gain one fixed string each (`Ascii, Text and Bytes`, `builders`, `grow parameters`, `unbounded collections`, `const declarations`, `global declarations`, `function values`, `capabilities`, and so on).

Each entry has a test, in an unused function, an unreachable statement and a test block, as in E1. Typed events have fixtures before and after a competing checker error.

## Checker order

The first error must equal stage 0's. The parts extend the documented order in the checker's source with stage 0's phases for what they add: `const` and `global` registration and evaluation (E3e) where stage 0 runs them relative to type names, signatures and bodies; collection capacity checks; place and overlap checks at each call, after the arguments are checked; view rules at each statement that changes a viewed collection; the loop-growth rule where stage 0 reports it. Where this file and checker.rs disagree, checker.rs wins and the report says so. Non-obvious steps get competing-error fixtures, at least: an overlap error against a bad argument type in a later argument; a view violation against an error later in the loop body; a capacity error against a body error; a `const` evaluation error against a signature error in another file.

## The compiler's own budget

New tables (collection types, lanes, regions per function, write-parameter facts, overlap work, literal data, constants, globals, reachable-function marks) take their capacities from the input policy's limits, listed in limits.nl with derivations, with N and N+1 tests for every limit the policy can reach. The IR bound gains per-entry terms for collection and constant tables and the bytes of string literals (bounded by source bytes). Collection helpers loop at run time, so no element count enters the IR bound.

## Harness

E2's protocol is unchanged, with these changes:

- **E3a** adds the relocation check as its own script and test file (see "Forced-relocation tests"). It doesn't edit compare-selfhost-build.py.
- **E3d** removes the C-runtime third leg (with the hook ABI) and adds one class, `expected`: the reference compiler isn't run; the self-hosted result is compared with the package's checked-in `expected.stdout`, `expected.stderr` and `expected.status` (or `expected.diagnostic`), written by hand and reviewed. Only packages using a feature stage 0 lacks may be `expected`, and the classification file says which feature in a comment.
- The default mode is -O1 and the core leg; `NLC_LONG_TESTS=1` adds -O3 (and, until E3d, the C leg). Each part's acceptance needs both modes at zero mismatches.

## Classification

Each part reclassifies by hand, from this file, the packages it makes buildable or diagnosable, and only those, under tests/run, tests/test, tests/e1, tests/e2 and tests/e3. It lists every movement with old and new class, and every expected-output change from a reference fix. The report gives counts per class before and after. New directed fixtures go under tests/e3/, grouped by part (tests/e3/a_*, b_*, ...), and are classified when added.

## Directed fixtures

Beyond those named in the sections above, each part covers, with exact output at both levels:

- **E3a:** every array and list form in the table; index failures at both ends, with output before; element and field assignment and compound assignment with overflow at the operator; evaluation order of receiver, index and arguments (each once, in source order); copies independent of their source; equality and printing including empty lists and lists that held more elements earlier (no stale element shows); writable views changing fields; each view refusal; values just under and just over 4096 bytes (native slot versus region) and one over 64 KiB; regions freed at block exit, `break`, `continue` and `return` (a loop allocating a large region a million times stays bounded); the `write` fixtures; the relocation fixtures; a list of structs with a `bool` field (one-byte lanes).
- **E3b:** `Full` from `push` and `insert` at capacity, with the list unchanged; `?` on a push inside a function returning `Result`; `pop` and `get` with `??` and `match`; proven pushes accepted and unproven ones refused, as stage 0 decides; `discard` refusals; `?.` flattening; the `write` copy-back fixtures on `?`.
- **E3c:** literals with every escape; a four-byte character at the declared maximum; slicing on code-point boundaries; comparisons; conversions succeeding and failing; `validate_utf8` on invalid input; fresh results returned and nested; the kind-22 assertion with an injected bad construction (a core test only).
- **E3d:** the render example; three builders open at once; a failed append leaving no partial result (and the checkpoint restored in nested appends); `continue` and `break` discarding iteration scratch while keeping the outer builder; the loop-growth error; `s = s + s`; `out.append(f(out))` as DESIGN's step 2 cases say; the unbounded and starting-size fixtures; the contract fixtures per hook.
- **E3e:** `const` arrays; globals with constant and startup initialisers; a global written through `write` parameters; nested lists of structs (counts per outer element, independent; a loop over all nested items); text lanes at 64 and 65 bytes, a text moving between classes at capacity (T31's cases); the reachable-function fixture; the core library unchanged in behaviour after the state-block retirement.
- **E3f:** stage 0's T20 fixtures and the T24 and T25 file cases; the fault-plan cases for reads, writes and the atomic write; the writer's control-flow and lifetime fixtures; `main` returning `err`.

Generated cases: the E1/E2 generator gains arrays, lists, element writes, `write` arguments (with seeded overlap errors) in E3a, and text in E3c. `cargo test` runs a fixed seed set; each report covers a larger run.

## Measurements

As E2's rules (release builds, `ulimit -v 8000000`, the bench lock, best of five with the spread and conditions). Per part, as it applies:

- scalar and aggregate regression: E1's and E2's benchmarks against the previous part's baseline;
- E3a: a tight list loop, a struct-of-arrays loop over two fields, and a `write`-parameter call loop, each built by both compilers, run for at least a second with a checksum, output to a file, with an empty program's time beside them; growth cost (moves and microseconds per move) under `NLC_STACK_STATS`;
- E3c and E3d: the Text-heavy benchmark and a builder benchmark, both compilers;
- E3e: IR bytes per source byte before and after reachable-only emission, on the self-hosted compiler's own source compiled as a package if the subset allows it by then, else on the generated benchmark; the nested-loop benchmark with gather cost;
- E3f: bench/memfn before and after; a file-heavy program, both compilers;
- every part: bootstrap time and `nlc inspect stacks selfhost` (what its tables add).

## Not part of E3

- Maps, sets, pools, queues, rings, grids and ids; refinements, `type` aliases, `fit`, `wrap`, `clamp`; generics; function values (the fixtures are written, classed `unsupported`); `recursive` functions and the native-stack budget; sorting; number parsing beyond what E3c's conversions need (E4 and later).
- The cap as a growth limit, `stack_reserve`, `strict_stack`, pooling, trimming, admission, jobs and asynchronous I/O pinning (later self-hosted tasks; manifest keys for them stay rejected).
- Self-compilation, the stage 2 and stage 3 check, per-file IR modules and parallel clang.
- String-literal patterns in `match`.

## Report

docs/tasks/E3a-report.md to E3f-report.md, each covering: the counts per class before and after, movements and expected-output changes; reference fixes and their fixtures; the checker order as extended and any difference from this file; the construct table as it now stands; the ABI as built (`write` passing, region planning, growth points, the addressing function); shared functions edited beyond the list in "Parallel work", with reasons (E3a); the merge step's movements (E3a); the measurements; what was awkward to write in next-lang; and the plan for the next part.
