# Round 8: `docs/DESIGN.md`

Reviewed round-7 commit `bcfa139`; concurrent uncommitted design edits are outside this review.

## 1. Round-7 fixes to correct

- **Database cancellation and commit** — *Databases / A database block is one wait; Types / What failing a job does; Risks / Decided.* Saying cancellation rolls a transaction back conflicts with the rule that committed batches stay committed. If commit succeeds before cancellation arrives, rollback is impossible. Require the database runtime to acknowledge whether the transaction committed or aborted before cleanup; a committed transaction stays committed, as shared-table batches do.

## 2. First steps and Ben's decisions

The cancellation issue above contradicts Ben's recorded committed-batches rule. No separate blocker for first steps 1–2 found.

## Shared immutable data across threads

Frozen tables support efficient reading: freeze publishes partition arrays and payload bytes without copying; workers pin one root and read through views, while type-checker caches stay on their own job tables. The batch lives through its creating scope and until its last reader unpins it. Shared storage is paid once, plus each reader's private cache and one root pin; no copy or reference count per node. The read side is supported, but parallel parser jobs building partitions into one batch aren't specified yet; that belongs to the later builder step. A global interner (a shared map assigning one identity to each distinct value) still needs one writer or per-thread copies merged later; mutable published trees and pointers into job stacks remain off the table.

## Later

- *Memory / Bounds and Layer 1, `shared`; Tables across threads:* check projected garbage for a whole transaction (`current garbage + bytes the batch invalidates`), include compaction scratch, and reject the batch before publishing if it exceeds the budget.
- *Databases / Keys, not ids and Migrations:* preserve and restore each table's issued-key high-water mark when a migration rebuilds its table; test deleting the highest key, rebuilding, then inserting. `AUTOINCREMENT` alone does not preserve the mark when a table is dropped ([SQLite documentation](https://www.sqlite.org/autoinc.html)).
- *Frozen tables / Build and A batch is a token made first:* define the disjoint partition-builder handoff so parallel producers can share one batch.

## Questions

None.
