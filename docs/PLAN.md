# Implementation plan

Started 2026-10-24, after the design rounds in DESIGN.md converged. Ben's decisions for the build: the compiler is written in **Rust**; it emits **LLVM IR as text** (as Burin's helper compiler does) and builds it with **clang**; development and tests run on **Linux (WSL)** first, Windows later.

## Roles

- **Claude** (manager and reviewer): writes each task (docs/tasks/T*.md) with its acceptance tests, reviews the diff and the test run, asks for fixes, commits and pushes. Keeps DESIGN.md and this plan current.
- **Codex, `gpt-6-luna`, reasoning `max`** (implementer): implements one task at a time in this repository. Never commits, never creates or switches branches. Ends each task with a short report (docs/tasks/T*-report.md): what it built, how to run it, what's left, and any place it had to choose something the task didn't say.
- **Codex, `gpt-6.1-sol`, reasoning `high`** (peer): reviews plans and tasks before they go to Luna, and is asked when a design question comes up during the build.

## Layout

```
Cargo.toml              workspace
compiler/               the `nlc` compiler (Rust): lexer, parser, checker, LLVM IR emitter, driver
runtime/                the small runtime the generated code links against (C, compiled by clang)
tests/                  language tests: one directory per program, with expected output
docs/                   DESIGN.md, EXAMPLES.md, PLAN.md, tasks/, reviews/
```

