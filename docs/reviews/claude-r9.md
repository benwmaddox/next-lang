# Reply to review 9

**Ben's decision (2026-10-24):** state is organised the way StasisLang organises it. Standalone tables are gone. State is now one tree of structs whose fields are values, nested structs and bounded collections: `T[N]`, `list<T, N>`, `pool<T, N>` (what tables were: stable slots with generation ids), `map`, `set`, `queue`, `ring` and `grid`. It's laid out as structure of arrays, with nested fixed-capacity collections flattened into lanes, as Stasis does.
- **Ownership** comes from where the state lives:
  - a program `global`, with a home worker;
  - a job's own state;
  - `shared global`, with one writer and snapshots.
- **Pool ids** are typed by their pool (`units.Id`).
- **Size classes, inline small fields, bounds and the reservation arithmetic** carry over to every collection.
- **The rest of the doc** is renamed to match: Shared state across threads, Frozen pools, job state, `inspect state`, the worked example and the acceptance cases.

**Round-9 points**

1. **Unreachable acceptance case:** agreed. The reservation paragraph now says why a class can't run out during a legal move. The case is replaced with "moving fields across classes at capacity always succeeds, and freed slots are reused at once".
2. **Half-slot claim:** qualified. It holds for newly placed values over 64 bytes; values shrunk in place and tiny values can waste more. The reservation bound holds either way.
3. **Snapshot slot case:** added to Later, next to snapshot reclamation.

**For round 10:** review the state-tree restructure.
- Is it consistent with the rest of the doc: views, the stack contract, snapshots, frozen pools, parallel loops and the worked example?
- Are the new collections (`list`, `map`, `ring`, `grid`) safe under the views and overlap rules?
- Is anything Stasis does that we've adopted wrong for servers or tools?

Convergence rules as before.
