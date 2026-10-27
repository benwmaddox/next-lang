# Self-hosted list performance, review 1

Sol, 2026-10-27. Investigated `86ff918`, branch `perf-selfhost-lists`, exclusively in `/mnt/d/code/next-lang-perf`. Stage 0, core, committed tests and the two other checkouts were not changed. The one experimental source edit was restored; its patch and all measured IR patches are in [sol-selfhost-perf/](sol-selfhost-perf/). No production optimization is installed by this review.

## Finding

The regressions are principally **missing alias information between the stable context header and program storage**, plus **regions reserved for collection receiver expressions that never use those slots**. Eager context-top synchronization amplifies both problems. Offset arithmetic and the descriptor ABI need not be abandoned: experiments retaining them reach stage-0 speed with all arithmetic checks intact.

First measurement round, seconds, best of five:

| Pair | Stage 0 | Self-hosted | Header/data alias information only | Also remove unused inner regions | Also omit redundant scope-exit top synchronization |
| --- | ---: | ---: | ---: | ---: | ---: |
| increment_heavy | 0.657 | 1.700 | 1.043 | 0.848 | **0.666** |
| struct_update | 0.766 | 1.772 | 1.117 | 0.906 | **0.747** |
| tight_list | 0.494 | 0.609 | 0.595 | 0.515 | **0.491** |
| calls | 0.831 | 0.644 | 0.641 | 0.614 | **0.579** |

These are cumulative interventions in the displayed order, each linked with `nlc link-ir` at O3. Conditional shares of the original self-hosted minus stage-0 gap are approximately:

| Pair | Header/data alias information | Unused regions, after alias fix | Redundant synchronization, after both | Residual |
| --- | ---: | ---: | ---: | ---: |
| increment_heavy, gap 1.043 s | 0.657 s / 63% | 0.195 s / 19% | 0.182 s / 17% | 0.009 s |
| struct_update, gap 1.006 s | 0.655 s / 65% | 0.211 s / 21% | 0.159 s / 16% | -0.019 s |
| tight_list, gap 0.115 s | 0.014 s / 12% | 0.080 s / 70% | 0.024 s / 21% | -0.003 s |

The interventions interact: these percentages depend on order and are not independent cost estimates. Negative residuals and differences below roughly 10% are noise-level. `calls` has no positive gap to apportion. Extending the same changes to its leaf helpers reduces its checked runtime further, to **0.208 s**; see below.

## Build and measurement controls

Read and followed [bench-vs-rust.sh](../../scripts/bench-vs-rust.sh). Its stage-0 command is `NLC_OPT_LEVEL=3 nlc build <pair> -o <exe>`: default Rust frontend, normal C runtime. It builds the compiler itself using `--frontend=rust build selfhost`, then invokes that executable inside each pair with `build . -o <relative.ll> --runtime=core`, and links using `NLC_OPT_LEVEL=3 nlc link-ir`. No `-march=native`, LTO, or different optimization level is added to either next-lang side. The script's Rust flags are immaterial to this comparison.

Built frozen stage 0 offline with `CARGO_TARGET_DIR=/home/ben/.cache/next-lang/target-perf`, `ulimit -v 8000000`, and `timeout 240 cargo build --release --offline -p next-lang`. Compiler bootstrap also used that virtual-memory limit and a 240-second timeout; each program build/link used 90 seconds. The worktree's tracked sources initially matched HEAD, so compiling its selfhost directory gives the script's HEAD source. Baseline self-hosted IR carries core fingerprint `4662151df84e1069eb811e1b1dfe9a3f2e9e9ce7aa9a166765318b072a403fd9`.

Tools: Ubuntu clang/LLVM **18.1.3**, x86-64, Intel Core Ultra 9 185H. All measurements retained for attribution used `taskset -c 8`, best of five, exclusively holding `/home/ben/linuxbench/bench.lock`. The initial round used Python `flock(LOCK_EX)` on the existing file opened read-only and a monotonic wall clock around process execution. The corrected confirmation round acquired the inherited descriptor with **`( flock -x 9; run_measurements ) 9</home/ben/linuxbench/bench.lock`** and used exactly `/usr/bin/time -f '%e %M' taskset -c 8 <binary>`. Opening the existing lock read-only avoids attempting a write outside this sandbox; both forms take the same exclusive flock. Each of the five executions of every variant had stdout compared byte-for-byte with its stage-0 output and exited successfully. Some samples had large outliers; the retained timing spreads are recorded below. This is an ablation study, not a claim of sub-percent precision. An earlier exact-clock harness accidentally used flock's filename-plus-command form with `9`, locking a scratch file rather than the inherited descriptor; it could overlap the last diagnostic batch. Those samples were discarded, the scratch lock was deleted, and the confirmation was repeated with the correct descriptor form. A nonblocking probe verified the real benchmark lock was held during the corrected run. The original attribution round already used the correct lock.

