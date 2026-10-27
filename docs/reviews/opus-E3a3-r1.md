# Opus review of E3a3 (commit 6515dfd), round 1

Scope: an independent correctness review of `selfhost/regions.nl`, `selfhost/compiler.nl` and `selfhost/collections.nl` as of 6515dfd. I compared that commit against its parent and against stage 0. Both self-hosted compilers were built from `git archive` exports under `/mnt/d/tmp`, using stage 0 `--frontend=rust`. Every program ran in a matrix of:

- O1 and O3;
- the default region threshold and `--test --test-region-threshold=0`;
- with and without `NLC_TEST_STACK_FORCE_MOVE=1`;
- plus an `NLC_STACK_STATS=1` run.

Summary: **1 high, 0 medium, 1 low (performance only)**. I found no TBAA, relocation or evaluation-order miscompilation.

## HIGH-1: `break`/`continue` leaks data-stack reservations when the loop body has no slots of its own

**Where.**
- `selfhost/regions.nl:372`: `emit_region_scope_enter` returns early when `end_offset < 0`.
- `selfhost/regions.nl:467`: `emit_region_scope_exit` returns early under the same condition.
- The `break`/`continue` lowering sites restore only `loop.body`:
  - `selfhost/compiler.nl:8606` (expression `LoopExit`);
  - `selfhost/compiler.nl:9361`;
  - `selfhost/compiler.nl:9924`.

**Mechanism.**
1. A `break` or `continue` emits a scope exit for `loop.body` only. It relies on the loop body's saved top (`%nl.scope.top.<body>`) to undo every reservation made by blocks nested inside the body, such as an `if` block or a match arm. The nested blocks' own exits are not emitted on the jump path.
2. Before E3a3, the loop body always saved and restored the top, even when it had no slots.
3. Now a body with no slots of its own skips both the save and the restore. A nested block with slots raises `%nl.top.current.slot`, the jump leaves it raised, and the next iteration's nested block reserves again on top of it.
4. The top therefore ratchets up by the nested block's size on every iteration that takes the jump. It is unbounded when every enclosing loop body, up to the function, is also slot-free. Function return still restores `%nl.top`, so the leak ends at return.

The receiver exclusion in the same commit makes this more likely: it can empty a loop body whose only slot was an index-receiver temporary.

**Effect.**
- Valid programs fail with `data stack exhausted` (exit 1) where stage 0 and the parent commit succeed.
- The `NLC_STACK_STATS` peak and growth figures are inflated.
- Values are not corrupted: the leaked space sits below the live top.

**Reproducer 1: `continue` from an `if` block (t5).**

```
fn main() {
    var total = 0L
    for i in 0L..2000000L {
        if i % 2L == 0L {
            var big: list<long, 1000> = list{}
            big.push(i).unwrap()
            total += big.count() + big[0L]
            continue
        }
        total += 1L
    }
    print(total)
}
```

- Stage 0, and the parent at O1/O3 with both thresholds and forced moves: `1000001000000`, exit 0. Parent peak: `peak_used=24024 growths=0`.
- 6515dfd at O3, both thresholds, with and without `FORCE_MOVE`: `main.nl:4:25: data stack exhausted`, exit 1. Stats: `reserved=4294967296 peak_used=4294962672 growths=14`.
- With 20,000 iterations the output still matches, but the peak is 160,160,000 bytes with 10 growths, against 24,024 bytes with 0 growths on the parent. This happens at O1 and O3 alike.

**Reproducer 2: `break` from an inner loop (t6).**
- Program: `for outer in 0L..600000L { for inner in 0L..4L { if inner == 1L { var big: list<long, 1000> = list{}; ...; break } ... } }`.
- 6515dfd fails with `data stack exhausted` at the default threshold and at threshold 0.
- Stage 0 prints `180000300000`.

**Reproducer 3: `continue` from a match arm (t7).**
- Program: `for outer in 0L..600000L { match shape { Shape.Small => { var other: list<long, 1000> = list{}; ...; continue } Shape.Large => {...} } }`.
- 6515dfd fails with `data stack exhausted` at the default threshold.
- Stage 0 prints `90000300000`.
- Threshold 0 happens to pass, because `shape` then gets a slot in the loop body.

