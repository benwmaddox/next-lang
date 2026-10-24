# Reply to review 7

The first run of this round stopped when the model hit capacity. This review comes from a rerun on the same model.

**Ben decided (2026-10-24):** only this program writes its databases in v1; other tools may read them. That's option A. Quotas, field maxima and invariants are enforced by the program's transactions, with schema CHECKs as a second line.

**New section and split**

1. **Database blocks:**
   - `db.read { }` and `db.transaction { }` are each one may-suspend call, whose body runs on a connection;
   - the queries inside don't suspend separately;
   - no outside waits or nested `db.` blocks are allowed inside;
   - cancellation closes or rolls back before cleanup continues.
2. **Query results:**
   - every query that returns rows declares `limit N`, which with the field maxima gives its byte bound;
   - v1 lists hold only fixed-size fields;
   - rows with text are processed one at a time, or copied into a bounded table;
   - no partial result on overflow.
3. **Keys:** never reused, including across restarts and migrations (SQLite `AUTOINCREMENT`); running out is `Full`; a delete-and-reinsert test.
4. **Leaks:**
   - the projection table's Storage column is now "Database (SQL)", with a row for the record ceiling and quota, and a note that tables check the same rules in memory;
   - Restart now says database records survive and plain or shared tables start empty.

**Round-6 leftovers**

1. **Shared capacity** is now the sum of four parts:
   - the live data;
   - current payload garbage, at most the live payload maximum, because the writer compacts before a write once garbage reaches it;
   - one transaction's scratch, under a per-set transaction budget (a transaction over it is refused whole);
   - the pinned-old-version budget.

   `inspect` and admission count all four.
2. **Builders:**
   - separate row and byte maxima (`b.builder(Node, rows …, bytes …)`);
   - derived from input only through a formula the parser proves (error-recovery insertions included);
   - checked against both as the builder grows.

**Smaller:** a page runs its queries first, and the cached pieces take the results as inputs; a `db.read` can never sit inside a cached piece.
