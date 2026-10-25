# Self-hosted compiler architecture for next-lang (research report)

Oct 24, 2026. Written for Ben. It replaces a rejected draft.

- **Sources:** facts about other projects carry a link in section 9, each fetched while writing this.
- **next-lang facts** come from this repository and from probes run in WSL:
  - Revision 1 was checked against commit `612245e`; revision 2 against `7734ecd`, with T15 in progress in the working tree.
  - The probes used an `nlc` debug binary copied from `~/.cache/next-lang/target/debug/` (built mid-T14) and lived in `~/shprobe`, outside the repository.
- **Estimates:** numbers I estimated, rather than measured or fetched, say so.

## Revision 2 (after docs/reviews/sol-selfhost-arch-r1.md)

Every one of Sol's 13 findings is addressed:

1. **"No heap anywhere" is qualified.** Compiler tables need no application heap, but the C runtime itself allocates its contexts and directory listings with `calloc`, `realloc` and `strdup` (2.3h).
2. **Maps.** Their 8-byte bucket array must be initialised, not just occupancy flags. Copies keep buckets, tombstones (markers for deleted entries), hashes and insertion order (2.3b, 6).
3. **A complete live-elements rule** (2.3b), covering:
   - pool high-water guards in lookup, iteration, equality and printing;
   - whole-value loads and stores;
   - queues and rings, nested collections, enum payloads;
   - the runtime's `fs.read` and `fs.list`.
4. **The memory map is rebuilt** (4.6). It gains:
   - the token-to-name-id array, the file table, side tables (extra data);
   - the 16 MiB read temporary and a measured printer-stack breadth;
   - wave-bounded worker outputs that coexist with joined results.

   It now separates reserved space, live payload and peak pages touched. The totals change: about 2.43 GiB reserved, 54.3 MiB peak touched, 27.8 MiB live.
5. **S1's limit order now follows `driver.rs` exactly** (4.3, 5.1). S1b picks errors by sequential file-and-phase order (5.1).
6. **Recursion.**
   - `else if` chains recurse in the Rust parser with no counter; a probe parsed a 123,999-deep chain.
   - S1 parses them with explicit frames.
   - The other paths' counters are listed, with a native-stack budget argument and test.
   - The completed-tree nesting walk is reproduced in its exact visiting order (5.1).
7. **The node encoding is specified** (5.1):
   - extra data for generic names, indexes, decoded strings, magnitudes and refinement endpoints;
   - synthetic nodes;
   - the 2-nodes-per-token bound, argued and then tested;
   - file-relative offsets;
   - no hidden scope-marker nodes.
