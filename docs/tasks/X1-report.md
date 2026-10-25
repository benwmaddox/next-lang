# X1 report: relocatable offset stack spike

## Result

`NLC_STACK_MODE=pointer|offset` is implemented. Unset and `pointer` retain the existing pointer ABI and reservation behavior. `offset` changes the hidden cached stack top to an `i64` offset, starts the runtime stack at 256 KiB, and uses an offset allocator that grows with Linux `mremap`, reinstalls a trailing guard page, and reports growth and relocation timing when `NLC_STACK_STATS=1` is set.

The compiler currently accepts only programs whose values do not require a data-stack region or stack-backed ABI value. It rejects the requested list, builder, copy, return-destination, write-view, collection, and sort paths before LLVM emission. This keeps the unsupported paths from silently using a stale address. The offset scalar smoke program compiled and printed the same `4999950002` as pointer mode. It made no data-stack allocation, so it does not measure the cost of offset-addressed list or builder accesses.

This is therefore a fail-closed compiler and runtime prototype, not the requested pointer-versus-offset language benchmark. The runtime relocation cost is measurable. The compiler's per-access cost and optimization effects remain unmeasured.

## Verification

`cargo fmt --all -- --check`, the offline release build, and the full pointer-mode test suite passed. The self-host lexer/parser parity test took 373.14 seconds. The language script verified that all five O1 and O3 offset-smoke outputs match pointer mode, and the runtime-growth script passed the data-integrity and guard-page checks in both dynamic and preallocated modes. The T13/T14/T15/T16/T23 offset probes all returned build errors with the expected first unsupported path.

## Implementation

- `NLC_STACK_MODE` is read for each compiler invocation. It defaults to `pointer`; any other value besides `pointer` or `offset` is a build error.
- Offset mode emits an `i64` hidden top in generated function signatures and calls. It uses `nl_context_base_offset`, `nl_context_set_top_offset`, and `nl_stack_alloc_offset`.
- Before emitting LLVM, the compiler rejects runtime global initializers and reports the first function contract that needs a stack-backed parameter, result destination, region, or nonzero stack requirement. Offset mode cannot currently convert Ascii/Text/Bytes payload descriptors, collection lanes, large arguments, or hidden result destinations to offsets.
- The Linux runtime's offset allocator starts with 256 KiB unless `NLC_STACK_PREALLOC=1` is set. It doubles the reservation as needed, moves the data mapping with `mremap(MREMAP_MAYMOVE | MREMAP_FIXED)`, keeps a guard page at the new end, and records growth count, relocation count, and time inside `mremap`.
- `spike/runtime-growth.c` tests the allocator independently of generated language code. It writes 512 64 KiB chunks, checks old data after allocations, verifies a checksum through offsets, and checks that a write into the final guard page traps.

## Platform and method

Measurements ran in WSL2 Linux 6.6.87.2, x86_64, 4,096-byte pages, with Ubuntu clang 18.1.3. The compiler was built in release mode. Language workloads were built at `NLC_OPT_LEVEL=1` and `3`; each elapsed result is the best of five process runs, timed with Python `perf_counter_ns`. Peak RSS is the maximum child-process `ru_maxrss` across those runs. The stack mapping size is the compiler's `inspect stacks` reservation plus one 4 KiB guard page; this reports the data-stack mapping, not the process's total virtual size.

No `~/bench-style` directory existed in this environment, so `spike/bench-style` is a representative workload with the requested operations: 16,384 map inserts and lookups, 100,000 pool add/remove cycles, 1,000 calls returning an 8 KiB list, and a one-million-element sort.

## Language benchmark results

Pointer mode ran all three spike programs. Each offset build was rejected before LLVM generation, so the offset columns have no runtime timing, RSS, or mapped-stack measurement.

