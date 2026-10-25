# Self-hosted compiler architecture for next-lang (research report)

Oct 24, 2026. Written for Ben. It replaces a rejected draft. Facts about other projects carry a link in the Sources section (section 9), each fetched while writing this. Facts about next-lang come from this repository at commit `612245e` (T14 prompt) and from probes run in WSL. The probes used an `nlc` debug binary copied from `~/.cache/next-lang/target/debug/` and lived in `~/shprobe`, outside the repository. Numbers I estimated, rather than measured or fetched, say so.

Terms used throughout:

- **Reserved:** address space set aside but not yet backed by RAM.
- **Touched** (or committed-and-used): pages actually written, so they cost RAM.
- **Postorder:** children are stored before their parent.
- **Interning:** storing each distinct name once and using a small number for it after that.
- **Stage N:** the compiler binary produced at bootstrap step N.

---

## 1. Recommendation (one page)

**The core idea:** keep every compiler table in a local collection on the compiling job's data stack. Reserve each table at a stated limit, and pay RAM only for what a program actually uses. Today that idea is blocked by implementation facts found while writing this (section 2.3):

- **Globals are touched in full at startup**, with or without `--allow-overcommit`.
- **The emitter writes whole collections, not just their live elements.** That happens when it creates an empty `list` or `pool`, builds a struct holding one, and returns or copies one.
- **`byte` takes 4 bytes.**
- **The data stack is fixed at 64 MiB.**

Three conditions remove the blocks (section 4.1):

1. No emitter path writes or copies a collection past its live elements.
2. Byte buffers take 1 byte per byte.
3. T17 sizes data stacks past 64 MiB.

With those in place, a 50,000-line program needs about 1.3 GiB of reserved address space and about 35 MiB of touched RAM (section 4.6). The design has no heap anywhere.

**S1, split in two:**

- **S1a (sequential), right after M3 plus the fixes in section 6.** A lexer and parser in next-lang that reproduce `nlc parse --tokens --tree` byte for byte, including stderr and exit status. The comparison runs over every package under `tests/`, the parse cases, and generated limit and fuzz inputs.
  - **Data:** one source buffer per package, a token list and a postorder node list. Nodes are linked by `int` indexes, with a subtree size per node, so there is no child-edge array. These follow Carbon's and Zig's layouts.
  - **Parsing:** recursive descent marked `recursive`, mirroring `parser.rs` function by function, so the first error and the order in which limits trigger come out the same as in Rust.
  - **Output:** the printer is an explicit-stack loop, not recursion. Output is streamed through a 1 MiB buffer.
- **S1b (parallel), once DESIGN step 6 exists** (builders, `batch`, `freeze`, `parallel for`; not yet scheduled as T-tasks). The same parser runs one file per chunk into per-file builders, which are then frozen into one batch. This is the validation plan's "parallel tool" program, measured against the Rust parser.

**S2, the checker:**

- **No deep recursion.** Explicit work stacks, and linear passes over postorder node arrays, as the T19 review already advised.
- **Interning:** one sequential interning pass right after parsing gives every name a package-wide id. That beats per-job tables merged later, because it is simple, deterministic and cheap (section 4.4).
- **Phases:**
  1. Declarations and signatures are checked sequentially and the results are frozen.
  2. Function bodies are checked in parallel. Each job keeps its own scratch, and its results go back through `collect` in function-index order.
  3. Any new types or generic copies a job finds are merged after the join, in that same order.
- **Comparison with Rust:** typed dumps and the first diagnostic. This needs a new `nlc check --dump` format and a documented error order (section 8).

**S3, code generation:**

- Keep emitting LLVM IR text and building it with clang, as Rust `nlc` does, so behaviour can be compared directly.
- Emit one module per source file. Run modules in parallel waves, each wave collected in index order and written out before the next starts. That bounds memory to the wave, not the program.
- Until a process capability exists, have the Rust driver (or a script) run clang on the files S3 writes.
- A fast debug backend (QBE, Cranelift, TPDE or similar) waits until measurements show clang is what breaks the 3-second aim.

**Bootstrap:**

1. The pinned Rust `nlc` (stage 0) builds stage 1.
2. Stage 1 builds stage 2, and stage 2 builds stage 3.
3. Require stage 2's IR text to equal stage 3's IR text byte for byte. Then compare binaries built with the pinned clang.

Because stage 1 was compiled by a different compiler (Rust `nlc`), step 3 is in effect Wheeler's diverse double-compiling check. The Rust `nlc` stays the behavioural reference until Ben decides to retire it.

**Most important PLAN changes** (all in section 8):

- O(1) empty collections.
- Data stacks above 64 MiB.
- Real 8-bit storage for `byte`.
- Capacity generics inferred from `list` arguments.
- The S1a/S1b split.
- A typed-dump task before S2.

---

## 2. Current state and constraints

### 2.1 Status (from docs/PLAN.md and the reviews)

| Item | State |
| --- | --- |
| M0, M1, M2 (T01 to T12) | done |
| M3 T13: data stack, regions, destination emission | done (claude-T13-review.md) |
| S0: T19 `recursive fn` with native-stack budget; T20 files, arguments and output through capabilities; T21 `nlc parse` and docs/syntax-tree-format.md | done (claude-T21-review.md: "With T19 and T20 this completes S0") |
| M3 T14: `Ascii` values in regions | in progress (prompt committed in `612245e`; another agent is editing compiler/ now) |
| T15 append mode and loop growth; T16 `Text`, `Bytes`, growing values in collections; T17 per-entry-point reservations and `inspect stacks`; T18 number parsing and formatting | to do, in that order |
| Layout follow-up (nested lanes flattened) and array/list literals | scheduled before M4 / before S1 |
| Builders, `freeze`, `batch`, `parallel for` (DESIGN first step 6) | designed, not scheduled as a T-task |
| Process capability (run clang) | effects step, "M5-ish" in the prerequisites table |
| S1, S2, S3 | after M3 |

Sol's S0 review said S0 plus M3 supports only a **sequential** S1. The parallel frozen-pool S1 needs step 6 (sol-S0-r1.md, verdict). That is why this report splits S1.

### 2.2 What next-lang gives a compiler writer today

All of the following were checked against fixtures, or compiled with `nlc` in my probes:

- **Declarations:** `struct` with field defaults; `enum` with payloads; exhaustive `match`; `Option` and `Result` with `?` and `??` (including `?? break`, `?? continue` and `?? return`); `const` with compile-time evaluation.
- **Collections:** `list<T, N>`, `pool<T, N>` and `pool<T, N, Owner>`, `map<K, V, N>`, `set<K, N>`, `queue`, `ring`, `grid`, `T[N]`. Collections of structs are stored as one array per field, which is Zig's MultiArrayList layout for free.
- **Methods and loops:** `push`, `pop`, `get`, `set`, `remove`, `count`, `sort_by` and `binary_search`. Loops are `for i in a..b` and `for x, i in xs`, with `break` and `continue`.
- **Parameters and functions:**
  - `write` parameters;
  - large values passed by pointer and large results built in the caller's destination (T13);
  - function values without closures (T11);
  - `recursive fn` with a native-stack byte budget (T19).
- **Capabilities and I/O (T20):** `fn main(env: Env) -> Result<(), E>`, with `env.fs`, `env.out` and `env.args()`. `fs.read` and `fs.list` fill bounded `list`s; `fs.list` sorts by raw bytes. `out.write` and `out.line` return `Result`.
- **Arithmetic:** wrapping operators `+%`, `-%`, `*%`, and `^`, `&`, `|`, `<<`, `>>`. That is enough for a hand-written FNV-1a hash (verified: FNV-1a of `"ab"` printed 1294271946, which is 0x4D2505CA).
- **Limits machinery:** `nlc inspect memory`, `nlc inspect contracts`, and the manifest keys `job_headroom`, `globals_budget` and `recursion_budget`.

