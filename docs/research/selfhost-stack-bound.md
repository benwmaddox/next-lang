# The self-hosted compiler's data-stack bound

Status: research note, 2026-10-27, at HEAD b34bc5c (E3b fix round). Read-only investigation; nothing in selfhost/ was changed.

## Why the bound matters at all

The stage-0-built self-hosted compiler runs in **pointer mode**: stage 0 refuses to build selfhost in offset mode (`function 'collection_method_kind' uses large type 'Bytes max 67108864' outside the offset stack slice`). In pointer mode, `nl_context_create` (runtime/nl_runtime.c) maps the entry point's whole computed reservation at startup with `mmap(PROT_NONE, MAP_NORESERVE)`. That mapping commits no memory, but it does count against `RLIMIT_AS`. The test harness and the hook set `ulimit -v 8000000`, which is KiB, so the real cap is 8,192,000,000 bytes. The 7,248,097,280-byte reservation therefore leaves about 944 MB of address space for the binary, the 8 MB native stack, the runtime and everything else in the process. Passing the cap fails at startup with `could not reserve the requested address range`. The stack_contracts test asserts against 8,000,000,000.

Resident memory is a different number and is small. Running the self-hosted compiler's `build` on selfhost/ peaks at 179 MB RSS, but that is RSS up to the first error (`collections.nl:213:5: name 'count' conflicts with ...`): the self-hosted compiler can't build itself yet. `parse` of selfhost/ peaks at 37 MB. `NLC_STACK_STATS=1` prints nothing in pointer mode, so no data-stack high-water figure is available.

**The 7.25 GB is address space, not memory.** It becomes irrelevant to `ulimit -v` once the compiler is built by itself (B1), because E3-built programs start with a 256 KiB moving stack and grow it as they need. Until then, every byte of the bound is address space reserved under the 8 GB cap.

## 1. Where the 7,248,095,393 bytes go

The critical path (`nlc inspect stacks selfhost`) is `main -> compile_selfhost_package -> compile_embedded_core -> register_package_declarations -> decode_string_token -> append_unicode_byte_value`. The tool attributes bytes per local. The per-field split of `main.tables` and `main.compiler` below is computed from the declared types: each list is `capacity * element size + 8`, and elements are packed with no padding (long 8, int and enum 4, bool 1). That rule reproduces the tool's `main.tables` (680,912,049) and `main.compiler` (2,714,171,021) exactly.

### Locals on the critical path

| Local | Declared type | Bytes | Share |
|---|---|---:|---:|
| `main.ir` | `Bytes max IR_BUFFER_CAPACITY` (2M nodes * (640+256+768) + 64 MiB + 8 MiB) | 3,403,497,480 | 47.0% |
| `main.compiler` | `CompilerTables` (below) | 2,714,171,021 | 37.4% |
| `main.tables` | `ParseTables` (below) | 680,912,049 | 9.4% |
| `main.tokens` + `compile_embedded_core.tokens` | `list<Token, 4,000,000>` (20 B) | 2 * 80,000,008 | 2.2% |
| `main.source` + `compile_embedded_core.source` | `Bytes max 64 MiB` | 2 * 67,108,872 | 1.9% |
| `main.entries` | `list<DirEntry, 4096>` | 67,158,024 | 0.9% |
| four 16 MiB name/value buffers (`compile_selfhost_package.name`, `register_package_declarations.prior_name` and `.name`, `decode_string_token.value`) | `Bytes max 16 MiB` | 4 * ~16,777,225 | 0.9% |
| `main.file_data` | `Bytes max 16 MiB` | 16,777,224 | 0.2% |
| `main.files` + `compile_embedded_core.files` | `list<SourceFile, 256>` | 2 * 2,095,208 | 0.1% |

### Top fields inside `CompilerTables` (2.71 GB) and `ParseTables` (0.68 GB)