| Workload | Optimization | Pointer best of 5 | Pointer peak RSS | Data-stack reservation | Stack mapping including guard | Offset mode |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Map, pool, 8 KiB returns, 1M sort | O1 | 0.036892 s | 17,600 KiB | 16,560,128 B | 16,564,224 B | Build error |
| Map, pool, 8 KiB returns, 1M sort | O3 | 0.032658 s | 17,600 KiB | 16,560,128 B | 16,564,224 B | Build error |
| 20 MB Ascii builder plus 16 MB list | O1 | 0.014185 s | 36,608 KiB | 36,003,840 B | 36,007,936 B | Build error |
| 20 MB Ascii builder plus 16 MB list | O3 | 0.015249 s | 36,608 KiB | 36,003,840 B | 36,007,936 B | Build error |
| 8,192-element list, sum and indexed update over 2,048 rounds | O1 | 0.008255 s | 11,440 KiB | 69,632 B | 73,728 B | Build error |
| 8,192-element list, sum and indexed update over 2,048 rounds | O3 | 0.008462 s | 11,440 KiB | 69,632 B | 73,728 B | Build error |

The tight-list program takes its round count and initial list seed from a runtime argument. It prints each round's accumulated sum, preventing the benchmark from collapsing into an unobserved constant result. The run script passes `measure` and redirects program output to `/dev/null`.

The offset diagnostics identify the blocking paths:

| Probe | First reported blocker |
| --- | --- |
| `t13_soa_gather` | `first` has an 8,004-byte read parameter passed by pointer. |
| `t14_ascii_values` | `identity` has a 96-byte Ascii parameter passed by pointer. |
| `t15_append_growth` | `label` returns Ascii through a stack-backed fresh/append destination. |
| `t16_collections` | `line` has an 80-byte struct parameter passed by pointer. |
| `t23_live_elements` | `numbers` returns a collection through a stack-backed destination. |
| `selfhost/` | `token_kind_name` returns Ascii through a 36-byte stack-backed destination. |

`nlc inspect contracts selfhost` reports 130 functions with a nonzero data-stack requirement, 345 pointer parameters, and five caller-destination results. `main` has a 192,745,324,564-byte requirement; `output_token_dump` has a 10,494,673-byte requirement and pointer parameters for its source, files, and tokens. `empty_parse_tables` returns a 616,907,937-byte value through a caller destination. The self-hosted lexer does not compile in offset mode.

The accepted scalar smoke binary has an `i64 %nl.entry.top` ABI and calls `nl_context_set_top_offset`. The benchmark script compares its stdout with a pointer-mode build at both optimization levels; all five offset runs match. `NLC_STACK_STATS=1` reports `reserved=262144`, `peak_used=0`, and zero growths/relocations. `inspect stacks` still reports its 4,096-byte contract reservation for that program; the runtime's 256 KiB initial mapping is the actual offset-mode reservation.

## Runtime relocation probe

This is a C runtime/API probe, not a generated next-lang program. Both variants execute the same 32 MiB of 512 chunk allocations and byte writes. Dynamic mode starts at 256 KiB and triggers seven forced relocations. Preallocated mode sets `NLC_STACK_PREALLOC=1`, maps the requested 32 MiB plus 4 KiB before the first allocation, and triggers no relocation. Both variants verify all data and the guard page. Elapsed times below are best of five; `mremap` time is the observed range across the five runs.

| Optimization | Runtime mode | Data reservation | Mapping including guard | Peak used | Growths / relocations | Total `mremap` time | Best elapsed | Peak RSS |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| O1 | Dynamic | 33,554,432 B | 33,558,528 B | 33,554,432 B | 7 / 7 | 101,682–109,217 ns | 0.26 s | 34,320 KiB |
| O1 | Preallocated | 33,558,528 B | 33,562,624 B | 33,554,432 B | 0 / 0 | 0 ns | 0.26 s | 34,320 KiB |
| O3 | Dynamic | 33,554,432 B | 33,558,528 B | 33,554,432 B | 7 / 7 | 97,145–105,884 ns | 0.23 s | 34,320 KiB |
| O3 | Preallocated | 33,558,528 B | 33,562,624 B | 33,554,432 B | 0 / 0 | 0 ns | 0.27 s | 34,320 KiB |

The timings include process startup, filling and validating 32 MiB, checksum work, and a forked guard-page check. The measured `mremap` time is about 0.1 ms across seven moves in this probe. Wall-clock variation is larger than that duration. This says little about the cost of adding `base + offset` to every language-level access.

## IR findings

The offset scalar smoke IR confirms the hidden top is an `i64` and the runtime entry point returns the base offset. It contains no call to the offset region allocator because the program needs no data-stack region. The compiler contains an offset-region allocation path that obtains an offset and reloads the base before deriving the region pointer, but the fail-closed check prevents stack-backed programs from reaching that path.

