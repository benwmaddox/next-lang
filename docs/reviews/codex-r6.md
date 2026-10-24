# Review 6: `docs/DESIGN.md`

## Problems

1. **Plain-table ownership does not cover suspension** — *Memory / plain table ownership and Views of tables that can change; Threads and data stacks / Jobs can wait.* A worker suspends one job and runs another. If both jobs access a thread-owned table, the second can delete a row, replace text or compact payload while the first holds a view on its suspended stacks. Bind thread/program tables to a designated worker and schedule their jobs there; require `shared` for access from other workers. End views before any may-suspend call or prevent other jobs from mutating the table until the view ends. Distinguish program-long lifetime from permission to access it. Add a suspended-view/later-mutation case.

2. **The advertised payload cap is not enforced** — *Memory / Variable-size fields and Every table is bounded; Tables across threads.* `Text max N` counts code points, so 100,000 rows × 2,000 code points permits 800,000,000 live text bytes before garbage, descriptors and row metadata. The 2× claim assumes compaction keeps pace, but shared compaction is idle-time-budgeted; writes can create garbage faster, and compaction itself needs old and fresh blocks at once. Insertion is now allowed during a view, but its payload allocation may need forbidden compaction. Define a hard byte budget and the behavior when maintenance cannot keep up: reserve compaction scratch and old-version headroom, then pause/fail a write before partial mutation. Include that scratch in `committed` game tables so play cannot touch the OS. `inspect tables` should report byte bounds, reserved address space and committed memory separately, including shared versions and frozen batches.

3. **Capacity reservation needs a layer-specific contract** — *Memory / Every table is bounded and Reserved once; Tables across threads; Layer 2, `stored`.* The plain-table section describes reserving the full maximum and keeping arrays stable. Shared tables use copy-on-write blocks; stored tables use SQLite and have no capacity-sized RAM arrays. State the plain reservation, shared block/old-version budget, and stored disk quota separately. Qualify `inspect tables` and admission so “every table” does not imply one physical-memory reservation rule.

4. **Choose what a stored maximum means for existing data** — *Layer 2, `stored`; Development experience / Restart, not swap; Open questions.* A persistent database may already exceed a newly lowered row or field maximum. The doc says changing a maximum takes a restart and migration, but does not define startup validation or the maximum's source. Treat row capacity as a finite disk quota, separate from RAM; validate existing rows at startup and require migration if rows or fields exceed new limits. Size a server's quota from records/day × retention days plus headroom; permanent history needs an archive/export or capacity-expansion plan before `Full`.

5. **Frozen builders need an aggregate bound** — *Memory / Every table is bounded; Frozen tables; Validation / parallel tool.* `b.builder(Node)` does not show whether maxima come from `Node` or builder creation, and a batch can add one partition per file. The tool plan caps files and source bytes but does not derive each builder's maximum nodes/bytes or reserve the total across partitions. Derive per-builder bounds from accepted file sizes or require maxima; cap partitions and report the batch total. Keep frozen IDs batch-scoped, with no reinterpretation as plain/shared/stored IDs; stored IDs need slot/generation state that survives restart.

6. **Plain reads have no snapshot semantics** — *Threads and data stacks / Reads, three kinds; Effects and capabilities; Memory / plain tables.* “Ordinary table reads see the job's pinned version” now overstates the rule: plain tables have no snapshot. Effects only makes versioned snapshot reads pure and cacheable. Call plain reads owner-state access and exclude them from caching, or pass an immutable/versioned view when caching is wanted. Test that updating a plain row between calls cannot reuse an old cached result.

## Smaller issues

- The opening `Message` example and worked `Row` example omit the now-required row maximum; update them to include `table Message max N` and `table Row max N`.
- Add acceptance cases for exactly-at-maximum insertion, the next insert returning `Full` without changing the table, oversized variable-field writes, and a live view that blocks compaction without invalidation or partial writes.
- State that a row maximum is a per-table limit, not a process-wide guarantee; show how limits across all plain tables and frozen batches fit the configured address and committed-memory budgets.

## Readability for Ben

The three headings and comparison table make plain, shared, and stored choices easier to scan. Capacity remains hard to follow because the plain section says “every table” and then gives a reservation rule that does not describe SQLite or shared copy-on-write storage. Scope each capacity sentence to its layer, put row/payload limits and their RAM or disk cost in the comparison table, and fix the two examples missing `max`.

## Question for Ben

- **How should a stored table’s row maximum be chosen?** **A:** use only the source-declared maximum, changing it through rebuild/restart; **B:** allow a deployment quota up to that declared ceiling, checked transactionally. **Recommend B** for servers whose disk capacity differs by deployment, with startup validation and explicit migration whenever a changed quota would reject existing data. Keep field maxima in the schema so copied values retain their build-time byte bounds.