There is no `while` or `loop`. A loop of unknown length is a counted loop with `break`: `for step in 0..LIMIT { let top = stack.pop() ?? break ... }`. That loop also serves as the step budget DESIGN asks for (PLAN's "steps" limit).

### 2.3 Facts that change the memory design

**(a) Globals cost RAM in full from startup, in every mode.**

- DESIGN "Static allocation" says globals are "reserved and committed" at startup. Outside strict overcommit, the runtime "touches the state's pages before scheduling any job".
- T08's report says "All globals are touched at startup on Linux".
- In the code, `nl_claim_memory` in `runtime/nl_runtime.c` runs its page-touch loop whether or not `--allow-overcommit` is given. The flag skips only the policy checks.
- Probe: a `global` holding a 48,000,000-byte `list<long, 6000000>` with nothing in it ran at 48,400 KB maximum resident memory (RSS), with and without `--allow-overcommit`. An empty program ran at 1,584 KB.

The brief behind this report assumed globals are committed only when touched. That isn't so: DESIGN, T08 and the runtime all say otherwise. Lazy commit holds today only for the **job data stack**. `nl_context_create` maps it with `PROT_NONE` and `MAP_NORESERVE`, then makes it writable, and the kernel backs pages on first touch.

So a compiler's big tables belong in **locals** on the data stack, or later in builders and frozen batches, which DESIGN also commits as used. They don't belong in globals.

**(b) Today an empty collection touches its whole capacity.**

- In `compiler/src/emit.rs`, the emitter's destination path handles `EmptyList`, `EmptyMap`, `EmptySet`, `EmptyQueue` and `EmptyRing` with an `llvm.memset` over the full type size.
- `EmptyPool` also loops over every slot, writing its free-list entry and generation (`pool.init.to.cond`).
- Probes:
  - A local `list<long, 6000000> = list {}` holding one element: 48,224 KB RSS.
  - A local `pool<Node, 2000000>` of a 12-byte struct (21 bytes per slot with its flag, generation and free-list entry): 42,416 KB RSS.

The literal isn't the only path. In the same file:

- `StructConstruct`, `Construct` (enum payloads) and `Fill` memset their whole destination.
- Copies and returns `memmove` the full type size.
- Probes:
  - A struct `Tables { xs: list<long, 6000000>, n: int }` built with a struct literal and holding one element: 48,224 KB RSS.
  - A function returning a `list<long, 2000000>` (16 MB) holding one element: 32,736 KB, i.e. both the callee's local and the caller's destination touched in full.
  - `inspect contracts` shows why: at 3,000,000 elements, the callee needs 24,000,008 bytes for its own local and the caller reserves another 24,000,008 for the destination. That's because returning a local collection isn't yet built in the caller's destination. T14 does that only for `Ascii`.
- **What is already right:** list equality walks only up to `count()` (`emit_collection_equal`).
- **What needs care:** maps and sets probe arbitrary slots, so their occupancy flags (1 byte per slot) must stay zero-initialised even when keys and values aren't.

DESIGN's rule that a large local collection "is committed only as it's used" therefore isn't implemented yet. The fix is one emitter-wide rule: **no path writes, copies, compares or hashes a collection past its live elements**, except a map's or set's occupancy flags. This is the single most important fix for the compiler (section 6, item 1).

**(c) `byte` is stored in 4 bytes.**

`byte` is defined in `checker.rs` as a refinement of `int` (0..=255). Refinements are laid out at their base type's width (`type_size` in emit.rs), so `list<byte, N>` takes 4N bytes.

DESIGN's "ranges pick storage" (a field `int 0..=1000` stored in 16 bits) isn't implemented either. Every `int`-based field is 4 bytes, `long` 8 and `bool` 1.

The implementation has only `int`, `long` and `bool` as number types. There are no unsigned or 8-bit or 16-bit types yet, and no 128-bit type. Yet S1 must print integer-literal magnitudes up to 2^128 − 1 exactly (syntax-tree-format.md).

**(d) The data stack is 64 MiB, fixed.**

`nl_data_stack_reservation()` returns 67,108,864 bytes. T17 replaces this with a per-entry-point computed worst case, and section 4 needs that number to go well past 64 MiB.

**(e) Capacity generics and constants.**

- `fn total<N>(xs: list<int, N>)` fails with "cannot infer generic parameter 'N'; pass a pool or id that determines it". Inference works from pools and ids, not lists.
- A capacity must be "a constant integer expression; use a literal or const value". `const MAX_NODES: long = 1000L` works as a capacity; a field of a `const` struct (`LIMITS.max_nodes`) doesn't.

Both matter, because a compiler wants its limits in one struct (section 6).

**(f) The Rust reference itself.**

- `compiler/src/` is about 34,900 lines: checker 13,421, emitter 11,647, parser 2,572, lexer 455.
- It uses heap vectors, boxed trees and hash maps.
- The whole compile runs on one thread with a 1 GiB stack (`COMPILER_STACK_SIZE`), reserved but not touched. T19 measured debug-build frames of 5 to 80 KB per nesting level (parser 12 KB and checker 15 KB per level after the frame split).
- The checker returns a single `CheckError`, and the parser reports only its first diagnostic.

**(g) Size and speed baselines, measured in WSL** on an Intel Core Ultra 9 185H, 22 logical cores, `vm.overcommit_memory = 0`:

- *Parse-able test corpus* (269 packages, generated stress fixtures excluded): 3,808 lines, 99,634 bytes, 31,187 tokens and 13,982 nodes.
- *A 54,145-line benchmark* (that corpus concatenated 13 times into 13 files, 1,327,053 bytes):
  - 410,163 tokens and 182,416 tree nodes, i.e. 24.5 bytes/line, 7.6 tokens/line and 0.44 nodes/token;
  - the dump is 20,516,871 bytes, about 24 bytes per token line and 47 per node line;
  - debug Rust `nlc parse --tokens --tree` takes 0.45 s at 52,872 KB maximum RSS.
- *Generated LLVM IR*: a 6,130-byte fixed prelude, then about 360 to 920 bytes per source line on four fixtures. The map-heavy `t09_maps_sets` is the outlier, at about 6,300 bytes per line (1,005,082 bytes for 159 lines).
- *clang 18.1.3 on that 1 MB IR file*: 0.08 s at `-O0`, 0.56 s at `-O1` and 0.68 s at `-O2`. That is one sample, three functions, single-threaded.

---

## 3. Survey: what to copy and what not to

### 3.1 Data-oriented compilers

**Zig.**

- *AST layout:* PR #7920 (merged February 2021) stores tokens and AST nodes as struct-of-arrays.
  - A token is 5 bytes (a 1-byte tag and a 4-byte offset).
  - A node is 13 bytes: a 1-byte tag, a 4-byte `main_token` and an 8-byte `lhs`/`rhs` pair.
  - Anything bigger goes into an `extra_data` array.
  - The PR's own line is that "the only purpose of an AST is to bring a tree structure to a list of tokens."
  - Measured with `zig fmt` on the standard library: 19.3% less peak memory and 11.4% faster wall-clock time. The rework had 34.5% more cache misses, yet fewer cycles.
- *Index types:* in today's `lib/std/zig/Ast.zig`, `TokenIndex = u32` and `Node.Index = enum(u32)`. The tree holds `source`, `tokens`, `nodes` and `extra_data: []u32`.
- *Speed:* the 0.8.0 release notes report tokenize, parse and ZIR together at 8.9 million lines per second on the standard library (292,458 lines in 33 ms, 8-core i9-9980HK). A later ZIR layout change cut a synthetic benchmark's peak memory from 645 MiB to 386 MiB.
- *InternPool:* `src/InternPool.zig` is "self-contained". It is sharded per thread ("one item per thread, indexed by `tid`"), with atomically published shared parts.
- *Bootstrap:* "Goodbye to the C++ Implementation of Zig" (December 7, 2022) replaced an 80,000-line C++ compiler with `zig1.wasm` (2.6 MiB, 2.4 MiB after `wasm-opt`, 637 KB compressed) and about 4,000 lines of portable C. `wasm2c` turns `zig1.wasm` into C, the system C compiler builds `zig1`, `zig1` builds `zig2.c`, and `zig2` builds the final compiler. Debug-build peak RSS fell from 11.3 GiB to 3.8 GiB.

**Copy from Zig:** struct-of-arrays tokens and nodes, 32-bit indexes, and a side array for variable-length data.

**Don't copy from Zig:**

- *The atomically shared InternPool.* next-lang has no shared mutable state outside a writer.
- *The wasm bootstrap, for now.* Zig's motive was deleting a second compiler. next-lang wants to keep its second compiler, the Rust `nlc`, as the reference.

**Carbon.** Carbon's toolchain docs:

- *Storage:* "Data is stored in vectors and flyweights are passed around, avoiding more typical heap allocation with pointers". A parse node is a 32-bit index.
- *Postorder tree:* "The parse tree's storage layout is in postorder", with a `subtree_size` per node. It is "most efficient to process the parsed output in postorder; this affects checking."
- *No recursion:* the parser is a state stack. The loop "pops the next state off the stack, and dispatches to the appropriate `Handle` function", because "Complex code must not cause recursion issues. We have experience in Clang seeing stack frame recursion limits being hit in unexpected ways".
- *Speed:* Carbon PR #4124, which added end-to-end benchmarks, measured lexing at about 5.02 million lines/s, parsing at 1.73 million and checking at 705 thousand at 262,144 lines, and called that "2x behind on lex and check, 5x on parse" of its goals.

**Copy from Carbon:**

- postorder plus subtree size;
- checking as a linear walk over postorder nodes;
- for S2, the state-stack idea for walks whose depth isn't capped.

**Don't copy from Carbon, yet:** a state-machine parser for S1. Reproducing Rust's diagnostics byte for byte is far easier with the same recursive structure, and nesting is already capped at 1,000 (section 5.1).

**TypeScript's Go port.**

- *Results:* the announcement (March 11, 2025) measured VS Code (1,505,000 lines) going from 77.8 s to 7.5 s, with "roughly half" the memory.
- *Parallel design:* the 7.0 beta post (April 21, 2026) says it "performs many steps in parallel, including parsing, type-checking, and emitting", with "a fixed number of type-checker workers with their own view of the world" (four by default). Workers "may end up duplicating some common work, but given the same input files, they will always divide them identically and produce the same results."

**Copy from TypeScript:** this is exactly next-lang's per-job caches, with a fixed, deterministic division of work.

**Odin and Jai:** I found no primary source on their compiler internals worth citing, so I've left them out.

### 3.2 Static allocation and fixed limits

- **TigerBeetle's TIGER_STYLE.md:**
  - "All memory must be statically allocated at startup. No memory may be dynamically allocated (or freed and reallocated) after initialization."
  - "Put a limit on everything because, in reality, this is what we expect—everything has a limit."
  - "Do not use recursion to ensure that all executions that should be bounded are bounded."

  Its blog states "TigerBeetle allocates no memory after startup", with memory "calculated with a bit of addition and multiplication at startup" from limits such as the most client connections.
- **NASA/JPL Power of Ten (Holzmann, 2006):**
  - Rule 1 forbids "direct or indirect recursion".
  - Rule 2: "Give all loops a fixed upper bound".
  - Rule 3: "Do not use dynamic memory allocation after initialization."

  JPL's 2009 C coding standard repeats both the recursion rule and the allocation rule.
- **MISRA C:2012 Rule 21.3** (quoted by MathWorks; the standard itself is paywalled): "The memory allocation and deallocation functions of <stdlib.h> shall not be used."
- **What next-lang already does better:** these rules are conventions checked by review. next-lang makes the equivalents compiler rules:
  - every collection has a capacity in its type;
  - recursion is opt-in, with a budget;
  - unbounded loops carry a step budget;
  - a full collection is a `Result`.

  It also differs in one useful way: a job's memory is **reserved** at its worst case and **paid** as used, rather than paid at startup. Fixing 2.3(b) is what makes that real.
- **Limits that real compilers ship:**
  - *The C standard.* C11 (N1570 §5.2.4.1) only requires implementations to accept at least "127 nesting levels of blocks", "63 nesting levels of parenthesized expressions within a full expression", "4095 external identifiers in one translation unit" and "4095 characters in a logical source line".
  - *MSVC* documents nesting of compound statements as "generally between 100 and 110".
  - *GCC* says of its preprocessor: "It is intended that there should be as few limits as possible."
  - *Zig* caps tokens and nodes at 2^32 through its `u32` indexes.

  next-lang's published limits (1,000 nesting levels, 4M tokens and 2M nodes per package) are generous by these standards. What's unusual is only that they are documented and reported by name.
- **Small fixed-memory compilers:**
  - *tcc*'s page reports compiling the Links browser (1,950,947 lines) at 859,000 lines/s, against 98,000 for GCC 3.2 at `-O0`, with an executable of about 100 KB.
  - I couldn't verify table sizes or design details for Wirth's Oberon compiler or Turbo Pascal from primary sources, so I make no claims about them.

### 3.3 Regions and arenas

- **Tofte and Talpin's regions** (1997) follow stack discipline: `letregion ρ in e end` creates a region, evaluates, then frees it, last in, first out.
- **MLKit** scaled this to large programs only by adding separate compilation and "a hybrid technique combining region inference with tracing garbage collection". Results ranged "between 10 times faster and four times slower" depending on how "region-friendly" the program was. Regions can hold dead data until freed ("leaks").
- **Cyclone** added explicit regions to a safe C dialect.
- next-lang's data-stack regions are Tofte-Talpin regions with the lifetimes written by the compiler's scope rules instead of inferred.
- **The leak risk applies to the compiler too:** tables live until the compile's scope ends. That's fine for a batch compile, but a long-running language server must run each compile as its own job, so the job's end frees everything.
- **Arenas elsewhere:** rustc allocates "from a global memory pool... from a long-lived arena". LLVM's `BumpPtrAllocator` objects "cannot be deallocated. Their lifetime is tied to the lifetime of the allocator." next-lang's design reaches the same bulk-free behaviour with no allocator call at all, since a region is a pointer bump.

### 3.4 Operating-system facts the design relies on

- **Linux:** the overcommit modes are 0 (heuristic), 1 (always) and 2 ("Don't overcommit... not permitted to exceed swap + a configurable amount (default is 50%) of physical RAM"). `mmap(2)` documents `MAP_NORESERVE` as "Do not reserve swap space for this mapping", and an anonymous mapping's "contents are initialized to zero". That pages are backed only when first touched is shown by the probes, not by a quote: 1,584 KB versus 48,224 KB.
- **Windows:** `MEM_RESERVE` "Reserves a range... without allocating any actual physical storage". `MEM_COMMIT` "Allocates memory charges (from the overall size of memory and the paging files on disk)... Actual physical pages are not allocated unless/until the virtual addresses are actually accessed."

  So on Windows a large reservation is free, but committing it all up front charges the commit limit. The Windows data stack will need to commit in chunks as its top grows. That's runtime work for the Windows port, not a design change.

### 3.5 Bootstrap practice

- **Go 1.5:** the compiler "was actually moved by automatic translation of the C code into Go. It is in effect the same program in a different language". Building it needed "Any Go 1.4 or later distribution". Today: "Go version 1.N will require a Go 1.M compiler, where M is N-2 rounded down to an even number."
- **Rust:** stage 0 is a downloaded beta `rustc`. It compiles the sources into stage 1, and stage 1 rebuilds them into stage 2.
- **OCaml** keeps `boot/` ("a version of ocamlrun and all the *.cm* files of the standard library") and re-bootstraps when bytecode or `.cmi` formats change.
- **Wheeler's diverse double-compiling (DDC):** "source code is compiled twice: once with a second (trusted) compiler... and then the compiler source code is compiled using the result of the first compilation. If the result is bit-for-bit identical with the untrusted executable, then the source code accurately represents the executable."
- **Reproducible builds:** "Timestamps make the biggest source of reproducibility issues."

**Copy from these:** Go's discipline that the compiler's source may use only what the pinned previous compiler accepts; Rust's stage numbering; and stage 2 equals stage 3 as a DDC-style check with Rust `nlc` as the diverse compiler.

**Don't copy, for now:** a checked-in binary seed like OCaml's or Zig's. The Rust compiler is a better seed while it's maintained.

### 3.6 Backends and incremental compilation

- **QBE** "aims to provide 70% of the performance of industrial optimizing compilers in 10% of the code".
- **rustc_codegen_cranelift** "has the potential to improve compilation times in debug mode".
- **Zig 0.15** made its own x86-64 backend the Debug default ("around a 5x decrease compared to LLVM in most cases"), except on NetBSD, OpenBSD and Windows.
- **TPDE-LLVM** (June 2025) reports an LLVM-IR back end "10-20x faster than the LLVM -O0 back-end", with 10 to 30% larger code. It is a drop-in for `-O0` LLVM IR on x86-64 and AArch64.
- **Incremental compilation:**
  - rustc's queries are "memoized" and loaded from disk, with a red-green dependency graph ("If all the inputs to query Q are colored green... need not be re-executed").
  - Zig's incremental mode reanalysed a half-million-line codebase in 63 ms after an edit, against 14 s for a full check (0.14.0 notes). It is still "experimental" in 0.15.

**What this means for next-lang:**

- LLVM IR text keeps the outputs of the Rust and self-hosted compilers comparable, and costs nothing new.
- The 1 MB sample in 2.3(g) took 0.56 s at `-O1` against 0.08 s at `-O0`. That suggests the optimization level, not the IR producer, is where dev-build time goes, so the first fix to try is DESIGN's own open question (`-O0` or FastISel for dev builds). TPDE accepts the same IR text and is a cheap later experiment. A home-made backend is the last resort.

---

## 4. Stack-only plus static-limit design (the core of this report)

### 4.1 The answer, plainly

Yes: S1 to S3 can run with no heap, entirely on next-lang locals on the compiling job's data stack (and later on frozen batches), under three conditions:

1. **No emitter path touches a collection past its live elements** (section 6, item 1). Otherwise every reserved table is paid in full the moment it's declared.

   Until that holds for struct literals, returns and copies too, each table must be its own local, declared with `list {}` in `main` and passed by pointer. Don't wrap tables in a constructed `Tables { … }` struct or return them from helpers.
2. **The data-stack reservation is sized from the computed worst case** (T17), with no 64 MiB cap. Address space is plentiful: DESIGN cites 128 TiB per process, and the whole compiler needs about 1.3 GiB (section 4.6).
3. **Byte buffers use 1 byte per byte** (`Bytes`, T16; or real `byte` storage). Otherwise source text costs four times its size.

**Globals aren't needed and should be avoided.** They are touched in full at startup and they count against `globals_budget`. The compiler's `main(env: Env)` declares its tables as locals and passes them down as `write` parameters, then as read parameters, which pass by pointer for large values (T13), so nothing is copied.

### 4.2 What must outlive which phase

| Data | Made by | Read by | Lives in | Sized by |
| --- | --- | --- | --- | --- |
| Source bytes, all files | driver (sequential I/O) | lexer, parser, dump printer, diagnostics, S2 (spellings), S3 (string constants) | one package buffer, local in `main` | fixed limit: 64 MiB per package + one 16 MiB file of slack |
| Tokens `{kind, start, len}` | lexer | parser, interning pass, printer | package list, local in `main` | fixed limit (4M per package + 1M per file of slack); derived bound: tokens of a file ≤ its bytes + 1 |
| Nodes, postorder | parser | printer, S2, S3 | package list | fixed limit (2M per package) + one file's worst case (bound to verify: ≤ 2 nodes per token) |
| Integer magnitudes (`u128` as two `long`s) | parser | printer, S2 | side list | ≤ number tokens |
| Decoded string bytes | parser | printer, S3 | side buffer | ≤ source bytes |
| Name table and hash slots | interning pass (start of S2) | S2, S3 | `main` locals | names ≤ identifier tokens; slot count = next power of two ≥ 2 × identifier tokens, chosen at run time (4.3) |
| Symbols, scopes, types, generic copies | S2 declaration phase | S2 bodies (read only), S3 | `main` locals | fixed manifest limits (assumed in 4.6) |
| Per-node facts (type, resolution) | S2 body jobs | S3 | `main` locals, filled at join | = node limit |
| Typed instructions | S2 body jobs | S3 | `main` locals, filled at join | fixed limit |
| Per-function scratch (scope stack, local maps, worklist) | each S2 or S3 job | that job | the job's own data stack | fixed per-job limit |
| IR text | S3 jobs | the file writer, then clang | per-job buffers, then a wave buffer; never the whole program | per-module limit × wave size |

**Phase hand-off without copying.** A phase gets its outputs as `write` parameters and passes them on as read parameters. Read mode is enforced by the checker, so the "freeze" is a type-level fact even before `freeze` exists. Large read parameters are passed by pointer (T13 report), so no table is ever copied between phases.

Once step 6 lands (S1b), the parser's tables become per-file builders, and `freeze` turns each into a read-only partition "with no copy" (DESIGN, Frozen pools). Ids then become 64-bit partition-and-row ids, `b.Node.Id`.

### 4.3 How each table is sized, given that untouched reservation is free

Three kinds of sizing, and when to use each:

1. **Fixed limits, written as constants.**
   - The limits S1 must reproduce are fixed by syntax-tree-format.md: 256 files, 16 MiB per file, 64 MiB per package, 1M tokens per file, 4M per package, 2M nodes, 2M child edges, delimiter nesting 2,048, parser nesting 1,000, 72M work units, 1 diagnostic.
   - S2's and S3's limits are new and should be documented the same way.
   - The capacity is the limit plus whatever **slack** is needed to reproduce Rust's timing of the check. `driver.rs` adds a file's bytes, tokens, nodes and edges to the package totals only *after* parsing that file. So if a later file has a syntax error, Rust reports the syntax error, not the node limit.
   - To match that exactly, S1's package lists need room for one more whole file past the package limit, then the same after-file check. That slack is reserved, not touched, so it costs nothing.
2. **Bounds derived from input,** proved by construction:
   - tokens ≤ source bytes + 1 (the `Eof` token);
   - magnitudes ≤ number tokens;
   - decoded string bytes ≤ source bytes;
   - names ≤ identifier tokens.

   These choose capacities or check the fixed ones. They're the "formula its parser proves" DESIGN allows for builders.
3. **Measured, then used as a prefix.** Some structures should *use* only part of their reservation, chosen at run time. Hash tables are the main case: a hash spreads entries over all its slots, so 10,000 names in a 2M-slot table touch nearly every page of it.

   The technique: reserve the table at its limit, count identifier tokens after lexing, and use only a power-of-two prefix twice that count, with the mask held in a variable. Today that is a `list<int, N>` grown to the chosen length, plus a mask. Only that prefix is ever touched.

**Overflow is a named error, never truncation.** Each limit's message names the limit and its value, as Rust's do:

- "token limit of 4000000 per package exceeded";
- "node limit of 2000000 per package exceeded";
- "expression nesting limit of 1000 exceeded".

For S1 these must be byte-identical to Rust's. For S2 and S3, write each message into the format document. A `push` that returns `err(Full)` is mapped to the limit's message at its call site. The rule "an unused `Result` is a build error" (T20) means none can be silently dropped.

### 4.4 Interning and shared tables under "nothing mutable is shared"

DESIGN's frozen-pools section already rules out a shared mutable interner: it must "live on a writer, or be per-thread and merged after the phase". The options:

1. **Per-job tables merged afterwards with deterministic renumbering** (sort by first occurrence in file order). This works, but every id produced in parallel must then be rewritten, which costs a pass over all the trees.
2. **A writer** serialises every lookup through a queue, which is the bottleneck Sol warned about.
3. **One sequential interning pass after parsing (recommended).**
   - A single loop over all identifier tokens in file order builds the package's name table and writes a name id per identifier token into a side array.
   - It's deterministic by construction: ids are first-occurrence order.
   - It needs no merge, and every later phase reads the table frozen.

   **Cost estimate** (not measured): 50,000 lines at 10 tokens/line and 40% identifiers is 200,000 lookups, each a hash of about 8 bytes plus one or two probes. At an assumed 50 ns each that's about 10 ms, well inside the 3-second aim.

   S1b can keep this pass sequential after the parallel parse. If it ever shows up in profiles, files can be interned in parallel into per-file tables, then merged in file order, which is option 1 restricted to names.

S2's declaration phase (symbols, struct layouts, signatures) is sequential for the same reason, and its output is frozen before bodies run in parallel. Bodies that discover new types (a `list<Foo, 8>` written only inside a body) or new generic copies record them in job-local lists with job-local ids. After the join, the coordinator appends them to the package tables in function-index order and rewrites the job-local ids. That rewrite touches only the new entries, not whole trees.

### 4.5 Parallel checking and emission with per-job stacks

- **Chunk rules:** each `parallel for` chunk "runs on stacks of its own" and may read the caller's tables through read-only views. It "may have no effects, and may write only what it owns: its own scratch and its slot of the result" (DESIGN, Parallel loops).
- **S2 bodies:** chunk *i* checks function *i*. Its scratch (scope stack, local symbol map, worklist) is on its own data stack. Its results are its slot of `collect`: per-node facts for its body, typed instructions, discovered types and generic copies, and its first diagnostic.
- **Join order is the determinism rule:** `collect` "copies the pieces in index order", and `reduce` combines "in a fixed tree order, whatever the scheduling". Since chunk bodies can't do I/O, read the clock, or write shared state, the output is a function of the input alone. Work stealing changes only the timing.
- **S3 emission:** chunk *i* emits module *i* (one per source file, matching DESIGN's per-module cache unit) into its own IR buffer. Chunks can't write files, so the caller writes each wave's collected modules to disk in index order, then reuses the wave buffer. Memory is bounded by wave size × per-module limit, not program size.
- **Generic copies:** they form a worklist that can grow while it's processed (checking a copy can request more copies). Run it in waves:
  1. Check the current set in parallel.
  2. Collect the new requests and deduplicate them in index order.
  3. Repeat until no new requests appear, or a named limit ("generic copy limit of N exceeded") is hit.

  That's the bounded fixed point Sol asked for (storage and step limits both).

**Cost versus a heap design.** Allocation cost disappears: every table is a pointer bump. Layout is the struct-of-arrays layout Zig measured as smaller and faster. What it costs:

1. **Limits must be stated** and raised by rebuilding.
2. **Every table reserves address space at its limit:** about 1.3 GiB here, against a 128 TiB address space.
3. **Hash tables need the prefix trick** above.
4. **Each parallel job reserves its own scratch.** That's address space again; touched memory stays proportional to the work.

The Rust compiler's heap design pays per-object allocation and pointer-sized links instead. On the measured baseline it used 52.9 MB maximum RSS just to parse and dump 54,145 lines (debug build).

### 4.6 Memory map for a 50,000-line program

**Assumptions.** Each is rounded up from the 54,145-line measurement in 2.3(g):

| Quantity | Assumed | Measured |
| --- | --- | --- |
| Bytes per line | 40 | 24.5 |
| Tokens per line | 10 | 7.6 |
| Nodes per token | 0.5 | 0.44 |
| Integer literals | 1 per 10 lines | not measured |
| Decoded string bytes | 5% of source | not measured |
| Identifier tokens | 40% of tokens | not measured |
| Distinct names | 10,000 | not measured |
| Symbols | 20,000 | not measured |
| Types | 10,000 | not measured |
| Typed instructions | 1.5 per node (1 per node, + 50% for generic copies) | not measured |
| IR text | 1,000 bytes per line, about 50 modules of 1 MB | 360 to 920 typical, 6,300 worst on four fixtures |
| Parallel jobs | 8 | |

**Derived counts:**

- source = 50,000 × 40 = 2,000,000 bytes;
- tokens = 50,000 × 10 = 500,000;
- nodes = 500,000 × 0.5 = 250,000;
- integer literals = 50,000 / 10 = 5,000;
- typed instructions = 250,000 × 1.5 = 375,000;
- identifier tokens = 500,000 × 0.4 = 200,000;
- IR = 50,000 × 1,000 = 50,000,000 bytes.

**Record sizes, from today's emitter rules** (`int` 4 bytes, `long` 8, refined fields at base width, an enum without payload 4):

| Record | Fields | Size |
| --- | --- | --- |
| Token | `{kind, start, len}` | 12 B |
| Node | `{kind, flags, token, start, end, subtree}` | 24 B |
| Magnitude | `{lo: long, hi: long}` | 16 B |
| Name | `{start, len, hash}` | 12 B |
| Hash slot | `int` | 4 B |
| Symbol | assumed | 24 B |
| Type | assumed | 32 B |
| Per-node fact | `{type, resolution}` | 8 B |
| Typed instruction | assumed | 16 B |
| Byte buffers | with `Bytes` (T16) | 1 B per byte |

Each table below is one `list` local in `main` (or in a per-job function), with O(1) empty initialisation.

**S1: lexing and parsing**

| Table | Capacity | Reserved bytes | Used | Touched bytes |
| --- | --- | ---: | --- | ---: |
| Source buffer | 64 MiB + 16 MiB slack | 83,886,080 | 2,000,000 B | 2,000,000 |
| Tokens | 5,000,000 × 12 | 60,000,000 | 500,000 × 12 | 6,000,000 |
| Nodes | 4,000,000 × 24 | 96,000,000 | 250,000 × 24 | 6,000,000 |
| Magnitudes | 5,000,000 × 16 | 80,000,000 | 5,000 × 16 | 80,000 |
| Decoded strings | = source capacity | 83,886,080 | 5% of source | 100,000 |
| Printer stack `{node, depth}` | 4,000,000 × 8 | 32,000,000 | a few pages | 4,096 |
| Delimiter stack | 2,048 × 4 | 8,192 | one page | 4,096 |
| Output buffer | 1 MiB | 1,048,576 | all, reused per flush | 1,048,576 |
| **S1 total** | | **436,828,928 (416.6 MiB)** | | **15,236,768 (14.5 MiB)** |

Page rounding adds at most one 4 KiB page per array lane. That's about 20 lanes, under 0.1 MiB. The dump itself (about 24 MB for this program, scaling 2.3(g)'s 20.5 MB) is streamed out through the 1 MiB buffer, never held.

**S2: checking** (the limits here are proposals; the Rust checker has none to match)

| Table | Capacity | Reserved bytes | Used | Touched bytes |
| --- | --- | ---: | --- | ---: |
| Names | 1,048,576 × 12 | 12,582,912 | 10,000 × 12 | 120,000 |
| Name hash slots | 2,097,152 × 4 | 8,388,608 | prefix of 524,288 (next power of two ≥ 2 × 200,000) × 4 | 2,097,152 |
| Symbols | 1,048,576 × 24 | 25,165,824 | 20,000 × 24 | 480,000 |
| Types | 1,048,576 × 32 | 33,554,432 | 10,000 × 32 | 320,000 |
| Per-node facts | 4,000,000 × 8 | 32,000,000 | 250,000 × 8 | 2,000,000 |
| Typed instructions | 8,000,000 × 16 | 128,000,000 | 375,000 × 16 | 6,000,000 |
| Generic copies | 65,536 × 16 | 1,048,576 | 2,000 × 16 | 32,000 |
| Work list | 1,048,576 × 4 | 4,194,304 | 10,000 × 4 | 40,000 |
| Diagnostics | 1,000 × 32 | 32,000 | 1 | 32 |
| Per-job scratch | 8 jobs × 4 MiB | 33,554,432 | 8 × 64 KiB | 524,288 |
| **S2 total** | | **278,521,088 (265.6 MiB)** | | **11,613,472 (11.1 MiB)** |

**S3: emission**

| Table | Capacity | Reserved bytes | Used | Touched bytes |
| --- | --- | ---: | --- | ---: |
| Per-job function IR buffer | 8 × 16 MiB | 134,217,728 | 8 × 256 KiB (largest function; assumed) | 2,097,152 |
| Wave buffer | 8 modules × 64 MiB | 536,870,912 | 8 × 1 MB, reused per wave | 8,000,000 |
| Symbol and mangling text | 4 MiB | 4,194,304 | assumed | 200,000 |
| **S3 total** | | **675,282,944 (644.0 MiB)** | | **10,297,152 (9.8 MiB)** |

**All three live at once.** S1's tables are still read by S3, for string constants and spans in messages.

- Reserved: 436,828,928 + 278,521,088 + 675,282,944 = **1,390,632,960 bytes (1,326.2 MiB, about 1.3 GiB) of address space**.
- Touched: 15,236,768 + 11,613,472 + 10,297,152 = **37,147,392 bytes (35.4 MiB) of RAM**, plus the binary and runtime.
- The 50 MB of IR goes to disk, and clang runs as a separate process with its own memory.
- The native stack for a recursive parser is a separate, much smaller amount (5.1).

**The same S1 tables under today's implementation,** with empty collections touching their capacity and `list<byte, N>` at 4 bytes per byte:

- source and decoded strings: 83,886,080 × 4 = 335,544,320 bytes each;
- everything else as above, 269,056,768 bytes;
- total 940,145,408 bytes (896.6 MiB), **all touched at declaration**.

That also doesn't fit today's fixed 64 MiB data stack. As globals, it would be touched at startup and trip the 64 MiB `globals_budget` warning. This gap, 897 MiB touched against 14.5 MiB, is the whole case for section 6's first three items.

**Where the limits bind.** At the measured 7.6 tokens per line, the 4M-token package limit is reached near 526,000 lines in one package; at the assumed 10, at 400,000 lines. Both are far past the 50,000 lines DESIGN's 3-second aim covers.

---

## 5. Per-stage design

Code labelled **accepted today** was compiled and run with `nlc` in `~/shprobe/s1sample`. Code labelled **DESIGN syntax** uses decided but unimplemented features.

### 5.1 S1: lexer, parser, dumps

**Data (accepted today).** Capacities must be `const` values or literals; a `const` struct field isn't accepted (2.3e).

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

**Spans and lines.** Line and column aren't stored. The token dump prints them, and the printer computes them with a running counter as it walks tokens in order. A diagnostic computes its one position by scanning from the file's start. That saves 8 bytes per token.

**Spans are stored, not derived.** The format's synthetic nodes are the reason: zero-width `default` calls, match-arm blocks, `else if` blocks, and `Program` spanning to EOF all have spans that differ from their tokens.

**Lexer:** one flat loop per file, with the delimiter stack as a `list<int, 2048>`. It's a straight translation of `lexer.rs`'s state machine: no recursion, one pass.

**Parser: recursive descent, marked `recursive`, mirroring `parser.rs`.** The reasons:

1. **Byte-identical diagnostics.** S1 must reproduce the *first* error. That depends on the exact order in which `parser.rs` tries alternatives (including its statement "candidates") and checks its nesting limits. The same function structure gives the same order. A state-machine rewrite would have to prove equivalence error by error.
2. **The depth is already bounded.** Parser nesting is capped at 1,000 and delimiter nesting at 2,048 by the format.
   - Every recursive call checks the native-stack budget (T19). The default is the thread's usable stack less an 80 KiB margin, and it fails the job by name.
   - next-lang frames are built by clang at `-O1`, not Rust debug frames. **Estimate** (to be measured by T17's `inspect stacks`): 4 to 6 frames per nesting level of 100 to 400 bytes, about 2 KB per level, about 2 MB at 1,000 levels.
3. **T19's region rule is satisfied naturally.** The parser holds only fixed-size indexes across recursive calls. The large lists are caller-owned and passed as `write` parameters, which T19 allows ("Caller-owned large values borrowed through parameters remain valid across recursive calls").

**Expression parsing** follows Rust's precedence climbing (`expression(min_precedence)`), which recurses once per operand. A shunting-yard loop with an explicit operator stack (`list<int, 1000>`) avoids even that. Keep it in reserve, if measurement shows the native stack matters, and note that it must then reproduce Rust's "expression nesting limit" checks at the same points.

**The printer: an explicit stack, no recursion (accepted-today idiom).**

```
var stack: list<long, 64> = list {}      // {node, depth} pairs in the real printer
stack.push(2L)?
for step in 0..64 {
    let top = stack.pop() ?? break
    print(nodes[top].kind)
}
```

The tree is in postorder, but the dump is preorder with two spaces per depth. So the printer:

1. starts at each file's root (its last node);
2. finds the root's children right to left by subtree sizes;
3. pushes them, so the first child comes out first;
4. repeats.

A field that the dump lists in an order different from creation order (the format's `pool` type-argument rule) is handled in the printer, as `syntax_dump.rs` does.

**Package flow.** It follows Rust: read the file list (`fs.list`, already sorted by raw bytes like Rust's filename order), then for each file:

1. read it into the package buffer;
2. lex, then parse;
3. add its counts to the package totals and check them in Rust's order: bytes, tokens, nodes, edges, work. Edges are counted, not stored: every node except a file's root has one parent edge.

Only after every file succeeds does anything go to stdout, because Rust prints nothing on a syntax error. Then print tokens and/or tree by streaming through the 1 MiB buffer with `out.write`. On error, print one `file:line:col: error: message` to stderr and exit 2.

**Integer magnitudes.** Up to 2^128 − 1 is printed in decimal with no 128-bit type. Store the magnitude as two 64-bit halves (or as four 32-bit limbs in `long`s to stay clear of sign problems) and format it by repeated division by 10^9. That's about 30 lines of code, and a test pins 0, 2^64 and 2^128 − 1 against Rust.

**Checking S1:**

- byte-identical stdout, stderr and exit status against the **live** Rust `nlc parse --tokens --tree` (and each flag alone) on every package under `tests/run`, `tests/test` and `tests/parse/cases`;
- every limit at exactly N and N + 1, generated;
- the 54,145-line benchmark from 2.3(g);
- a byte-level fuzzer (random edits of corpus files), comparing both outputs until the first difference.

The comparison script runs both compilers and `cmp`s their outputs, so the stored dumps (which leave out the over-100 KB stress cases) aren't the only reference.

**Speed target:** report lines/s against the Rust release build (the Rust build of the same commit, release mode). Carbon's lexing at about 5M lines/s and parsing at 1.7M (3.1) show what array layouts reach.

**S1b.** S1b adds `batch(max 256)`, one builder per file with derived row and byte limits, a `parallel for` over files that moves each builder to one chunk, then `freeze`. Interning stays a sequential pass after the join. Files are read sequentially before the loop, since chunks can't do I/O. It's measured against Rust with the same thread count, as the validation plan's parallel-tool row asks: 0.9x of Rust's time and 3x on 4 cores.

### 5.2 S2: the checker

**Prerequisite (a PLAN change):** a `nlc check --dump` typed-output format, documented like syntax-tree-format.md, plus a stated rule for which error is "first" when there are several. Today `check_package` returns one `CheckError`, chosen by the Rust checker's traversal order, and S2 can't match an unspecified order. Two choices:

1. document Rust's order as the contract;
2. better: make the Rust checker report the error with the smallest (file, byte offset), so the order is independent of traversal and parallel S2 can reproduce it with a `reduce` that takes the minimum.

**Phases:**

1. **Interning pass** (sequential, 4.4).
2. **Declaration phase** (sequential): one linear loop over each file's top-level nodes collects declarations into the symbol table. Package files see each other's declarations, so this phase must complete before any body is checked. Then resolve type expressions in signatures, struct fields, enum payloads and constants, compute struct layouts, check function contracts (modes, effects bounds, `recursive` cycles over the call graph) and evaluate constants. Freeze the result.
3. **Bodies** (parallel per function): a linear postorder pass over each body's nodes, with an explicit value stack of partial types. Postorder means operands are typed before their operator; that's Carbon's checking design.
4. **Whole-program analyses** after the join: effects, may-suspend, stack contracts and noalias facts over the call graph. These are graph walks; use explicit worklists, never recursion (T19 review: "S2's self-hosted checker should be designed with explicit work stacks rather than deep recursion").

**Two places where a pure postorder pass needs care:**

1. **Scopes must open before their children are checked.** Have the parser emit zero-width "begin" marker nodes at block and function starts, as Carbon does with introducer nodes. The printer skips them (a flag bit), so the dump format is unchanged.
2. **Literals take their type from context.** For example, `count += 1` on a `long`, or a loop counter typed by its use. Give an unsuffixed literal a provisional "integer literal" type and fix it when the parent node is reached. Where a type flows down further, record a pending constraint resolved by the parent. Ranges proved by the refinement contract follow the same parent-resolves rule.

**Interfaces with the Rust checker:**

- Effects use the closed set (`out`, `env`, `fs.read`, `fs.write` and the rest).
- Refinement facts and range analysis mirror `checker.rs`.
- Constant evaluation runs as an explicit-frame interpreter with the same 10,000-call and 10,000,000-step limits. The T19 report shows why it must not recurse: 250 KB per evaluated call in Rust debug before the split.

**Checking S2:** typed dumps and first diagnostics equal Rust's on every test package and on a mutated corpus (seeded slips, as DESIGN's mutation harness plans).

### 5.3 S3: code generation

- **Input:** S2's typed instructions and facts, read-only.
- **Output:** LLVM IR text per module (one per source file), produced in parallel waves (4.5). Each function's text is built in its own `Ascii` buffer in append mode, then appended to its module's slot of the wave.
- **Determinism inside the text:**
  - names come from declaration order;
  - the `; generated by nlc` header and `source_filename = "next-lang"` stay fixed, as `emit.rs` does today;
  - no temp-directory names, PIDs or times appear (`driver.rs`'s temp directories, named from the PID and a counter, must never reach output);
  - debug info, when added, uses package-relative paths.
- **Running clang:** until the process capability exists, S3 writes `.ll` files (`fs.write`) or streams IR to stdout, and a thin driver (the Rust `nlc`, or a shell script during bootstrap) runs clang and links the runtime. That keeps S3 inside today's effects.
- **Checking S3:** for every test program, the behaviour of the S3-built binary (stdout, stderr, exit status) equals the Rust-built one's, at the development level and at `NLC_OPT_LEVEL=3`. The IR text needn't equal Rust's: it's a different emitter, and only behaviour is compared.

### 5.4 Bootstrap and the Rust reference

1. Stage 0 is the Rust `nlc` at a tagged commit, with clang pinned (18.1.3 in today's WSL), the runtime, target level, flags and paths fixed.
2. Stage 0 builds stage 1 from the next-lang compiler's source. Stage 1 builds stage 2; stage 2 builds stage 3.
3. **IR(stage 3 build) must equal IR(stage 2 build), byte for byte,** then the binaries. Stage 1 was compiled by Rust `nlc` and stage 2 by stage 1, so the same source compiled by two different compilers must produce identical outputs. That's the DDC check, with Rust `nlc` as the trusted second compiler.
4. Identical stages show stability, not correctness (PLAN says so). The S1 to S3 comparisons over valid, invalid, generated and limit-boundary inputs stay in CI.

**Source discipline, Go-style:** the compiler's own source may use only features the pinned stage 0 accepts. Bump stage 0 deliberately, in its own commit, after the feature lands in both compilers.

**Real sources of nondeterminism to rule out.** Run time and machine load aren't among them: a compiler's output is a function of its input.

- *Hash iteration order:* T09 maps and sets iterate in insertion order, and hand-written hash tables are never iterated for output.
- *Parallel join order:* `collect` joins in index order, `reduce` uses a fixed tree, and new types and generic copies merge in function-index order.
- *Directory order:* `fs.list` sorts by raw bytes.
- *Timestamps, absolute paths, temp names:* none are emitted.
- *Uninitialised memory:* once collections are no longer zeroed in full, reused data-stack pages keep old bytes past `count()`. Then any path that reads past the live elements makes output depend on earlier jobs. This includes equality, `print`, structural hashing, copying, and a pool slot above the high-water mark.

  List equality already stops at `count()`. The section 6 item 1 task must check every such path, keep map and set occupancy flags zeroed, and test it: compare two equal lists, built after a job that dirtied the same stack pages.
- *Tool versions:* the LLVM/clang version and the target level are part of the build's identity (DESIGN). They're pinned for the binary comparison; the IR comparison doesn't depend on them.

### 5.5 Room for incremental compilation later

Nothing in S1 to S3 needs incremental compilation. Rustc's query system and Zig's 63 ms reanalysis (3.6) show where it pays. To leave room for it:

- **Per-file partitions (S1b's batch):** ids are (file, row), so one file's tree can be replaced without renumbering others.
- **Content hashes:** a hash of each file's bytes and of each declaration's interface (types, effects, refinements, stack contract), as DESIGN's per-module cache keys already need.
- **Stable symbol identity by (package, declaration name)** across builds; package-wide indexes stay an in-memory detail.
- **Name ids:** first-occurrence numbering changes when an earlier file changes. An incremental mode would key caches by spelling or hash, not by name id.
- **Side tables kept per file,** so they can be invalidated per file.

---

## 6. Language and runtime features the compiler needs, ranked

Each item is checked against PLAN's prerequisites table and the T-tasks.

1. **Collections touched only as far as they're used (not scheduled; blocks the memory design).**
   - `list {}`, `queue {}` and `ring {}` should write only their counts and headers.
   - `map {}` and `set {}` should write only headers and their 1-byte-per-slot occupancy flags.
   - `pool {}` should keep a high-water mark: slots at or above it are free with generation 1, and the free list holds only slots below it.
   - Struct and enum construction must initialise collection fields the same way, not memset them.
   - Copies and returns must move only the live elements.
   - Returning a local collection should build it in the caller's destination, as T14 does for `Ascii`.
   - Equality, `print` and hashing must stop at the live elements; list equality already does.
   - *Suggestion:* an M3 follow-up task before T17. Its acceptance tests:
     - maximum RSS for a 48 MB local list holding one element (48,224 KB today);
     - the same list as a struct field (48,224 KB today) and as a returned value (16 MB list: 32,736 KB today);
     - a determinism test comparing lists built on dirtied stack pages.
2. **Data-stack reservation sized past 64 MiB (T17).** T17 should drop the 64 MiB constant as an upper bound, size from the computed worst case, and report reserved versus touched. *Suggestion:* add an acceptance case to T17 with a 1 GiB worst-case entry point that touches 10 MB.
3. **Real 8-bit storage.** `Bytes` (T16) solves source buffers. Token kinds, flags and the many small fields of a compiler want 1- and 2-byte lanes. *Suggestion:* implement DESIGN's "ranges pick storage" for collection lanes, and make `byte` a real 8-bit type (C#'s `byte`, already a decided name) in the layout follow-up before M4.
4. **Capacity generics inferred from `list` arguments, and capacities from `const` struct fields.**
   - Today a helper over `list<T, N>` must name a concrete capacity.
   - Ben prefers grouping limits in one config struct over many separate constants, which a capacity like `LIMITS.max_tokens` would allow.
   - *Suggestion:* a small task with the generics work.
5. **`Ascii`, `Text`, `Bytes`, append mode, number formatting (T14 to T16, T18).** All scheduled. S1 needs `Ascii` builders for dump lines and JSON escaping, and `str` for numbers.
6. **Array and list literals (scheduled before S1).** For keyword and operator tables.
7. **128-bit magnitudes.** No `u128` is planned. *Suggestion:* don't add one for this. S1 implements limb arithmetic (5.1), and a `ulong` (decided name, unimplemented) would make the limbs simpler.
8. **Builders, `batch`, `freeze`, `parallel for` (DESIGN step 6, no T-number).** Needed for S1b and parallel S2/S3. *Suggestion:* schedule them as T-tasks right after S1a, with S1b as their acceptance program.
9. **Reading a file into the tail of a list.** `fs.read` fills a whole list; S1 wants to append each file to the package buffer without a temporary copy. *Suggestion:* an `fs.read_append(path, buffer)` or an offset argument. Until then, read into a 16 MiB temporary and copy; that's cheap.
10. **A process capability (effects step).** Needed only when S3 drives clang itself. Bridge with the Rust driver or a script until then (5.3).
11. **Chunked file writing.** `fs.write` writes a whole file from one list. S3's per-wave writes work with whole module files; streaming one huge module would need file handles (PLAN puts bounded writers with the effects work).
12. **Typed index types.** Plain `int` node indexes can be mixed up with token indexes. An `Id<P>`-style owner check needs pools or batches, and a pool costs 9 bytes per slot of overhead (flag, generation, free-list entry) plus initialisation. *Suggestion:* for S1a, wrap indexes in one-field structs (`struct NodeIx { at: int }`). Later, consider newtypes (DESIGN mentions them; unimplemented), or append-only `list` ids with an owner parameter.
13. **Interfaces (`Eq`, `Hash`, `Ordered`).** Not needed: the compiler's hash tables are hand-written over spelling ranges, which a structural `Hash` of `{start, len}` would get wrong anyway.

**Not needed:** `while`. Counted loops with `break` express every explicit-stack walk and double as step budgets.

---

## 7. Risks and open questions for Ben

1. **Should globals ever be committed lazily?** The brief assumed so; the design says no (2.3a).
   - *Recommendation:* keep DESIGN's rule. Globals are meant for state that really lives for the whole run, and the startup guarantee is valuable. The compiler doesn't need globals.
2. **First-error parity in S2.**
   - *Recommendation:* before S2, change the Rust checker to report the smallest-position error and document it. Without this, a parallel S2 can't match Rust deterministically.
3. **Limits are compile-time.** Raising one means rebuilding the compiler.
   - *Recommendation:* document every limit with its message in a format file, as syntax-tree-format.md does. Ship generous values (reservations are free once item 1 of section 6 lands), and add a test per limit at N and N + 1.
4. **Recursive parser versus explicit stack in S1.**
   - *Recommendation:* recursive for S1a (parity with Rust), measured with T17. An explicit stack only if the native stack proves costly.
5. **Windows.** Commit charging means data stacks must commit as they grow, not at reservation (3.4).
   - *Recommendation:* note it in the scheduler follow-ups. S1 to S3 run on Linux first, as PLAN already says.
6. **The 3-second aim.** One sample suggests clang `-O1` dominates (0.56 s versus 0.08 s at `-O0` for 1 MB of IR). At 1,000 bytes per line, a 50,000-line program is about 50 MB of IR.
   - *Recommendation:* measure per-module rebuilds once S3 runs. Try `-O0` (or FastISel) for development builds before any new backend; TPDE is the next experiment after that.
7. **Language changes while the compiler is written in it.**
   - *Recommendation:* Go's discipline (5.4). Also keep S1a small and start it only after T14 to T17 and section 6's items 1 to 4.
8. **Bugs that reinforce each other.** A bug in the Rust compiler and the same bug in S1 to S3 would agree with each other.
   - *Recommendation:* keep the fuzzed and limit-boundary comparisons, plus the language's own test suite, run on both compilers.
9. **A language server later.** Region "leaks" (3.3) mean a long-running process must run each compile as a job.
   - *Recommendation:* design the language server as a job per request from the start.

---

## 8. Proposed PLAN.md changes

Listed only; PLAN.md is not edited here.

1. **New M3 follow-up, before T17:** no emitter path touches a collection past its live elements. That covers empty literals (count-only lists; occupancy flags only for maps and sets; a high-water mark for pools), struct and enum construction, copies, returns built in the destination, and equality, print and hash. Tests: maximum RSS, plus determinism on dirtied pages.
2. **T17:** no 64 MiB ceiling on computed reservations, and an acceptance case with a 1 GiB reservation that touches about 10 MB. `inspect stacks` shows reserved and touched separately.
3. **Layout follow-up (before M4):** real 8-bit `byte` storage, and ranges picking lane widths.
4. **Generics task:** infer capacity parameters from `list` arguments, and allow capacities from `const` struct fields.
5. **Split S1** into **S1a** (sequential; after T14 to T18 and items 1 to 4; byte-identical against live `nlc parse`) and **S1b** (parallel with builders, `batch`, `freeze`, `parallel for`; the validation plan's parallel-tool program).
6. **Schedule DESIGN step 6** (builders, freeze, parallel loops) as T-tasks right after S1a, with S1b as their acceptance program.
7. **Before S2:** `nlc check --dump` with docs/typed-tree-format.md. Make the Rust checker report the smallest (file, offset) error, and document it.
8. **S1 design note:** record the compiler's limits table, its sizing classes (fixed, derived, measured-prefix) and the after-file check order (4.3) as the answer to the prerequisites row "Limits for a compiler's own inputs".
9. **S3:** state that the Rust driver (or a script) runs clang until the process capability exists.
10. **Bootstrapping:** add the Go-style rule (compiler source uses only stage-0 features), and name the stage 2 equals stage 3 IR comparison as the first check, before binaries.
11. **Scheduler follow-ups:** Windows data stacks commit as they grow.

---

## 9. Sources

Fetched while writing this report (October 24, 2026):

**Zig**

- Zig PR #7920, AST memory layout: https://github.com/ziglang/zig/pull/7920
- Zig `Ast.zig`: https://raw.githubusercontent.com/ziglang/zig/master/lib/std/zig/Ast.zig
- Zig `InternPool.zig`: https://raw.githubusercontent.com/ziglang/zig/master/src/InternPool.zig
- Zig 0.8.0 release notes: https://ziglang.org/download/0.8.0/release-notes.html
- Zig 0.14.0 release notes: https://ziglang.org/download/0.14.0/release-notes.html
- Zig 0.15.1 release notes: https://ziglang.org/download/0.15.1/release-notes.html
- Goodbye to the C++ Implementation of Zig: https://ziglang.org/news/goodbye-cpp/

**Carbon and TypeScript**

- Carbon toolchain docs: https://docs.carbon-lang.dev/toolchain/docs/
- Carbon parse docs: https://docs.carbon-lang.dev/toolchain/docs/parse.html
- Carbon PR #4124, compile benchmarks: https://github.com/carbon-language/carbon-lang/pull/4124
- TypeScript native port announcement: https://devblogs.microsoft.com/typescript/typescript-native-port/
- Announcing TypeScript 7.0 Beta: https://devblogs.microsoft.com/typescript/?p=5152

**Static allocation and coding rules**

- TigerBeetle TIGER_STYLE.md: https://raw.githubusercontent.com/tigerbeetle/tigerbeetle/main/docs/TIGER_STYLE.md
- TigerBeetle, A Database Without Dynamic Memory Allocation: https://tigerbeetle.com/blog/2022-10-12-a-database-without-dynamic-memory/
- Power of Ten rules (quoted from): https://en.wikipedia.org/wiki/The_Power_of_10:_Rules_for_Developing_Safety-Critical_Code; the paper: https://spinroot.com/gerard/pdf/P10.pdf
- MISRA C:2012 Rule 21.3 (MathWorks): https://www.mathworks.com/help/bugfinder/ref/misrac2012rule21.3.html
- JPL Institutional Coding Standard for C (2009): https://www.slideshare.net/slideshow/jpl-coding-standard-for-the-c-programming-language/226808547

**Regions and arenas**

- Region-based memory management (the source for the Tofte-Talpin, MLKit and Cyclone statements; a secondary source): https://en.wikipedia.org/wiki/Region-based_memory_management
- rustc memory management: https://rustc-dev-guide.rust-lang.org/memory.html
- LLVM `Allocator.h`: https://llvm.org/docs/doxygen/Allocator_8h.html

**Operating systems**

- Linux overcommit accounting: https://docs.kernel.org/mm/overcommit-accounting.html
- Linux `mmap(2)`: https://man7.org/linux/man-pages/man2/mmap.2.html
- Windows `VirtualAlloc2`: https://learn.microsoft.com/en-us/windows/desktop/api/memoryapi/nf-memoryapi-virtualalloc2

**Compiler limits and small compilers**

- C11 draft N1570 §5.2.4.1: https://port70.net/~nsz/c/c11/n1570.html
- MSVC compiler limits: https://learn.microsoft.com/en-us/cpp/cpp/compiler-limits?view=msvc-170
- GCC preprocessor implementation limits: https://gcc.gnu.org/onlinedocs/cpp/Implementation-limits.html
- Tiny C Compiler: https://bellard.org/tcc/

**Bootstrap and reproducibility**

- Go 1.5 release notes: https://go.dev/doc/go1.5
- Installing Go from source (bootstrap rule): https://go.dev/doc/install/source
- rustc bootstrapping: https://rustc-dev-guide.rust-lang.org/building/bootstrapping/what-bootstrapping-does.html
- OCaml BOOTSTRAP.adoc: https://raw.githubusercontent.com/ocaml/ocaml/trunk/BOOTSTRAP.adoc
- David A. Wheeler, diverse double-compiling: https://dwheeler.com/trusting-trust/
- Reproducible Builds, timestamps: https://reproducible-builds.org/docs/timestamps/

**Backends and incremental compilation**

- QBE: https://c9x.me/compile
- rustc_codegen_cranelift: https://github.com/rust-lang/rustc_codegen_cranelift
- TPDE-LLVM: https://discourse.llvm.org/t/tpde-llvm-10-20x-faster-llvm-o0-back-end/86664
- rustc queries: https://rustc-dev-guide.rust-lang.org/query.html
- rustc incremental compilation: https://rustc-dev-guide.rust-lang.org/queries/incremental-compilation.html

**Local sources** (this repository at `612245e`): docs/DESIGN.md, docs/PLAN.md, docs/syntax-tree-format.md, docs/tasks/T08-report.md, T13-report.md, T19-report.md, T20-report.md, T21-report.md, docs/reviews/claude-selfhost.md, sol-selfhost-r1.md, sol-S0-r1.md, claude-T13-review.md, claude-T19-review.md, claude-T20-review.md, claude-T21-review.md, compiler/src/emit.rs, checker.rs, driver.rs, typed.rs, runtime/nl_runtime.c.