8. **Exit status 2/3** (now PLAN's "Exit status for tools (before S1)"), and raw UTF-8 output through byte buffers, not `Ascii` (5.1, 6).
9. **Literal limbs** (32-bit pieces of a large number): overflow detection and the boundary tests (5.1).
10. **S2 phases now mirror the reference's order.** Registration comes first. Constants and recursion contracts are evaluated after bodies, from bounded pending lists. Merging rewrites every reference, and 10,000 is call *depth* (5.2).
11. **The smallest-position error rule is replaced** by a documented phase, function and traversal order compatible with the reference (5.2).
12. **S3** now specifies:
    - module ownership of globals, entry initialisation and generic copies;
    - cross-module declarations and stable symbols;
    - a driver bridge that keeps the frame-size measurement and recursion-check patching (5.3).
13. **Precise bootstrap claims.** Stage 2 equals stage 3 is a stability check. A diverse double-compiling check needs a named candidate, a trusted seed and a trusted toolchain, and binaries, not IR (3.5, 5.4).

    Section 6 is re-ranked into hard S1 blockers and conveniences with workarounds. Section 8 no longer proposes the two items PLAN already has: live elements (line 33) and exit status (line 34).

Terms used throughout:

- **Reserved:** address space set aside but not yet backed by RAM.
- **Touched:** pages actually written, which then cost RAM.
- **Live payload:** bytes that hold data still in use.
- **Postorder:** children are stored before their parent.
- **Interning:** storing each distinct name once and using a small number for it after that.
- **Stage N:** the compiler binary produced at bootstrap step N.

---

## 1. Recommendation (one page)

**The core idea:** keep every compiler table in a local collection on the compiling job's data stack. Reserve each table at a stated limit, and pay RAM only for what a program actually uses.

**What blocks that today** (2.3):

- Globals are touched in full at startup, with or without `--allow-overcommit`.
- The emitter and runtime write whole collections, not just their live elements. That happens on empty literals, struct and enum construction, copies, returns, and `fs.read` and `fs.list`.
- `byte` takes 4 bytes.
- The data stack is fixed at 64 MiB.

**Conditions** (4.1):

- **Hard:** S1 is incorrect or can't run without these.
  - The data stack must be sized past 64 MiB (T17).
  - `main` needs an exit-status facility (PLAN line 34).
  - Output must go through raw byte buffers (`Bytes`, T16, or `list<byte, N>` today).
- **For the memory goal:**
  - PLAN's live-elements task (line 33);
  - 1-byte bytes.

**With all of these in place,** a 50,000-line program needs about 2.43 GiB of reserved address space, about 54 MiB of pages touched at peak and about 28 MiB of live payload (4.6). Compiler tables need no application heap; the C runtime's own small allocations remain (2.3h).

**S1, in two parts:**

- **S1a (sequential), after M3 and the hard items.** A lexer and parser in next-lang that reproduce `nlc parse --tokens --tree` byte for byte, including stderr and exit status. The comparison runs over every package under `tests/`, the parse cases, and generated limit and fuzz inputs.
  - **Data:** one source buffer per package; a token list; a postorder node list with subtree sizes and a Zig-style extra-data list.
  - **Order:** limit checks in `driver.rs`'s exact order.
  - **Parsing:** recursive descent marked `recursive` where Rust's counters bound the depth, and explicit frames for `else if` chains, which Rust doesn't bound.
  - **Output:** the printer and the completed-tree nesting walk are explicit-stack loops in Rust's visiting order.
- **S1b (parallel), once DESIGN step 6 exists** (builders, `batch`, `freeze`, `parallel for`). Files are read sequentially, parsed in parallel, and errors are picked by sequential file-and-phase order. This is the validation plan's parallel-tool program.

**S2, the checker:**

- **Interning:** one sequential interning pass.
- **Phases, in the Rust checker's order:**
  1. Registration.
  2. Global initialisers.
  3. Function bodies, in parallel waves, picking the lowest-index failing function.
  4. Tests and constant expressions.
  5. Call graph and recursion, then constant evaluation.
- **Comparison:** typed dumps, plus a documented "first error" order, against a new `nlc check --dump`.

**S3, code generation:**

- LLVM IR text, one module per source file, emitted in parallel waves.
- One module owns the global state and entry initialisation. Generic copies belong to the first module that requests one.
- Until a process capability exists, a Rust-side bridge links the modules and runs clang, keeping the frame-size and recursion-check patching steps.

**Bootstrap:**

- **Steps:** Rust `nlc` (stage 0) builds stage 1, stage 1 builds stage 2, and stage 2 builds stage 3.
- **Stability check:** stage 2 must equal stage 3, comparing binaries built with the pinned clang and runtime (IR first, for diagnosis).
- **A real diverse double-compiling check** needs more than that: a named candidate binary, Rust `nlc` as the trusted seed, and a trusted clang, runtime and linker (5.4).
- **Reference:** behavioural comparison against Rust `nlc` stays.

---

## 2. Current state and constraints

### 2.1 Status (from docs/PLAN.md and the reviews)

| Item | State |
| --- | --- |
| M0, M1, M2 (T01 to T12) | done |
| M3 T13 data stack, regions, destination emission | done |
| S0: T19 `recursive fn`; T20 files, arguments, output; T21 `nlc parse` and docs/syntax-tree-format.md | done (claude-T21-review.md: "With T19 and T20 this completes S0") |
| M3 T14 `Ascii` values | done (`dc1acc8`) |
| T15 append mode | in progress |
| T16 `Text`/`Bytes`, T17 reservations and `inspect stacks`, T18 number parsing and formatting | to do |
| Live-elements task; exit status for tools | in PLAN (lines 33 and 34), from revision 1 of this report and Sol's review |
| Layout follow-up; array/list literals | before M4 / before S1 |
| Builders, `freeze`, `batch`, `parallel for` (DESIGN step 6) | designed, no T-task |
| Process capability | effects step, "M5-ish" |

Sol's S0 review (sol-S0-r1.md) said S0 plus M3 supports only a **sequential** S1. That is why S1 is split here.

### 2.2 What next-lang gives a compiler writer today

All of the following were checked against fixtures or probes:

- **Types and control flow:**
  - `struct` with defaults; `enum` with payloads; exhaustive `match`;
  - `Option` and `Result` with `?` and `??` (including `?? break`, `?? continue` and `?? return`);
  - `const` with compile-time evaluation.
- **Collections:** `list`, `pool` (including `pool<T, N, Owner>`), `map`, `set`, `queue`, `ring`, `grid` and `T[N]`. Collections of structs are stored one array per field, which is Zig's MultiArrayList layout.
- **Methods and loops:** `push`, `pop`, `get`, `set`, `remove`, `count`, `sort_by` and `binary_search`; `for i in a..b` and `for x, i in xs`, with `break` and `continue`.
- **Parameters and functions:**
  - `write` parameters, plus large values passed by pointer and large results built in the caller's destination (T13);
  - function values (T11);
  - `recursive fn` with a native-stack budget (T19).
- **Capabilities and I/O (T20):** `fn main(env: Env) -> Result<(), E>`, with `env.fs`, `env.out` and `env.args()`. Filesystem access is rooted at the working directory: absolute paths and escaping symlinks return `Outside`.
- **Bit and wrapping operators:** `+%`, `-%`, `*%`, `^`, `&`, `|`, `<<` and `>>`. A hand-written FNV-1a hash works: `"ab"` printed 1294271946.

There is no `while`. A loop of unknown length is a counted loop with `break`, which doubles as the step budget:

```
for step in 0..LIMIT {
    let top = stack.pop() ?? break
    ...
}
```

### 2.3 Facts that change the memory design

**(a) Globals cost RAM in full from startup, in every mode.**

- DESIGN "Static allocation" says globals are "reserved and committed", and the runtime "touches the state's pages before scheduling any job".
- T08's report: "All globals are touched at startup on Linux".
- `nl_claim_memory` (`runtime/nl_runtime.c`) runs its touch loop even with `--allow-overcommit`, which only skips the policy checks.
- Probe: a global holding an empty 48,000,000-byte list ran at 48,400 KB maximum resident memory (RSS) in both modes, against 1,584 KB for an empty program.

Only the job data stack is committed on touch: it is mapped with `MAP_NORESERVE`. So compiler tables belong in locals, not globals.

DESIGN does promise that large local collections are "committed only as [they're] used" (DESIGN, Collections). What follows are implementation defects against that promise.

**(b) Collections are written past their live elements.**

*The emitter.* Its destination path memsets the whole type size for `EmptyList`, `EmptyMap`, `EmptySet`, `EmptyQueue` and `EmptyRing`. `EmptyPool` also loops over every slot, writing generation 1 and a free-list entry. `StructConstruct`, `Construct` (enum payloads) and `Fill` memset their whole destination, and copies and returns move the full type size.

Probes, each holding one element:

| Case | Peak memory (RSS) |
| --- | ---: |
| Local `list<long, 6000000>` | 48,224 KB |
| Local `pool<Node, 2000000>` of a 12-byte struct (21 B per slot) | 42,416 KB |
| The same list as a struct field built with a struct literal | 48,224 KB |
| A returned 16 MB list (callee's local and caller's destination both touched) | 32,736 KB |

`inspect contracts` shows why the returned list costs twice. At 3,000,000 elements the callee needs 24,000,008 bytes for its local, and the caller reserves another 24,000,008 for the destination, because a returned local collection isn't yet built in place.

*The runtime.* `fs.read` and `fs.list` clear their whole destination buffer on entry and on failure (Sol, `nl_runtime.c:946–980`, `:1003`).

What "live elements" must mean, per representation (Sol's findings 2 and 3; PLAN line 33 now carries these rules):

- **`list`, `queue`, `ring`:**
  - Only `count` (and a queue's or ring's head) is initialised.
  - Elements are live from head for `count` positions, wrapping.
  - Copies, equality, `print` and hashing visit only those positions.
- **`map`, `set`:**
  - Lookup first reads an 8-byte bucket entry (0 = empty, negative = tombstone, positive = entry + 1; `emit.rs`, map probe code), so the **bucket array must be zeroed**, or probing redesigned. Zeroing just occupancy flags isn't enough.
  - Insertion-order entry records past the entry count stay untouched.
  - Copies preserve or rebuild buckets, tombstones, hashes and insertion order.
- **`pool`:**
  - A **high-water mark** is the end of the slots ever initialised. Slots at or above it are implicitly free with generation 1.
  - Lookup (today it checks only capacity), iteration, equality and printing must check the mark before reading flags or generations.
  - Removed slots' generations, retired slots and free-list order survive copies and resets (DESIGN, Pools and their ids).
- **Arrays and grids** are always fully live: `fill` is a real cost, so keep them small.
- **Nested collections and enum payloads:**
  - A collection inside a struct, an array element or an enum payload follows its own rule.
  - An enum writes its tag and only the active case's payload.
  - A struct literal initialises each field by its type's rule, never by one memset.
- **Whole-value loads and stores:** equality and printing currently load whole operands first (Sol, `emit.rs:9666–9675`, `:8288–8293`). These must become pointer-based walks, or a 48 MB operand is read in full.

Tests use dirtied destinations (reused stack pages full of stale bytes) with:

- stale pool ids and slot retirement;
- map tombstones;
- equality, hashing and printing.

They report peak pages touched. Equal lists alone don't establish safety.

**(c) `byte` is 4 bytes.** It is an `int` refinement (`checker.rs`), and refinements keep their base width. DESIGN's "ranges pick storage" isn't implemented. The only number types today are `int`, `long` and `bool`: no unsigned, 8- or 16-bit, or 128-bit types.

**(d) The data stack is 64 MiB, fixed** (`nl_data_stack_reservation`).

**(e) Generics and capacities.**

- `fn total<N>(xs: list<int, N>)` fails with "cannot infer generic parameter 'N'".
- Capacities must be literals or scalar `const`s, not fields of a `const` struct.
- Both are conveniences: concrete `const` capacities work (5.1's sample uses them).

**(f) The Rust reference.**

- About 34,900 lines: checker 13,421, emitter 11,647, parser 2,572, lexer 455.
- It uses heap vectors and boxed trees.
- It compiles on one 1 GiB-stack thread. T19 measured 5 to 80 KB debug frames per nesting level.
- It reports a single error.

**(g) Baselines** (WSL, Intel Core Ultra 9 185H, 22 logical cores, `vm.overcommit_memory = 0`):

- *Parse-able test corpus:* 3,808 lines, 99,634 bytes, 31,187 tokens, 13,982 nodes.
- *A 54,145-line benchmark* (that corpus repeated 13 times into 13 files, 1,327,053 bytes):
  - 410,163 tokens and 182,416 nodes, i.e. 24.5 bytes/line, 7.6 tokens/line and 0.44 nodes/token;
  - a 20,516,871-byte dump;
  - debug Rust `nlc parse --tokens --tree` took 0.45 s at 52,872 KB maximum RSS;
  - its printer would need at most 888 pending entries (the most children of one node is 871, the deepest node is at depth 13).
- *Generated IR:* a 6,130-byte prelude, then 360 to 920 bytes per source line on four fixtures, with an outlier at about 6,300 (`t09_maps_sets`).
- *clang 18.1.3 on 1 MB of that IR:* 0.08 s at `-O0`, 0.56 s at `-O1`, 0.68 s at `-O2` (one sample).
- *Deep `else if` chains:*

  | Chain depth | Peak memory | Time | Result |
  | ---: | ---: | ---: | --- |
  | 1,000 | | | parses |
  | 1,001 | | | exit 2, "expression nesting limit of 1000 exceeded" |
  | 20,000 | 220,176 KB | | exit 2, same message |
  | 100,000 | 1,083,280 KB | 1.17 s | exit 2, same message |
  | 123,999 (about 992,000 tokens, under the 1M-per-file limit) | 1,342,176 KB | 1.53 s | exit 2, same message |

  So Rust parses arbitrarily deep chains and rejects them only afterwards, in the completed-tree walk.
- *2,049 nested `!` or `-`:* rejected at the 2,049th operator by the 2,048-deep expression parser counter, which reports the "1000" message.

**(h) The runtime heap.** `nl_context_create` allocates its context with `calloc`. The test environment uses `calloc` and `strdup`, the file-name table `realloc`, and `fs.list` `calloc`, `realloc` and `strdup`. These are small and outside the compiler's tables. A no-heap claim covers application data, not the C runtime.

---

## 3. Survey: what to copy and what not to

### 3.1 Data-oriented compilers

**Zig.**

- *AST layout:* PR #7920 (merged February 2021) stores tokens and AST nodes as struct-of-arrays.
  - A token is 5 bytes: a 1-byte tag and a 4-byte offset.
  - A node is 13 bytes: a 1-byte tag, a 4-byte `main_token` and an 8-byte `lhs`/`rhs` pair. Anything larger goes into `extra_data`.
  - In the PR's words: "the only purpose of an AST is to bring a tree structure to a list of tokens."
  - Measured with `zig fmt` on the standard library: 19.3% less peak memory and 11.4% faster wall-clock time, despite 34.5% more cache misses.
- *Index types:* in `lib/std/zig/Ast.zig`, `TokenIndex = u32`, `Node.Index = enum(u32)` and `extra_data: []u32`.
- *Speed:* the 0.8.0 notes report tokenize, parse and ZIR at 8.9 million lines/s (292,458 lines in 33 ms on an 8-core i9-9980HK). A ZIR change cut one benchmark's peak memory from 645 MiB to 386 MiB.
- *InternPool* (`src/InternPool.zig`): sharded per thread ("one item per thread, indexed by `tid`"), with atomically published shared parts.
- *Bootstrap:* "Goodbye to the C++ Implementation of Zig" (December 7, 2022) replaced an 80,000-line C++ compiler with `zig1.wasm` (2.6 MiB; 637 KB compressed) plus about 4,000 lines of C. `wasm2c`, then `zig1`, then `zig2.c`, then the final compiler. Debug-build peak RSS fell from 11.3 GiB to 3.8 GiB.

Copy: struct-of-arrays, 32-bit indexes, an extra-data side array. Don't copy: an atomically shared interner (next-lang has no shared mutable state), and the wasm seed (Zig's goal was deleting a second compiler; next-lang keeps one as reference).

**Carbon.**

- *Storage:* "Data is stored in vectors and flyweights are passed around, avoiding more typical heap allocation with pointers".
- *Postorder tree:* "The parse tree's storage layout is in postorder", with `subtree_size` per node, because it's "most efficient to process the parsed output in postorder; this affects checking."
- *No recursion:* the parser pops states off a stack, because "Complex code must not cause recursion issues. We have experience in Clang seeing stack frame recursion limits being hit in unexpected ways".
- *Speed:* PR #4124 measured lexing at about 5.02M lines/s, parsing at 1.73M and checking at 705K (262,144 lines), "2x behind on lex and check, 5x on parse" of its goals.

Copy: postorder plus subtree sizes; checking as a linear postorder walk; explicit stacks wherever depth isn't bounded. Revision 2 adopts this for `else if` chains (5.1).

**TypeScript's Go port.**

- *Results:* VS Code (1,505,000 lines) went from 77.8 s to 7.5 s at "roughly half" the memory (March 11, 2025).
- *Parallel design:* the 7.0 beta (April 21, 2026) "performs many steps in parallel, including parsing, type-checking, and emitting". It uses "a fixed number of type-checker workers with their own view of the world", four by default. Given the same inputs, they "will always divide them identically and produce the same results."

Copy: per-job caches with a fixed, deterministic division of work.

**Odin and Jai:** no primary source on compiler internals found, so they're omitted.

### 3.2 Static allocation and fixed limits

- **TigerBeetle's TIGER_STYLE.md:**
  - "All memory must be statically allocated at startup. No memory may be dynamically allocated (or freed and reallocated) after initialization."
  - "Put a limit on everything because, in reality, this is what we expect—everything has a limit."
  - "Do not use recursion to ensure that all executions that should be bounded are bounded."

  Its blog: "TigerBeetle allocates no memory after startup", with memory "calculated with a bit of addition and multiplication at startup".
- **Power of Ten (Holzmann, 2006):**
  - Rule 1 forbids "direct or indirect recursion".
  - Rule 2: "Give all loops a fixed upper bound".
  - Rule 3: "Do not use dynamic memory allocation after initialization."

  JPL's 2009 C standard repeats the recursion and allocation rules.
- **MISRA C:2012 Rule 21.3** (via MathWorks; the standard is paywalled): "The memory allocation and deallocation functions of <stdlib.h> shall not be used."
- **What next-lang does differently:** it makes these rules compiler checks: capacities in types, opt-in recursion with a budget, step budgets, `Full` as a `Result`. A job's memory is also reserved at its worst case and paid as used, once 2.3(b) is fixed.
- **Shipped limits elsewhere:**
  - C11 (N1570 §5.2.4.1) requires at least "127 nesting levels of blocks", "63 nesting levels of parenthesized expressions within a full expression", "4095 external identifiers in one translation unit" and "4095 characters in a logical source line".
  - MSVC's compound-statement nesting is "generally between 100 and 110".
  - GCC's preprocessor docs: "It is intended that there should be as few limits as possible."
  - Zig's indexes are `u32`.

  next-lang's documented limits are generous by comparison.
- **tcc** reports 859,000 lines/s on the 1,950,947-line Links browser, against 98,000 for GCC 3.2 `-O0`. I couldn't verify Oberon or Turbo Pascal table sizes from primary sources, so I make no claims about them.

### 3.3 Regions and arenas

- **Regions** (summarised from a secondary source, Wikipedia):
  - Tofte and Talpin's `letregion ρ in e end` creates, evaluates in, then frees a region, last in, first out.
  - MLKit scaled to large programs only with "a hybrid technique combining region inference with tracing garbage collection", with results "between 10 times faster and four times slower" depending on how "region-friendly" a program was. Regions can hold dead data until freed ("leaks").
  - Cyclone added explicit regions to a safe C dialect.
- **next-lang's data-stack regions** are such regions with scope-written lifetimes. The leak lesson: a long-running language server must run each compile as its own job.
- **Arenas:** rustc allocates "from a global memory pool... from a long-lived arena". LLVM's `BumpPtrAllocator` objects' "lifetime is tied to the lifetime of the allocator."

### 3.4 Operating-system facts

- **Linux overcommit:**
  - mode 0 is "Heuristic overcommit handling... This is the default";
  - mode 1 is "Always overcommit";
  - mode 2 is "Don't overcommit... not permitted to exceed swap + a configurable amount (default is 50%) of physical RAM".
- **`mmap(2)`:** `MAP_NORESERVE` means "Do not reserve swap space for this mapping", and an anonymous mapping's "contents are initialized to zero". That pages are backed only when touched is shown by the probes, not by a quote.
- **Windows:** `MEM_RESERVE` "Reserves a range... without allocating any actual physical storage". `MEM_COMMIT` "Allocates memory charges (from the overall size of memory and the paging files on disk)", and "Actual physical pages are not allocated unless/until the virtual addresses are actually accessed". So the Windows data stack must commit as it grows.

### 3.5 Bootstrap practice

- **Go 1.5:** the compiler "was actually moved by automatic translation of the C code into Go"; building it needed "Any Go 1.4 or later distribution". Today: "Go version 1.N will require a Go 1.M compiler, where M is N-2 rounded down to an even number."
- **Rust:** stage 0 (a beta `rustc`) builds stage 1, and stage 1 builds stage 2.
- **OCaml** keeps `boot/` ("a version of ocamlrun and all the *.cm* files of the standard library") and re-bootstraps when formats change.
- **Wheeler's diverse double-compiling (DDC):** "source code is compiled twice: once with a second (trusted) compiler (using the source code of the compiler's parent), and then the compiler source code is compiled using the result of the first compilation. If the result is bit-for-bit identical with the untrusted executable, then the source code accurately represents the executable."
- **Reproducible builds:** "Timestamps make the biggest source of reproducibility issues."

What this means for next-lang:

- **Stage equality is a stability check.** PLAN's stage 2 equals stage 3 shows the compiler reproduces itself.
- **It becomes a DDC check only when stated precisely** (5.4):
  - name the candidate executable;
  - treat Rust `nlc`, and the `rustc` that built it, as the trusted seed;
  - trust clang, the runtime and the linker;
  - compare executables.
- **Copy:** Go's rule that the compiler's source uses only what the pinned stage 0 accepts, and Rust's stage numbering.

### 3.6 Backends and incremental compilation

- **QBE** "aims to provide 70% of the performance of industrial optimizing compilers in 10% of the code".
- **rustc_codegen_cranelift** "has the potential to improve compilation times in debug mode".
- **Zig 0.15** defaults to its own x86-64 backend in Debug ("around a 5x decrease compared to LLVM in most cases"), except on NetBSD, OpenBSD and Windows.
- **TPDE-LLVM** (June 2025): "10-20x faster than the LLVM -O0 back-end", with 10 to 30% larger code, on x86-64 and AArch64.
- **rustc queries** are "memoized" with a red-green graph ("If all the inputs to query Q are colored green... need not be re-executed").
- **Zig incremental** reanalysed a half-million-line codebase in 63 ms after an edit, against 14 s for a full check, and is still "experimental" in 0.15.

For next-lang: keep LLVM IR text. The one sample suggests the `-O1` versus `-O0` choice dominates dev-build time, so try `-O0` or FastISel first, then TPDE, which reads the same IR.

---

## 4. Stack-only plus static-limit design (the core of this report)

### 4.1 The answer, plainly

S1 to S3 can keep all their tables in next-lang locals on the compiling job's data stack (later in frozen batches), with no application heap. The conditions:

1. **Hard: the data-stack reservation is sized from the computed worst case** (T17), not capped at 64 MiB. The tables at S1's documented limits reserve about 567 MiB (4.6).
2. **Hard: exit status and raw byte output** (5.1).
3. **For the memory goal: PLAN's live-elements task** (2.3b; PLAN line 33), and 1-byte buffers (`Bytes`, T16).
   - Without them, S1 still works on a large enough data stack, but touches about 1.1 GB at declaration (4.6).
   - Until struct literals, copies and returns follow the rule, each table must be its own local declared with `list {}` in `main` and passed by pointer: no `Tables { … }` literal, and no helper returning a table.

**Globals aren't needed.** They are touched at startup and count against `globals_budget`. `main(env: Env)` declares the tables and passes them down as `write` parameters, then read parameters. Both are passed by pointer for large values (T13), so nothing is copied.

### 4.2 What must outlive which phase

| Data | Made by | Read by | Sized by |
| --- | --- | --- | --- |
| Source bytes, all files (file-relative offsets, plus a per-file base in the file table) | driver loop | lexer, parser, printer, diagnostics, S2, S3 | package limit, 64 MiB (no slack needed; 4.3) |
| File table `{name, base, length, first token, token count, first node, node count}` | driver loop | everything | 256 files + 1 |
| Read temporary | driver loop | copied into the source buffer | 16 MiB file limit |
| Tokens `{kind, start, len}` | lexer | parser, interning, printer | 4M package + 1M current-file slack |
| Nodes (postorder), plus an extra-data list | parser | printer, S2, S3 | 2M package + current file (≤ 2 per token + 1) |
| Literal values (integer magnitudes, refinement endpoints) | parser | printer, S2 | ≤ number tokens |
| Decoded string bytes | parser | printer, S3 | ≤ source bytes |
| Token-to-name-id array; name table; hash slots | interning (start of S2) | S2, S3 | per token; names ≤ identifier tokens; a measured prefix (4.3) |
| Symbols, types, generic copies, pending tasks | S2 | S2, S3 | proposed limits (4.6) |
| Per-node facts, typed instructions | S2 body waves, copied in at each join | S3 | node limit; instruction limit |
| Per-function scratch and outputs | each S2/S3 chunk | its join | per-chunk limits × wave size |
| IR text | S3 chunks, then the wave result | file writer, then the bridge | per-module limit × wave size |

**Phase hand-off without copying.** Phases hand tables on as read parameters, so the "freeze" is enforced by the checker. With step 6, S1b's per-file builders are frozen "with no copy" (DESIGN, Frozen pools).

### 4.3 How each table is sized

1. **Fixed limits** (syntax-tree-format.md), with capacity set by **when Rust checks**. Per file, `driver.rs` checks in this order:
   1. read the file;
   2. bytes per file;
   3. package bytes, including this file;
   4. UTF-8;
   5. lex, which includes delimiter nesting and the per-file token limit;
   6. package tokens;
   7. parse;
   8. per-file tree counts in the dump writer;
   9. package nodes;
   10. package edges;
   11. work units.

   Before the loop come "package has no .nl source files" and the 256-file limit. So:
   - The package source buffer needs exactly 64 MiB. The file is read into the 16 MiB temporary first. A larger file fails at step 2, and steps 3 and 4 happen before it's copied in.
   - The token list needs 4M + 1M. Rust lexes the whole file (at most 1M tokens) before step 6.
   - The node list needs 2M plus the current file's worst case. The tree is counted only after a successful parse, so a later syntax error in the same file still wins.

   That slack is reserved, not touched.
2. **Derived bounds:**
   - tokens ≤ bytes + 1;
   - literal values ≤ number tokens (plus two endpoints per refined type, each with its own number token);
   - decoded bytes ≤ source bytes;
   - names ≤ identifier tokens;
   - nodes ≤ 2 × tokens + 1 per file (argued in 5.1, and asserted).
3. **Measured prefix:** hash tables use a power-of-two prefix at least twice the number of identifier tokens, so only that prefix is touched.

**Errors.** Limit messages are byte-identical to Rust's, for example "token limit of 4000000 per package exceeded". A `push` returning `err(Full)` maps to the named limit; an unused `Result` is a build error.

### 4.4 Interning

A shared mutable interner is off the table (DESIGN, Frozen pools).

**Recommended: one sequential pass after parsing.** It walks the identifier tokens in file order and writes a dense `name_id` per token (an `int` array the size of the token list), building the name table and its hash prefix. The ids are first-occurrence order, so it's deterministic with no merge.

**Cost (estimate, not measured):** about 200,000 lookups at an assumed 50 ns is 10 ms. Measure it in S1a's benchmark.

If it shows in profiles: per-file tables merged in file order, with a rewrite pass over each file's `name_id` slice.

### 4.5 Parallel checking and emission

- **Chunk rules:** chunks read caller tables through views and write only their own scratch and result slot (DESIGN, Parallel loops).
- **When outputs are copied:** chunks of unknown output size build outputs "on its own stack and the join copies the pieces in index order before those stacks are reset". So **every chunk's outputs stay alive until the join**, alongside the joined copy.
- **Waves:** run each phase in waves of W chunks (W = 64 for S2, 8 modules for S3). Peak = one wave's chunk stacks, plus the package tables the joins copy into.
- **Determinism:** `collect` joins in index order, and `reduce` combines in a fixed tree order. Chunks can't do I/O or read the clock, so output is a function of input.
- **Generic copies:** a bounded fixed point in waves. Check the known set, gather requests in requester order, deduplicate, repeat. A copy-count limit and a work limit both apply.

**Cost versus a heap design.** Allocation becomes a pointer bump, and layout is struct-of-arrays. The prices:

1. Stated limits, raised by rebuilding.
2. Address space at each limit (about 2.4 GiB here, out of a 128 TiB address space).
3. The hash-prefix trick.
4. Per-wave chunk stacks.

### 4.6 Memory map for a 50,000-line program

**Assumptions,** rounded up from 2.3(g):

| Quantity | Assumed | Measured |
| --- | --- | --- |
| Bytes per line | 40 | 24.5 |
| Tokens per line | 10 | 7.6 |
| Nodes per token | 0.5 | 0.44 |
| Literal values | 7,000 (5,000 integer literals + 2,000 refinement endpoints) | not measured |
| Decoded string bytes | 5% of source | not measured |
| Identifier tokens | 40% of tokens | not measured |
| Distinct names | 10,000 | not measured |
| Symbols | 20,000 | not measured |
| Types | 10,000 | not measured |
| Extra-data entries | 0.5 per node | not measured |
| Typed instructions | 1.5 per node | not measured |
| Files | 50, the largest 200,000 bytes, names about 16 bytes | not measured |
| IR | 1,000 bytes per line, i.e. 50 modules of 1 MB | 360 to 920 typical, 6,300 worst |
| Printer stack | 888 entries | measured on 2.3(g)'s benchmark |

**Derived counts:** source 2,000,000 B; tokens 500,000; nodes 250,000; identifier tokens 200,000; extra-data entries 125,000; typed instructions 375,000.

**Record sizes** (today's rules: `int` 4, `long` 8, `bool` 1, struct = sum of fields, one array per field):

| Record | Fields | Size |
| --- | --- | --- |
| Token | `{kind, start, len}` | 12 B |
| Node | `{kind, flags, token, start, end, subtree, extra}` | 28 B |
| File entry | 8 ints | 32 B |
| Literal value | four 32-bit limbs in `long`s, plus `negative: bool` | 33 B |
| Name | `{start, len, hash}` | 12 B |
| Symbol | assumed | 24 B |
| Type | assumed | 32 B |
| Per-node fact | | 8 B |
| Typed instruction | assumed | 16 B |
| Pending task | | 8 B |
| Byte buffers | `Bytes` | 1 B per byte |

"Peak touched" counts bytes written; page rounding adds at most 4 KiB per array lane. The tables assume the live-elements rule, `Bytes`, and `fs.read` no longer clearing its whole buffer.

**S1**

| Table | Capacity | Reserved | Live payload at end | Peak touched |
| --- | --- | ---: | ---: | ---: |
| Source buffer | 64 MiB + 16 MiB | 83,886,080 | 2,000,000 | 2,000,000 |
| Read temporary | 16 MiB | 16,777,216 | 0 | 200,000 |
| File table | 257 × 32 | 8,224 | 1,600 | 1,600 |
| File names | 256 × 255 | 65,280 | 800 | 800 |
| Tokens | 5,000,000 × 12 | 60,000,000 | 6,000,000 | 6,000,000 |
| Nodes | 4,000,002 × 28 | 112,000,056 | 7,000,000 | 7,000,000 |
| Extra data | 8,000,000 × 4 | 32,000,000 | 500,000 | 500,000 |
| Literal values | 5,000,000 × 33 | 165,000,000 | 231,000 | 231,000 |
| Decoded strings | 80 MiB | 83,886,080 | 100,000 | 100,000 |
| Printer stack `{node, depth}` | 4,000,002 × 8 | 32,000,016 | 0 | 7,104 |
| `else if` frames | 1,000,000 × 8 | 8,000,000 | 0 | 160 |
| Delimiter stack | 2,048 × 4 | 8,192 | 0 | 80 |
| Output buffer | 1 MiB | 1,048,576 | 0 | 1,048,576 |
| **S1 total** | | **594,679,720 (567.1 MiB)** | **15,833,400** | **17,089,320 (16.3 MiB)** |

Notes on the S1 table:

- **Source buffer:** revision 2 keeps 80 MiB to be safe; 4.3 shows 64 MiB suffices, which would save 16 MiB of reservation.
- **Printer stack:** 4,000,002 entries is the worst case, a node with every other node as its child. The measured breadth was 888 entries (7,104 bytes).
- **The dump** (about 25 MB here) streams through the 1 MiB buffer and is never held.
- **The output buffer and printer exist only in `parse` mode;** a full compile doesn't run them.
- **Today's runtime** `fs.read` touches the full 16 MiB temporary on every read (it clears it), so the peak rises by 16,577,216 bytes.

**S2** (the limits are proposals)

| Table | Capacity | Reserved | Live payload | Peak touched |
| --- | --- | ---: | ---: | ---: |
| Token name ids | 5,000,000 × 4 | 20,000,000 | 2,000,000 | 2,000,000 |
| Names | 1,048,576 × 12 | 12,582,912 | 120,000 | 120,000 |
| Name hash slots | 2,097,152 × 4 (a 524,288-slot prefix used) | 8,388,608 | 2,097,152 | 2,097,152 |
| Symbols | 1,048,576 × 24 | 25,165,824 | 480,000 | 480,000 |
| Types | 1,048,576 × 32 | 33,554,432 | 320,000 | 320,000 |
| Per-node facts | 4,000,002 × 8 | 32,000,016 | 2,000,000 | 2,000,000 |
| Typed instructions | 8,000,000 × 16 | 128,000,000 | 6,000,000 | 6,000,000 |
| Generic copies | 65,536 × 16 | 1,048,576 | 32,000 | 32,000 |
| Pending tasks | 1,048,576 × 8 | 8,388,608 | 80,000 | 80,000 |
| First diagnostic | 1,000 × 32 | 32,000 | 32 | 32 |
| Body-wave chunk stacks | 64 × 8 MiB (4 MiB scratch + 4 MiB outputs) | 536,870,912 | 0 | 8,388,608 |
| **S2 total** | | **806,031,888 (768.7 MiB)** | **13,129,184** | **21,517,792 (20.5 MiB)** |

The chunk stacks' peak assumes each of the 64 reused stack sets reaches a 128 KiB high-water mark (estimate). The outputs a wave holds on its chunk stacks are inside that figure; their joined copies are in the per-node fact and typed instruction rows.

**S3** (waves of 8 modules)

| Table | Capacity | Reserved | Live payload | Peak touched |
| --- | --- | ---: | ---: | ---: |
| Chunk stacks | 8 × (64 MiB module + 16 MiB function buffer) | 671,088,640 | 0 | 10,097,152 (8 × (1,000,000 + 262,144)) |
| Wave result (collect destination) | 8 × 64 MiB | 536,870,912 | 0 | 8,000,000 |
| Symbol and mangling text | 4 MiB | 4,194,304 | 200,000 | 200,000 |
| **S3 total** | | **1,212,153,856 (1,156.0 MiB)** | **200,000** | **18,297,152 (17.4 MiB)** |

During each join a wave's module text exists twice, once on the chunk stacks and once in the wave result; both are counted.

**Totals**

- Reserved: 594,679,720 + 806,031,888 + 1,212,153,856 = **2,612,865,464 bytes (2,491.8 MiB, 2.43 GiB)**.
- Peak pages touched: 17,089,320 + 21,517,792 + 18,297,152 = **56,904,264 bytes (54.3 MiB)**. This is an upper estimate: data-stack pages stay mapped once touched, and if S3 reuses S2's stack sets from the worker pool, its chunk peak lands on pages already counted.
- Live payload at the end: 15,833,400 + 13,129,184 + 200,000 = **29,162,584 bytes (27.8 MiB)**.
- clang runs as a separate process.

**S1 under today's implementation:**

- The three byte buffers at 4 bytes per byte become 335,544,320 + 67,108,864 + 335,544,320 = 738,197,504 bytes.
- The other S1 tables reserve 410,130,344 bytes.
- Total: **1,148,327,848 bytes (1,095.1 MiB), all touched at declaration.**

That doesn't fit the 64 MiB data stack at all, and as globals it would be touched at startup.

**Where the limits bind:** the 4M-token package limit is reached at about 526,000 lines at the measured 7.6 tokens/line, and 400,000 at the assumed 10.

---

## 5. Per-stage design

Code labelled **accepted today** was compiled and run with `nlc` in `~/shprobe`.

### 5.1 S1: lexer, parser, dumps

**Data (accepted today).** Capacities must be scalar `const`s.

```
const MAX_NODES: long = 4000000L        // package limit plus one file's slack

enum TokenKind { Ident, Number, Newline, LParen, RParen, Plus, Eof }   // the real list has 51 kinds

struct Token {
    kind: TokenKind
    start: int 0..=83886080      // byte offset into the package source buffer
    len: int 0..=16777216
}

struct Node {
    kind: int                     // a NodeKind tag
    flags: int                    // recursive, mutable, inclusive, prefault, negative, long_suffix, mode, op
    token: int                    // index of the node's main token
    start: int                    // span start, bytes
    end: int                      // span end, bytes
    subtree: int 1..=4000000      // nodes in this subtree, itself included (postorder)
}

// Postorder: the children of node i end at i - 1. Walk them right to left.
fn child_count(nodes: list<Node, MAX_NODES>, i: long) -> long {
    var count = 0L
    var child = i - 1L
    let first = i - nodes[i].subtree.to_long() + 1L
    for step in 0L..nodes.count() {          // a counted loop is the step budget
        if child < first { break }
        count += 1L
        child -= nodes[child].subtree.to_long()
    }
    count
}
```

The real `Node` adds `extra: int`, an index into the extra-data list or −1, for 28 bytes in total. The sample omits it.

**Offsets.**

- Token starts and node spans are **file-relative**, which is what the dump prints (syntax-tree-format.md).
- The file table holds each file's base in the package buffer, so the source byte at a file-relative offset is `source[base + offset]`.
- Line and column are computed by the printer with a running counter, and for a diagnostic by scanning from the file's start.

**Node encoding.** Every field in syntax-tree-format.md and `syntax_dump.rs` maps to one of these:

| Field | Encoded as |
| --- | --- |
| `name` fields (functions, structs, lets, parameters, calls, fields, cases) | the node's main token, an identifier; printed from its source text with JSON escaping |
| A second name (`QualifiedCase enum` and `case`; `CasePattern enum`) | a token index in extra data |
| Booleans (`recursive`, `mutable`, `inclusive`, `prefault`, `negative`, `long_suffix`, `value`) | `flags` bits |
| Small enums (`mode`, `Binary op`, `Assign op`, `Unary op`, `LoopExit kind`, `Effect kind`, `policy`) | `flags` bit fields |
| `generics=[...]` (functions, structs) and `indexes=[...]` (`ForEach`) | extra data: a count, then token indexes |
| `Integer magnitude` | an index into the literal-value list |
| Type `range=lower..upper` | extra data: two literal-value indexes (a signed value: magnitude and negative flag, within Rust's i128 rule) plus the inclusive bit; `range=none` when absent |
| `ByteString value` | extra data: start and length in the decoded-string buffer |
| `Effect path`, `Expect source` | extra data: a source byte range |
| Synthetic nodes (zero-width `Call name="default"`, a match-arm `Block`, an `else if` `Block`) | a `synthetic` flag with the explicit spans the format gives; `Program` spans the whole file |

Children are created in **dump order**, which is written order. That includes `pool<T, N, Owner>`, which the Rust AST stores split and the dump restores. Every subtree is contiguous.

A sentence in syntax-tree-format.md should name this encoding the S1 contract, and every field should have a corpus case.

**The 2-nodes-per-token bound** (argument, then a check). Every non-synthetic node owns a distinct main token: a keyword, a name, an operator, `{` or a number. Rust's tree has a few places where a second node shares a token:

- synthetic blocks;
- a shorthand initializer field;
- a type node under a parameter name.

None has more than one extra node per token, plus one `Program` per file, so nodes ≤ 2 × tokens + 1 per file. S1 asserts this as it builds. A fuzz test and the corpus check it. If it ever failed, the node list's `Full` would report as an internal error, never as a wrong limit message.

**No hidden nodes.** S2 finds where a scope opens from subtree sizes: block *i* opens at index *i* − subtree(*i*) + 1. Nothing is added that would change Rust's node, edge or work counts.

**Lexer:** one flat loop per file, with a `list<int, 2048>` delimiter stack.

**Parser: where it may recurse.** Rust's counters (Sol's finding 6):

- **Expressions:** `expression()` is limited to depth 2,048 (`EXPRESSION_PARSER_STACK_LIMIT`), but the error message says 1000. A probe rejected 2,049 nested `!` at the 2,049th operator.
- **Blocks:** `block()` is limited to depth 1,000.
- **Parentheses:** 1,000 (in `grouped_expression`).
- **Types:** 1,000.
- **`else if`:** `if_expression` calls itself for `else if` with **no counter**. Rust parses chains of any depth up to the token limit (123,999 levels in the 2.3g probe), then rejects them in the completed-tree walk.

S1 therefore:

- **Recurses (marked `recursive`) only along counted paths.** Expression depth is at most 2,048 and block depth at most 1,000, so the recursion depth is bounded by about (2,048 + 1,000) levels × the functions per level (about 4).
- **Native-stack estimate,** to be measured: 12,000 frames at about 300 bytes is about 3.6 MB. That fits the process's default 8 MiB main stack, minus T19's 80 KiB margin.
- **Acceptance:** a fixture combining 2,048 nested prefix operators, 1,000 nested blocks, 1,000 parentheses and 1,000-deep types runs under S1's recursion budget with at least a 2× margin reported. A path that misses the margin moves to explicit frames.
- **Parses `else if` chains with explicit frames.** A loop consumes `else if cond { … }` repeatedly, pushing a pending frame per level. Each frame holds the `If` node's first-node index, its start byte and its then-block's end. After the final `else { … }` (or none), it closes the frames innermost-first, emitting each synthetic `Block` and its `If` in postorder.

  Tokens are consumed in the same order as Rust, so syntax errors inside the chain come out identically. The frame list is bounded by tokens per file / 2, since each `else if` takes at least 2 tokens; the map reserves it at 1,000,000.

**The completed-tree nesting walk.** After each outermost expression (depth 0), Rust runs `expression_nesting_exceeded`, an explicit-stack depth-first walk over the expression tree:

- the root's depth is 0 for a `print` call, else 1;
- "nesting" kinds add 1;
- children are pushed in a fixed order per kind and popped last-first;
- it reports the first node found deeper than 1,000, at `expression_diagnostic_span` (the operator span for binary nodes).

S1 ports this walk task for task over the expression's contiguous postorder range, pushing children in the same order, and runs it at the same moment, before parsing continues. Node `token` holds the operator for binary and unary nodes, so the span is available. A depth summary computed differently would need its own equivalence argument, so don't.

**Literal limbs** (32-bit pieces of a large number).

- *Storage:* each magnitude is four 32-bit limbs kept in non-negative `long`s.
- *Accumulating digits* is `limb * base + carry`, which never exceeds 2^36 for base 16, so it can't overflow a `long`. A carry out of the top limb, or an empty digit string after `0x` or `0b`, gives Rust's "integer literal is too large to represent; use a smaller value".
- *Range endpoints* additionally check Rust's i128 rule ("range bound is too large to represent").
- *Printing* divides by 10^9 limb by limb; intermediates stay under 2^62.
- *Tests:* decimal, hex and binary at 2^64 − 1, 2^64, 2^127, 2^128 − 1 and 2^128; underscores; `L` and `l` suffixes; negative literals; refinement endpoints at the i128 edges.

**Package flow and errors**, in `driver.rs`'s order (4.3):

- **Listing:** Rust keeps directory entries whose extension is exactly `nl` and for which `is_file()` is true. That follows symlinks, so a dotfile named `.nl` has no extension and isn't kept. It then sorts the paths. S1's `fs.list` sorts by raw bytes, but classifies symlinks as `Other`, so S1 must stat symlink entries, or the corpus must forbid them. Add a test either way.
- **Paths:** filesystem access is rooted at the working directory, so S1 takes a relative package path and the comparison script runs from the repository root.
- **UTF-8:** check before lexing, reproducing Rust's column for the first invalid byte (`invalid_utf8_span`): a one-based byte column from the last newline, `valid_up_to` semantics.
- **Tool failures** print `nlc: tool failure: …` and exit 3. Read errors include Rust's I/O error text (for example `Permission denied (os error 13)`), which needs an errno-to-text table. Until then, compare tool failures by exit status and prefix only.
- **Syntax and limit errors** print `file:line:col: error: …` and exit 2. Nothing goes to stdout unless every file succeeds.
- **Exit status:** today `main` can only exit 0 or 1, and prints an `error:` prefix. S1 needs PLAN's "Exit status for tools (before S1)" item.

**Output.** Dumps contain raw UTF-8 (names and decoded strings), so the 1 MiB output buffer is a byte buffer:

- `list<byte, N>` with `out.write` works today, at 4 bytes per byte;
- `Bytes` after T16.

`Ascii` can't hold it.

**The printer** walks preorder from postorder with an explicit `{node, depth}` stack. Starting from each file's root (its last node), it finds each node's children right to left by subtree sizes and pushes them, so the first child pops first. The pattern (accepted today):

```
var stack: list<long, 64> = list {}
stack.push(2L)?
for step in 0..64 {
    let top = stack.pop() ?? break
    print(nodes[top].kind)
}
```

**Checking S1:**

- byte-identical stdout, stderr and exit status against **live** `nlc parse` (tokens, tree, both, and neither) on `tests/run`, `tests/test` and `tests/parse/cases`;
- every limit at N and N + 1, in each position of the check order (for example, a package-byte overflow in a file that also has a syntax error);
- `else if` chains at 1,000, 1,001 and 123,999 levels;
- the 54,145-line benchmark;
- byte-level fuzzing of corpus files.

**S1b.** Files are read sequentially, because chunks can't do I/O, and reading stops at the first read error or byte-limit failure, exactly as in Rust. Then a `parallel for` lexes and parses one file per builder. Each chunk records its counts and its first error.

A sequential pass in file order then replays steps 4 to 11 of 4.3 with the cumulative counts, and reports the first failure in (file, step) order. Jobs that finish out of order can't change the result.

Then the freeze and the sequential interning pass. It's measured against Rust with equal threads, as the validation plan's parallel-tool row asks.

### 5.2 S2: the checker

**Before S2, two contracts:**

1. `nlc check --dump`, a typed-output format documented like syntax-tree-format.md.
2. **A documented first-error order compatible with the reference.** Rust aborts each phase at its first error. Within the body phase it stops at the first failing function in index order, and within a function at the traversal-first error (`checker.rs`, `run`).

S2 reproduces that order. A global smallest-position rule isn't used: an earlier body error may never be discovered once a later signature error stops the run, and making it work would need error recovery and tie-breaking, a separate tooling change.

**Phases, in the reference's order** (`checker.rs`, `run`):

1. **Registration** (sequential):
   1. type names, aliases, enum cases, struct fields and globals;
   2. recursive value types and type sizes;
   3. constant declarations.
2. **Global initialisers** (sequential).
3. **Function bodies**, in parallel waves (4.5). Each chunk:
   - walks its function's postorder nodes linearly with an explicit value stack;
   - opens scopes at subtree starts;
   - gives an unsuffixed literal a provisional type that its parent resolves;
   - returns its first error, its facts and instructions, its job-local new types and generic-copy requests, and its call edges.

   The wave's error is the one from the lowest-index function. Waves run in index order, so a later wave's error matters only if every earlier function passed.

   Generic copies are appended in requester order and checked in later waves. That matches the Rust loop over a growing function list (`while id < self.ast_functions.len()`), provided Rust appends requests in check order. A test compares the typed dumps' numbering.
4. **Tests,** then **constant expressions** (sequential).
5. **Whole-program analyses:**
   - effect paths, then the call graph and indirect targets;
   - the recursion check and recursive regions;
   - **constant evaluation**;
   - global finishing and initialisation order, then access contracts.

   Constants can call functions (`tests/run/t05_constants`), which is why evaluation comes after bodies and the call graph. Graph walks use explicit worklists.

   The constant evaluator is an explicit-frame interpreter with the reference's limits: a **call depth** of 10,000 (`CALL_DEPTH_LIMIT`, not a count of calls) and 10,000,000 steps.

**Merging job-local results.** A job-local type or copy id can appear in that job's facts, instructions, requests and call edges. The merge assigns package ids in function order, deduplicating against existing entries, then rewrites **every** reference in that job's outputs. That costs work proportional to the job's output, and is counted against a named work limit.

**Checking S2:** typed dumps and the first error equal Rust's on every test package, plus a seeded-slip corpus.

### 5.3 S3: code generation

- **Modules:** one per source file, matching DESIGN's cache unit. Rust emits one module today (`emit.rs`), so IR isn't compared; behaviour is.
- **Ownership:**
  - module 0, the first file, owns the global state block and the startup and entry initialisation;
  - each generic copy belongs to the module whose function first requested it, in S2's deterministic order;
  - every other module `declare`s what it uses.
- **Symbols:** derived from S2's package-wide function, type and copy ids (`nl_fn_<id>`, as today), so they are stable for a given input.
- **Emission:** in waves of 8 (4.5). Each function's text is built in an `Ascii` buffer in append mode, and the caller writes each wave's modules in index order.
- **Determinism:**
  - fixed header and `source_filename = "next-lang"`;
  - no temp-directory names, process ids or times;
  - package-relative paths in any future debug info.
- **The bridge,** until a process capability exists. A Rust-side `nlc` subcommand (proposed: `nlc link-ir <dir> -o <file>`) takes S3's `.ll` files, links them with `llvm-link`, and runs the existing pipeline in `driver.rs`:
  1. a probe build;
  2. reading `.stack_sizes` frame sizes;
  3. patching the recursion checks (`nlc.recursion.targets=`);
  4. rebuilding until the frames stabilise, up to 3 times;
  5. linking the runtime.

  Merely running clang would drop T19's native-stack guarantee. The second clang pass also counts toward build time: T19 measured 0.4 s against 0.18 s for a small program.
- **Checking S3:** stdout, stderr and exit status of every test program equal the Rust-built binaries', at the development level and at `NLC_OPT_LEVEL=3`.

### 5.4 Bootstrap and the Rust reference

**Steps:**

1. Pin stage 0: Rust `nlc` at a tag, with clang 18.1.3, the runtime, target level, flags and paths fixed.
2. Stage 0 builds stage 1; stage 1 builds stage 2; stage 2 builds stage 3.
3. **Stability check:** compare stage 2 and stage 3, IR first for diagnosis, then executables. PLAN calls this stability, not correctness.
4. **Correctness evidence** stays the S1 to S3 comparisons against Rust over valid, invalid, generated and limit-boundary inputs.

**What a diverse double-compiling claim needs,** stated precisely:

- **The candidate:** a named executable claimed to be built from source S. Here that is stage 3, the self-built binary that is shipped.
- **The trusted seed:** Rust `nlc`, and with it the `rustc` that built it, and its source.
- **The trusted toolchain:** clang, the runtime, the linker and the OS.
- **The check:** compile S with the seed (stage 1), compile S with stage 1 (stage 2), and require stage 2 to be bit-identical to the candidate's executable.

If stage 2 equals stage 3, stage 3 reproduces itself and matches the seed-derived build. Under those trust assumptions, that shows stage 3 corresponds to S. It doesn't show that S is correct.

IR equality alone doesn't show executable correspondence: clang and the runtime sit between them. A candidate built elsewhere is checked by rebuilding stage 2 here and comparing executables.

**Source discipline:** the compiler's source uses only features the pinned stage 0 accepts (Go's discipline). Bumping stage 0 is its own commit.

**Real sources of nondeterminism to rule out.** Machine load isn't one; output depends only on input.

- *Hash order:* T09 iterates in insertion order, and hand-written tables are never iterated for output.
- *Parallel joins:* index order and fixed reduce trees.
- *Directory order:* raw-byte sort.
- *Timestamps and paths:* none emitted.
- *Stale bytes past live elements* (2.3b) leaking into equality, hashing or output.
- *Tool versions:* pinned.

### 5.5 Room for incremental compilation

- Per-file partitions (S1b), so one file's tree can be replaced.
- Content hashes per file and per declaration interface, as DESIGN's cache keys need.
- Stable identity by (package, declaration name), not by first-occurrence name ids.
- Side tables kept per file.

---

## 6. Features the compiler needs, ranked

**Hard S1a blockers** (no workaround that keeps parity):

1. **Exit status for tools.** In PLAN (line 34). S1 must exit 2 and 3.
2. **A data stack sized past 64 MiB (T17).** The tables at the documented limits reserve about 567 MiB. A temporary workaround is a larger hard-coded reservation behind a manifest key.
3. **Raw byte output and byte buffers.** Works today with `list<byte, N>` at 4 bytes per byte; `Bytes` (T16) fixes the cost.
4. **Explicit-frame `else if` parsing and the ported nesting walk.** Design work in S1, not a language feature.

**Hard for the memory goal** (S1 runs without them, at about 1.1 GB touched):

5. **The live-elements task.** In PLAN (line 33) with Sol's rules. Revision 2 adds:
   - report peak pages touched separately from live payload;
   - update the byte-buffer layout shared with the C runtime when `byte` or `Bytes` storage changes.
6. **1-byte buffers** (`Bytes`, T16). A primitive 8-bit `byte` type is a separate decision from packed lanes: DESIGN's "ranges pick storage" already keeps declared arithmetic while narrowing storage, so it would also shrink `byte` lists. Either suffices.

**Conveniences with workarounds:**

7. **Capacity inference from `list` arguments.** Workaround: concrete `const` capacities.
8. **Capacities from `const` struct fields.** Workaround: scalar `const`s.
9. **Array and list literals** (scheduled before S1). Workaround: `fill` plus element writes, or `match` tables for keywords.
10. **128-bit integers.** Workaround: limbs (5.1).
11. **Typed indexes.** Workaround: one-field wrapper structs; later, newtypes or owner-typed append-only ids.
12. **Reading into the tail of a buffer.** Workaround: the 16 MiB temporary plus a copy.
13. **A process capability.** Workaround: the Rust bridge (5.3).
14. **Chunked file writing.** Workaround: per-module whole-file writes.
15. **Builders, `freeze`, `parallel for`.** Needed for S1b, S2 and S3 parallelism only; schedule them after S1a.

**Not needed:** `while` (counted loops with `break` cover it), and interfaces (hash tables over spelling ranges are hand-written).

---

## 7. Risks and open questions for Ben

1. **Lazy globals?** The brief assumed them; the design says no. *Recommendation:* keep DESIGN's rule. The compiler doesn't need globals.
2. **The first-error order in S2.** *Recommendation:* document the reference's phase, function and traversal order (5.2) before S2. Treat any smallest-position rule as a separate later change.
3. **The native stack in S1.** Rust's counters bound it except for `else if`. *Recommendation:* use explicit frames there, measure the rest with T17 against a 2× margin, and convert any path that misses it.
4. **The reference's own deep-chain cost.** Debug Rust used 1.34 GB peak memory on the 123,999-level `else if` probe, on its 1 GiB-stack thread. *Recommendation:* give Rust's `else if` path a counter or a loop too, if Ben agrees. That would change the reference's behaviour (an earlier diagnostic), so it needs a format-document note and new dumps.
5. **Limits are compile-time.** *Recommendation:* document every limit and message, and ship generous values; reservations cost nothing once the live-elements task lands.
6. **Windows** commit charging (3.4). *Recommendation:* the data stack commits as it grows; Linux comes first.
7. **The 3-second aim.** *Recommendation:* measure per-module rebuilds once S3 runs, including the bridge's second clang pass; try `-O0` or FastISel before any new backend.
8. **A moving language.** *Recommendation:* the stage-0 discipline, and start S1a only after the hard items.
9. **Bugs that reinforce each other.** *Recommendation:* keep fuzzed, boundary and test-suite comparisons, and keep reference changes (like item 4) explicit.

---

## 8. Proposed PLAN.md changes

Listed only; PLAN.md is not edited here. Items PLAN already has are not repeated: live elements (line 33) and exit status (line 34).

1. **Live-elements task (line 33):** add acceptance for reporting peak pages touched separately from live payload, and for the C runtime's byte-buffer layout when `byte` or `Bytes` storage changes.
2. **T17:** no 64 MiB cap; a case with a computed reservation over 600 MiB that touches about 20 MB.
3. **Split S1** into S1a (sequential; after T16 to T18 and items 1 to 4 of section 6; byte-identical against live `nlc parse`) and S1b (parallel; with step 6; the parallel-tool validation program).
4. **Schedule DESIGN step 6** as T-tasks right after S1a, with S1b as their acceptance program.
5. **An S1 contract note in syntax-tree-format.md:**
   - the check order of 4.3;
   - the node encoding of 5.1;
   - the nodes ≤ 2 × tokens + 1 bound;
   - the `else if` behaviour.
6. **Before S2:** `nlc check --dump`, and a documented first-error order (phase, then function index, then traversal).
7. **S3:** a Rust-side `nlc link-ir` bridge that keeps frame-size measurement and recursion-check patching.
8. **Bootstrapping:** state the stability check (stage 2 equals stage 3, executables) separately from a diverse double-compiling claim with its trust assumptions (5.4). Add the stage-0 source rule.
9. **Optional, Ben's call:** a counter or loop for `else if` in the Rust parser (risk 4).
10. **Scheduler follow-ups:** Windows data stacks commit as they grow.

---

## 9. Sources

Fetched while writing this report (October 24, 2026):

**Zig**

- Zig PR #7920: https://github.com/ziglang/zig/pull/7920
- Zig `Ast.zig`: https://raw.githubusercontent.com/ziglang/zig/master/lib/std/zig/Ast.zig
- Zig `InternPool.zig`: https://raw.githubusercontent.com/ziglang/zig/master/src/InternPool.zig
- Zig 0.8.0 release notes: https://ziglang.org/download/0.8.0/release-notes.html
- Zig 0.14.0 release notes: https://ziglang.org/download/0.14.0/release-notes.html
- Zig 0.15.1 release notes: https://ziglang.org/download/0.15.1/release-notes.html
- Goodbye to the C++ Implementation of Zig: https://ziglang.org/news/goodbye-cpp/

**Carbon and TypeScript**

- Carbon toolchain docs: https://docs.carbon-lang.dev/toolchain/docs/
- Carbon parse docs: https://docs.carbon-lang.dev/toolchain/docs/parse.html
- Carbon PR #4124: https://github.com/carbon-language/carbon-lang/pull/4124
- TypeScript native port: https://devblogs.microsoft.com/typescript/typescript-native-port/
- TypeScript 7.0 Beta: https://devblogs.microsoft.com/typescript/?p=5152

**Static allocation and coding rules**

- TIGER_STYLE.md: https://raw.githubusercontent.com/tigerbeetle/tigerbeetle/main/docs/TIGER_STYLE.md
- TigerBeetle, A Database Without Dynamic Memory Allocation: https://tigerbeetle.com/blog/2022-10-12-a-database-without-dynamic-memory/
- Power of Ten (quoted from): https://en.wikipedia.org/wiki/The_Power_of_10:_Rules_for_Developing_Safety-Critical_Code; the paper: https://spinroot.com/gerard/pdf/P10.pdf
- MISRA C:2012 Rule 21.3 (MathWorks): https://www.mathworks.com/help/bugfinder/ref/misrac2012rule21.3.html
- JPL C coding standard: https://www.slideshare.net/slideshow/jpl-coding-standard-for-the-c-programming-language/226808547

**Regions and arenas**

- Region-based memory management (secondary source for the Tofte-Talpin, MLKit and Cyclone statements): https://en.wikipedia.org/wiki/Region-based_memory_management
- rustc memory: https://rustc-dev-guide.rust-lang.org/memory.html
- LLVM `Allocator.h`: https://llvm.org/docs/doxygen/Allocator_8h.html

**Operating systems**

- Linux overcommit accounting: https://docs.kernel.org/mm/overcommit-accounting.html
- Linux `mmap(2)`: https://man7.org/linux/man-pages/man2/mmap.2.html
- Windows `VirtualAlloc2`: https://learn.microsoft.com/en-us/windows/desktop/api/memoryapi/nf-memoryapi-virtualalloc2

**Compiler limits and small compilers**

- C11 draft N1570: https://port70.net/~nsz/c/c11/n1570.html
- MSVC compiler limits: https://learn.microsoft.com/en-us/cpp/cpp/compiler-limits?view=msvc-170
- GCC preprocessor limits: https://gcc.gnu.org/onlinedocs/cpp/Implementation-limits.html
- Tiny C Compiler: https://bellard.org/tcc/

**Bootstrap and reproducibility**

- Go 1.5: https://go.dev/doc/go1.5
- Go from source: https://go.dev/doc/install/source
- rustc bootstrapping: https://rustc-dev-guide.rust-lang.org/building/bootstrapping/what-bootstrapping-does.html
- OCaml BOOTSTRAP.adoc: https://raw.githubusercontent.com/ocaml/ocaml/trunk/BOOTSTRAP.adoc
- Wheeler, DDC: https://dwheeler.com/trusting-trust/
- Reproducible Builds, timestamps: https://reproducible-builds.org/docs/timestamps/

**Backends and incremental compilation**

- QBE: https://c9x.me/compile
- rustc_codegen_cranelift: https://github.com/rust-lang/rustc_codegen_cranelift
- TPDE-LLVM: https://discourse.llvm.org/t/tpde-llvm-10-20x-faster-llvm-o0-back-end/86664
- rustc queries: https://rustc-dev-guide.rust-lang.org/query.html
- rustc incremental: https://rustc-dev-guide.rust-lang.org/queries/incremental-compilation.html

**Local sources** (this repository):

- docs: DESIGN.md, PLAN.md, syntax-tree-format.md; tasks/T08, T13, T19, T20 and T21 reports; reviews/claude-selfhost.md, sol-selfhost-r1.md, sol-S0-r1.md, sol-selfhost-arch-r1.md, and claude-T13, T19, T20 and T21 reviews;
- compiler/src: emit.rs, checker.rs, const_eval.rs, parser.rs, driver.rs, syntax_dump.rs, typed.rs, main.rs;
- runtime/nl_runtime.c.