No offset IR was emitted for the list, collection, builder, return, or write-parameter workloads. I could not check whether LLVM keeps the base in a register, combines `base + offset` with lane indexing, or hoists loads for those workloads. There is no per-access offset-addressed language measurement in this report.

## What full adoption would change

The emitter's current large-value ABI passes raw pointers for read/write parameters and caller-owned result destinations. Ascii/Text/Bytes descriptors store payload pointers. Collection lanes, loop views, structure-of-arrays gather/scatter, sort scratch, copies, and builder streaming all derive and retain pointers. Supporting movement requires offset-aware representations at each boundary and base reloads wherever a stack growth call can invalidate a derived address.

The implementation would need to:

- Change every stack-backed parameter and hidden result destination, including direct, indirect, optional, append, and callback calls, to use offsets.
- Store offsets in stack-backed Ascii/Text/Bytes descriptors and in any collection lane or view that can survive a growth point.
- Recompute addresses at use sites in copies, returns, constructors, equality, print/IO, `write` copyback, loop views, map/pool operations, and sort scratch.
- Mark every call that can grow and prove that no raw data-stack pointer remains live across it. Foreign and runtime calls need an explicit pinning boundary.
- Update scope cleanup, branch/loop stack-top joins, function-type stack contracts, and error paths to carry offsets.
- Add movement fixtures for append mid-call, loop growth, a growing callee with a `write` parameter, several live builders, copies, large return destinations, and the T13/T14/T15/T16/T23 paths.

The 18.9k-line emitter has pointer-based address construction across many subsystems, alongside an 1.8k-line runtime. A low-confidence implementation estimate is roughly 3,000–6,000 changed or added compiler/runtime/test lines, with the borrow/pin analysis potentially expanding that work.

New language/runtime rules need to say that offsets belong to one job stack and cannot escape into globals or returned references; an offset stays valid across moves, but a derived raw pointer expires at the next possible growth; calls that may grow invalidate cached base pointers; and foreign/runtime calls pin the stack until return. The compiler must enforce those rules for hidden destinations, `write` parameters, callbacks, views, and builders.

## Risks

- A missed emitter path can leave a stale raw pointer after `mremap`, causing silent corruption. The current preflight avoids that by rejecting region-bearing programs.
- Offsets need provenance. An offset into the job stack must not be confused with a pointer into globals, native stack storage, static strings, or foreign memory.
- `noalias`, pointer identity, alias checks, and LLVM load motion may change when stack pointers become integer offsets and are reconstructed.
- Pinning every foreign/runtime boundary and every callback into generated code expands the ABI and limits where growth can occur.
- `mremap` failure, address-space fragmentation, memory limits, and per-platform equivalents remain to be handled. This prototype is Linux-specific.
- Most importantly for the adoption decision, the compiler-side access overhead and optimizer response have not been measured.

## Recommendation

Keep pointer mode as the default and do not use these numbers to adopt offset addressing or to size T28. The Linux runtime moved 32 MiB through seven relocations with about 0.1 ms of accumulated `mremap` time, but the language benchmarks that would expose the per-access cost all fail closed before IR generation. A decision needs a compiler vertical slice that can run the list, builder, result-destination, and write-parameter workloads through actual relocations and through the preallocated variant.

## Reproduction

From the worktree root, build the release compiler offline and run the pointer suite:

```sh
CARGO_TARGET_DIR="$HOME/.cache/next-lang/spike-target" cargo build --release --offline
NLC_STACK_MODE=pointer NLC_OPT_LEVEL=1 \
  CARGO_TARGET_DIR="$HOME/.cache/next-lang/spike-target" cargo test --offline
```

Then run the benchmark and safety probes:

```sh
./spike/run-language-benchmarks.sh
./spike/run-runtime-growth.sh
./spike/probe-offset-fixtures.sh
```

The scripts use the release compiler at `$HOME/.cache/next-lang/spike-target/release/nlc`. They save per-optimization timings, RSS, stack reservations, offset build diagnostics, and runtime growth counters under `spike/results/`; the language script also compares the offset smoke program's output against pointer mode. The self-host failure and contract counts can be reproduced with:

