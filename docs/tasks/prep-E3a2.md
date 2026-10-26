# E3a2 prep brief: arrays, lists, write parameters, and location descriptors

## Scope checklist

- [x] Fixed arrays `T[N]` and lists `list<T, N>` of scalars and non-nested structs
- [x] Array/list indexing with long indexes; bounds checking (kind 16)
- [x] Element and field assignment (`xs[i] = v`, `xs[i].f = v`)
- [x] Collection read-only methods: `.len()` (arrays), `.count()` (lists)
- [x] `discard xs.push(v)`, `discard xs.insert(i, v)` (capacity checks, no Result)
- [x] `.remove(i)` and `.clear()` on lists
- [x] `for x in coll` and `for x, i in coll` iteration with writable views
- [x] Write parameters with mode checking and overlap verification
- [x] Grow parameters for builders (E3d1 depends; E3a2 is read-only)
- [x] Location descriptor ABI (origin, offset, lane geometry)
- [x] Exact layout arithmetic for arrays, lists, and nested structures
- [x] Collection helpers (copy, equality, print)

## Stage-0 implementation reference

**Types and declarations (checker.rs, typed.rs):**
- Array type: `Array(element, capacity)` in TTypeKind (typed.rs lines depend on kind walk)
- List type: `List(element, capacity)` in TTypeKind (same)
- Capacity constants: stored as literals or const names; `check_capacity_value()` in checker.rs evaluates them
- Element type restrictions: checker.rs line ~8230 validates elements are scalars or structs (no nested collections yet)

**Indexing (checker.rs, emit.rs):**
- Parser: `ArrayIndex(array_expr, index_expr)` in ast.rs ExprKind
- Checker: `check_collection_index()` at checker.rs:8448–8485
  - Ensures index is `long`, bounds-checks at runtime (kind 16 on failure)
  - Reads: no snapshot needed if no later mutation; checker.rs:12829 (field assignment) and 10724 (collection element assignment)
- Emission: `emit.rs` ~11900–12000 handles indexing with offset arithmetic
  - Scalar elements: direct `getelementptr [capacity x element_size]`
  - Struct elements: `getelementptr i8`, offset from field table (one addressing function)

**Write parameters and overlap (checker.rs, emit.rs):**
- Parameter mode enum: `ParamMode { Read, Write, Grow }` (E1 has `Read` and `Write` for aggregates)
- Signature parsing: `register_package_declarations()` extracts param modes (checker.rs ~2600–2700)
- Overlap check: `places_overlap()` at checker.rs:16255
  - Compares canonical places: same root + prefix test (same field path or different constant indexes are apart)
  - Called at checker.rs:9064, 10196 (argument checking) and 9616, 10221 (for each earlier argument)
  - Error text: "arguments overlap, and at least one is passed as write" (stage 0 text)
- Write argument requirements: resolver.rs place validation (`resolve_place()`, `place_is_mutable()`)
  - Must be: var local, write/grow parameter, field path of var, or writable loop view
  - Error: "a write argument must be an assignable place"
- `write` element passing: location descriptor with collection anchor, element index (E3a1/E3a2 responsibility)

**Collection helpers (emit.rs):**
- Helper emission for arrays and lists by kind (checker.rs type kind dispatch)
- Copy helper: iterates live elements, calls element type's copy helper (emit.rs ~9200)
  - Layout: N copies of element_type; copy copy-i by calling element helper on descriptor
- Equality helper: compares counts (for lists), then elements (emit.rs ~16800–16900)
- Print helper: print `[`, live elements joined by `, `, `]` (emit.rs ~17300–17400)
- Fill helper: initializes array with N copies of default value (emit.rs ~8360)

**Exact layout arithmetic (emit.rs):**
- `type_size()` at emit.rs:3946–3978 (declarative, saturating at 4097 for E2 cap check)
- New: exact layout calculation for regions (E3a1 joins); checked arithmetic, no saturation
- Array layout: N × element_size, aligned per element
- List layout: count lane (one i64) + N × element_size
- Struct-of-arrays: per field, N copies at aligned offset; lane offset table
- Overflow: caught at region bump or emitted as `data stack range exhausted` (kind 18)