Captured stage-0 input IR using a temporary PATH wrapper for `clang` that copied its `.ll` input before executing `/usr/bin/clang`; no compiler source change was necessary. Produced both `opt-18 -S -O3` and `clang -O3 -S -emit-llvm` outputs, then `llc-18 -O3` assembly from the latter. Counts below use clang's optimized module, the pipeline relevant to linking. `opt -O3` alone differs in some loop unswitching/unrolling. Used `-Rpass=loop-vectorize -Rpass-missed=loop-vectorize -Rpass-analysis=loop-vectorize` and optimization-record YAML to distinguish benchmark loops from vectorized initialization/copy loops.

Raw input IR SHA-256 prefixes (16 hex digits), stage 0 / self-hosted:

| Pair | Stage 0 | Self-hosted |
| --- | --- | --- |
| increment_heavy | `980de120c4e9ce97` | `3206fbb847f7df7a` |
| struct_update | `be30b32b9e81b14b` | `3b3cee1f5fa8da75` |
| tight_list | `4aa14adf54cb6bd4` | `fa8d3edb50c615a8` |
| calls | `7066ee29f9992791` | `b3422e84331ed35a` |

Full generated modules and binaries were scratch artifacts and were removed. The following excerpts, exact patches and reproduction procedure preserve the evidence needed to recreate them.

## What LLVM leaves in the hot loops

Counts are per element, after optimization, on the normal non-growing path. They exclude cold failure/growth blocks and outer-loop work. Intrinsic overflow operations are instructions, not machine calls. Header loads in the “other” column mean reservation and peak accounting. Conditional peak stores are listed separately.

| Pair / compiler | Element loads / stores | Count loads | Base reloads | Other header loads | Header stores | Bounds checks | Real successful-path calls |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| increment / stage 0 | 4 / 3 | 0 | 0 | 0 | 0 | 1 | 0 |
| increment / self | 4 / 3 | 4 | 3 | 2 | 4, plus conditional peak | 4 | 0; cold grow edge remains |
| struct / stage 0 | 4 / 2 | 0 | 0 | 0 | 0 | 1 | 0 |
| struct / self | 6 / 2 | 3 | 2 | 2 | 4, plus conditional peak | 3 | 0; cold grow edge remains |
| tight / stage 0 | 1 / 0 | 0 | 0 | 0 | 0 | 1 | 0 |
| tight / self, unswitched fast version | 1 / 0 | 1 | 0 | 0 | 4, plus conditional peak | 1 | 0 |
| calls / stage 0 | 6 / 4 | 6 | 0 | 0 in caller IR | 0 in caller IR | 6 | **6 `nl_context_set_top` calls** |
| calls / self | 6 / 4 | 6 | 4 | 2 | 12, plus conditional peak | 6 | 0; cold grow edge remains |

For tight_list, LLVM emits several loop versions. The fast version carries peak state in a phi and hoists the reservation/base work; another version retains the reservation load and growth edge. Do not sum instructions across mutually exclusive versions. For calls/stage 0, runtime memory accesses inside the six opaque calls are additional to the table.

The fully combined checked change leaves 3 loads/3 stores for increment, 4/2 for struct, and 1/0 for tight; each retains one bounds check but no base/count reload or header store in the inner loop. The final leaf-helper change gives calls 4 element loads/4 stores and one bounds check, with its arithmetic still checked.

### increment_heavy

Stage 0 uses a fixed pointer and `inbounds` typed GEPs. Its nested `Middle` leaves are adjacent in a 16-byte element lane; the id lane is separate. The self-hosted flattened layout instead has three 8-byte lanes, at offsets 8, 4104 and 8200. This layout difference does not prevent parity.

Before optimization, self-hosted code repeatedly calls `nl_context_current_base`, computes `region.offset + field_offset + index * 8`, gathers struct elements into native temporaries, and recomputes the place for store-back. LLVM removes the unused native gathers and most repeated address arithmetic. It does **not** remove the unused region's allocation side effects:

```llvm
; Original emitted IR, every inner iteration (scope 89).
%nl.scope.end.89 = add i64 %nl.scope.base.89, 49184
%nl.scope.reserved.89 = call i64 @nl_context_reservation_bytes(ptr %nl.ctx)
%nl.scope.grow.89 = icmp ugt i64 %nl.scope.end.89, %nl.scope.reserved.89
br i1 %nl.scope.grow.89, label %nl.scope.slow.89, label %nl.scope.ready.89
; ready: publish top and peak, then define four region.offset values.
; All four region.offset definitions have zero uses.
```