```sh
NLC_STACK_MODE=offset \
  "$HOME/.cache/next-lang/spike-target/release/nlc" build selfhost -o /tmp/nlc-selfhost-offset
NLC_STACK_MODE=pointer \
  "$HOME/.cache/next-lang/spike-target/release/nlc" inspect contracts selfhost
```

## Round 2

### Working offset-mode slice

Offset mode now compiles and runs a constrained relocatable slice: local `list<long, N>` and lists of small scalar-field structs, list `push`/`count`/`len`, indexed reads and writes, list and counted loops, field reads and updates, read and `write` list parameters, and list results written through caller destinations. It also supports local Ascii builders with literal and `str(long)` appends, `try_append`, `len`, printing, and `grow` parameters. Large locals, parameters, and hidden result destinations cross function boundaries as offsets. Stack-backed Ascii payload descriptors and streaming write destinations store offsets; code reloads the base at use sites and after calls that can grow.

The offset-mode preflight walks functions reachable from `main` and tests and rejects unsupported paths before LLVM emission. The current slice excludes maps and other collection types, large values other than the supported lists, Ascii function results, runtime globals and large/string constants, indirect and optional calls, runtime calls other than print, non-list iteration, most collection methods, calls in collection indices or list push arguments, and large call results outside a direct local initializer. The error names the function and unsupported type or operation. The T13/T14/T15/T16/T23 probes now fail with these diagnostics rather than emitting unsafe code. For example, the map probe reports that `map<long, long, 1024>` is outside the slice.

`spike/offset-slice/main.nl` covers both list layouts and parameters/results, two lists and builders live at once, counted and collection loops, and builder growth. Its `try_append` takes the scratch-allocation path with only 18 bytes left in the builder. A later loop calls a function with a `write` list parameter; that callee allocates a 1.6 MB list before updating the parameter and appending to the builder. With `NLC_STACK_VERIFY=1`, the runtime reserves a fresh mapping on each growth and replaces the old mapping with `PROT_NONE`. The O1 and O3 fixture runs both passed the poison check, each recorded four relocations, and each produced the same stdout as pointer mode. The final run recorded 2,648,612 bytes peak stack use, a 4,194,304-byte reservation, and 21,434 ns (O1) / 18,508 ns (O3) inside `mremap` across the four moves.

The pointer ABI remains the default. The complete existing suite passed with `NLC_STACK_MODE=pointer`, including the self-host parity test. The offset-mode compiler test now checks that the slice compiles and an unsupported map fails clearly.

### Measurement method

Measurements ran in WSL2 Linux 6.6.87.2, x86_64, 4,096-byte pages, with Ubuntu clang 18.1.3. The compiler was release-built offline. Each program was compiled with `NLC_OPT_LEVEL=1` and `3`; elapsed time is the best of five runs measured with Python `perf_counter_ns`. Peak RSS is the maximum child-process `ru_maxrss` across those runs, reported in KiB. For each binary, the runner checks that stdout is consistent across its five runs, then compares the first dynamic and preallocated offset outputs with the first pointer output. The dynamic offset runtime starts with 262,144 bytes and doubles its reservation as needed. To ensure movement happened in every dynamic workload, the tight-list and struct-list programs allocate a reserve region after initializing the measured collection and before the hot loop. Preallocated mode (`NLC_STACK_PREALLOC=1`) reserves the compiler-reported amount from startup. Both modes include one 4,096-byte guard page beyond the reported data reservation. Benchmark timings do not enable poison verification; the separate functional slice run does.

### Timing results

Each timing is best of five. The RSS columns give the measured maximum child RSS; the same process-level value applied to all three variants for each workload and optimization level.

