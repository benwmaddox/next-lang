# Review 7: `docs/DESIGN.md`

## Problems

### New Databases section and tables/databases split

1. **Database blocks have no executable suspension rule** — *Databases / Consistent reads and Writes and transactions; Threads and data stacks / Thread kinds and jobs.* The thread section says database queries and transactions may suspend (pause the job while it waits), while `db.read { }` must keep one read transaction open and contain no may-suspend call. The database section never explains how queries inside that block run without suspending, and it does not forbid a network call or nested transaction inside `db.transaction { }`. Define the whole block as one may-suspend call: its body runs on a database connection and can do SQL plus bounded synchronous checks/computation; queries inside it do not separately suspend the job. Forbid external waits and nested transactions; cancellation must close or roll back before replying.

2. **Typed query results have no usable result bound or v1 shape** — *Databases / Typed queries; Threads and data stacks / Loops can't quietly fill a stack.* Field maxima bound one row's fields, not the number returned. A query over 50 million Messages can exceed the job's stack reservation; moreover, bounding the count still does not make `List<Message>` legal when `Message.body` is `Text`, because nested growing values are deferred past v1. Require a row-count and result-byte maximum. V1 may build result lists only from fixed-size fields within those bounds; otherwise process one row at a time with bounded temporary bytes and cleanup, or copy rows into a bounded table. Defer materialized nested results until the stack model supports them; expose no partial value on overflow.

3. **Persistent keys lack a reuse rule** — *Databases / Keys, not ids.* A typed integer key can be saved in another database record or outside the program. After deleting a row, the design promises lookup returns `none` if the row is gone but never says whether the key may later name a different row. Require database-generated keys never to be reused (including after restart and migration), define exhaustion behavior, and test delete/reinsert; otherwise a retained link could silently point to a new person or order.

4. **The split still leaks into the storage story** — *One declaration, every layer; Development experience / Restart, not swap.* The `Storage` cells show SQLite checks, while plain/shared tables enforce rules on in-memory writes; the table never distinguishes those projections. Label SQL checks as database storage and add the in-memory write checks. Also show the record-row rule as source ceiling plus deployment quota and startup validation. The restart section still says “Table data in SQLite” and “a changed table’s migration”; rename these to database records/schema changes because plain and shared tables do not survive restart.

### Remaining round-6 points

1. **Shared-table capacity still omits write-time headroom** (*review 6, points 2–3*) — *Memory / Bounds and Layer 1, `shared`; Tables across threads.* The shared-set budget names live data, pinned old versions and compaction scratch, but not garbage in the current payload or space for a transaction's tentative copies of changed storage blocks (copy-on-write). A transaction can replace many fields while the old bytes and blocks remain needed, so peak memory may exceed the stated bound. Specify when shared payload compaction runs and reserve a worst-case per-transaction scratch budget; include both in `inspect` and admission, and reject an oversized batch atomically before publishing changes.

2. **Frozen builder bounds still rely on an unproved parser claim** (*review 6, point 5*) — *Threads and data stacks / Frozen tables.* “A parser can't make more nodes than its file has bytes” needs proof for the actual parser representation; nodes inserted for missing syntax or error recovery may outnumber source bytes. Also `b.builder(Node, max 2_000_000)` does not say whether that number limits rows, payload bytes, or both. Require separate row and payload maxima; derive them from input only with a parser-specific proven formula, then check the actual builder against both.

## Smaller issue

- *Effects and capabilities / Cacheable:* state that database queries load bounded, owned results before page rendering and that any pure/cached renderer takes those results as inputs; `db.read` itself is effectful and cannot be inside a cached page piece.

## Question for Ben

- **Can another process or an external tool write the same database in v1?** A: only this runtime writes it (recommended; quotas and checks run through its transactions). B: external writers are supported; then define database-enforced constraints and how concurrent changes interact with quotas and startup validation.