| Field | Element (bytes) x capacity | Bytes | Share of 7.25 GB |
|---|---|---:|---:|
| `compiler.line_starts` | long (8) x 67,109,120 (one per source byte) | 536,872,968 | 7.4% |
| `tables.nodes` | Node (84) x 4,000,257 | 336,021,596 | 4.6% |
| `compiler.call_edges` | CallEdge (32) x 8,000,000 | 256,000,008 | 3.5% |
| `compiler.type_records` | TypeRecord (80) x 2,000,006 | 160,000,488 | 2.2% |
| `compiler.intern_slots` | NameSlot (32) x 4,194,304 | 134,217,736 | 1.9% |
| `compiler.collection_count_branch_values` | (32) x 4,000,257 | 128,008,232 | 1.8% |
| `compiler.functions` / `struct_fields` | (64) x 2,000,000 each | 128,000,008 each | 1.8% each |
| `tables.literals` | Literal128 (32) x 4,000,000 | 128,000,008 | 1.8% |
| `compiler.bindings` | BindingRecord (59) x 2,000,000 | 118,000,008 | 1.6% |
| `compiler.enum_cases` | (56) x 2,000,000 | 112,000,008 | 1.5% |
| `compiler.collection_count_changes` | (24) x 4,000,257 | 96,006,176 | 1.3% |
| `compiler.type_walk` | (48) x 2,000,000 | 96,000,008 | 1.3% |
| `compiler.facts`, `parameters` | (40) x 2,000,000 each | 80,000,008 each | 1.1% each |
| `tables.extra` | long x 8,000,000 | 64,000,008 | 0.9% |
| `enum_payloads`, `tests`, `loop_push_proofs` | (32) x 2,000,000 each | 64,000,008 each | 0.9% each |
| `tables.match_frames` | MatchFrame (56) x 1,000,000 | 56,000,008 | 0.8% |
| `compiler.scopes` | (24) x 2,000,000 | 48,000,008 | 0.7% |
| `tables.nesting` | NestTask (24) x 2,000,001 | 48,000,032 | 0.7% |
| eight `list<long, 4,000,257>` graph tables (`edge_first`, `cycle_*`, `frame_*`) | 8 x 32,002,064 | 256,016,512 | 3.5% |
| seven token-, type- or node-indexed long tables (`token_name_ids`, `enum_type_by_name`, `enum_case_name_counts`, `enum_type_ids`, `child_first`, `child_next`, `expected`) | 8 B each | ~160,000,000 | 2.2% |

Everything that scales with the input is sized from the H1b input policy: 2,000,000 tree nodes, 4,000,000 tokens and 64 MiB of source. That follows the E1 rule: "Every new table's capacity comes from the H1b policy limits, never tighter."

### How the bound grew (git log -p compiler/tests/stack_contracts.rs)

| Commit | Step | Bound | Change | What drove it |
|---|---|---:|---:|---|
| 5498f54 | E1 | 3,478,494,879 (E1 report; test asserted < 4 GB) | | parse tables, typed facts, call edges, IR at 640 B/node |
| e52860e | E2a | 5,115,732,009 | +1.64 GB | struct, type and field tables, `type_walk`, IR +256 B per table entry (+512 MB) |
| bcb58d8 | E2i | 5,115,732,521 | +512 B | interface scratch |
| a5c0b3a | E2b | 6,859,732,537 | **+1,744,000,016** | IR +768 B per enum entry x 2M = **1,536,000,000**; `enum_cases` 112 MB; `enum_payloads` 64 MB; `TypeWalkFrame` +2 longs 32 MB |
| 82ecbc2 | E2b fix | 6,943,732,617 | +84,000,080 | `enum_type_by_name` 32 MB, `enum_case_name_counts` 32 MB, `enum_type_ids` 16 MB, `reserved_names` 4 MB |
| f413c13 | E3b | 7,007,732,625 | +64,000,008 | `loop_push_proofs` 48 MB; `BindingRecord.collection_count` 16 MB |
| b34bc5c | E3b fix | 7,248,095,393 | **+240,362,768** | `collection_count_branch_values` 128 MB; `collection_count_changes` 96 MB; `LoopPushProof.loop_depth` 16 MB; joins and snapshots 0.37 MB |

Each step adds every new table at policy capacity, so each new 8-byte per-node field costs 16 MB and each new per-node record costs 50 to 130 MB. One IR allowance term cost 1.5 GB. E3c, E3d1, E3d2 and E3e will keep adding at that rate, and the remaining headroom to the 8.192e9 cap is 944 MB.

## 2. Real need versus capacity

What one real input needs. Compiling selfhost/ itself is the largest real input. The counts come from the self-hosted compiler's own `lex --tokens` and `parse --tree` (tree lines are taken as nodes):