| Workload | Opt | Pointer seconds / RSS KiB | Offset dynamic seconds / RSS KiB | Offset preallocated seconds / RSS KiB |
| --- | ---: | ---: | ---: | ---: |
| `offset-tight-list`: 8,192 longs; 2,048 sum-and-update rounds | O1 | 0.009190 / 12,320 | 0.018107 / 12,320 | 0.018197 / 12,320 |
| `offset-tight-list` | O3 | 0.009061 / 12,320 | 0.018486 / 12,320 | 0.018412 / 12,320 |
| `offset-struct-list`: 8,192 `Pair` values; 2,048 sum-y/update-x rounds | O1 | 0.009044 / 12,320 | 0.019854 / 12,320 | 0.019706 / 12,320 |
| `offset-struct-list` | O3 | 0.008897 / 12,320 | 0.019979 / 12,320 | 0.019772 / 12,320 |
| `offset-calls`: 1,000 `write` calls and list-result calls | O1 | 0.003353 / 12,320 | 0.003621 / 12,320 | 0.003513 / 12,320 |
| `offset-calls` | O3 | 0.003470 / 12,320 | 0.003257 / 12,320 | 0.003389 / 12,320 |
| `offset-builder`: 3,000,000 `str(i) + ","` appends; final length 22,888,890 | O1 | 0.049354 / 23,760 | 0.050746 / 23,760 | 0.050214 / 23,760 |
| `offset-builder` | O3 | 0.034174 / 23,760 | 0.039969 / 23,760 | 0.039951 / 23,760 |

The call benchmark invokes `bump(write list, index)` once per iteration. `bump` allocates a 240,008-byte scratch list and updates the passed list. Each iteration also calls `copy_values`, which returns the list through a caller destination, then reads from the copy. The dynamic run grows once in the first `bump`; the preallocated run does not grow. These short timings are close to process-level noise, and the repeated list copies dominate much of their work.

### Stack use and relocation

`inspect stacks` gives the static reservation used by pointer mode and by offset preallocation. Offset dynamic starts at 256 KiB. `peak_used` is from the offset runtime counters. Relocation time is the observed range across five runs at each optimization level and measures only time inside `mremap`; it excludes mapping and poison setup.

| Workload | Static reservation / offset preallocation | Peak used | Dynamic reservation | Dynamic growths / relocations | Dynamic `mremap` ns, O1 / O3 | Preallocated growths / relocations |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `offset-tight-list` | 307,200 B | 305,552 B | 524,288 B | 1 / 1 | 5,824–7,037 / 5,519–7,476 | 0 / 0 |
| `offset-struct-list` | 294,912 B | 291,088 B | 524,288 B | 1 / 1 | 5,781–8,616 / 5,798–8,253 | 0 / 0 |
| `offset-calls` | 372,736 B | 305,552 B | 524,288 B | 1 / 1 | 6,033–7,971 / 5,728–11,920 | 0 / 0 |
| `offset-builder` | 24,002,560 B | 24,000,016 B | 33,554,432 B | 1 / 1 | 5,042–7,620 / 5,491–8,334 | 0 / 0 |

Each reservation above has an additional 4,096-byte guard page in the mapping. The builder's dynamic reservation is the next power-of-two growth target above its 24 MB data requirement. The timing difference for list loops is about 2x. The builder is close at O1 and about 17% slower in dynamic offset mode at O3. The call result varies around pointer mode at these durations. The measured relocation itself is only several microseconds per move; address reconstruction in hot loops, rather than moving the mapping, is the visible cost here.

### Inner-loop IR

The saved optimized IR is in `spike/results/offset-ir/offset-tight-list-{pointer,offset}-O{1,3}.opt.ll` and the corresponding struct-list files. At both O1 and O3, pointer mode loads the list count before the inner loop and reuses the list pointer in the loop:

```llvm
%smax = tail call i64 @llvm.smax.i64(i64 %t33, i64 0)
...
%t38 = getelementptr inbounds %nl.ty.18, ptr %t0, i64 0, i32 1, i64 %local.6
%t39 = load i64, ptr %t38
...
store i64 %t53, ptr %t38
```

Offset mode does not hoist the base or the list count. The optimized hot loop calls `nl_context_base` once for the read and again for the indexed update, and it reloads the count at each access:

```llvm
%t56 = tail call ptr @nl_context_base(ptr %nl.ctx)
%t57 = getelementptr i8, ptr %t56, i64 %t7
%t60 = load i64, ptr %t57                 ; list count for read
...
%t71 = tail call ptr @nl_context_base(ptr %nl.ctx)
%t72 = getelementptr i8, ptr %t71, i64 %t7
%t75 = load i64, ptr %t72                 ; list count for update
```

The struct-list loop shows the same repeated base reconstruction for its field accesses. The pointer mode keeps the collection pointer available; offset mode calls the runtime accessor each time. The accessor is an external call without purity attributes, so LLVM conservatively keeps these calls and count loads in the loop. This matches the roughly twofold tight-loop timings.