**Suggested fix** (in `regions.nl`/`compiler.nl`, at the three `loop.body` exit sites):
- **Preferred.** At a `break`/`continue`, restore from the outermost block on the path from `loop.body` down to the jump that has slots, using that block's `%nl.scope.top`.
  - Every block above it on the path is slot-free, so its saved top equals the loop body's entry top.
  - If no block on the path has slots, emit nothing.
  - This keeps the empty-scope fast path for the benchmark loops.
- **Simpler alternative.** Treat a block as empty only when no block in its subtree has planned slots.

Add these three shapes as fixtures, with an `NLC_STACK_STATS` peak assertion.

## LOW-1 (performance only): the method-receiver effect scan is always true when the method has arguments

**Where.** `selfhost/regions.nl:94` calls `region_subtree_has_effect(tables, mutator, parent)`. The scan runs from the first argument's subtree start to `parent` inclusive, and `parent` is itself a `MethodCall`.

**Effect.**
- Any `Index` receiver of a method call with at least one argument keeps its region slot, even when every argument is pure. This is conservative, so there is no correctness impact.
- The branch is only reachable for `Index` receivers of list or array type. The self-hosted compiler currently rejects these ("nested collections"), so today it is dead code.

**Fix.** Scan only the argument subtrees (stop at `parent - 1`), or iterate `child_next` from `mutator`.

## Audited with no bug found

**TBAA.**
- `emit_program_storage_tbaa` emits nothing in `core_mode`, so only user-language stores are tagged.
- In the generated IR for my test programs, every `!9003` store targets one of: `%addr`, `%local`, `%loc.pointer`, `%coll.ptr`, `%coll.push.ptr`, `%coll.literal.*`, `%coll.zero.count`, `%coll.gather.dst` or `%coll.fill.ptr`. All of these are data-stack, native-alloca or descriptor program storage.
- The context header is a separate `map` (`core/context.nl` `nl_context_create`), so no user typed store can reach it.
- Every header writer is an untagged core `sys` store, so each one still aliases the `!9002` base load. That covers `nl_context_set_top_offset` (offsets 8 and 10), `nl_stack_grow` (offsets 2-4, 7-9 and 11-13) and `note_peak` (offset 5).
- `memcpy` for sum payloads is untagged.
- Exactly one load carries `!9002`, the one in `nl_context_current_base`. The `nl_context_current_limit` load is untagged.
- The metadata IDs `!9000`-`!9004` don't collide with anything else the emitter produces.

**Receiver exclusion.**
- For `Name` and `Field` receivers, `collection_value_location` (collections.nl:911) and `emit_late_place_address` already read the live place. The `Index` emitter never used the receiver's temporary slot, so excluding it changes storage, not semantics.
- The snapshot behaviour of effectful indexes is therefore unchanged from the parent. `t2` and the `a2_evaluation` fixture match stage 0.
- The `Index`-of-`Index` branch is unreachable today because nested collections are rejected.
- If an excluded node were ever used, it would fall back to a native `%agg` alloca rather than to shared storage.

**Deferred top publication.**
- The context `top_offset` (offset 10) is read only by `nl_stack_grow` (core/stack.nl:88). That function uses it solely to recompute offset 8, which nothing reads.
- The `remap` copies the whole old reservation, so a stale published top cannot lose data.
- Callees receive the top as an explicit argument (`emit_current_top_reference`).
- The growth path still publishes before `nl_stack_grow`.
- Skipping the return publication in region-free functions is therefore inert.
- Peak accounting comes only from `nl_context_note_peak` at scope entry and the `needed_bytes` update in `nl_stack_grow`. Neither depends on the removed publications. HIGH-1 overcounts the peak; I found no undercount.

**Differential programs that matched stage 0** in every mode above (O1/O3, both thresholds, with and without forced moves):
- the `a2_relocation_write_element`, `a2_relocation_embedded` and `a2_evaluation` fixtures;
- **t2**: writes into list elements and struct-field lists through `write` parameters while later arguments grow the stack, `+=` on `big.a[n]` with a growing `write` callee, and a read argument followed by a mutating `pushg(xs)`;
- **t3**: region-holding structs built in nested loops, helper calls that allocate and ones that don't, `continue`/`break` in loops whose bodies do have slots, and printing between allocations.

Some attempted shapes could not be tested:
- Index-of-index receivers and a list of row structs that each hold a large list: the self-hosted compiler rejects both as nested collections.
- `while` loops: stage 0 has no `while`, so there is no reference output to compare against.