| Measure | selfhost/ (+ core) | Policy capacity | Headroom |
|---|---:|---:|---:|
| source bytes | 1,416,450 (+53,754 core) | 67,108,864 | 47x |
| tokens | ~241,600 | 4,000,000 | 16.5x |
| syntax nodes | ~130,800 | 2,000,000 (node storage 4,000,257) | 15x |
| source lines | 20,104 (+1,322) | 67,109,120 line starts | ~3,100x |
| functions | 612 | 2,000,000 | 3,300x |
| struct fields / enum cases | 326 / 285 | 2,000,000 each | >6,000x |
| bindings (package) | ~7,200 | 2,000,000 | 280x |
| largest function | 11,083 nodes, 329 bindings (`check_one_body`) | per-function tables at 2M to 4M | 180x+ |

**IR per node.** I built 161 test packages under tests/e1, e2, e3 and run with the self-hosted compiler. An empty package gives 608,508 IR bytes, the fixed core and helper part. Above that, IR bytes per parse node are: median 227, 90th percentile 424, maximum 698 (`tests/e3/merge_regions`). The largest sample is `tests/e2/size_padding`: 12,262 nodes and 6.19 MB of IR, 454 B/node. The E2c aggregate benchmark gives 254 B/node. The allowance is 1,664 B/node. A selfhost-sized package at the worst observed rate would need about 92 MB of IR; the derived bound for 131k nodes is about 293 MB. The buffer holds 3.40 GB.

These ratios are headroom, not proof. Every capacity above is a derived worst case under the input policy, and the E1 spec ("never tighter"; "On a package the reference builds, a limit diagnostic is a failure") rules out cutting a table just because real inputs are small. Stage 0 is frozen at those policy limits. So the reductions below fall into two classes:

- **Class A** keeps every policy capacity: shorter lifetimes, narrower elements, restructured tables, or a tighter but still sound derivation.
- **Class B** lowers a limit below the policy. That needs a manager decision and a declared departure from stage 0, because stage 0 can't gain the new limit.

### Per contributor

**`main.ir`, 3.40 GB (47%).**
- All IR goes through `ir_push_byte`, which catches `Full` and sets `compiler.ir_overflow`. That reports `self-hosted LLVM IR buffer limit exceeded` with status 2. A smaller capacity is therefore already a checked limit with a clear error. (`ir_overflow` is also reused for a missing-helper internal error; see sol-E2b-r1.)
- The buffer is append-only (one `ir.push`; `next_location_serial` reads `ir.count()`).
- **A1, a tighter derivation (class A, needs review).** The formula adds 640 (use-site output) + 256 (type/field helper entry) + 768 (enum entry), each times *all* 2M nodes. Every table entry belongs to a distinct declaration node: a type, a field, an enum case or a payload part. If no such declaration node also produces the 640-byte use-site output, the bound is 640·U + 1024·D with U + D ≤ N, which is at most 1,024 B/node, not 1,664. Savings: 640 x 2M = **1,280,000,000 bytes**. The constant changes in limits.nl, and the derivation check in scripts/compare-selfhost-build.py (`derived_bound`) must change with it. Whoever owns the E2a/E2b emitters should confirm or refute that no node falls in both classes.
- **B1, a checked output cap (class B).** Set `IR_BUFFER_CAPACITY` to 1 GiB. Savings: **2,329,755,648 bytes**. Even at 1,664 B/node it covers the derived worst case for packages up to about 600k nodes (4.6x selfhost/), and at the worst observed rate (698 B/node) up to about 1.4M nodes. Stage 0 has no IR limit, so an adversarial package within the policy could build with stage 0 and fail here: a declared departure, with an N/N+1 test through a test-only `--test-ir-limit=` hook like `--test-region-threshold`. A 512 MiB cap saves 2.87 GB.
- **Later.** Two routes remove the buffer:
  - Stream IR to the output file. This needs a file writer (E3f2) in the compiler that compiles selfhost, and stage 0's `Fs` has only `read`, `list` and a whole-file `write`. It also changes the "single write" rule, so a failed build must not leave a partial file.
  - Make `ir` `Bytes max unbounded` (E3d2). That is allowed for a local, but `ir` grows while `compile_selfhost_package.name`, `compile_embedded_core`'s buffers and their callees' regions sit above it, which breaks the topmost-region rule. It would need a restructure.

**`compiler.line_starts`, 537 MB (7.4%).** There is one long per possible source byte, because a file of newlines has that many lines. Only `build_line_start_index` and `position_for_offset` touch the table. `position_for_offset` is called from 49 sites, mostly `fail_*` paths that exit, but also from emission (`emit_runtime_failure`, `emit_checked_division`, `emit_checked_shift`, `emit_collection_index_address`, `emit_region_scope_enter`, ...), once per runtime-check site.
- **A2a, line checkpoints (class A).** Record the line number at every 1 KiB of source: 65,536 + 256 longs, about 0.53 MB. A lookup scans at most 1 KiB of `source`, which stays live through emission anyway. Savings: **536,346,624 bytes**. Cost: `position_for_offset` needs the source, so its 49 call sites gain a parameter. That is mechanical. Emission runs about one lookup per checked operation, so time a large package before and after.
- **A2b, int elements (class A).** Offsets are below 2^31 under the policy. This touches three functions and saves 268,436,480 bytes.

