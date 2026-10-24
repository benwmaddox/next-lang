# Review 5: `docs/DESIGN.md`

## 1. Round-4 fixes that still need correction

1. **A returned view contradicts the reference rule** — *Memory / Copies and moves; References.* The copy rules say a function can avoid copying by returning a view, but References says references exist only as parameters and cannot be returned. For v1, remove the returned-view promise: callers can pass a read-only view into a function, which copies if it returns owned `Text`. Add returned views later only with an explicit lifetime rule.

## 2. Remaining blockers

No additional blocker for steps 1–2 or conflict with Ben’s decisions. Step 1 can start with fixed-size in-memory rows. Step 2 can start with explicit bounds and the documented fresh-result and append contracts; general refinement inference (deriving type constraints such as maximum lengths) belongs to step 3.

## 3. Readiness and acceptance cases

**Readiness:** Step 1 is ready as a fixed-field subset; the slot-indexed columns, occupied flag, generation and free list resolve the round-4 storage issue. Step 2 is ready to start after the one-line view correction above. Keep variable-size table payloads and snapshots out of step 1.

Before calling either step complete, add these cases to its acceptance criteria:

- **Step 1:** live lookup succeeds; out-of-range and stale ids return `none`; deleting and reusing a slot does not change any other id’s row; initialize a test slot near the maximum generation and verify it is retired; an id for another table type is rejected. Verify deletion never moves another row between slots.
- **Step 2 copies and moves:** `fn f(s: Text) -> Text { s }` returns equal bytes while `s` remains usable. Test returning a local after it was read, plus a forced copy from scratch (temporary workspace) to the destination and the peak memory while the old and new values coexist. For `take`, assert that the source becomes unusable, the destination inherits the source stack slot and cleanup responsibility, and the storage remains alive until the destination scope ends. Initially reject transfers that cannot preserve this no-copy rule. The local-return scratch-copy fallback is a separate case.
- **Step 2 append and bounds:** test exact output for fresh-result and append modes, including a four-byte UTF-8 character at the declared maximum. Check that capacity is enforced before a store and that a failed append leaves no partial builder result. In the `render` example, verify `str` appends to the output while `name` is live, without a second growing temporary on its stack, and check N (the total stack count) and the reported peak. Also exercise a nested call while live values occupy separated stacks; verify its consecutive group of stacks avoids those live values and N is one greater than the highest stack index used.
- **Overlapping storage and iteration cleanup:** `s = s + s` must use a safe fallback or be rejected. For `out.append(f(out))`, evaluate `f(out)` into separate, non-overlapping temporary storage and finish its read before appending to `out` begins; reject it if that ordering cannot be guaranteed. Confirm `continue` and `break` discard iteration scratch but preserve the outer builder, and a failed job resets scratch before its stack set is reused.

These checks can use explicit `Text max` and counted-loop bounds; they need not wait for step 3’s broader refinement analysis.

**Later**

- Snapshot reclamation and payload compaction, SQLite read pins and transaction staging, and native-stack admission/foreign-call margins need acceptance criteria before their respective implementation steps. None blocks steps 1–2.

## 4. Questions only Ben can answer

None.