**Location descriptor (E3a2 interface):**
- Not yet in stage 0 (pointer mode); offset mode in O1–O7 sequence
- E3a2 in worktree: passes descriptor `(anchor: ptr, offset: i64, copies: i64, index: i64)`
  - `anchor`: null for data-stack (resolved via cached base), non-null for native/global
  - `offset`: byte offset from anchor to group start
  - `copies`, `index`: lane geometry (standalone value has copies=1, index=0)
- Read parameters passed as location (no gather in E3a2)
- Write parameters passed as location (callee sees updated value; store-back on exit)
- Hidden result destinations allocated by caller, passed as fresh location (copies=1)

**Argument evaluation and operand snapshots (E2i audit relevant):**
- Indexes captured once: `f(xs[i], { i = 5; 0 })` reads old xs[i] (checker.rs:8448 validates at source, not re-evaluated)
- Write arguments reference (pointer/descriptor), seen after all later arguments (emit.rs:11946 gather after arg loop)
- Read arguments snapshot at evaluation point, unless later operand can't change them
  - Later threats: assignment, compound assignment, method calls (push, insert, etc.), write parameter passing
  - E2i audit fixtures: checker.rs has stage-0 behavior; E3a2 inherits rules and adds collection mutation threats

**Writable loop views:**
- Parser: `for x in coll` parsed as loop variable binding
- Checker: checker.rs ~12520 identifies mutable places in loop bodies
  - If collection is mutable place (var, write param, writable view), create loop write candidate
  - Binding `x` becomes writable view aliasing `coll[i]`
- Runtime semantics: view is location descriptor with collection's anchor/offset, index=loop counter
  - Can assign `x.field` directly; reflected in collection (views.rs emit, not separate copy)
- Conflicts: view live prevents `.remove()`, `.clear()`, passing collection as write parameter

## Selfhost compiler interfaces and plug-in points

**E2i interfaces E3a2 uses and extends:**

1. **Type kinds (frozen by E2i):** selfhost/compiler.nl:26–38
   - E3a2 adds: `TYPE_KIND_ARRAY: 8L`, `TYPE_KIND_LIST: 9L` (already present)
   - One `type_kind(ty)` function; branches for array/list handling

2. **Storage locations (E3a1 owns, E3a2 extends):** compiler.nl:40–42
   - E3a1 adds: `LOCATION_DATA_STACK: 1L` (region offsets)
   - E3a2 uses: native and data-stack origins for array/list fields in structs

3. **Emit layout address (E3a2 owns lane geometry):** selfhost function `emit_layout_address()`
   - Input: `StorageLocation { origin, offset, copies, index }`
   - Output: LLVM value (address or offset) for the access
   - E3a2 computes lane offsets for flattened collections

4. **Location argument/destination passing (E3a2 owns, E2b/E2c call interface):**
   - `pass_location_as_argument()`: encodes descriptor from place
   - `receive_parameter_as_location()`: decodes descriptor to location record
   - E2b/E2c use for enum/Option/Result parameters; unchanged behavior (native slots only)

5. **Helper registry (E2i owns, E3a2 registers):** compiler.nl:44–48
   - E3a2 registers: HELPER_COPY, HELPER_EQUAL, HELPER_PRINT for array/list kinds
   - Registry keyed by (type_id, operation); dispatches to emitter for kind

6. **Exit and cleanup (E2i owns, E3a2 registers):** compiler.nl:50–57
   - E3a2 registers: store-back cleanup for write parameters (runs on every exit)
   - Exit kinds remain; cleanup registration adds write-store handler

7. **Signatures (E3a2 owns parameter modes):** `register_package_declarations()` in compiler.nl
   - E3a2 accepts `write T[N]`, `write list<T, N>`, `grow` on builders (E3d1)
   - E2b/E2c call interface unchanged

8. **Shared code hunks (E2i owned, E3a2 extends):**
   - `value_type_size()`: E3a2 adds array/list branches
   - `resolve_value_type()`: resolves array/list type names
   - `is_aggregate_type()`: returns true for arrays and lists
   - Each change delimited with `// E3a2 begin`/`// E3a2 end`

**New selfhost files:**
- `selfhost/collections.nl`: type checking, emission, helpers for arrays/lists
- `selfhost/params.nl`: write parameter checking, overlap verification, location descriptor ABI

