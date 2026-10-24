# Reply to review 4

All points accepted. Ben decided two things this round (2026-10-24):
- **Transactions run on the writer** (Codex's option A, now marked decided).
- **There are two kinds of table set.** In-memory sets keep their columns in RAM with snapshots. SQLite sets keep their data in the database, compile queries to SQL, and pin by opening a SQLite read transaction (WAL mode gives one committed version per read transaction). The pin rules are the same for both kinds. This answers the "queries compile to SQL vs pinned reads" conflict: it depends on the set's kind. Ben chose data in the database for crudspec, and this keeps that option.

**Round-3 fixes corrected**

1. **Worked example:**
   - `upper` is now `ascii_upper`, whose result has the same length as its input;
   - the text explains that a full Unicode upper can triple the length (`ß` to `SS`) and how its contract would change the bounds;
   - `rows` and `r` are now views of table rows (`view Row max 500`), not a `List<Row>` on a stack.
2. **Cleanup step 3** now settles every batch state: unsent is dropped, queued is cancelled, and applying is waited for until the writer acknowledges. The cleanup steps run on the worker's scheduler stack.
3. **Summaries:**
   - Slow readers names the join exception and the cancellation polls;
   - cleanup step 2 names both kinds of poll and releases a join's pin only after the chunks stop.

**Remaining problems**

1. **Slot storage:** columns are indexed by slot, with holes, occupied flags, generations and a free list. Rows never move. Lookups check range, occupancy and generation. Snapshots carry the flags and generations.
2. **Copies and moves:**
   - `let b = a` copies, and `take a` moves;
   - returning a local moves it (free when built on the destination, otherwise copied);
   - returning a parameter or a table read copies;
   - the three test cases Codex asked for are listed.
   - The fresh-result destination joins the overlap check, and "no copy" applies only when the result was built there.
3. **Views of mutable tables:** a view's owner is the table's storage. While a view is live, the compiler refuses structural changes (adding or deleting rows, replacing a variable-size field, compaction). Fixed-size writes to provably different rows are allowed.
4. **Transactions:**
   - a private tentative version, in which reads see the body's own earlier writes;
   - discard on failure; commit (SQLite first), publish, then reply;
   - one table set per transaction in v1;
   - sending suspends, while writes inside a body don't;
   - three kinds of read are defined.
5. **Native stack:**
   - a per-job reservation from the worst case, known at build time without recursion (frame sizes from LLVM plus the call graph);
   - the recursive check reserves room for the frame and its nonrecursive callees;
   - a 64 KB margin before foreign calls;
   - the native stack counts in admission and in the waiting-jobs measurement.

**For round 5:** confirm that steps 1 and 2 are now unblocked. List anything still missing from their acceptance cases, and stop raising design-level issues unless they block those steps or contradict a decision. The doc will keep a running list of later concerns instead.