Commands (in WSL; Codex itself runs inside WSL, with its own settings in `~/.codex-nl` and the binary in `~/.local/codex-nl`): `cargo build`, `cargo test` (the compiler's own tests and the language tests), and `nlc run <dir>` / `nlc test <dir>` on a package directory. The Cargo target directory lives in the WSL home (`CARGO_TARGET_DIR=~/.cache/next-lang/target`), not on the Windows drive, so builds stay fast.

## Milestones

Each is small enough to review in one sitting, ends with passing tests, and maps to DESIGN.md's first steps.

- **M0 Pipeline,** in two tasks. T01: the whole path from source to a native program, with a typed representation between the checker and the emitter, functions, scalars, checked arithmetic and casts, `if`, calls, `print` and build errors. T02: `for` loops over `..` and `..=` ranges with `break`/`continue`, and `test` blocks with `nlc test`.
- **M1 Values.** Uses the refinement contract decided 2026-10-24 (DESIGN.md, "The refinement contract": prove it or write a cast). Then: `enum` with payloads and exhaustive `match`; `Option` and `Result` with `?`, `?.`, `??` (including `?? return/continue/break`); `struct` with field defaults and initialisers; named refinements and range refinements on integers (checked on store; `wrap` and `clamp`); `const` with compile-time evaluation.
- **M2 State and ids (DESIGN step 1, fixed-size part;** tasks T06 arrays and lists; T07 pools and owner parameters; T08 globals and static allocation; T09 `map` and `set`; T10 `queue`, `ring` and `grid`; T11 function values; T12 sorting as a compiler built-in). Fixed arrays `T[N]`, `list<T, N>`, `pool<T, N>` with generation-checked ids, as locals and in a small `global`, holding fixed-size fields only; structure-of-arrays layout, nested collections flattened; `Full` as a `Result`, `discard`; writable loop views and the no-removal-while-viewing rule. Step 1's cases that need text payloads, large-local scratch, iteration cleanup or suspension move to M3 or later; the task lists which cases it owns.
- **M3 Data stacks (DESIGN step 2;** tasks T13 stack contracts and destination-directed emission; T14 `Ascii` values on data stacks; T15 append mode and loop growth; T16 `Text`, `Bytes` and growing values in collections; T17 per-entry-point reservations and `inspect stacks`). Growing values (`Ascii`, then `Text` and `Bytes`) on compiler-assigned data stacks: stack contracts, fresh-result and append modes, iteration scopes, bounds per entry point, `inspect stacks`. All of DESIGN.md's step 2 acceptance cases.
- **Scheduler follow-ups (with the job scheduler, after M3):** waiting jobs keep their regions, provisional bytes, checkpoints and native frames; admission counts waiting jobs; cancellation finishes I/O and writer cleanup before a job's stack is reused; per-job native-stack reservation and switching (T17 reports the bound only). Recursion's tests must refuse keeping any region alive across a recursive call, including through indirect cycles.
- **M3 follow-up, T18: number parsing and formatting** (`parse_int`, `parse_long`, `str_fixed` and padding, plus `abs`, `min` and `max` on numbers, all pure; assigned here from the self-hosting prerequisites). Bounded file writers that flush in chunks need file I/O and belong with the effects work. M3 does not cover, and these are scheduled later: rendering from shared snapshots (with `shared global`), reusing stack sets across jobs (with the job scheduler), and recursion with `recursive`.
- **Touch only live elements (M3 follow-up, before T17; from docs/research/selfhost-architecture.md 2.3b):** no emitter path writes, copies, compares or hashes a collection past its live elements: empty `list`/`queue`/`ring` write only headers, `map`/`set` only headers and occupancy flags, `pool` keeps a high-water mark; struct and enum construction, copies and returns (built in the caller's destination) follow the same rule. Today a `list<long, 6000000>` holding one element touches 48 MB. Acceptance: maximum RSS checks for a local, a struct field and a returned value, plus a determinism test on dirtied stack pages. Safety rules from docs/reviews/sol-selfhost-arch-r1.md (points 2 to 4): a map's lookup reads its 8-byte bucket entries first, so the bucket array must be initialised (or probing redesigned), not just the occupancy flags, and copies keep or rebuild buckets, tombstones, hashes and insertion order; a pool's high-water mark is the end of its initialised slots, and lookup, iteration, equality and printing check it before reading flags or generations, keeping removed-slot generations, retirement and free order through copies and resets; whole-value loads and stores (equality and printing load whole operands today) are audited as well as explicit copies, including wrapped queues and rings, nested collections and enum payloads; the runtime's `fs.read` and `fs.list` stop clearing their whole destination. Tests use dirtied destinations with stale pool ids, retirement, map tombstones, equality, hashing and printing, and report peak pages touched.
- **Exit status for tools (before S1):** a way for `main` to end with a chosen status (S1 must exit 2 on a syntax error and 3 on a tool failure, matching `nlc parse`), e.g. `env.exit(code)` or a `main` result type that carries one; from sol-selfhost-arch-r1.md point 8.
- **Parser nesting fixes (small task after T15, before S1):** the Rust parser recurses once per `else if` with no counter (a 124,000-link chain parsed at 1.34 GB before the finished-tree check rejected it), and its expression-depth counter trips at 2,048 while the message says 1,000. Count `else if` links toward the 1,000 construct-nesting limit (or parse them iteratively), make the expression counter match its documented 1,000, update docs/syntax-tree-format.md and the parse corpus, and add N and N+1 tests for each counted path. From docs/research/selfhost-architecture.md revision 2.
- **Offset addressing milestone (decided 2026-10-25; after T27 and T29, built on X1):** data-stack references become offsets (DESIGN.md "The job's data stack"). Tasks, each keeping the whole suite passing in both modes until the switch: O1 merge X1's runtime (base in the context, mremap growth, guard page, NLC_STACK_VERIFY) and its working slice into main behind `NLC_STACK_MODE`; O2 descriptors and builders (Ascii, Text, Bytes) as offsets; O3 parameters, hidden result destinations and function values; O4 collections, views and element references (an element passed as list offset plus index, read in place through its lanes, replacing T13's copy-in/copy-out); O5 runtime I/O and foreign calls with pinning; O6 the self-hosted lexer and parser running in offset mode with the comparison passing and under NLC_STACK_VERIFY; O7 make offsets the default, remove pointer mode, and replace T28's cap with growth limits; O8 32-bit scaled offsets if X1 round 2 shows they pay. Gate: if X1 round 2 shows more than about 10% cost in tight loops after tuning, Claude brings the numbers to Ben before O2.
- **Locals that work against the memory theory (T30, docs/tasks/T30-locals-locality.md):** reassignment like `buffer = f(buffer)` builds a second copy (the self-hosted dumper's 1 MiB copy-down temporaries): update in place when the compiler can prove `f` only appends or rewrites, otherwise warn and suggest a `grow` or `write` parameter; place reserve-ahead regions after a function's other locals where possible so small values stay together.
- **Floats (after M3):** `double` and `float` per DESIGN.md "Floats" and "Deterministic by default" (no NaN in plain floats, `double nan`, `fast { }`, the language's own `sin`/`exp`, no fast-math by default), then `str_fixed(x, digits)` for doubles (EXAMPLES.md's logsum `percent` needs it).
- **Small diagnostics fixes:** matching `ok(_)` against an `Option` (e.g. `pool.remove` result) reports "unknown enum case 'ok'; did you mean 'ok'"; it should say the value is an `Option` and suggest `some`/`none`. Byte-string literals need a `xNN` escape (today non-UTF-8 bytes must be pushed one at a time). nlc panics when its stdout pipe closes early (`nlc inspect stacks x | head`); exit quietly on EPIPE.
- **Never-returning functions (before S1a-2):** allow `-> never` on user functions (the checker proves the body never falls through: it ends in `env.exit`, a `never` call, an infinite-free failure, etc.), so error helpers can be used in value positions; from claude-S1a-1-review.md.
- **Optional convenience: string-literal patterns** in `match` over `Ascii`/`Text`/`Bytes` (`match word { "fn" => ..., "let" => ..., _ => ... }`), compiled to length-then-bytes comparisons; S1 works without it.
- **Layout follow-up (before M4):** flatten nested collections into one lane per field across all enclosing elements, as DESIGN.md's Layout section says (T06 stores each nested collection's lanes inline per element; see docs/reviews/claude-T06-review.md), with a benchmark of a loop over all nested items.
- **Array and list literals (before S1):** `[5, 3, 9]` for `T[N]` (exactly N elements) and `list<T, N>` (at most N), typed from context like other literals; today arrays start from `fill(x)`. S1 wants literal keyword and operator tables.
- **M4 onwards** follow DESIGN.md's first steps 3 to 7 (refinements as LLVM facts, measured on DEFLATE; `check fast == reference`; effects; builders, `freeze` and parallel loops), each planned when the one before is done.

## Rules for every task

- Tests first-class: every feature lands with language tests (a program and its expected output, or a `test` block), and every error the compiler reports lands with a test that triggers it.
- Error messages name the line and say what to do, as DESIGN.md's Development experience asks.
- No dependency on Burin; code may be copied from it (D:\code\burin, Apache 2.0) with a note in the file.
- No new external Rust crates without saying why in the report.
- Keep it simple: no optimisation passes of our own; LLVM does that.

## Self-hosting track (decided 2026-10-24)

Ben adopted the recommendation both reviews reached (docs/reviews/claude-selfhost.md, docs/reviews/sol-selfhost-r1.md): self-host the compiler in stages, starting after M3, as DESIGN.md's planned "parallel tool" validation program. The Rust `nlc` stays the reference throughout.

- **S0, before M3 (decided 2026-10-24): the prerequisites S1 needs that don't depend on M3.** T19 `recursive` functions with a native-stack budget; T20 files, arguments and output through capabilities, using `list<byte, N>` until T16 brings `Bytes`; T21 a parse-only `nlc parse` with a stable token and tree format, the reference S1 is compared against. Order (after Sol's S0 review): T11, T12, T13, then T19, T20, T21, then T14 to T17. S0 plus M3 support a sequential S1; the parallel, frozen-pool S1 waits for the builders and parallel-loop work.
- **S1, after M3: lexer, parser and diagnostic formatter in next-lang.** It parses every package under `tests/` in parallel into frozen pools and prints the trees; the result must match the Rust parser's trees and diagnostics exactly. This doubles as the validation plan's parallel-tool program (frozen pools, builders, parallel loops and bounds on a real workload), measured against the Rust parser.
- **S2: the checker,** compared with the Rust checker's typed output and errors on every test package.
- **S3: code generation,** compared by behaviour on every test program at development and release optimisation levels.
- **Bootstrapping, at S3:** the pinned Rust `nlc` (stage 0) builds the next-lang compiler (stage 1), which builds stage 2, which builds stage 3; stages 2 and 3 must be byte-identical (fixed clang, runtime, target, flags, paths, no timestamps, no hash-order output). Identical stages show stability, not correctness, so the cross-compiler comparison on valid, invalid, generated and limit-boundary inputs stays.
- **Retiring the Rust compiler** is a later decision, only after the validation programs pass and the next-lang compiler has proved cheaper to maintain.