49,184 bytes is **four copies of the entire 12,296-byte list**. The region planner mistakes the list receiver Name in each `items[index]` expression for a collection temporary, although emission reads the existing binding. Root scope 109 separately reserves 49,184 bytes, including unused receivers in the final prints.

After O3, this sequence remains between field stores (actual names, abbreviated control flow):

```llvm
store i64 %asgn.value.67, ptr %addr.65, align 1
%nl.ctx.val24 = load ptr, ptr %2, align 1       ; %2 = ctx + 56
%loc.pointer.18002 = getelementptr i8, ptr %nl.ctx.val24, i64 %nl.scope.base.109
%coll.index.count.70 = load i64, ptr %loc.pointer.18002, align 1
%coll.index.high.70.not = icmp slt i64 %local.5.0101, %coll.index.count.70
br i1 %coll.index.high.70.not, label %coll.index.ok.70, label %coll.index.fail.70
```

There was **no intervening call** and no possible legitimate relocation. LLVM cannot prove the preceding unannotated store misses the header's base field. The resulting newly loaded base makes even successive references to the same list look different, defeating count CSE and value forwarding. Stage 0 keeps the list pointer fixed and its count from initialization in SSA; it has one bounds check, three checked increments and a checked checksum addition. Self-hosted also has four arithmetic checks, but four bounds checks.

Stage-0 O3's stable-address form is:

```llvm
%t91 = getelementptr inbounds %nl.ty.21, ptr %local.0, i64 0, i32 1, i64 %local.5.026
%t94 = load i64, ptr %t91, align 1
%t95 = tail call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %t94, i64 1)
; overflow branch, then store to the same %t91; other fields use fixed lanes.
```

With header/data TBAA plus dead-region and synchronization removal, the checksum directly consumes `%asgn.value.67`; no fourth data load is needed. Descriptor arithmetic still lowers to a shift and ordinary address generation. The measured 0.666 s versus stage 0's 0.657 s rules out unavoidable descriptor cost as the source of the original one-second gap.

### struct_update

Both compilers use four scalar lanes. Before optimization, self-hosted emission gathers unused whole Particle values and reserves six unused copies of its 131,080-byte list per inner iteration: **786,480 bytes**, scope 122. Root scope 140 reserves 524,320 bytes. Again, all six hot-scope `region.offset` definitions are unused.

The optimized self-hosted loop has the same false alias chain after writing x and y. It reloads base twice, checks the count three times, and rereads both updated fields for the checksum:

```llvm
; Self-hosted O3, after y's checked update:
store i64 %asgn.value.110, ptr %addr.105, align 1
%nl.ctx.val38 = load ptr, ptr %2, align 1
%loc.pointer.35429 = getelementptr i8, ptr %nl.ctx.val38, i64 %nl.scope.base.140
%coll.index.count.114 = load i64, ptr %loc.pointer.35429, align 1
; bounds branch, then:
%v115 = load i64, ptr %addr.115, align 1       ; x again
%v119 = load i64, ptr %addr.119, align 1       ; y again
```

Stage 0 forwards both updates instead:

```llvm
store i64 %t176, ptr %t164, align 1           ; updated y
%t197 = tail call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %t155, i64 %t176)
; %t155 is updated x, still in SSA.
```

Both sides retain four checked additions per element: x, y, x+y, checksum. There are no user calls, descriptors passed to callees, or `write`-parameter store-backs in this loop. Header/data separation alone saves 0.655 s; the full checked change saves 1.025 s and reaches 0.747 s.

### tight_list

There are no element stores to invalidate the base. Accordingly, base reloads are already hoisted in LLVM's fast loop version, and the alias-only experiment helps little. The planner still reserves **800,008 unused bytes** for the receiver Name per iteration (scope 53), on top of root scope 69's 3,200,032 bytes. This drives top/peak bookkeeping and inhibits hoisting the count past context stores.

```llvm
; Original emitted region (unused offset.33):
%nl.scope.end.53 = add i64 %nl.scope.base.53, 800008
; Optimized fast version, normal inner iteration:
store i64 %nl.scope.target.53, ptr %sys.ptr.1025.i24, align 1
store ptr %v1036.i38.us.us.us, ptr %sys.ptr.1037.i27, align 1
%coll.index.count.35.us.us.us = load i64, ptr %loc.pointer.10346.us.us.us, align 1
; load element, checked add round, parity test, checked add/sub checksum
store i64 %nl.scope.target.69, ptr %sys.ptr.1025.i24, align 1
store ptr %v1036.i55.us.us.us, ptr %sys.ptr.1037.i27, align 1
```

Stage-0 O3 has the following address/load; its induction/count comparison uses SSA values and there is no corresponding header publication:

```llvm
%t59 = getelementptr inbounds %nl.ty.18, ptr %local.0, i64 0, i32 1, i64 %local.5.021
%t60 = load i64, ptr %t59, align 1
%t62 = tail call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %t60, i64 %local.4.023)
```

