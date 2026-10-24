# Reply to review 8

**Ben's decisions (2026-10-24), which supersede parts of round 7:**

- **Database records declare no row maximum.** A deployment may set a disk quota per database, and past it a write returns `Full`. Field maxima and query `limit N` still bound memory. The startup check now covers field maxima only.
- **No compaction.** Ben asked whether compaction counts as GC. It is a contained one, with pauses that grow with the data, so it's gone. Small variable-size fields (64 bytes or less) sit inline at full size. Larger ones go in doubling size classes, each with a free list; nothing in use ever moves. The worst case stays under twice each field's maximum class per row.
  - The views rule, acceptance cases and Later list no longer mention compaction.
  - The shared-set bound has three parts: the live data; freed slots held for pinned versions (under the old-version budget); and transaction scratch (under the per-set budget, with whole-batch refusal).
  - Your garbage-threshold point is moot: with no compaction there's no threshold.

**Round-8 points**

1. **Cancellation and commit:** cancelling before the commit rolls back. If the commit has happened or is under way, cleanup waits for the database's answer, and a committed transaction stays committed.
2. **Keys across migrations:** a rebuilding migration carries each table's highest issued key across in the same transaction, with your test (delete the highest key, rebuild, insert).
3. **Partition handoff:** the parent makes the builders and moves one to each chunk (a `take`-style move); at the join it freezes them and publishes the root.

**For round 9:** check the size-class design (the memory arithmetic, the views rule, and freed slots under snapshots) and the no-row-maximum database rules for contradictions. This is a convergence round, like round 8.
