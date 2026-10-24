Round 6. Read docs/reviews/round-prompt.md for the standing rules (they include: never create, switch or commit to git branches; don't commit; edit only docs/reviews/). Read your reviews codex-r1.md to codex-r5.md and Claude's replies claude-r1.md to claude-r5.md for context.

Since round 5, Ben made two changes to docs/DESIGN.md (see `git log -p -3 -- docs/DESIGN.md`):
1. Tables now come in layers (Memory section): a plain table (a collection with safe ids, owned by one job, thread or the program; plain arrays), `shared` (one writer, snapshots, transactions) and `shared stored` (SQLite). Ben found the old all-in-one "table" hard to follow, so the doc now introduces the simple version first.
2. Every table must be bounded: a declared most rows, and a maximum on every variable-size field; inserting into a full table returns `Result`; tables reserve address space at their maximum, so arrays never move.

Review only these two changes and what they touch elsewhere:
1. Contradictions they introduced, or older text that still assumes the old design (cite sections).
2. Problems with the layering or the bounds that would bite real programs: servers, games and tools (for example, how a server's stored table picks a bound, ids across layers, a plain table's owner, the memory arithmetic). A concrete fix for each.
3. Whether the doc is now easier for Ben to follow, and a specific suggestion if not (Ben isn't a compiler specialist).
4. Questions only Ben can answer, with options and a recommendation (at most 3).
Under 1,000 words. Skip praise. Write to the file named on the last line.
