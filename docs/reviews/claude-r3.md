# Reply to review 3

All points accepted; no new decisions from Ben were needed, except one I proposed and marked for Ben to confirm (transactions run on the writer).

**Round-2 fixes corrected**

1. **Loop cleanup erased the result.** An iteration now resets only its own scratch; the stacks of values that live outside the loop keep their new end. The two-value peak of `acc = merge(acc, x)` is counted in the bounds.
2. **Two output contracts.** A fresh result goes on a caller-owned destination. Append mode gives the callee exclusive grow permission on the builder (a hidden parameter, covered by the overlap check) and its remaining capacity; the callee returns the length written, and on failure the builder's end and stack top are restored. Otherwise the result is built on scratch and copied. The worked example now has its bounds: `Row.name max 60`, `line: Text max 80`, `rows max 500`, `render: Text max 40000`, which is 160,000 bytes of reservation for stack 0.
3. **Join and pins.** The caller's pin is held, structured, until every chunk has stopped; chunks use that root and don't pin. There's now a *may suspend* property inferred across calls; `db.write` and parallel joins suspend.
4. **Deadlines in counted loops.** A cancellation poll every few thousand iterations; uncancellable foreign calls are noted.

**Remaining issues**

1. **Nested growing values:** refused in v1 (first steps, step 2); the later design is a descriptor stack plus a payload stack, with frozen elements.
2. **Transactions:** the body runs on the writer against its latest version (Burin's model), can't suspend, and has a step budget. There are three kinds of reads (snapshot, transaction, `db.read`) and batch states with the failure race. Version-checked optimistic writes are deferred.
3. **Batch tokens:** `let b = batch()` comes first; builders get partitions up front; cross-file references are stored as names and resolved after freezing into a job-owned table; ids can't escape the token's scope.
4. **Job-owned tables:** scoped ids typed by a token (`cache.TypeEntry.Id`).
5. **Reclamation:** writer-only counts on tree nodes and blocks, held by roots; dropping a root frees what it alone reached. Compaction writes a new version, keeps old bytes for pinned versions, and runs on a per-batch budget in idle time.

**For round 4:** check the doc as a whole for leftover contradictions, now that three rounds have changed it, and say whether it's ready for first steps 1 and 2 or what still blocks them.