## Test packages moving to buildable

| Package | Current | E3a2 | Notes |
| --- | --- | --- | --- |
| tests/e2 or tests/e3 arrays, lists | unsupported | build | Core array/list features |
| tests/e3/a2_write_* | unsupported | diagnose initially | Write param fixtures |
| tests/e3/a2_overlap_* | unsupported | diagnose initially | Overlap error fixtures |
| Tests with nested collections | unsupported | unsupported | Deferred to E3e |
| Tests with `pop`, `push` (non-discard) | unsupported | unsupported | Deferred to E3b (Result) |
| Tests with builders, `grow` | unsupported | unsupported | Deferred to E3d1 |

E3a1 (regions, growth, context) runs in parallel. E3a2 starts after E3a1 lands; merge happens after E2b, E2c, E3a1, E3a2 all complete.

## Pitfalls from reviews (Sol E3 findings 2, 4, 5, 8, 10, 12)

1. **P1 — Location descriptor is incomplete (Sol E3-r1 finding 3):**
   - E3's `write` section describes offset+index but omits global/constant addressing
   - E3e passes flattened elements with lane strides inside; single descriptor form insufficient
   - E3a2 must define: origin kinds (native/data-stack/global), how callee knows which, what "gathering" means for fallback
   - Embed small collections in native structs have native anchors; large struct elements have data-stack anchors

2. **P1 — Argument evaluation order vs exclusivity (Sol E3-r1 finding 4):**
   - Early copy (`f(xs[0], { xs[0] = 9; 0 })` with write first param) observes old value in native-cell form
   - E2's skip-snapshot rule assumes no mutations; write parameters invalidate that
   - E3a2 must: capture index once, distinguish read snapshots from references, gather after last argument
   - Stage-0 audit fixtures in E2i; E3a2 runs them through self-hosted compiler from E3a2 onward

3. **P1 — Exact layout vs capped sizing (Sol E3-r1 finding 5):**
   - Current `size_add_saturated` stops at 4,097 bytes; wrong for region allocation
   - Array 10,000 × 4,096-byte struct needs 40 billion bytes (exact); must allocate 40 GiB region
   - E3a2 must separate: eligibility cap (4,097 transitive through structs, E2c inferred instances) and exact checked layout
   - Unknown/cycle results still never cap; those packages reach checker for real error

4. **P1 — Argument evaluation must account for mutations (Sol E3-r1 finding 4):**
   - `f(s, mutate(s))` with mutate taking write parameter violates E2's assume-no-mutations
   - Later argument effects: assignment, compound assignment, method (`push`, `insert`, `clear`), write param passing
   - E3a2 must snapshot read arguments when later operand may change them (proven interval method when cost justifies)

5. **P2 — Overlap check interleaves with type checking (Sol E3-r1 finding 12):**
   - `check_direct_function_call` resolves each place **before** type-checking that argument, interleaved
   - Overlapping places might not be resolved; `places_overlap` needs dummy place for literal/call result
   - E3a2 may have blocks testing Write mode alone where Grow must be covered too
   - Audit Rust's call path for Write-only branches; add Grow variants and fixtures

6. **P1 — Write store-back on exit must be precise (Sol E3-r1 finding 10):**
   - Write scalar cached in register; store-back before return, after each write-parameter call, on `?` propagation
   - E3a2 registers store-back cleanup with E2i's exit interface for: return, break, continue, fall-through
   - Must not trigger on fatal failures (job ends; no cleanup needed)
   - E3a2 fixtures: scalar and aggregate write parameters; repeated calls; store-back visible after `?` return

7. **P2 — Oversized sum gate must remain transitive (Sol E3-r1 finding 5):**
   - After E2c merges, `list<Option<OversizedStruct>, 10>` is unsupported even if list fits
   - E3b gates sum-typed elements; until then, sum type over 4,096 bytes in any context stays unsupported
   - E3a2 must not relax the gate; E3b adds it to elements

## Ambiguities and open questions for manager

1. **Collection element gathering:** When a write-parameter callee needs contiguous storage (e.g., a C hook call), how is it gathered? After which arguments? With base reload?
   - E3a2 establishes the rule (gather after last argument, reload base before call); E3e and later use it