### What broke and what was fixed

The first offset emitter pass handled region allocation but could not safely carry the result through the existing pointer-based value ABI. Large parameters and result destinations were pointers, list iteration and structure-of-arrays lanes derived pointers from them, and Ascii descriptors stored payload pointers. Any one of those could become stale after a callee or append relocated the data stack. The round 2 implementation changed those boundaries in the supported slice to offsets and reconstructs pointers at each use. It also re-resolves list and builder addresses after growth-capable calls, including caller destinations and `write` parameter copyback, and handles append scratch storage after allocation.

The `NLC_STACK_VERIFY=1` fixture turns stale accesses into faults by keeping old mappings poisoned. Its four moves include an append scratch allocation and growth inside a callee with a live `write` list parameter while a builder and other list regions remain live. The T13/T14/T15/T16/T23 probes and unsupported operations remain build errors, keeping unsupported code from silently using the pointer emitter assumptions.

### Revised full-adoption estimate and recommendation

This narrow vertical slice required about 1,100 added lines and 180 removed lines in the emitter, plus runtime relocation verification and tests. With that implementation cost known and the unimplemented global, map/pool, array/grid, sorting, callback, indirect-call, and broader Ascii/Text/Bytes paths still outstanding, a full implementation is now estimated at roughly 4,000–7,000 changed or added compiler/runtime/test lines in total. Confidence is medium-low because a general offset provenance and pointer invalidation analysis could require a larger emitter redesign.

Keep pointer mode as the default. The slice demonstrates that relocation can work across list and builder operations, including calls and `write` parameters, and that the runtime move itself is inexpensive. The measured list loops are still about twice as slow because the emitted code reconstructs the base and reloads count for each access. Before considering broad adoption, the compiler would need a safe way to cache a base across non-growing regions of code and invalidate it at every growth point, then repeat these measurements. The optional 32-bit-offset experiment was not attempted; all Round 2 measurements are x86_64 with 64-bit offsets.

### Reproduction

From the worktree root, build and run the full existing test suite in pointer mode:

```sh
CARGO_TARGET_DIR="$HOME/.cache/next-lang/spike-target" cargo build --release --offline
CARGO_TARGET_DIR="$HOME/.cache/next-lang/spike-target" \
  NLC_STACK_MODE=pointer cargo test --offline
```

Run the verified functional fixture, the T13/T14/T15/T16/T23 unsupported probes, and the benchmark suite with its IR capture:

```sh
./spike/run-offset-slice.sh
./spike/probe-offset-fixtures.sh
./spike/run-offset-benchmarks.sh
```

The benchmark runner compiles each program for pointer mode and offset mode at O1 and O3, measures five runs each, compares stdout, and saves timings, RSS, stack counters, compiler reservations, and optimized/raw IR under `spike/results/`. `run-offset-benchmarks.sh` also invokes the verified fixture and IR capture, so it is the single command to regenerate the language measurements and IR after the release build. The 32-bit experiment is optional and was not run.

## Round 3

### Cached base and aliasing

Offset-mode functions now keep the current data-stack base in a private pointer slot. Pointer reconstruction loads that value instead of calling `nl_context_base` for every access. The optimizer promotes the slot to SSA: it uses the entry base until an offset region allocation or a call whose stack contract has a nonzero requirement, then uses the reloaded base. Offset allocation refreshes the base immediately after `nl_stack_alloc_offset`; pointer mode emits no slot or refresh and remains the default.

The optimized IR still kept the list count check inside the loop after the base cache alone. I added an offset-only alias scope to list count loads and a matching no-alias scope to list payload-lane stores. The list header and its structure-of-arrays lanes occupy disjoint ranges, and count stores remain unannotated, so a push or other count change is still visible to LLVM as a possible write to the loaded count. With this distinction, LLVM hoists the count load in both the tight-list and struct-list loops.