Stage 0 loads one element, compares against the count retained from initialization, checks the value+round addition and the selected checksum add/sub, and performs no stores. The no-region ablation alone reaches 0.494 s, essentially its stage-0 time; the combined form is 0.491 s. This pair is chiefly a region-planning regression, not expensive scalar indexing.

### calls: preserve the visible core helpers

LLVM inlines `bump_field` and `process_value` on **both** sides. Stage 0 nevertheless retains six opaque C-runtime `nl_context_set_top` calls per element: four bump exits and two process exits. Assembly confirms six `callq nl_context_set_top@PLT` in the inner loop. Those functions validate top against context base/limit and store it; their opaque declarations also invalidate caller memory knowledge. The self-hosted helpers' exit calls target core IR in the same module; LLVM inlines them into two header stores and removes some redundant updates. There are no actual `bump_field`/`process_value` calls in either machine hot loop.

```llvm
; Stage-0 O3, bump inlined but runtime exit remains:
store i64 %t2.i, ptr %t125, align 1, !alias.scope !2
tail call void @nl_context_set_top(ptr %nl.ctx, ptr %t10), !noalias !2
%t128 = load i64, ptr %local.0, align 1

; Self-hosted O3 equivalent:
store i64 %asgn.value.4.i, ptr %loc.pointer.677.i, align 1
store i64 %nl.scope.target.140, ptr %sys.ptr.1025.i57, align 1
%nl.ctx.val.i.i = load ptr, ptr %2, align 1
%v1036.i.i = getelementptr i8, ptr %nl.ctx.val.i.i, i64 %nl.scope.target.140
store ptr %v1036.i.i, ptr %sys.ptr.1037.i60, align 1
```

`calls.opaque-top.patch` replaces the self-hosted user functions' top-update calls with an opaque declaration backed by module assembly implementing **the same two stores** (top_offset and base+offset). It preserves the updates, introduces no libc, and gives LLVM a C-like visibility barrier. Runtime rises **0.644 → 1.022 s**, a 0.378 s penalty, larger than the observed 0.187 s advantage over stage 0. This is not an exact additive estimate for the different C helper, which also validates; it demonstrates that visibility and resulting optimization explain the advantage without invoking a faster `write` ABI.

The self-hosted hot scope also reserves six unused lists (196,656 bytes), but the direct `write` descriptor itself specializes away: null anchor selects the stack, the scalar field offset is folded, and there is one checked load/increment/store per bump. It does not gather/copy-back a scalar. The current implementation accesses `write` in memory, rather than using a dedicated register-cache/store-back cleanup.

Starting with the combined 0.579 s variant, removing the leaf helpers' needless top updates alone gives **0.549 s**; adding header/data separation to their stores alone gives **0.384 s**; doing both gives **0.208 s**. LLVM then forwards updated a/b into process_value and hoists the list count/base, while retaining all bump/process/checksum overflow behavior. Keep runtime helpers visible, and propagate the alias classification into callee stores; tagging only the caller's stores misses most of this pair's benefit.

## LICM, GVN, attributes and vectorization

The blocking dependency is concrete: an ordinary user-field store may alias `ctx+56`, so LLVM reloads base. Its new pointer then prevents GVN of count/field loads. Top/peak stores may alias a count reached through a pointer loaded from that same header. A possible `nl_stack_grow` call is a real relocation/clobber barrier; LLVM cannot legally carry derived addresses through it. Removing unused reservations removes this otherwise spurious barrier. Eager header writes then remain another obstruction until omitted or isolated.

The alias experiment adds two sibling TBAA categories under a private root: `context base` on the load in `nl_context_current_base`, and `program storage` on selected typed stores. It adds **no `invariant.load`**, no purity promise for growth, and no unchecked arithmetic. Growth's actual writes remain unannotated and still invalidate the base. LLVM's BasicAA can reason about constant disjoint field offsets once the base is stable; separate per-field TBAA was unnecessary.

Stage 0 uses `inbounds` typed aggregate GEPs and gives its scalar `write` pointer `noalias`; inlining creates alias scopes. Self-hosted user definitions pass plain `(ptr anchor, i64 offset[, copies, index])`, with no corresponding user `noalias`, TBAA, `nonnull`, or `dereferenceable` promises. LLVM infers some `nonnull` call arguments and core attributes, and generates `nonnull`/`dereferenceable` on initialization memcpy calls. These are not user hot-loop alias facts. Both sides frequently use `align 1` for element loads/stores. Adding nonnull or alignment alone cannot establish that a field store misses the context header. A descriptor's **anchor may intentionally be null**, so blanket `nonnull` or `dereferenceable` on anchors is wrong.