**`main.tables`, 681 MB (9.4%).**
- **A3, parser-only scratch.** `nesting`, `child_scratch`, `child_scratch2`, `match_frames`, `seen`, `if_frames` and `for_frames` are used only in parser.nl, plus parse_output.nl's tree dump of `nesting`, which runs only for `parse`. Together they are 152,890,312 bytes. Moving them into a `ParserScratch` that ends with parsing removes them from `main`.
- The catch: `compile_embedded_core` parses core while `main`'s frame is live, so core's parse needs its own scratch, at the same capacities because parameter capacities must match. On the critical path the net saving is only about **50 MB**: 153 MB leaves `main`, and core's scratch helper becomes the deepest child of `compile_embedded_core` instead of `register_package_declarations` (50 MB). A3 is worth doing only alongside A4, or after core compiles from `main`'s own buffers.
- `nodes` (336 MB), `literals` and `extra` are the parse result itself. Narrowing `Node`'s ten long fields to int, where they are indices or offsets, would halve `nodes`; see A6.

**`compile_embedded_core`'s source, tokens and files, 149 MB.**
- These are policy-sized buffers for 54 KB of embedded core.
- **A4.** The user package is fully emitted before `compile_embedded_core` runs, and that function already resets `main`'s `tables` and `compiler`. So core can lex into `main`'s `source`, `files` and `tokens`, which have the same types, after clearing them. Savings: up to **149,204,088 bytes**. It is "up to" because another path through `compile_selfhost_package` may become critical; recheck with `inspect stacks`.
- Risks:
  - `files[0].name` is used for the IR-limit diagnostic after the call, so save the name first.
  - `main` reads `files[...]` for `internal_emit_error_*` after `compile_selfhost_package`. Today an internal emit error raised while compiling core would index the *user's* `files` with a core file index. Check that path either way.

**`main.entries`, `main.file_data`, `main.delimiters`, 84 MB.**
- **A5 (class A, exact).** These are lexer-only scratch. The E1 spec already says lexer scratch "ends with parsing", yet the three are declared in `main` and live through emission. Make them locals of `load_and_parse` (or of a block around the call). Nothing after `load_and_parse` reads them, and core lexing takes only `delimiters`, which `compile_embedded_core` declares itself. Savings: **83,943,448 bytes**.

**The per-function checker logs, 288 MB** (`collection_count_branch_values` 128 MB, `collection_count_changes` 96 MB, `loop_push_proofs` 64 MB).
- These are already delta logs, with rollback by log position, and are cleared per function body. They are not per-binding copies, so "a stack of deltas" is what they already are.
- They are sized at node-storage capacity (4,000,257) and pushed with `.unwrap()`, with no capacity guard, so they depend on the derivation being right.
- **A6 (narrowing) cuts them about 40%:** `binding`/`join_index`/`branch` to int; `value`/`previous` stay long.
- A per-function checked limit would be class B.
- A side note for E3b's owner: the join merge loop in compiler.nl (around line 3925) scans `values_base..count` for each change, which is quadratic per join.

**The four 16 MiB name buffers on the path, 67 MB.** These copy one identifier or string token into a `Bytes max 16 MiB`. A token can be 16 MiB under the policy, so the capacity is honest. Passing (start, length) into `source`, or a name id, removes the copies (class A). Savings: up to 67 MB, but they recur in many functions, so this is a wider edit.

**A6, narrow index fields from long to int everywhere (class A).**
- Every node, token, type, binding and edge index, and every source offset, is below 2^31 under the policy.
- Sizes, field offsets, counts and masks stay long.
- Estimated savings: about 1.16 GB in `CompilerTables` (268 MB of it is `line_starts`, already covered by A2) and about 0.26 GB in `ParseTables`. About **1.15 GB** beyond A2.
- Cost: `int` and `long` don't mix without conversion (`fail_mixed_types`), so this touches most of the 12k lines of compiler.nl. It is a step of its own, not a trim.