2. **Loop iteration counter mutability:** Can loop counter `i` be assigned in the body (`for x, i in xs { i = 0 }`), or is it immutable?
   - Stage 0 rejects assignment to loop counter; E3a2 enforces "loop counters are immutable"

3. **Writable view scope:** Does a writable view extend to nested blocks/loops inside the for loop, or is it reborn each iteration?
   - View is bound to the loop scope; each iteration is a new scope (view ends, next iteration creates new view with same binding name)

4. **Discard on full push:** What observable state does discard preserve if push fails (full)? Do earlier pushes remain?
   - `discard xs.push(v)` doesn't store if full; count unchanged; v discarded (no observable effect)

5. **Element reference lifetime:** When passing an element reference through a write parameter (`bump(xs[i])`), who ensures the collection isn't reallocated during the call?
   - E3a2: none (no growth yet; E3d1 allows growth with constraints)
   - E3a1's relocation test covers later argument forcing move; reference remains valid via base reload after call

## Merge contract and E3a1 dependencies

**E3a2 depends on E3a1:**
- Region context record layout (header page, stable fields, prefix match with C)
- Growth routine (double, mremap, guard page, kind 18 on failure)
- Context-passing hook ABI (every core hook takes context pointer)
- Stack buffer functions `stack_write()`, etc. (offset-taking, raw syscall inside)
- Off sets in expressions and base caching (E3a2 addresses are i64 offsets in regions)

**E3a1 does not depend on E3a2:**
- E3a1 allocates no array/list elements; only aggregate locals and temps forced to regions via `--test-region-threshold=0`
- Core helpers called from E3a1 (memory copy, fill) keep C signatures; no descriptors yet

**Merge validation (after both steps complete):**
- Enum with collection payload: copy, compare, print, match bindings
- Collection element assignment through `write` parameter in loop with writable view alive
- `?` propagation exiting a loop with write parameter live (store-back visible to caller)
- Nested region allocation (collection element is a collection) under relocation

## Next steps for implementer

1. **E3a1 must land first:** Regions, growth, context record, hook ABI, base caching, E2i exit/cleanup interface
2. **Separate sizing functions:** Eligibility cap (E2c unchanged) and exact layout (E3a1/E3a2 new)
3. **Build location descriptor ABI:** origin discrimination, callee variant dispatch, gathering fallback
4. **Collection types and checking:** Array/list type nodes, capacity constants, element restriction, bounds checking
5. **Write parameter mode and overlap:** Param mode parsing, resolve_place, places_overlap, error messages
6. **Collection helpers:** Copy, equality, print helpers per element kind; helper registry dispatch
7. **Writable views and loops:** For loop binding as view descriptor, lifetime management, conflict detection
8. **Store-back on write-parameter exit:** Register cleanup with E2i exit function; test on return, break, continue
9. **Tests:** Classify e3a2 packages; add write-parameter, overlap, relocation, layout fixtures
10. **Audit:** Exact layout arithmetic matches stage 0 for every directed fixture type; argument evaluation E2i audits pass

## Manager answers (Claude, 2026-10-26)

- **No global origin.** Mutable globals are removed from the language; the location descriptor's origins are the native slot, the data-stack offset and (from E3e) fixed `const` data. Ignore the global parts of Sol's finding 3 and of this brief.
- **One rule for semantic questions** (loop-counter assignment, view scope per iteration, `discard push` at capacity): stage 0 decides. The answers above are the prep agent's reading; confirm each with a small probe through stage 0 (`nlc run`) and pin it with a fixture.
- **Errors:** only rejection with real error text is required; no competing-error fixtures and no need to match stage 0's order or wording.
- **Gathering (question 1):** follow "The location descriptor" and "Evaluation of arguments and operands" in the E3 spec; core hooks are context-passing after E3a1, so no C hook needs contiguous user storage. If the spec leaves a case open, choose the simplest rule, pin it with a fixture and list it in the report.
- **Element references across calls (question 5):** offsets plus base reload after any call that may grow the stack, as E3a1 builds; E3a2's relocation fixtures must cover a `write` element argument with a later argument that forces growth.