Original loops retain checked overflow branches: four per element in increment and struct, two executed per element in tight, and checked bump/process/checksum arithmetic in calls. Bounds checks have already lost redundant negative-index tests where range analysis proves the induction variable nonnegative. Stage 0 supplies cold failure branch weights; self-hosted lacks these explicit weights. The `weights` ablation, setting the same 1:2000 failure preference, produces no material improvement (table below).

The **benchmark hot loops are scalar** in both original compilers and in the checked fixes. Successful vectorization remarks in these functions concern initialization/copy loops, not the billion-iteration update/reduction loops. Function-specific YAML reports `CantComputeNumberOfIterations`, `NonReductionValueUsedOutsideLoop`, and for self-hosted variants `NoCFGForSelect`/`CantIdentifyArrayBounds`; stage-0 initialization also reports `UnsafeDep`. Checked exceptional exits stop LLVM from treating the hot loop as an ordinary fixed-trip vector reduction. Removing only hot-main bounds and overflow branches in the `unchecked` experiment vectorizes the first three hot loops (width 2, interleave 2). It gives 0.361 / 0.448 / 0.235 s, respectively. This is a **P1 upper-bound experiment**, not a correct generic transformation. It does not explain the self-hosted/stage-0 gap: parity was reached with these checks retained. In calls, that edit leaves checks inside the separately emitted leaf functions and its hot loop remains scalar. Separate diagnostic removals confirm that overflow exits are the main vectorization barrier in increment/struct: removing overflow checks alone also produces vector hot loops (0.31/0.45 s in the confirmation round). Tight_list needs both classes removed to vectorize; overflow-only remains scalar but faster (0.26 s). Bounds-only remains scalar (0.63/0.97/0.39 s for the three pairs), and even slows struct_update relative to its 0.76 s checked control. I did not isolate that secondary scalar-code timing effect further; it does not affect the attribution of the original regressions. These interactions are another reason not to assign an independent additive cost to each check or treat deleting branches as a production fix.

## Changes to make, in payoff order

1. **Separate header storage from typed user values; cache base/limit across non-growth work.** Start in `selfhost/compiler.nl::emit_location_pointer_materialization`, the scalar load/store and compound-assignment emitters, and `selfhost/collections.nl`'s index/field/mutator emission. Use shared alias-scope/TBAA emission, including callee `write` stores, or implement the spec's explicit SSA caches with well-defined invalidation. Also classify no-region leaf calls so they are not pessimistic growth points. This recovers about 0.65 s in each large update pair before other changes. It fits an E3 correctness-preserving follow-up before collections/text emission expands; it need not wait for P1's arithmetic/range analysis. Ownership touches `params.nl` for descriptor-facing parameters and `regions.nl` for cache lifetime. Do not retrofit it into stage 0.

2. **Plan only storage the emitter actually uses.** In `selfhost/regions.nl::region_node_is_temporary` and `region_node_is_collection_method_receiver`, distinguish borrowed collection receivers from value-producing temporaries/snapshots. The one-line source patch extending the existing receiver exclusion to `NodeKind.Index` was built and measured. It removes the phantom hot reservations on all four pairs and reduces root overreservation too. It is suitable for E3b or a separate E3a follow-up. Coordinate with E3b rather than editing the other checkout. This is especially valuable for tight_list: about the entire 0.115 s regression disappears without changing its indexing arithmetic. Do not globally exclude every Name or Field: E2/E3 read snapshots may need real storage.

3. **Keep top and peak in SSA; synchronize only at required boundaries.** In `regions.nl::emit_region_scope_enter`, `emit_region_scope_exit`, `emit_current_top_*`, plus `compiler.nl::lower_scope_exit` and leaf-function exit lowering, retain logical scope resets but avoid publishing unchanged top on empty-scope exits and no-region leaf returns. Fold peak at real synchronization points. This is already the intended E3a1 model; implement it before E3d1/d2 add builder iteration scopes and more growth. The cumulative experiment saves another 0.18/0.16 s in increment/struct; leaf-helper integration has a large interaction with aliasing in calls. Preserve output/flush, failure and growth accounting behavior; a general lazy-top change needs more than the benchmark-only deletions used here.

4. **Keep core helpers optimizable across E3f/E3g.** The upcoming driver/process work should preserve same-module visibility or equivalent correct memory summaries. Emitting only reachable functions in E3e reduces module size/build work, but is not the measured hot-loop fix. A runtime ABI boundary must not accidentally restore six opaque updates per element.

5. **Defer proof-based overflow/bounds elimination and vector reduction to P1.** Use range facts to retain failures where needed and eliminate only proven checks, with arithmetic differential fuzzing and failure-order fixtures. The unchecked ceiling establishes worthwhile remaining work beyond stage-0 parity. Branch weights are a small follow-up, not the main fix. Avoid redesigning lane geometry or replacing descriptors with raw persistent pointers on this evidence.