`spike/offset-cache-call/main.nl` adds a loop that calls `grower` every four iterations and reads and updates `values[0]` on every iteration, including immediately after each call. `grower` allocates an 800,008-byte scratch list. At O1 and O3, `run-offset-slice.sh` ran this fixture with `NLC_STACK_VERIFY=1`: each run relocated once, poisoned the old mapping, and matched pointer-mode stdout (`0`, `0`, `0`, `12559`). The recorded peak use was 801,040 bytes in a 1,048,576-byte reservation; the measured `mremap` times were 6,755 ns (O1) and 5,548 ns (O3). The main offset-slice fixture also passed poison verification at both levels, with four relocations each, peak use 2,648,612 bytes, and reservations of 4,194,304 bytes. The T13/T14/T15/T16/T23 probes still produce explicit unsupported diagnostics.

### Re-measured timing results

The method is unchanged from Round 2: WSL2 Linux 6.6.87.2, x86_64, 4,096-byte pages, clang 18.1.3; compiler and benchmark programs built at O1 and O3; five fresh-process runs per variant; best elapsed time from Python `perf_counter_ns`; maximum child RSS in KiB; and stdout compared across pointer, offset dynamic, and offset preallocated modes. Dynamic offset runs started with 256 KiB and doubled the reservation as needed. Measurements did not enable poison verification; the separate fixture runs above did.

| Workload | Opt | Pointer seconds / RSS KiB | Offset dynamic seconds / RSS KiB | Offset preallocated seconds / RSS KiB |
| --- | ---: | ---: | ---: | ---: |
| `offset-tight-list`: 8,192 longs; 2,048 sum-and-update rounds | O1 | 0.008904 / 12,320 | 0.008809 / 12,144 | 0.009020 / 12,320 |
| `offset-tight-list` | O3 | 0.008999 / 12,320 | 0.009012 / 12,320 | 0.008907 / 12,320 |
| `offset-struct-list`: 8,192 `Pair` values; 2,048 sum-y/update-x rounds | O1 | 0.008910 / 12,320 | 0.009152 / 12,320 | 0.008661 / 12,320 |
| `offset-struct-list` | O3 | 0.009174 / 12,320 | 0.009384 / 12,320 | 0.009191 / 12,320 |
| `offset-calls`: 1,000 `write` calls and list-result calls | O1 | 0.003470 / 12,320 | 0.003827 / 12,320 | 0.003383 / 12,320 |
| `offset-calls` | O3 | 0.003356 / 12,320 | 0.003496 / 12,320 | 0.003303 / 12,320 |
| `offset-builder`: 3,000,000 `str(i) + ","` appends; final length 22,888,890 | O1 | 0.050259 / 23,760 | 0.049775 / 23,760 | 0.050296 / 23,760 |
| `offset-builder` | O3 | 0.034562 / 23,760 | 0.034472 / 23,760 | 0.035439 / 23,760 |

| Workload | Static reservation / preallocation | Peak used | Dynamic reservation | Dynamic growths / relocations | `mremap` ns, O1 / O3 | Preallocated growths / relocations |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `offset-tight-list` | 307,200 B | 305,552 B | 524,288 B | 1 / 1 | 5,309–7,295 / 5,801–7,589 | 0 / 0 |
| `offset-struct-list` | 294,912 B | 291,088 B | 524,288 B | 1 / 1 | 5,738–6,139 / 5,965–6,381 | 0 / 0 |
| `offset-calls` | 372,736 B | 305,552 B | 524,288 B | 1 / 1 | 5,623–7,342 / 5,603–7,277 | 0 / 0 |
| `offset-builder` | 24,002,560 B | 24,000,016 B | 33,554,432 B | 1 / 1 | 7,188–7,555 / 6,992–8,387 | 0 / 0 |

Each runtime reservation also has a 4,096-byte guard page. Preallocated mode uses the static reservation shown in the table. The builder's dynamic reservation is the next power of two above its 24 MB data requirement.

### Inner-loop IR

Round 2's optimized offset IR called `nl_context_base` for each access and loaded the list count again for the indexed update:

```llvm
%t56 = tail call ptr @nl_context_base(ptr %nl.ctx)
%t57 = getelementptr i8, ptr %t56, i64 %t7
%t60 = load i64, ptr %t57                 ; count for read
...
%t71 = tail call ptr @nl_context_base(ptr %nl.ctx)
%t72 = getelementptr i8, ptr %t71, i64 %t7
%t75 = load i64, ptr %t72                 ; count for update
```

In Round 3, O1 and O3 both have one refreshed base and one count load before the hot loop; element accesses use that stable list address:

