# Reply to review 6

**Ben's decisions this round (2026-10-24):**

- **Databases are a separate feature**, not a table layer. Ben: "SQLite or other DBs should be considered separate". The `stored` layer is gone. Tables are in-memory only, plain or `shared`. A new "Databases: a separate feature" section covers:
  - a `database Chat: sqlite { record … }` declaration;
  - typed queries compiled to SQL, whose results are copied onto stacks (no views into a database);
  - typed keys, separate from table ids;
  - `db.read`/`db.write` as effects behind a capability;
  - `db.read { }` read blocks in one read transaction, with no suspending calls inside;
  - `db.transaction { }`, which for SQLite goes through one writer connection;
  - migrations from the diff.
- **A database record's row limit:** a ceiling in source plus a quota per deployment, checked at startup against existing data (your option B).

**Points**

1. **Ownership and waits:** a thread's or the program's plain table has a home worker, and only jobs on that worker use it; others need `shared`. A view of a mutable table can't be live across a may-suspend call. Both are added to the acceptance cases.
2. **Payload in bytes:**
   - the bounds are worked in bytes (`Text max 2000` is 8,000 bytes);
   - a plain table reserves twice the live byte maximum plus one block of compaction scratch;
   - compaction runs inside the write that needs room, so it can't fall behind;
   - if a view blocks it, the write fails with `Full` before changing anything;
   - `committed` includes the scratch;
   - `inspect tables` reports byte bounds, reserved and committed memory separately, plus shared old-version budgets and frozen-batch totals.
3. **Per-layer capacity:**
   - plain tables reserve up front;
   - shared sets use the live maximum plus the old-version budget plus scratch;
   - databases use a disk quota;
   - all three are in the comparison table.
4. **Stored maxima:** moved to Databases, with startup validation, a refusal to start until migrated, and sizing guidance including archiving.
5. **Frozen builders:**
   - `batch(max N)` partitions;
   - per-builder row and byte maxima, declared or derived from the input (no more nodes than file bytes);
   - batch totals in `inspect` and admission;
   - ids of each kind (table, frozen, database key) can't be used as another kind.
6. **Plain reads:** reading a plain table isn't cacheable in v1, with a test. Snapshot reads remain versioned and cacheable.

**Smaller issues:** both examples now declare row maxima; the acceptance cases cover exactly-at-maximum inserts, `Full` without change, oversized field writes, a view blocking compaction, and a view across a suspend; a row maximum is per table, with the process-wide fit handled by admission.

**For round 7:** review the Databases section and the split (do any table rules still leak into databases or the other way round, and does `One declaration, every layer` still read right with databases separate?), plus anything from your round-6 points that's still wrong.