## Correctness limits and what the E3 spec requires

[E3's allocation/growth-point contract](../tasks/E3-selfhost-collections-text.md) explicitly says the function caches base and limit in SSA, reloads after a possible growth point, and keeps long-lived references as offsets. It permits proving functions region-free. Thus the specification **supports** the proposed cache; it does not require reloading base after every ordinary field store. A cached base becomes invalid after `mremap`, even if a specific benchmark never grows after startup. Never hoist a cache above an actual grow, growing user/core call, or a later argument evaluation that can grow. The retained descriptors must still rematerialize addresses after that boundary. Do not mark the base invariant for a function or whole job. Validate a production implementation with the directed forced-relocation cases and threshold-zero suites, including a growing callee reached through a `write` argument.

The spec requires logical iteration scopes/reset on every exit, native-versus-stack descriptors, checked allocation, and correct high-water accounting. It does **not** require phantom list slots, four context stores per iteration when nothing allocates, or eager peak publication on each iteration; it explicitly describes caching peak and folding at synchronization points. The benchmark deletion patches are justified by zero-use region offsets and no live inner allocation, not by a general license to omit cleanup.

Read arguments/operands are evaluation-point snapshots; write/grow arguments reference the place after later arguments have run. Capture/check indexes once, keep deferred gathering where necessary, and never turn an effectful read into a borrowed live pointer merely to avoid a copy. Extending receiver exclusion should use the actual emission/snapshot decision, particularly for an index expression that calls a mutator.

`write` arguments have an overlap proof, but descriptor anchors can share an enclosing allocation or both be null. `noalias` on the anchor alone is not a substitute for disjoint resolved places. The spec permits noalias only where exclusivity is proved and there is no hidden result destination. Header-versus-program TBAA is a narrower fact, applicable here without falsely making separate fields or descriptors separate allocations. Raw `sys` accesses and memory primitives must remain conservatively classified unless their destination is proven. Do not tag arbitrary core pointer stores as user data: some legitimately update the context.

A future scalar write-register cache must flush before forwarding the reference, reload after a forwarded write, and store back on fallthrough, every return, `?`, and `?? return` via the shared cleanup machinery (E3b). These experiments do not require that feature. All benchmark-only elisions were checked for these fixed valid inputs; they are not a substitute for general relocation, evaluation-order, alias and failure testing. No full compiler suite was claimed for the restored source experiment.

## Experimental patch inventory and reproduction

All `.patch` files are exact diffs. Except `regions-access-receivers.patch` and `*.access-aa.patch`, they apply independently to the unmodified generated `<pair>.sh.ll`, including patches with cumulative names. `*.access-aa.patch` instead applies to the IR generated by the compiler built with the one-line source patch. Source lines were restored byte-for-byte immediately after building that experimental compiler. No test was edited or removed.

| Filename suffix | Exact intervention |
| --- | --- |
| `.dead.patch` | Delete the inner region enter/reserve/publish block and its zero-use offset definitions. Keep scope save/restore and its exit publication. |
| `.sync.patch` | Remove non-root scope-exit `nl_context_set_top_offset` calls; retain root exit publication. No region planning change. |
| `.dead-sync.patch` | Both preceding changes. |
| `.base-aa.patch` | Tag current-base load and selected typed user stores with disjoint header/program TBAA. |
| `.dead-base-aa.patch` | Dead-region plus alias changes, leaving scope-exit publication. |
| `.dead-sync-base-aa.patch` | All three, only main's typed stores classified. |
| `.weights.patch` | Add 1:2000 failure/success branch weights to hot main bounds/overflow branches. |
| `.unchecked.patch` | Combined checked change, then force hot main bounds/overflow branches to their success edge. Leaf functions are unchanged. Diagnostic only. |
| `.no-bounds.patch` / `.no-overflow.patch` | Combined checked change, then remove just one class of hot-main checks. First three pairs only; diagnostic only. |
| `regions-access-receivers.patch` | The only source edit: extend the collection-method-receiver exclusion to index receivers. Rebuild compiler; measured as `access`. |
| `.access-aa.patch` | Header/data TBAA applied to the IR from that source experiment. |
| `calls.opaque-top.patch` | Original self-hosted module, opaque assembly-backed top publication in user functions. |
| `calls.leaf-nosync.patch` | Combined change plus removing leaf functions 0/1's redundant top publication. |
| `calls.leaf-aa.patch` | Combined change plus classifying leaf functions 0/1's stores. |
| `calls.leaf-sync.patch` | Both leaf changes; all arithmetic checks remain. |

Minimal rebuild procedure (from this worktree, scratch paths of your choice):

```bash
export CARGO_TARGET_DIR="$HOME/.cache/next-lang/target-perf"
export NLC_OPT_LEVEL=3
work=$(mktemp -d /tmp/sol-perf-reproduce.XXXXXX)
mkdir "$work/bin"
cat > "$work/bin/clang" <<'WRAPPER'
#!/usr/bin/env python3
import os, sys, shutil
for arg in sys.argv[1:]:
    if arg.endswith('.ll') and os.environ.get('SOL_CAPTURE'):
        shutil.copyfile(arg, os.environ['SOL_CAPTURE'])
os.execv('/usr/bin/clang', ['/usr/bin/clang'] + sys.argv[1:])
WRAPPER
chmod +x "$work/bin/clang"
export PATH="$work/bin:$PATH"
ulimit -v 8000000
nlc="$CARGO_TARGET_DIR/release/nlc"
(ulimit -v 8000000; timeout 240 "$nlc" --frontend=rust build selfhost -o "$work/selfhost-nlc")
for p in increment_heavy struct_update tight_list calls; do
    SOL_CAPTURE="$work/$p.s0.ll" "$nlc" --frontend=rust build "bench/vs-rust/$p" -o "$work/$p.s0"
    (cd "bench/vs-rust/$p" && "$work/selfhost-nlc" build . -o .sol-perf.ll --runtime=core && mv .sol-perf.ll "$work/$p.sh.ll")
    opt-18 -S -O3 "$work/$p.s0.ll" -o "$work/$p.s0.opt.ll"
    opt-18 -S -O3 "$work/$p.sh.ll" -o "$work/$p.sh.opt.ll"
    clang -O3 -S -emit-llvm -Rpass=loop-vectorize -Rpass-missed=loop-vectorize \
        -Rpass-analysis=loop-vectorize "$work/$p.sh.ll" -o "$work/$p.sh.clang.ll"
    llc-18 -O3 "$work/$p.sh.clang.ll" -o "$work/$p.sh.s"
    # Repeat clang/llc for stage 0. Link the raw input, retaining link metadata:
    "$nlc" link-ir "$work/$p.sh.ll" -o "$work/$p.sh"
    patch -o "$work/$p.dead-sync-base-aa.ll" "$work/$p.sh.ll" \
        < "docs/reviews/sol-selfhost-perf/$p.dead-sync-base-aa.patch"
    "$nlc" link-ir "$work/$p.dead-sync-base-aa.ll" -o "$work/$p.changed"
done
# Run each binary five times, compare stdout each time, take minimum %e:
(
    flock -x 9
    /usr/bin/time -f '%e %M' taskset -c 8 "$work/increment_heavy.changed"
) 9</home/ben/linuxbench/bench.lock
```

`link-ir` requires the original metadata header as the first line and end marker as the last; append experimental LLVM metadata before the end marker. All submitted patches do this. Optimized modules were for inspection, not substituted for raw link inputs.

## Timing record

Initial correctly locked monotonic-wall measurements below show **minimum–maximum seconds across five runs**; all outputs matched. Suffixes map directly to the patch inventory. `access` denotes the source patch. The overlapping diagnostic and incorrect-lock confirmation samples described above are excluded.

| Variant | increment_heavy | struct_update | tight_list | calls |
| --- | ---: | ---: | ---: | ---: |
| s0 | 0.657–0.676 | 0.766–1.339 | 0.494–0.498 | 0.831–0.849 |
| sh | 1.700–1.989 | 1.772–1.859 | 0.609–0.624 | 0.644–0.666 |
| dead | 1.407–1.511 | 1.570–1.781 | 0.494–0.506 | 0.581–0.613 |
| sync | 1.641–1.780 | 1.733–2.655 | 0.604–0.655 | 0.650–0.672 |
| dead-sync | 1.388–1.654 | 1.389–2.325 | 0.493–0.499 | 0.584–0.809 |
| base-aa | 1.043–1.065 | 1.117–1.128 | 0.595–0.612 | 0.641–1.146 |
| dead-base-aa | 0.848–0.858 | 0.906–0.921 | 0.515–0.561 | 0.614–0.630 |
| dead-sync-base-aa | 0.666–0.675 | 0.747–0.762 | 0.491–0.503 | 0.579–0.588 |
| weights | 1.652–1.948 | 1.797–1.830 | 0.610–0.660 | 0.630–0.671 |
| access | 1.403–1.520 | 1.596–1.729 | 0.507–0.515 | 0.610–0.647 |
| access-aa | 0.845–0.856 | 0.902–1.416 | 0.516–0.522 | 0.589–0.631 |
| unchecked | 0.361–0.387 | 0.448–0.493 | 0.235–0.250 | 0.456–0.469 |
| leaf-nosync | — | — | — | 0.549–0.575 |
| leaf-aa | — | — | — | 0.384–0.403 |
| leaf-sync | — | — | — | 0.208–0.222 |
| opaque-top | — | — | — | 1.022–1.073 |

Corrected confirmation under the real benchmark lock, using the script’s `/usr/bin/time` clock: **all five wall times**, seconds. Rows follow measurement order. Peak RSS over this confirmation was 1,584–2,288 KiB. The isolated `no-bounds`/`no-overflow` diagnostics were also rerun here without overlapping measurement processes.

| Binary | Five times | Best |
| --- | --- | ---: |
| increment_heavy.s0 | 0.68, 0.68, 0.68, 0.68, 0.67 | 0.67 |
| increment_heavy.sh | 1.70, 1.78, 1.79, 1.78, 1.75 | 1.70 |
| increment_heavy.base-aa | 1.09, 1.06, 1.06, 1.04, 1.06 | 1.04 |
| increment_heavy.dead-base-aa | 0.85, 0.86, 0.85, 0.85, 0.85 | 0.85 |
| increment_heavy.dead-sync-base-aa | 0.67, 0.65, 0.66, 0.66, 0.65 | 0.65 |
| increment_heavy.no-bounds | 0.63, 0.63, 0.64, 4.04, 2.92 | 0.63 |
| increment_heavy.no-overflow | 1.35, 0.31, 0.31, 0.31, 0.31 | 0.31 |
| struct_update.s0 | 0.76, 0.77, 0.77, 1.25, 0.77 | 0.76 |
| struct_update.sh | 1.81, 1.80, 1.81, 1.79, 1.75 | 1.75 |
| struct_update.base-aa | 1.13, 1.12, 1.12, 1.12, 1.13 | 1.12 |
| struct_update.dead-base-aa | 0.88, 0.88, 0.89, 0.91, 0.90 | 0.88 |
| struct_update.dead-sync-base-aa | 0.77, 0.77, 0.77, 0.76, 0.76 | 0.76 |
| struct_update.no-bounds | 0.99, 3.23, 1.00, 0.98, 0.97 | 0.97 |
| struct_update.no-overflow | 0.46, 0.45, 0.46, 0.46, 0.45 | 0.45 |
| tight_list.s0 | 0.51, 0.51, 0.51, 0.51, 0.51 | 0.51 |
| tight_list.sh | 0.63, 0.64, 0.64, 0.63, 0.63 | 0.63 |
| tight_list.base-aa | 0.62, 0.62, 0.61, 0.61, 0.59 | 0.59 |
| tight_list.dead-base-aa | 0.49, 0.49, 0.49, 0.51, 0.50 | 0.49 |
| tight_list.dead-sync-base-aa | 0.50, 0.49, 0.50, 0.50, 0.50 | 0.49 |
| tight_list.no-bounds | 0.39, 0.39, 0.39, 0.40, 0.39 | 0.39 |
| tight_list.no-overflow | 0.26, 0.27, 0.27, 0.27, 0.27 | 0.26 |
| calls.s0 | 0.84, 0.85, 0.86, 0.85, 0.85 | 0.84 |
| calls.sh | 0.67, 0.66, 0.64, 0.64, 0.64 | 0.64 |
| calls.base-aa | 0.64, 0.66, 0.65, 2.92, 0.67 | 0.64 |
| calls.dead-base-aa | 0.60, 0.59, 0.60, 0.58, 0.60 | 0.58 |
| calls.dead-sync-base-aa | 0.59, 0.61, 0.60, 0.60, 0.60 | 0.59 |
| calls.leaf-nosync | 0.56, 0.55, 0.55, 0.56, 0.57 | 0.55 |
| calls.leaf-aa | 0.40, 0.40, 0.38, 0.38, 0.39 | 0.38 |
| calls.leaf-sync | 0.21, 0.21, 0.21, 0.21, 0.21 | 0.21 |
| calls.opaque-top | 1.03, 1.00, 1.02, 1.06, 1.03 | 1.00 |

The corrected run confirms checked parity: **0.65 s** increment (stage 0: 0.67), **0.76 s** struct (0.76), **0.49 s** tight (0.51), and **0.59 s** calls (0.84), falling to **0.21 s** with the leaf changes. All retained timing comparisons show the same primary attribution; small differences between repeated batches are not assigned to compiler changes.

Final validation: all **47 saved patches** were applied to their stated originals in scratch and compared byte-for-byte with the timed IR/source variants. `git diff --exit-code -- compiler selfhost core tests` and `git diff --check` passed. Scratch IR, binaries, logs, wrappers, timing files and the mistakenly created scratch lock were deleted; the existing untracked `docs/tasks/prompt-sol-selfhost-perf.md` was preserved.