```llvm
%t39 = tail call ptr @nl_context_base(ptr %nl.ctx) ; after the reserve allocation
%t57 = getelementptr i8, ptr %t39, i64 %t2
%t60 = load i64, ptr %t57, align 1, !alias.scope !0
%smax = tail call i64 @llvm.smax.i64(i64 %t60, i64 0)
br label %for.cond.10.preheader
...
%t65 = getelementptr inbounds %nl.ty.18, ptr %t57, i64 0, i32 1, i64 %index
%t66 = load i64, ptr %t65, align 1
...
store i64 %updated, ptr %t65, align 1, !noalias !0
```

The struct-list IR likewise loads its count before the loop, then addresses the x and y lanes from the cached collection pointer. The cache-call fixture exercises the complementary case: after `grower` returns, the caller refreshes the base before resolving the list offset again. Raw and optimized IR for both benchmark layouts are saved in `spike/results/offset-ir/offset-{tight-list,struct-list}-{pointer,offset}*`.

### Adoption gate and remaining work

The tight-list dynamic and preallocated results differ from pointer mode by -1.1% and +1.3% at O1, and +0.1% and -1.0% at O3. Struct-list differences are +2.7% and -2.8% at O1, and +2.3% and +0.2% at O3. Both tight loops are under the 10% adoption gate in both allocation modes. The call workload's O1 dynamic run is 10.3% slower, while its preallocated run is 2.5% faster; O3 is +4.2% dynamic and -1.6% preallocated. Those runs take about 3.5 ms and remain noisy. Builder results are within 2.6% of pointer mode at both optimization levels.

The loop-level cost that remains is offset-based address calculation and the normal index check; the base accessor and count reload are outside the hot loop. Relocation itself remains several microseconds per move and is outside the measured loop. No `nonnull`, `dereferenceable`, or broad `noalias` function attributes were added. The alias metadata is limited to the proven separation between list header counts and payload lane writes.

The optional 32-bit offset variant was not attempted. Current stack offsets and local offset slots remain 64-bit. The benchmark's list storage is 65,544 bytes for `list<long, 8192>` and 131,080 bytes for `list<Pair, 8192>` (8-byte count plus two 8-byte structure-of-arrays lanes); these are collection storage sizes, not 32-bit descriptor measurements. A scaled 32-bit offset slot would be 4 bytes instead of 8, but no timing or descriptor implementation result is claimed.

### Reproduction

From this worktree, rebuild offline and run the complete pointer-mode suite:

```sh
CARGO_TARGET_DIR="$HOME/.cache/next-lang/spike-target" cargo build --release --offline
CARGO_TARGET_DIR="$HOME/.cache/next-lang/spike-target" \
  NLC_STACK_MODE=pointer cargo test --offline
```

Regenerate the poison-verified fixtures, unsupported diagnostics, five-run timing/RSS tables, stack counters, compiler reservations, and raw/optimized IR:

```sh
./spike/run-offset-slice.sh
./spike/probe-offset-fixtures.sh
./spike/run-offset-benchmarks.sh
```

`run-offset-benchmarks.sh` invokes the verified fixtures and IR capture itself. The standalone `run-offset-slice.sh` checks pointer/offset stdout at O1 and O3 with `NLC_STACK_VERIFY=1`; it also checks that the cache-call fixture actually relocates. The benchmark runner measures five fresh processes per variant, compares outputs, and saves artifacts under `spike/results/offset-benchmarks/`, `spike/results/offset-slice/`, and `spike/results/offset-ir/`.

### Verification

- `CARGO_TARGET_DIR="$HOME/.cache/next-lang/spike-target" cargo fmt --all -- --check` — passed.
- `CARGO_TARGET_DIR="$HOME/.cache/next-lang/spike-target" cargo build --release --offline` — passed.
- `CARGO_TARGET_DIR="$HOME/.cache/next-lang/spike-target" NLC_STACK_MODE=pointer cargo test --offline` — passed, including self-host parity (299.42 seconds) and doc-tests.
- `./spike/run-offset-benchmarks.sh` — passed; it regenerated the timing matrix and IR and reran the poison-verified fixtures.
- `./spike/probe-offset-fixtures.sh` — passed; all five unsupported probes produced their expected clear diagnostics.