**What E3d2 can and can't do.**
- Stage 0 rejects `list<long, unbounded>` (checked: `collection capacity must be a constant integer expression`).
- The selfhost compiler is built by stage 0, so it can't use unbounded values until it builds itself (E4/B1).
- After that, DESIGN forbids `unbounded` in struct fields. `CompilerTables` and `ParseTables` would have to become separate locals, and only one unbounded value may grow at a time (the topmost rule; earlier ones freeze). That fits phase-ordered tables (parse, then check, then emit) but not tables that grow together.
- Once self-built, the moving stack makes the reservation irrelevant to `ulimit -v` anyway. So unbounded tables are a long-term tidy-up, not the fix for the 8 GB problem now.

## 3. Recommended plan

### Small trim, right after E3c (class A only, no policy change)

1. **A5:** move `entries`, `file_data` and `delimiters` into `load_and_parse`. **−83,943,448**, exact.
2. **A2a:** replace `line_starts` with 1 KiB line checkpoints plus a bounded scan of `source`. **−536,346,624**, exact. If the 49-site parameter change is unwelcome, use A2b instead (int elements, −268,436,480).
3. **A4:** compile embedded core from `main`'s cleared `source`, `files` and `tokens`. **Up to −149,204,088.** Then optionally A3 (parser scratch out of `ParseTables`), about −50 MB net.

Expected bound:
- A5 + A2a: **6,627,805,321** (6.63 GB), exact.
- Adding A4: **about 6.48 GB**.
- With A2b instead of A2a: about 6.75 GB.

That is roughly 1.5 to 1.7 GB of headroom under the 8.192e9 cap. At the E2b-fix to E3b-fix rate (64 to 240 MB per step) that covers several steps, but one IR-sized term would consume it.

Tests that pin it, all in compiler/tests/stack_contracts.rs `selfhost_stack_bound_has_an_exact_attributed_path`:
- `worst_case` 7_248_095_393;
- the reservation 7_248_097_280;
- the `main.nl:96 main.tables (680912049 bytes)` line (its line number moves with A5; its size changes only with A3).

Also run:
- the selfhost build/diagnose parity (scripts/compare-selfhost-build.py);
- the relocation check;
- diagnostics fixtures with line:col positions (all callers of `position_for_offset`), plus the runtime-failure location fixtures, for A2;
- for A4: the core embed tests (compiler/tests/core_embed.rs) and an internal-emit-error fixture if one exists.

Risks:
- A2's lookups are slower per call; measure emission time on the largest package.
- A4 changes which buffers hold core while `main` still reads `files` afterwards.

### Next, decided separately

- **A1 (IR derivation as a max, not a sum): −1.28 GB, giving about 5.2 GB.** It is a one-line constant plus the derivation note and the `derived_bound` check. It needs the emitter owner to confirm that declaration nodes emit no use-site output. This is the largest class-A cut, and I'd do it in the same trim if the review agrees.
- **B1 (IR as a checked 1 GiB output cap): −2.33 GB, giving about 4.1 GB with the trim.** This is Ben's call, because it departs from "never tighter" for an output that stage 0 doesn't limit.
- **A6 (int narrowing): about −1.15 GB more.** It is a large mechanical step, best done with E4's parity suite as a guard.

### Wait for self-build (E4/B1) and E3d2/E3f2

- Moving-stack execution, after which the bound stops counting against `ulimit -v`.
- A streamed IR writer, or `ir` as an unbounded tail value after restructuring for the topmost rule.
- Phase-local unbounded tables in place of policy-sized struct fields.

## Side finding: a compile-time blow-up

I timed the self-hosted compiler's `build` on generated scalar packages (scripts/gen-selfhost-bench.py) at HEAD, without the bench lock, so the timings are rough: 1,000 functions take 6.4 s, 2,000 take 60.6 s, and 40,000 didn't finish in 600 s. E2b's report measured 0.12 s for 10,000 functions. Doubling the input costs about 10x, which is algorithmic, not noise. It needs its own investigation. The suspects are the E3b count-log scans and the `pop_step` loops, or something newer.

## Method

- `git archive HEAD selfhost core tests` was exported to a scratch directory.
- `nlc inspect stacks` and `inspect memory` were run under `ulimit -v 8000000`.
- The self-hosted compiler was built with stage 0 (pointer mode) and run on selfhost/ (`lex --tokens`, `parse --tree`, `build`) and on every test directory, for IR sizes and node counts.
- Per-field sizes were computed from the declarations with the packed layout rule above, which matches the tool's totals.
- Scratch was removed afterwards.