**Prerequisites to schedule before S1** (gaps both reviews found; each goes into the milestone named):

| Gap | Milestone |
| --- | --- |
| Generic constraints: decided 2026-10-24, named interfaces with explicit `impl` (DESIGN.md, "Generics and interfaces"); `Eq`, `Hash`, `Ordered` built-in interfaces | a generics task after M2 (T09 and T12 use compiler built-ins until then) |
| How a reusable `Node` or `Type` definition names ids belonging to a particular pool or batch: decided 2026-10-24, owner parameters (DESIGN.md, "Owner parameters in reusable definitions") | M2 |
| `map`, `set`, `queue`, hashing and sorting, firmly scheduled rather than on the Later list | M2 (collections) |
| Byte slicing, UTF-8 validation, number parsing and formatting, bounded writers that flush to a file in chunks | M3 |
| A process capability and its effect (run clang with arguments, bounded stdout and stderr, exit status), file handles, paths, temporary files, cleanup on cancellation | effects step (M5-ish), with a small C binding as a bridge |
| Builder handoff to chunks, batch-dependent helper types, aggregate budgets | builders and parallel loops step |
| Limits for a compiler's own inputs: files, source bytes, tokens, nodes, child edges, interned names, types, generic copies, pending work, diagnostics, recursion bytes, steps, concurrent jobs; reported by name when exhausted, never a truncated success | S1 design |
| Generic expansion bounded by its own count and work limits, not source size | generics milestone |
