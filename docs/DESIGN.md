# A general-purpose language: correct, easy, efficient

Oct 23, 2026 · Ben Maddox. Working copy, refined with Codex; reviews and replies are in [reviews/](reviews/). The two diagrams are in the original shared doc: https://claude.ai/artifact/AfD3gnVW8QqwrVXomjv48H

## Goals and non-goals

One language that is hard to get wrong, quick to work in, and within about 10% of C on CPU and memory, for servers, games and tools (weighted equally). Each goal has a test, not an adjective:

- **Correct:** the compiler enforces a stated set of properties (no null, no data races, no dangling ids, exhaustive matches, refinements, effects), and the language's own tests catch most of the rest. Measured by seeded slips caught at build time, scenarios passing, and fast-versus-reference checks. No language catches every wrong program; this one aims to catch the common ones before production.
- **Easy:** a small edit is running again within 3 s, a release builds in under 30 s, and every error names the fix. Measured by edit-to-running time and the mutation harness's "did you mean" rate.
- **Efficient:** no garbage collector, no allocation in steady state, compute at 0.9x of C or better, servers within 1.2x of the optimized Rust port's memory. Measured on DEFLATE, a Campfire-class server, a game simulation and a parallel tool (see Validation).

Non-goals for the first version:

- Full dependent types or proofs of arbitrary properties (refinements stay decidable, see Types).
- Pointer graphs with arbitrary aliasing; long-lived links are typed ids.
- 32-bit and WebAssembly targets: v1 is 64-bit only (Windows, Linux, macOS, 64-bit Android), because the stack design relies on large address reservations. WebAssembly comes later with its own stack design (decided 2026-10-24).
- Replacing Burin or the other languages: Burin continues as its own web language, and this is a separate project in its own folder that borrows their ideas and code.
- A package ecosystem or governance model before the core proves itself.

## Evidence from the six languages

The design keeps what was measured to work in four weeks of building six languages, and drops what was measured not to.

| Idea | From | Evidence | Verdict |
| --- | --- | --- | --- |
| Scenarios, golden outputs, fast-versus-reference checks | crudspec, AgentLang, Burin | Scenarios caught 86% of seeded bugs; the checker's main rule alone, 9% (crudspec H1) | Keep, as language features |
| Work done before run time | Burin, AgentLang | Constant tables: CRC-32 on 64 B 683 to 75 ns (against a C version that also builds its table per call); write-time pieces: Campfire 54k to 69k pages/s | Keep |
| Facts handed to LLVM, not a home-made optimizer | Burin helpers | DEFLATE 0.70x to 0.85x of clang -O2 in Burin's measured table (dickens, one core, median of 9), 0.89x after later sign-analysis work | Keep |
| Load only what is used | Burin | Guarded list loads: +27% to +50% pages/s | Keep, generalized |
| Explicit bounded state, deterministic ticks | Stasis, Burin | Replays and live swap for free; bounded lists | Keep |
| Rules declared once, carried to every layer | crudspec | `max 80` = CHECK, maxlength, schema limit; 0.26x Rails' lines | Keep, generalized |
| Inferred effects and capabilities | Hobthrush | Shortest call path when a bound is exceeded | Keep |
| Bump memory freed in bulk | Burin, AgentLang, Goose | Zero allocations on the fast path | Keep |
| Vocabulary rules as the reliability lever | AgentLang | F# equally correct, 1.7 to 5x fewer agent exchanges | Drop |
| Interpreter as the shipped runtime | AgentLang, crudspec v1 | Both replaced by compiled code | Drop |
| A platform garbage collector | Hobthrush (.NET) | No control over memory or speed | Drop |
| Two implementation stacks | crudspec (TypeScript + Go) | Double the upkeep | Drop |
| Caches cleared on every write | crudspec | 17k to 0.6k pages/s at 50 posts/s | Drop |

## Memory: data lives in a state tree, computing lives on stacks

There are two lifetimes and no garbage collector: long-lived data in a declared tree of state, everything temporary on scope stacks freed in one store.

**Where data lives** (decided 2026-10-24: static state is meant to be used lightly). Most data shouldn't be in a global. In order of how often a program should reach for each:

| Data | Where it lives |
| --- | --- |
| What one request, task or tick computes, including its lists, sets and maps | locals on its stacks (bounded collections are ordinary values, see Collections), freed when their scope ends |
| A server's records, anything that must survive a crash or outgrow RAM | a database (see Databases) |
| Big read-only data built in parallel (syntax trees, an index) | frozen pools, freed with the scope that built them |
| Small data many jobs read while it changes (presence, counters, a live cache) | a small `shared global` |
| Configuration, and a game's world, which really does live for the whole run | a `global`, sized deliberately |

Globals are allocated in full at startup for their worst case (Static allocation, below), so every byte declared there is paid for the whole run; `inspect memory` warns when they pass a budget.

**State** holds in-memory data that outlives a call. Whether it's a global, a shared global or a local, it's organised the way StasisLang organises it (decided 2026-10-24): one tree of structs, whose fields are values, nested structs and bounded collections. There are no standalone tables; what earlier drafts called a table is a `pool`, one kind of collection. Data kept in a database (SQLite, later others) isn't state; it's a separate feature (see Databases).

```
struct App {
    cfg: Config
    world: World
}
struct World {
    units: pool<Unit, 4096>                  // stable slots with ids (units.Id)
    tiles: Tile[64 * 64]                     // a fixed array, always 4,096 tiles
    names: map<Text max 32, units.Id, 4096>  // name to unit
    events: ring<Event, 1000>                // the last 1,000 events
}
struct Unit {
    name: Text max 32
    hp: Int 0..1000
    inventory: list<Item, 8>                 // up to 8, inside each unit
}
global app: App                              // the program's state, reserved once at start
```

*Why a state tree:* with no garbage collector and no borrow checker, data that outlives a call, keeps changing and has many items needs a home. The usual answers are owned heap objects with borrow rules (Rust), reference counting (Swift), manual freeing (C) or pools of items named by ids (game engines' entity systems, Burin's and crudspec's entities, Stasis's pools). This design takes the last, and Stasis's way of organising it: one root, nested structs, every collection with a capacity in its type. So:

- **Every value's maximum size is in its type.** Declared capacities and field maxima let the compiler work out each value's bound. Program and shared globals are claimed in full at startup and never move (Static allocation); locals have fixed bounds on their job's stacks, which are reserved per entry point and committed as used, and count toward that job's admission. That's the "every table is bounded" decision (2026-10-24), now applying to all state.
- **Everything has a path.** `app.world.units[id].hp` names one value. `inspect` can read any path between steps, and a replay or a save snapshots the tree, as Stasis's `stasis inspect` and record and replay do.
- **One concept, not several.** Structs, fixed arrays and collections nest freely; a pool is just a field.

**Collections** (all bounded; the capacity is part of the type)

- **Collections are ordinary values.** A bounded collection has a fixed worst-case size (its capacity, with its text's size classes), so it can be a local, a field, a parameter (as a view, or in write or grow mode) or a result, like any fixed-size value. A local one goes on the fixed-scratch stack when it's over 4 KB (How the compiler assigns stacks), is committed only as it's used, and is freed with its scope. Pushing into a local `list` never moves a stack top: its space was set aside when it was declared, so it isn't a growing value and needs no stack of its own.

| Type | What it is | Elements named by |
| --- | --- | --- |
| `T[N]` | a fixed array: always N elements | index `0 <= i < N` |
| `list<T, N>` | up to N elements in order, with a count; push, pop, insert, remove | index, valid until the list changes shape |
| `pool<T, N>` | up to N elements in stable slots (what tables were) | a typed id with a generation |
| `map<K, V, N>`, `set<K, N>` | up to N keys, hashed | the key |
| `queue<T, N>`, `ring<T, N>` | first in, first out; a ring overwrites its oldest | position |
| `grid<T, W, H>` | a W × H fixed array with 2-D indexing | `(x, y)` |

Adding to a full collection (or writing a field past its maximum) returns `Result`, which the code must handle, unless the compiler proves it can't happen there (a loop pushing at most 500 items into a fresh `list<T, 500>`, say). A failed write leaves the collection unchanged. A ring is the exception: it overwrites, by definition.

**Layout: structure of arrays, as Stasis lowers it**

- A collection of structs is stored as one array per field, so a loop that reads two fields streams through just those two arrays. `app.world.units[id].hp` reads the array `World_units_hp` at the id's slot.
- **Nested fixed-capacity collections flatten:** each unit's `inventory: list<Item, 8>` becomes arrays of 4,096 × 8 items plus one count per unit, as Stasis flattens nested fixed arrays. So a collection inside a collection needs no pointers and no growing values; it's just more lanes.
- **Fixed-size fields** (numbers, ids, enums, small records) sit in their array directly.
- **Variable-size fields** (text, bytes) can't sit in a fixed-width array, and nothing that stores them ever moves bytes that are in use: there's no compaction, which would be a contained garbage collector, with pauses that grow with the data (decided 2026-10-24). Instead:
  - *Small fields inline:* a field whose maximum is 64 bytes or less (`Text max 16` is up to 64 bytes) sits in its array at full size, with its length. No garbage, ever.
  - *Larger fields in size classes:* the field's bytes go in a slot of the smallest class that fits: 128 bytes, 256, 512 and so on up to the class that holds the field's maximum. Each class is an array of equal slots with its own free list, as a memory allocator keeps. The field holds `{class, slot, length}`. A new value that fits the current slot is written in place; one that needs another class takes a slot from that class's free list and returns the old slot to its own. Nothing else moves, and no write ever waits for a cleanup.
  - The cost is the space left unused inside slots. A value newly placed in a class uses more than half its slot (for values over 64 bytes), but a value shrunk in place can use less (a 300-byte text cut to 100 bytes in a 512-byte slot), and a 1-byte value in a 128-byte slot wastes almost all of it. The reservation bound below holds either way.

**Pools and their ids**

- **Typed ids:** a pool's elements are named by ids, 64 bits: a 32-bit slot and a 32-bit generation counter. The id's type names its pool (`units.Id`, written `Id<app.world.units>` where that's ambiguous), so an id from one pool can't be used with another, even of the same element type. Removing an element bumps its slot's generation, so an old id no longer matches. Looking up an id returns `Option`: `none` for a stale id, never a dangling pointer. A slot whose generation reaches its maximum is retired, never reused, so wraparound can't make a stale id match again.
- **A slot is a fixed position, never moved:** a pool's arrays are indexed by slot, with holes where elements were removed. Each slot has an occupied flag and its generation, and the pool keeps a list of free slots for reuse. A lookup checks the slot is in range, occupied, and of the id's generation before reading any field. Elements are never moved to fill holes (moving the last one into a removed one's place would silently change which element an id names; Stasis's plain `pool` does that swap, and its `stable_pool` doesn't). Flags and generations are arrays like any other, so snapshots carry them.
- A pool nested inside an array of structs (a pool per world in `worlds: World[4]`) would need its ids to carry the outer index; that's left for later. Frozen pools and database rows have ids of their own (see Frozen pools, Databases), and no id of one kind can be used as another.
- Invariants are declared on state and checked on every write (see Correctness).

**Who owns state**

- **The program:** `global app: App` is reserved once at start and lives for the whole run. A global has a *home worker*, and only jobs scheduled on that worker may use it, so its arrays are plain memory: no writer, no snapshots, no counting, no locks. A game's simulation is the typical case.
- **A function or a job: locals.** A struct or collection declared as a local (`let seen: set<units.Id, 500>`) lives on that function's stacks and is freed when its scope ends; one declared in a job's entry function lasts the whole job, which is all "job state" is (a type checker's cache, a request's working set). A local pool's ids are typed by the local (`seen.Id`, `cache.types.Id`), so they can't leave its scope or mix with another's. Locals aren't part of the startup claim: a local collection is a fixed-size value on the job's stacks (on the fixed-scratch stack when it's over 4 KB), so it counts toward that job's stack reservation and admission, and `inspect stacks` reports it. Returning or copying a local collection copies its contents to the destination (or builds it there), so it stays valid after the source scope ends.
- **Shared:** `shared global chat: Chat` is for data many jobs on many workers read while it keeps changing: a server's live data, a multiplayer game's world. One writer changes it; jobs send it changes and `transaction { }` blocks (Thread kinds and jobs), and readers on other workers read an immutable snapshot, pinned once per read phase, never per element (Burin's model; details in Shared state across threads). Everything about snapshots, pins, blocks, reclamation and transactions applies only to shared state; the other kinds pay none of it.
- Several instances of one shared global (one per tenant, say) would need an instance field in its ids, and are left for later.

**Bounds**

- **Declared:** every collection has a capacity and every variable-size field a maximum; a missing one is a build error that names it. How all state together fits the process's memory is the admission budget's job.
- **In bytes:** `Text` maxima count code points, and a code point takes up to 4 bytes in UTF-8, so `body: Text max 2000` is up to 8,000 bytes: 100,000 messages can hold 800,000,000 live bytes of text. `Ascii` maxima count bytes, one per character, so `code: Ascii max 2000` is 2,000 bytes; fields known to be ASCII (codes, slugs, hex, identifiers, many names in games) should use it. The compiler works in bytes from here on.
- **Reservation:** for each collection, capacity × fixed fields (with flags, generations, counts and inline fields), plus, for each variable-size field, every size class reserved for every element: the classes double, so their sizes add up to less than twice the largest, and a field's worst case is under capacity × 2 × its largest class. That holds however lengths shift between classes over time. A class can't run out while a legal write needs a slot in it: an element moving into a class came from another one, so at most capacity − 1 others are in it. How this memory is claimed is in Static allocation, below; either way a collection's arrays never move and growing never copies.
- **Shared state's bound** is laid out the same way, plus slots and blocks freed but still visible to a pinned old version (returned to their free lists only when no pinned version can see them, capped by the budget for old versions) and one transaction's scratch, the blocks it copies and the new slots it fills (capped by a per-global transaction budget, so a transaction whose whole batch would pass it is refused before anything is published). It lives in RAM and is lost on a crash unless the program saves it (or keeps the data in a database instead).

**Static allocation** (decided 2026-10-24)

- **Globals are allocated in full at startup.** The program's state (every `global` and `shared global`, with all their collections, size classes, flags and generations, and a shared global's budgets for old versions and transaction scratch) is sized by the compiler and claimed from the operating system in one piece when the program starts: reserved and committed. After startup the state never allocates and never grows its claim; a full collection is a `Result`, never an allocation failure. How firmly the operating system backs that claim depends on the platform, so the runtime checks at startup and refuses to start rather than rely on a promise the system may not keep:
  - *Windows:* committing charges the memory against RAM plus the page file, so a successful commit is a guarantee that the memory will be there.
  - *Linux:* committing is only a guarantee in strict overcommit mode (`vm.overcommit_memory = 2`); in the default mode the kernel can promise more than it has and kill a process later. And in a container, the kernel's per-group limit (cgroup `memory.max`, plus its swap limit) is separate again: a mapping can succeed and the group still be unable to pay for the pages, so the process is killed when they're first used. So at startup the runtime reads the overcommit mode and the effective cgroup limits, requires the state's claim plus the configured job headroom to fit them, and touches the state's pages before scheduling any job, which charges them to the group; outside strict mode, or if anything doesn't fit, it locks the state in RAM (`locked`, below) or refuses to start, by configuration. The guarantee holds while those limits stay as they were at startup; the operating system killing the process for other reasons is outside it. macOS and Android need their own policies, left for later. As in Stasis, the layout is known at compile time and `inspect state` prints it.
- **Touching is separate from claiming:** committed pages still cost physical RAM only when first written. `prefault` touches all of the state at startup, which moves first-touch page faults to startup, but the operating system can still page memory out later. A game that must never take a page fault on its state asks for `locked` too (`global app: App prefault locked`): the pages are locked in RAM (`VirtualLock` on Windows, `mlock` on Linux), and if the lock fails the program refuses to start. `inspect memory` reports the state claim and what is locked separately. Job stacks are never locked; they're committed as used.
- **Initialised before use** (decided 2026-10-24). Every field gets its starting value in one of two ways, for globals and locals alike:
  - *A default in the struct definition:* `struct Unit { hp: Int 0..1000 = 100, … }`, as Stasis allows. Every value of that struct starts there unless told otherwise.
  - *Values given when the variable is initialised:* `global app: App = App { cfg: Config { level: 3 } }`, or `let seen = set<units.Id, 500> {}`. Given values override the struct's defaults; fields not mentioned keep them.

  `list`, `pool`, `map`, `set`, `queue` and `ring` start empty unless the initialiser fills them; fixed arrays (`T[N]`, `grid`) need every element's value, from the element type's defaults or a fill (`Tile[64 * 64] = fill(Tile.grass)`). A global's initialiser is evaluated at compile time when it depends only on constants, so the starting state is data in the binary; otherwise it runs once at startup, before the first job is scheduled, and may read configuration but do no other I/O. A field whose type has no valid zero (an `Int 1..100`) and gets no default and no initial value is a build error that names it. The value is built unpublished: an initialiser can't read a field of the value it's building (`App { a: 1, b: a + 1 }` is a build error; compute it first with a `let`), each field's refinement is checked as it's given, and rules relating fields (`invariant start <= end`) are checked once on the completed value, before it's usable. For a global that's at startup, before any job is scheduled; for a local (`let s = Span { start: 10, end: 20 }`) it's at its declaration, inside the running job, and a completed value that fails fails the job without anyone seeing it partly made. Defaults and state restored from a save get the same completed-value check, so a program never runs with invalid state; once a value is usable, the every-write invariant rule applies as usual.
- **Stacks are not static.** Data stacks, native stacks, job state and frozen batches belong to jobs, and jobs come and go, so they're reserved as address ranges and committed as they're used, within their bounds (N stacks per job, Loops can't quietly fill a stack). Admission limits how many jobs exist at once. The difference: a global's worst case is paid once, for the whole run; a job's worst case would be paid per job, and most jobs use a fraction of it.
- **Foreign code** keeps its own allocation unless configured: SQLite can be handed a fixed memory region at startup (its `SQLITE_CONFIG_HEAP` option, which needs SQLite built with one of its fixed-heap allocators, `MEMSYS3` or `MEMSYS5`), and the binding generator does so and checks that the configuration call succeeded before starting. Other C libraries' allocation is outside the guarantee, and the audit report lists them.
- **Reported:** `inspect memory` prints the startup claim (state, shared budgets, foreign fixed regions) and, separately, the per-job worst case for each entry point. It warns when the globals' startup claim passes a configured budget (64 MB by default), so heavy static use is a visible choice, not an accident; a game that wants a big world raises the budget in its configuration.
- **Reported:** `inspect state` lists, per path, the byte bound, the reserved address space and the committed memory, separately; for shared state also the budget for old versions, and for frozen batches their totals.
- **Globals aren't on the data stacks:** a global's or shared global's memory comes from the startup claim (locals are on their job's stacks, as above). A job uses a stack only when it copies something out of state; reading through a view copies nothing.

| | Program global | Locals (and job state) | `shared global` | Database (separate feature) |
| --- | --- | --- | --- | --- |
| Lives in | RAM | RAM | RAM | the database (disk) |
| Who changes it | jobs on its home worker | the function or job that owns it | one writer | the database, through transactions |
| Who reads it | jobs on its home worker | its job | any job, through a snapshot | any job, through queries |
| Bound | capacities and field maxima, allocated in full at startup | the same, reserved when the job makes it, committed as used | the same, plus old versions | disk, plus an optional quota per deployment |
| Survives a crash | no (unless saved) | no | no (unless saved) | yes |
| Extra cost | none | none | snapshots, pins | a query per read |
| Typical use | a game simulation, a tool's index | a cache, a request's working set | a server's live data, a shared game world | a server's records |

**Stacks** hold temporaries.

- Each job (a request, a tick, a task) runs on N data stacks, each a large reserved address range with a bump pointer. N is computed by the compiler.
- At most one growing value per stack, always on top of it (Goose's rule). The compiler picks each growing value's stack (see How the compiler assigns stacks). So growth is a pointer moving up, nothing moves, and positions stay valid.
- Fixed-size values sit in registers or the native stack; small arrays too (up to 4 KB, as Burin's helpers do).
- A scope's memory is freed by setting its stacks back: one store each. Kept pages stay mapped for the next job (time over memory).
- **Growth is bounded by design** (see Loops can't quietly fill a stack): every value a loop keeps growing has a maximum the compiler knows, so most entry points have a worst-case stack size computed at build time.
- **Growing past a stack's reservation fails the job** (decided 2026-10-24), which bounded growth makes rare: the request, tick or task ends with an error and goes through the job-failure steps (see Types, Failures). The program keeps running. Code doesn't handle a `Result` on every push; the check is one predictable compare.

**References** exist only as parameters: a function may read, write or grow what it is handed, but cannot store or return a reference. So no lifetime annotations are needed, and Goose's "roots" check reduces to a call-graph rule.

**No overlapping arguments:** a call may not pass two arguments whose memory could overlap when either is written or grown. The check works on what each argument is part of (its owner: a local, a parameter, a row) and the fields or index ranges it covers, not on how the expressions look: passing a record for reading and one of its own fields for writing is refused, while two different fields of one record, or `a[0..n]` and `a[n..m]`, are allowed because they're provably apart. Where the compiler can't prove two arguments apart it refuses the call and says so. That proof, and only that proof, is what lets it give LLVM `noalias` (a promise that two pointers never refer to the same memory).

**Copies and moves of growing values:**

- `let b = a` copies `a`'s bytes; both stay usable. `let b = take a` moves it instead: no copy, and `a` can't be used after. Passing a growing value to a read parameter neither copies nor moves.
- Returning a local moves it. When the local was built on the caller's destination (the usual case, which the compiler arranges when it can prove it safe) the move costs nothing; otherwise the result is copied from scratch onto the destination, and the bounds count both while the copy runs.
- Returning a read-only parameter, or anything read from state, copies it, since the function doesn't own those bytes. Views can be passed in but, like any reference, not returned in v1; returning a view would need a lifetime rule, which is left for later.
- Three cases the first implementation tests: `fn f(s: Text) -> Text { s }` copies; `fn f() -> Text { let t = build(); t }` builds `t` on the destination, no copy; and `acc = merge(acc, x)` in a loop copies down over `acc` (Loops can't quietly fill a stack).

Between the two: a value moves from a stack into state by copy (`app.world.units.add(Unit { … })`), and from state onto a stack by reading fields. Reading a large field needn't copy: a function can take a read-only view of it (see Frozen pools). Database rows have no views: a query's result is copied onto the stack (see Databases).

**Views of state that can change:** a snapshot's or a frozen pool's storage never changes, so views of them are safe for the whole read phase. Program state, job state and builders are mutable. Adding an element can't move a collection's arrays (they're reserved at its capacity), but removing an element or replacing a text field can invalidate what a view points at, and so can any change that shifts a `list`'s elements (an insert or remove in the middle). So a view's owner is the collection's storage, not the element, and while any view of a mutable collection is live, the compiler refuses the changes that can invalidate it: removing elements (which frees their slots), shifting a list, and replacing a variable-size field (which writes over its slot or frees it). Adding elements to a pool, or pushing onto the end of a list, is allowed. Writing a fixed-size field of a different element is allowed, because the overlap check proves it apart. The view must end first. And a view of mutable state can't be live across a call that may suspend: while a job waits, another job on the same worker may change it (a global is used by every job on its home worker). The compiler refuses such a view and names the call.

*(Diagram in the shared Claude Doc: memory model · tables (now state), snapshot, per-thread stacks.)*

The writer changes shared state and publishes snapshots that readers share; every job computes on its own stacks, freed in bulk.

## Databases: a separate feature

Data that must survive a crash, or that is bigger than RAM, lives in a database, not in state (decided 2026-10-24). A database is a separate feature with its own rules, sharing only declarations with the rest of the language: the same records, refinements and permissions. SQLite comes first; Postgres and others can follow behind the same declarations.

```
database Chat: sqlite {
    record Room { name: Text max 80 }
    record Message { room: Room.Key, author: User.Key, body: Text max 2000 }
}
```

- **The only writer** (decided 2026-10-24): in v1 the program is the database's only writer. Quotas, field maxima and invariants are enforced by its own transactions, plus CHECK constraints in the schema as a second line. Other tools may read the database, but not write it.
- **Typed queries:** reads and writes are written in the language and compile to SQL against the declared schema, as crudspec's do, with typed results (no rows of untyped values). There are no views into a database; results are copied onto the job's stacks.
- **Query results are bounded:** field maxima bound one row, not how many come back, so every query that returns rows declares its most rows (`limit 50`), which, with the field maxima, gives its result's bound in bytes. A query without one is a build error. A query with `limit N` may produce a bounded `list<Row, N>` when every variable-size field in `Row` has a declared maximum (as database fields must): its capacity and field maxima give the result's byte bound, and it may hold bounded `Text`, `Ascii` or `Bytes`. Rows may also be processed one at a time (`for m in query { … }`), each row's bytes a temporary freed when its iteration ends, which avoids holding all of them at once. Only a container whose elements grow without their own bounds is a nested growing value, refused in v1. If a result would pass its bound it's an error, and no partial result is visible.
- **Keys, not ids:** a database row is named by a typed key (`Message.Key`, the row's integer primary key). Keys aren't pool ids and can't be mixed with them; looking up a key returns `Option`, `none` if the row is gone. Keys are never reused, including after a restart or a migration, so a key saved elsewhere can't come to name a different row. SQLite's `AUTOINCREMENT` keeps the highest key issued, but forgets it if a migration drops and rebuilds the table, so a migration that rebuilds a table carries each table's highest issued key across, in the same transaction, before any insert (a test deletes the highest key, rebuilds, inserts, and checks the new key is higher). Running out of keys (2^63) is a `Full` error. A test deletes and reinserts and checks the new row gets a new key.
- **Effects:** database access is an effect (`db.read`, `db.write`) granted by a capability, so only code handed the database can reach it, and a function that queries isn't cacheable. A page loads its query results first; the cached, pure pieces that render them take the results as inputs and never query (see Effects and capabilities).
- **A database block is one wait:** `db.read { … }` and `db.transaction { … }` are each one may-suspend call. The job waits once while the block's body runs on a database connection, and the queries inside the block don't suspend separately. The body may run queries and bounded computing, nothing that waits: no outside I/O, no sleeps, no nested `db.` blocks, which the compiler refuses. Cancelling a job inside a block closes its read transaction. For a transaction, cancellation before the commit rolls it back; if the commit has already happened or is under way, cleanup waits for the database to say whether it committed, and a committed transaction stays committed, as shared-state batches do. Either way the job's cleanup goes on only after that answer.
- **Consistent reads:** `db.read { … }` runs its queries in one read transaction, so they all see one committed version (SQLite's WAL mode gives this). Since its body can't wait on anything else, it never holds a version open across an outside wait.
- **Writes and transactions:** `db.transaction { … }` runs its checks and writes as one database transaction, all or nothing. For SQLite the runtime sends every write transaction through one writer connection, in order, so two jobs can't both sell the last item (the same reasoning as for shared state). Postgres would use its own serializable transactions with a retry.
- **Bounds** (decided 2026-10-24): records declare no row count; a database grows with its disk. Field maxima stay in the schema, so a value copied out keeps its build-time byte bound, and queries keep `limit N`, so memory stays bounded however many rows there are. A deployment may set a disk quota for a database in configuration; past it, a write returns `Full` inside its transaction instead of failing with the database's own "disk full" error. At startup the runtime checks existing data against the field maxima; if a change lowered one below what's stored, the program refuses to start until a migration fixes the data. Data kept forever needs an archive or export plan; `inspect databases` warns when a database without a quota grows fast.
- **Migrations:** a change to a database's declarations is planned from the diff (crudspec's approach) and runs at start (Development experience).
- **Reported:** `inspect databases` lists each database's quota, if any, its current size and the rows per record.

## Threads and data stacks

A fixed set of threads, one per core. Each job owns N data stacks that only it touches while it runs. So the common operations (push, free a scope, read state) take no locks and no atomic operations (the special CPU instructions threads use to update shared memory safely, each costing far more than an ordinary store), and nothing mutable is shared.

### Thread kinds and jobs

- **Workers,** one per core, pinned. Each runs jobs: requests, tasks or game ticks.
- **Jobs can wait** (decided 2026-10-24). A job that waits for I/O (a call to another service, a slow file, a timer) is suspended and the worker runs other jobs meanwhile; when the I/O completes, the job resumes on the same worker where it stopped. Code reads straight-line, with no `async` in source (Go's goroutines work this way). A suspended job keeps its own native stack and its own N data stacks; that's what makes resuming possible.
  - Only some calls can suspend, and the compiler knows which: every function has a *may suspend* property, inferred across calls like an effect. The calls that suspend directly are I/O (`net`, `fs`), `clock` sleeps, `spawn` joins, a parallel loop's join, and sending a change to a shared set's writer (it waits for the reply), and database queries and transactions. Before a call that may suspend, a function writes its cached stack tops back to memory, as it does before any call that can reach those stacks.
  - Each worker keeps a pool of free stack sets, so starting a job takes one from the pool, not a system call. The pool is sized by load, and a set's touched pages stay mapped when it goes back (time over memory).
  - A job doesn't move between workers in v1. That keeps every stack single-threaded, with no locks.
  - **A snapshot pin never spans a wait,** with one exception below. Before a call that can suspend, the job's views of the snapshot must have ended (the compiler refuses a view live across such a call) and the runtime releases its pin. After the wait the job pins the then-current snapshot, so what follows is a new read phase that may see newer data. A waiting job therefore never holds old versions of shared state alive, and can't stall the writer.
  - **The exception, a parallel loop's join:** the chunks read the snapshot the caller had pinned, so the caller's pin is held, structured, until every chunk has stopped. Chunks use that root, never a newer one, and don't pin on their own. That retention counts against the slow-reader budget like any pin, and it's bounded by the loop's time limit.
  - **Time limits are enforced on waiting jobs too:** a job past its deadline is cancelled by the runtime, whether running or suspended (its pending I/O is cancelled), and goes through the job-failure steps. A running job notices at its next cancellation poll: loops that keep a step budget check it there, and loops that provably end (and so drop the budget) still poll a cancellation flag in the job's context every few thousand iterations, one load and compare. A foreign call that doesn't return can delay this; the deadline is enforced when it does.
  - **Admission:** a worker starts a new job only while committed memory and reserved address space stay under the configured limits; past them, a request gets a "busy, retry" response (HTTP 503 with `Retry-After` for servers) and other jobs wait in a bounded queue.
- **The writer,** one per shared global. It applies change batches in order and publishes snapshots (Burin's model). Workers send it change requests on a queue and wait (suspended) for the reply.
- **Transactions** (decided 2026-10-24): each change request is one batch, applied all or nothing. Changes that must succeed together go in one `transaction { … }`, which is sent as a single batch. Once the writer has committed a batch it stays committed: a job that fails later doesn't undo it, just as an email it sent can't be unsent.
- **A transaction decides on the writer** (decided 2026-10-24; this is for shared state, and databases have their own transactions, see Databases). If two jobs read the same snapshot showing one item in stock and each sends "set stock to zero, record a sale", both sales succeed. So a transaction's body, its checks as well as its writes, runs on the writer against the writer's latest version, as Burin's actions do. Inside it, reads see that latest version, not the job's snapshot. A transaction body can't suspend (no I/O, no waits) and has a step budget, so it can't stall the writer. Values the job computed earlier go in as arguments. The alternative, version-checked writes that reject a decision made on stale data and make the job retry, is left for later if writer time becomes the bottleneck.
- **Inside a transaction:** the writer builds the batch as a private tentative version. Reads in the body see the latest published version plus the body's own earlier writes. If a check fails or the body fails, the tentative version is discarded and nothing was changed; on success the writer publishes it, then replies to the job. In v1 a transaction touches one shared global.
- **Sending vs writing:** a job sending a change or a transaction to the writer suspends until the reply (a may-suspend call). Writes inside a transaction body run on the writer itself and never suspend.
- **Reads, two kinds:** ordinary reads of a shared set see the job's pinned snapshot; reads inside a transaction see the writer's tentative version. (Program and job state are read directly by their owner; databases are read through queries, see Databases.)
- **Batch states:** queued, applying, then committed or aborted. If the sending job fails while its batch is queued, the batch is cancelled; if it's being applied, the writer finishes or aborts it and acknowledges before the job's cleanup frees the buffers the batch was sent from.
- **Parallel loops** borrow the workers (fork and join) rather than starting threads.
- The thread count is fixed at start (configured; the number of cores by default).

### N stacks per job

- N is computed at build time per entry point (a request handler, a job, a tick, a parallel loop's body): the highest stack index any call chain from it can use, counting each function's window, the destinations of returned values and the fixed-scratch stack. Counting only how many growing values are live at once isn't enough, since windows are consecutive and can leave gaps.
- Each stack is a reserved address range with a guard page (an unmapped page that traps if touched) at its end. Pages are committed on first touch and kept between jobs (time over memory). They're given back only when a stack's high-water mark stays far above its use, or on request.
- **Reservations are sized per entry point, per stack.** Because growth is bounded (Loops can't quietly fill a stack), the compiler computes each stack's worst case for an entry point and reserves that, rounded up to a page. Only an entry point with an unbounded source left (see that section) gets the default reservation, 64 MB per stack, configurable.
- **Address space and memory, worked out:** a process can address 128 TiB on 64-bit Windows and Linux. A request handler whose stacks are bounded at 1 MB each, with N = 8, reserves 8 MB per job: 100,000 waiting jobs reserve 0.8 TB. With the 64 MB default instead, 100,000 jobs would reserve 51 TB, so admission control (Thread kinds and jobs) caps how many jobs with default reservations may exist at once. Committed memory is separate: a waiting job that touched one 4 KiB page on each of 8 stacks holds 32 KiB plus its native stack, so 10,000 such jobs hold over 312 MiB before their native stacks. These are estimates; the server validation measures them.

### How the compiler assigns stacks

The compiler gives every function a **stack contract**, computed from its body and its callees, the way a type is:

- **Window:** how many consecutive stacks the function needs for its own growing locals and its callees', `k`. A caller passes the index of the first free stack, the *base*; the callee's own scratch uses stacks base to base + k − 1.
- **Inputs:** each reference parameter's mode, read, write or grow. A growing parameter is a value at the top of one of the caller's stacks, below base; the callee grows it in place. That named stack is the one exception to "nothing below base": the callee may grow it and may not touch any other stack below base.
- **Output, two contracts:**
  - *Fresh result:* a function that returns a growing value builds it on a destination stack the caller names. The destination belongs to the caller: it's below the callee's base, it takes part in the overlap check like a parameter, and the caller keeps it out of scratch assignment for as long as the result is live. A result built there is returned with no copy; one the function couldn't build there (see Copies and moves) is copied onto it.
  - *Append:* when a call's result goes straight into a builder (`out.append(line(r))`, where `out` is a growing value used as a builder), the compiler calls the function in append mode. It gets exclusive permission to append to that builder (a hidden grow parameter, so the overlap check covers it like any other) and the builder's remaining capacity. It writes its result just past the builder's end and returns the length written, not a second value. On success the caller moves the builder's end over those bytes; on failure the builder's end and its stack top go back to where they were. If the function can't be compiled in append mode (it reads the builder, say), the result is built on a scratch stack and copied.
- **Assignment:** inside a function, each growing local takes the lowest stack in its window that's free at that point, and gives it back at its scope's end (Goose's recipe). Two live growing values never share a stack, so neither is ever trapped under the other.
- **A worked example.** `render(rows)` returns a `Text` and calls `line(r)`, which also returns a `Text`. The bounds are part of the example, since the loop rule needs them:

  ```
  struct Row { name: Ascii max 60, count: Int 0..999999 }
  shared global report: Report       // struct Report { rows: pool<Row, 10000> }

  // rows: a read-only view of up to 500 rows of report.rows in the job's
  // snapshot; a bounded list<Row, 500> copied onto a stack would also be
  // legal, but the view avoids copying the rows
  fn render(rows: view Row max 500) -> Ascii max 40000 {  // a fresh result, on the caller's destination D
      var out = Ascii.empty()          // out is the result, built on D directly
      for r in rows {                  // r: a view of one row
          out.append(line(r))          // line runs in append mode: it writes onto out's end, on D
      }
      return out
  }
  fn line(r: view Row) -> Ascii max 80 {  // 60 + 2 for ": " + up to 6 digits = 68, within 80
      let name = ascii_upper(r.name)      // a temporary Ascii on base + 0, the same length as r.name
      return name + ": " + str(r.count)
  }
  ```

  A request handler with its first free stack at 0 calls `render` with destination 0 and base 1. `render` calls `line` in append mode on `out`, with base 1, so `ascii_upper`'s temporary goes on stack 1 and `line`'s output is written past `out`'s end on stack 0. When `line` returns, `render` moves `out`'s end over the new bytes, and stack 1 goes back to where the iteration started: one store. This entry point uses stacks 0 and 1, so N = 2, as long as `ascii_upper` and `str` use only stack 1 for scratch and write their results where they're told (their contracts say so).

  The bounds add up, and each helper's result bound is part of its contract. `ascii_upper` changes only the letters a to z, so its result has exactly its input's length, and `": "` and `str`'s digits are ASCII too, so `line`'s result is `Ascii`. 500 rows × at most 80 bytes is 40,000 bytes, `render`'s declared maximum, so stack 0 needs 40,000 bytes plus page rounding, and stack 1 needs `ascii_upper`'s result, at most 60 bytes.

  The same example with `name: Text max 60` shows what `Ascii` saves. Text maxima count code points of up to 4 bytes, so stack 0 would need 160,000 bytes. And a full Unicode `upper` can lengthen text (`ß` becomes `SS`, so 60 of them become 120); its contract says so (at most 3 times the input's code points), which would make `line` need `Text max 200` and stack 0 need 400,000 bytes.
- **Passing the base:** a hidden argument by default. A function is also compiled for a constant base (its stack addresses fixed offsets from the context pointer) only when it's small or hot and called with that base; at most two copies of any function, and the compiler reports code-size growth from copies.
- **Recursion** (opt-in, on functions marked `recursive`, decided 2026-10-24): a recursive cycle may not hold a growing value across its recursive call, since that would need a stack per call; the compiler refuses it and names the value. Every recursive call checks the native stack against a byte budget (one compare, like the data stacks); passing it fails the job. That bounds bytes, not just depth.
- **The native stack** (the ordinary call stack that holds return addresses, locals and small arrays): each job has its own, reserved from its entry point's worst case. Without recursion that worst case is known at build time, because every function's frame size is (LLVM reports it) and the deepest call chain is in the call graph. With recursion it's that plus the recursion budget. Before a recursive call the check reserves room for the call's frame and everything it can call without recursing; before a foreign call it checks for a fixed margin (64 KB by default, configurable per binding), since C's use is unknown. The native reservation and its touched pages count in admission and in the waiting-jobs measurement.
- Fixed values over 4 KB go on the fixed-scratch stack, never on top of a growing one.

### Loops can't quietly fill a stack

A bump stack frees nothing until its scope ends, so a careless loop can fill one: a temporary per iteration that piles up, rebuilding an outer value (`s = s + piece`) so each old copy is trapped under the new one (memory that grows with the square of the size), or appending to an outer value with no limit. The language rules out all three (decided 2026-10-24):

- **Every iteration is a scope.** Temporaries made in a loop body are freed when the iteration ends, including on `continue` and `break`. Only the iteration's own scratch goes back: the stacks of values that live outside the loop (`out` in the worked example) keep the end they've grown to, and every other stack's top returns to where the iteration started, which costs a register move each. Nothing made in an iteration survives it unless it's written into a value that lives outside the loop.
- **Results go straight to where they're kept.** `out.append(f(x))` runs `f` in append mode (see the append contract in How the compiler assigns stacks), so keeping a result costs no copy and leaves no temporary to collapse.
- **Rebuilding an outer value never traps the old one.** `s = s + piece` compiles to an append in place. Any other reassignment of an outer growing value (`acc = merge(acc, x)`) builds the new value on a scratch stack and copies it down over the old one. The memory stays bounded by two values, the old and the new, during the copy, never by the sum of all iterations; the compiler counts that two-value peak in the bounds and reports the copy in `inspect stacks`, since it costs time per iteration.
- **A value a loop keeps growing must have a bound.** Either its type says so (`list<Hit, 10000>`, `Bytes max 1 MB`, `Text max 4000`), or the loop is counted over a bounded input and each iteration's growth is bounded (`for r in rows` with `rows: view Row max 500`, appending a `line(r): Text max 80` each time, is 500 × 80 code points). The bound is on what each iteration adds, so a helper that formats a piece declares its own result's maximum, separators included. Without either, it's a build error that names the value and the loop, and offers both fixes. At run time, an append past a declared maximum returns a `Result` the code must handle (`out.try_append(x)`), or is proved impossible.
- **Bounds come from where data enters.** Request bodies, files, and state and database fields have declared maxima (`Text max N`, `Bytes max N` on the input or field; state's and databases' are required), so a bound found at the edge carries through the code.
- **The compiler adds it up.** From the bounds it computes each stack's worst case per entry point, which sizes reservations (N stacks per job). `inspect stacks` lists, per entry point, each stack's worst case and the lines that drive it, and every loop's growth per iteration. An entry point with something still unbounded (an untyped external call, say) is listed as such and gets the default reservation.
- **Tests can pin it:** `expect stack_peak(handler) < 2 MB` fails a test when a change raises the worst case past a budget.
- **Tools that read whole projects** bound their inputs too: a source tool declares the most files and bytes per batch it accepts, and a budget for the trees it keeps, rather than relying on the default reservation and failing.
- **Nested growing values wait:** in v1 a growing value can't contain growing values on a stack (an unbounded list of texts built by appending, a record with two growing fields; a bounded `list<Text max 40, 100>` is not one of these, see Collections). The first implementation refuses them with an error suggesting a bounded collection instead (`list<Ascii max 40, 100>` as a local, say), which isn't a growing value: it has a fixed worst-case size and nests freely, since collections flatten into arrays. The later design keeps two compiler-assigned stacks for such a value, one for its fixed-size descriptors (`{offset, length}` per element, offsets rather than pointers) and one for the elements' bytes. An element is frozen once it's added; changing it means rebuilding it at the end and updating its descriptor. Both stacks, alignment and any temporary copy count in the bound.

### Keeping it fast

- **A context pointer, not thread-locals.** Every function takes one hidden pointer to its job's context: stack bases, tops, limits and the step budget. Hot code never looks up thread-local storage (Burin's helpers do today; that goes).
- **Stack tops in registers** (Goose's top caching): a function keeps the top of each stack it grows in a register, and writes it back only before a call that can reach that stack (or suspend), and at exits. A loop that pushes is a store, an add and one compare.
- **No aliasing between stacks:** different stacks never overlap, so LLVM knows a push to one doesn't change what's read from another. `noalias` is emitted only where it's proved: distinct stacks, or parameters the call-site rule keeps apart.
- **Freeing a scope** puts saved tops back: register moves, with memory written only at function exit.
- **No locks, no atomic operations on stacks,** since a job's stacks belong to it alone.

### Crossing threads

Nothing mutable is shared. Values cross in four ways:

1. **Queues of flat values.** A flat value is one contiguous block with no pointers in it (data inline, typed ids instead of pointers), so sending is one copy into the queue and one onto the receiver's stack. Queues are bounded rings: one producer and one consumer where possible, with no locks; many producers to one consumer for workers sending to the writer.
2. **Snapshots** of a shared global (Shared state across threads).
3. **Frozen pools** (below).
4. **Parallel loop inputs and results** (Parallel loops).

A typed id means an element of a pool, not a memory address, so it stays valid in any thread reading the same snapshot.

### Parallel loops

- `parallel for t in texts { … } collect`, or `parallel for i in 0..n reduce sum`: the runtime splits the work into chunks that idle workers take (work stealing: an idle worker takes chunks from a busy one's queue). Each chunk runs on stacks of its own.
- **Inputs:** the loop is scoped (the caller waits until every chunk is done), so the caller's stacks stay alive and unchanged for the whole loop. Chunks get read-only views of what the body reads from the caller (`texts` here), with no copy; the views end at the join, before the caller can change anything again. Chunks may also read the caller's pinned snapshot, which stays pinned until the join (Thread kinds and jobs).
- **The body** may have no effects, and may write only what it owns: its own scratch and its slot of the result. Reads of captured caller values are read-only views; a body that tries to write or grow a captured value is refused, whatever its effects. So there are no data races.
- **Outputs:** `collect` writes into a result buffer the caller owns, on its destination stack. When the output sizes are known up front (one value per item, fixed size) each chunk writes its slice directly. Otherwise each chunk builds its output on its own stack and the join copies the pieces in index order before those stacks are reset. `reduce` combines chunk results in a fixed tree order, whatever the scheduling, so floating-point sums come out the same on every run.
- **No nesting in v1:** a `parallel for` reached from inside another runs sequentially, so workers can't all end up waiting for work nobody can run. A worker waiting at a join runs other chunks of the same loop meanwhile.
- Small loops run sequentially below a cost threshold, so a fork never costs more than it saves.

### Shared state across threads

This section is about `shared global` state only.

- **One writer per shared global.** Workers send change requests on a queue and get a reply (Burin's model); writes are batched.
- **Snapshot cost proportional to what changed:** each collection's arrays and payload are stored in fixed blocks (4,096 rows, say). The blocks hang off a small tree (a radix tree: each level indexes into the next by part of the row number). A write copies the blocks it touches and the tree nodes on the path to them, and shares everything else with the previous version. Publishing is proportional to the blocks changed, not the state's size.
- **One version per shared global:** everything in it is published together under one root, so a reader never mixes one collection's new elements with another's old ones. Shared sets are lost on a crash unless the program saves them.
- **Publishing and pinning safely:** the writer finishes writing a version's blocks before publishing it. Taking a pin (reading the current root and counting it) and publishing a new root happen under one short runtime lock, so a reader can never pin a root the writer is freeing; the lock covers only those few instructions, never row reads. v1 uses this lock because it's simple and obviously right; a lock-free scheme can replace it if measurements show contention.
- **Pinning:** a job pins the current root when it starts reading and unpins it when it ends or before it waits (Thread kinds and jobs): one pin per read phase, never per row or block.
- **Freeing old blocks:** readers' pins keep a version's root alive; roots and tree nodes keep blocks alive. Each tree node and block has a count of the tree nodes or roots that point to it, kept by the writer alone, so no reader ever touches it. When an old root is neither current nor pinned, the writer drops it: it decrements the counts of what it points to, and frees each node or block whose count reaches zero, recursively. A block shared with the current version keeps a count above zero and stays. This costs work proportional to what the dropped version didn't share.
- **Slow readers:** a pin lives only for a stretch of computing with no waits, or across a parallel loop's join (the one structured exception, Thread kinds and jobs), and both are bounded by the job's time limit, which cancellation polls enforce in every kind of loop. If pinned old versions still hold more memory than a budget, the writer pauses applying writes until they're released. A live view is never invalidated.
- Program and job state skip all of this: plain arrays, no counting.

### Frozen pools: big shared data built in parallel

Many programs build a large structure once and then read it from many threads: a compiler's syntax trees (the TypeScript compiler's Go rewrite parses files in parallel, then several type-checker threads read the same trees), a game's level, a search index. Funnelling every node through one writer would be far too slow, and stacks die with their job. So (decided 2026-10-24):

- **Build:** a job creates a *builder* pool that only it owns: no writer, no snapshot, plain arrays. One file's syntax-tree nodes, for example, with child links as typed ids and source text as `{offset, length}` into the builder's payload blocks. Data-oriented compilers (Zig, Carbon) already store trees this way: compact and fast to walk.
- **Freeze:** `freeze b` ends the builder and turns its blocks into a read-only partition, published as one pointer, with no copy. The type system then refuses writes to it, and the old builder name is gone.
- **Group:** a batch root lists the partitions (one per file). A frozen id is 64 bits: a 32-bit partition number and a 32-bit row. Frozen rows are never deleted, so no generation is needed. A node in file 3 can refer to a declaration in file 7.
- **A batch is a token made first:** `let b = batch()` creates a unique, scoped batch token before any builder exists. The batch declares its most partitions (`batch(max 20000)`), and each builder its most rows and its most payload bytes, separately (`b.builder(Node, rows 2_000_000, bytes 8 MB)`). A builder may derive them from its input only through a formula its parser proves, for example at most one node per source byte plus one per error-recovery insertion, capped; the builder is checked against both maxima as it grows, and passing one fails it with `Full`. Each builder gets its partition number up front, so ids are final while they're built and freezing renumbers nothing. `inspect state` reports the batch's total worst case, and admission counts it.
- **Building in parallel:** the parent job makes the batch and one builder per file, then hands each builder to one chunk of a parallel loop. Handing it over moves the builder (as `take` moves a value), so exactly one chunk can write each partition and the partitions are disjoint. At the join the parent gets the builders back, freezes them, and publishes the batch root. There's no central writer and no copying per node.
- **Ids can't cross batches:** the id's type names its batch token (`b.Node.Id`), and each `batch()` call makes a distinct token, even in a loop or in two calls of one function. So mixing ids from two batches is a build error, and since the token is scoped, ids can't escape it (they can't be stored in state that outlives it or returned from its scope). A lookup still checks the partition and row against the batch's sizes (one compare each).
- **References between partitions while building:** a builder can refer to its own rows by id at once. A reference to a row in another file isn't known until that file is parsed, so it's stored as a name and resolved in a pass after freezing (as compilers resolve names after parsing), which writes the found ids into a job-state map of resolutions rather than into the frozen rows.
- **Read:** jobs pin the batch root once, as with snapshots; functions take read-only views of rows, text and lists as parameters, with no copying and no counting per node.
- **Lifetime:** a frozen batch lives until the scope that created it ends (for example "check this project") and no job pins it; then its blocks are freed in bulk.
- **Per-job caches:** each reading job keeps its own job state for what it computes (the TypeScript checkers each keep their own type caches the same way).

Still off the table: many threads writing into one shared structure (a global interner that stores each distinct type once has to live on a writer, or be per-thread and merged after the phase); freezing part of a structure while changing the rest; pointers from a frozen pool into a job's stack; counting per node.

### Targets

| Operation | Target |
| --- | --- |
| Push in a loop | under 1 ns, no atomic operations |
| Free a scope | under 5 ns, whatever it held |
| Start a job (stack set from the pool) | under 200 ns |
| Suspend and resume a job | under 1 µs |
| Send a 64-byte value through a queue | under 100 ns |
| Parallel loop overhead (fork and join) | under 5 µs |
| Independent chunks of one parallel loop, 4 cores | at least 3.5× one core (hardware reported with every timing) |
| Publish a snapshot | proportional to blocks changed, not state size |
| Freeze a builder | constant, whatever its size |

### Open questions

- How many copies code size can bear, and when constant-base copies pay.
- How large N grows in programs that use many libraries.
- Parallel loops inside a game tick, keeping ticks deterministic and within their time budget.
- The block size for snapshots of shared state.
- Whether jobs should ever move between workers (better balance, but stacks would then need to be safe to hand over).

*(Diagram in the shared Claude Doc: threads · workers with their own stacks, one writer, snapshots.)*

Workers grow and free their jobs' stacks without locks; changes go to the writer through queues, and every job reads a pinned snapshot. A parallel loop's chunks run on these same workers.

## Types, and refinement types

Refinement types are the design's best lever: one declaration serves correctness, efficiency and every layer at once, if they stay small enough to check quickly.

**The base:** values with no null; `Option` and `Result`; records; enums with payloads and exhaustive `match`; generics with static traits; newtypes (a `UserId` is not an `Int`). Arithmetic is checked: an overflow is a failure, and wrapping is spelled `+%`.

**Failures** that aren't values: an overflow, a divisor of 0, an index the compiler couldn't prove in range and that turns out not to be, a data stack or the native-stack budget exhausted, the step budget spent (an unbounded loop's limit), a time limit passed. Each fails the job, as a stack limit does (see Memory): the job ends with an error carrying the source line. A function returning plain `T` therefore never returns a half-made value.

**What failing a job does,** in this order, so nothing can touch memory after it's reused:

1. Stop scheduling the job: no more of its code runs.
2. Cancel its pending I/O and its unstarted parallel-loop chunks; wait until running chunks have stopped (a chunk notices at its next cancellation poll: a step-budget check, or the periodic poll in a loop that has no budget) and the event loop has confirmed no I/O will write into the job's buffers. A pin held for a join is released only after this.
3. Settle its change batches: one not yet sent is dropped; one queued at the writer is cancelled; one the writer is applying is waited for, until the writer acknowledges that it aborted or committed it, since the writer reads the batch from the job's buffers until then. Batches the writer committed stay committed (decided 2026-10-24, see Transactions).
4. Release its snapshot pin and any frozen batches or builders it owns.
5. Reset its stacks and return the stack set to the worker's pool. These steps run on the worker's own scheduler stack, not the job's, so a job that failed because its native stack ran out can still be cleaned up.
6. Report the failure: to the client (a 500 for a request), to the log, and to the parent if it was a parallel-loop chunk, which fails the parent job with the chunk's error. Code that wants to handle one of these locally uses the checked form that returns `Option` (`checked_add(a, b)`, `a.get(i)`), or a refinement that proves the failure can't happen.

**Text, ASCII and bytes** (decided 2026-10-24): `Text` is always valid UTF-8; `Ascii` is text known to hold only ASCII characters (bytes 0 to 127), the compact form, one byte per character; and `Bytes` is raw data (DEFLATE's output, files, the network). An `Ascii` value is a valid `Text` too, so passing one to a *read* parameter of type `Text` costs nothing. A write or grow parameter is different: the function could store a non-ASCII character, or need up to 4 bytes for a character where `Ascii max N` owns exactly N, so passing `Ascii` there needs an `Ascii` parameter, a proof that the function writes only ASCII within the bound, or an explicit checked conversion into `Text` storage of the right size; going from `Text` or `Bytes` to `Ascii`, or from `Bytes` to `Text`, is a checked step that returns `Result`. For `Ascii`, a character, a code point and a byte are the same thing, so `Ascii max N` is exactly N bytes, its length is O(1) and indexing by character is direct; operations like `ascii_upper` and comparisons skip UTF-8 decoding. Text lengths count Unicode code points (what a person would call characters, roughly); byte lengths are written on `Bytes`, or as `Text bytes max N` when a byte budget is what matters.

**Refinements** are a type plus a predicate the compiler understands, a closed set kept decidable:

| Kind | Written | Example use |
| --- | --- | --- |
| Range | `Int 0..100`, `Int >= 0` | quantities, percentages, indexes |
| Length | `Text max 80`, `list<T, 20>` with at least 1 (`list<T, 1..20>`) | names, bounded lists |
| Membership | `Text in ["low", "high"]`, an enum | states, options |
| Pattern (a regular-language subset) | `Text matches slug` | slugs, codes, emails as syntax only |
| Index | `Index(a)`, meaning `0 <= i < len(a)` | array positions with no bounds check |
| Linear relation between fields | `invariant start <= end` | intervals, budgets |

**How they are checked:**

- Values enter a refined type at a boundary only: parsing input, reading a column, or an explicit `check`, which returns `Result`. Inside, operations keep or prove the refinement. Parse, don't validate.
- The compiler infers refinements by interval and sign analysis (Burin's sign analysis is a first version): `x: Int 0..100` plus `y: Int 0..100` is `Int 0..200`, with no overflow check.
- Where it can't prove a refinement it asks for one of three things: a `check` (a runtime test with an error to handle), a stronger parameter type, or a rewrite. It never assumes silently.
- A fact about a growing value's length (`i` is an `Index(a)`) holds until something can change that length: a grow of `a` itself, or a call that takes `a` in grow mode. The compiler sees both, since references are only parameters and two parameters never overlap when one changes; after either, the fact is gone and the index must be proved again.
- Field relations and state invariants go to a solver (Z3, as crudspec does) only in a separate deep check, so ordinary builds stay fast.

**What refinements buy, per goal:**

- *Correct:* bad values can't exist past the boundary; slips like a negative stock are build errors.
- *Efficient:* proved ranges become LLVM facts: an `Index(a)` carries no bounds check, and a sum of bounded values none for overflow. The DEFLATE work showed this is where checked code loses to C.
- *Easy:* one declaration replaces validation code in the form, the API, the database and the tests (next section).

**What to avoid:** full dependent types and arbitrary predicates (slow checking and baffling errors, as Liquid Haskell and F\* show), and refinements on everything by default. They stay opt-in on the fields and parameters where they say something.

## One declaration, every layer

crudspec's best idea generalized: a type, a rule or a permission is declared once, and the compiler projects it into every layer that needs it, so the layers can't disagree.

In crudspec today a field's size carries through: `title: Text max 80` is a CHECK in SQLite, a refusal in the action, `maxlength` on the form and `maxLength` in the agent's schema. The general version treats each layer as a projection of the same declaration:

| Declaration | Database (SQL) | Wire (JSON, CLI, forms) | UI | Agent API | Tests | Compiler |
| --- | --- | --- | --- | --- | --- | --- |
| `Text max 80` (code points) | CHECK with the runtime's own SQLite function that counts every code point (SQLite's `length()` stops at the first zero character, which is valid text) | rejected on parse | a code-point counter that blocks submit (not `maxlength`, which counts UTF-16 units) | `maxLength` (JSON Schema counts code points) | boundary cases 0, 80, 81, with characters outside the basic plane and a zero character | buffer bound known (at most 4 bytes per code point) |
| `Ascii max 80` (bytes) | CHECK with the same function, plus a check that every byte is below 128 | rejected on parse if longer or not ASCII | `maxlength=80` is exact (for ASCII, UTF-16 units are characters) and a `pattern` limits input to ASCII | `maxLength` plus an ASCII `pattern` | 0, 80, 81 characters and one non-ASCII character | buffer exactly 80 bytes |
| `Bytes max 4096` | CHECK on `length()` of a blob (exact for blobs) | the decoded byte count is checked | a file-size check | `maxLength` on the base64 text, only as a first filter (4,096 and 4,098 bytes encode to the same length); the server checks decoded bytes | 0, 4096, 4097 bytes | buffer size known |
| `Int 0..100` | CHECK range | rejected on parse | `min`/`max` input | `minimum`/`maximum` | -1, 0, 100, 101 | no overflow check |
| enum `State` | CHECK IN | one of the names | a select | `enum` | every case | exhaustive `match` |
| `invariant start <= end` | CHECK on the row | rejected on parse | the form's error | described in the schema | generated pairs | solver proof per writer |
| permission `read Item: owner == actor` | WHERE on queries | 404, not 403 | hidden rows and links | the tool can't see them | an outsider scenario | change review flags widening |
| error `Result<_, OutOfStock>` | none | status 409 + code | a message | an error code | the failing path | must be handled |
| effect `db.write` | transaction | none | none | marked as a write tool | effect assertion | capability required |
| a query's `limit 50` | `LIMIT 50` | a page size | paging controls | `maxItems` | 0, 50, 51 rows | the result's byte bound |

The Database column applies to database records. State (program, job or shared) checks the same rules in memory instead, on every write (a field past its maximum, a value out of range, an invariant), with no SQL involved.

**Rules for the projections:**

- A projection is generated only where the layer's rule means the same thing as the declaration. Where a layer counts differently (HTML's `maxlength` counts UTF-16 units, not code points), the generated code checks it the declaration's way instead of using the layer's near-miss.
- Layers are compiler back ends, not libraries, so each projection is checked. A form can't drop a field an action needs; a page can't show a row a permission hides.
- A layer may override how a declaration looks (a label, a message, a widget), attached to the same declaration and flagged by the change review. It may not override what it means.
- The projections are generated, never hand-edited (crudspec's rule). Hand code goes in typed extension functions with declared effects.
- Tests come out too: every refinement yields boundary cases, every enum its cases, every permission an outsider scenario. These run with the scenarios.

This is also where refinement types pay twice: the same `Int 0..100` that a form enforces is the fact that removes an overflow check.

## Effects and capabilities

What a function may touch is part of its type, inferred across calls, and granted only by the program's entry point (Hobthrush's model).

- A closed effect set: `db.read`, `db.write`, `fs.read`, `fs.write`, `net`, `clock`, `random`, `env`, `secret`, `log`, `spawn`. No effects means pure.
- **Pure** means deterministic (the same inputs give the same result) with no effects. A pure function may still change or grow what it's handed through a write or grow parameter; those modes are part of its type, so callers and the compiler see them.
- **Cacheable** is narrower than pure: no effects, every parameter read-only, and a result the function owns. Only cacheable functions may be cached, evaluated at compile time or used by cached page pieces, since skipping a call to one changes nothing but the time taken. A pure function that appends to its caller's list isn't cacheable: reusing a saved result would skip the append.
- **Reading a snapshot is pure,** because the snapshot is an input: a function that reads shared state takes the pinned snapshot as a read-only parameter (passed implicitly, like the context pointer), and its result depends on that version. Reading program or job state isn't: it's the owner's current state, which can change between two calls, so a function that reads it isn't cacheable in v1 (a test checks that changing a row between calls can't reuse an old cached result). Database reads are effects (`db.read`). Parallel loop bodies and cached pieces may read the snapshot; a cache keys its entries by the snapshot's version, so a cached result never outlives the data it came from.
- Effects are inferred. A function may state an upper bound; exceeding it is an error that shows the shortest call path to the effect.
- Capabilities are values the entry point hands down (`Clock`, `Db`, `Http`), granted in the package manifest. A library can't reach the network unless a caller passes it a capability.
- Burin's rule "pages call only pure functions" falls out of cacheability. Database queries are effects, so a page runs its queries first, with bounded, owned results, and its cached pieces take those results as inputs; a `db.read` can never sit inside a cached piece.
- Time and randomness come only through capabilities, so tests and replays can supply fixed ones.
- C functions declare their effects at the binding (`fn crc(b: Bytes) -> Int = c "crc32_z" from "z" effects none`). The declaration is trusted, and the audit report lists it as such.
- `inspect effects` and the change review report effect widening, like permission widening.

## Correctness tools

Testing is part of the language, because measured over four weeks, scenarios and reference checks caught bugs and type rules alone mostly didn't.

- **`test` blocks with `expect` steps** (AgentLang's form): several per test, `let` between them, both sides shown on failure.
- **Scenarios:** a named sequence of actions by named actors with expected outcomes, written against the app's own vocabulary. They're the language's integration tests and the change review's evidence.
- **Reference checks:** `check fast == reference` holds an optimized function to a plain one, over generated inputs and the refinements' boundary cases. Burin's interpreter-versus-native, Rust-versus-SQL and fast-path-versus-fresh-render checks become one construct.
- **Golden outputs:** a test may pin bytes (a page, a file); `accept` updates them after a reviewed diff.
- **Invariants** on state are checked on every write at run time, and optionally proved for every writer by the deep check.
- **Determinism:** fixed iteration order, and time and randomness only through capabilities. Any failing run is replayed from its inputs; a game tick or a server's write batch is a recorded step.
- **Generated cases:** boundary values from refinements, every enum case, an outsider for every permission (previous section).
- **Fuzzing:** random inputs within refinements, and random action sequences against the invariants.

## Performance model

The compiler doesn't try to out-optimize LLVM; it tells LLVM what the language knows and does early what can be done early.

- **Facts for LLVM:** refinements and inferred ranges as `assume` and `range` attributes, non-negative values, `noalias` where it's proved (distinct stacks, parameters the call-site rule keeps apart), `smin`/`smax` for `min`/`max`, plain `add nsw` (an add LLVM may assume doesn't overflow) where overflow is ruled out. Every fact comes from a proof; none is assumed. In Burin these took DEFLATE from 0.70x to 0.85x of C (0.89x after later work).
- **Loops that provably end** carry no step budget: counted up or down, or any counted part of an `and`. Long ones still poll for cancellation every few thousand iterations (one load and compare), so deadlines hold.
- **Compile-time evaluation:** statements that depend only on constants run in the compiler; their tables become read-only data.
- **Layout:** collections as one array per field, nested collections flattened; fixed-size data inline, small text inline, larger text in size classes; enums sized to their largest case; typed ids 64 bits in v1 (narrower ids would weaken the generation check, so they wait for measurements).
- **No steady-state allocation:** stacks and state are reserved once and reused; a test asserts zero allocations on chosen paths, as Burin's hot-path test does.
- **Load what is used:** queries and loads guarded by the conditions around their uses; a per-request piece rendered once per page. Burin's +27% to +50%.
- **Work at write time where reads dominate:** derived values and rendered pieces kept up to date by the writer, behind the same purity rules (a library, as Burin's caching becomes).
- **One release pipeline:** LLVM with cross-language LTO, so the runtime's helpers inline into generated code.

## Development experience

One compiler target, LLVM, for development and release alike: no JIT, no interpreter, no live swap, so nothing can drift between two back ends. A small edit is running again within 3 s (decided 2026-10-24).

- **Development builds:** LLVM at `-O1`, no LTO, one object file per module cached by a hash of its source, its dependencies' interfaces, the generic copies it contains (each per-type copy is compiled into the module that first needs it, and its key includes the generic's source), and whatever compile-time evaluation read, so a one-function change rebuilds one object and relinks. Target: 3 s from save to running on a Campfire-sized program; release builds (`-O3`, LTO) under 30 s.
- **Restart, not swap:** a change restarts the program. Database records survive, and a changed schema's migration, planned from the diff (crudspec), runs at start; program and shared state start from their defaults and initialisers (or from what the program saved, checked the same way).
- **What you test is what ships:** tests run on the same code generator as release, at the development optimization level, and in release mode in CI.
- **Compile-time evaluation** covers some of what a REPL would: constant code runs in the compiler.
- **One way to write each thing:** small syntax, inferred types, no imports inside a package (an app or library is a directory), one formatter.
- **Errors that name the fix:** "did you mean" for names, keywords and attributes, the error at the slip's own line. Their quality is measured by seeding slips, as crudspec's mutation harness does (99% of misspelled names caught there).
- **For agents:** `inspect` reports in JSON (API, effects, refinements, state, call graph), and a change review that lists what a change widens: effects, permissions, refinements loosened, invariants dropped.
- **Editor:** a language server from the start, sharing the compiler's code (Stasis's VS Code extension is the model).

## Concurrency and interop

Threads share nothing mutable; C is reachable through typed bindings that declare their effects.

**Concurrency**

- Threads, data stacks, queues, snapshots and parallel loops are designed in Threads and data stacks, above.
- No locks in the language: nothing mutable is shared, so data races can't happen.
- I/O waits suspend the job, and an event loop per worker resumes it (Thread kinds and jobs): no `async` colouring in source.

**Interop**

- C functions bind with a declared C prototype and effects. The ABI (the binary calling rules both sides follow) is the platform's C calling convention, with these mappings:
  - Integers as 64-bit (or the declared C width), `Bool` as a byte, floats as `double`.
  - `Text` and `Bytes` as a pointer and a length, valid only during the call; C must not keep the pointer.
  - Records as a pointer to a C struct with the same field order and C's alignment rules; enums as a 32-bit tag followed by the largest payload.
  - Results that grow (text, bytes) written through a runtime buffer function the call is handed (Burin's and AgentLang's ABI).
  - Errors as a return code the binding maps to `Result`; C never returns `none` by convention.
  - No unwinding across the boundary: a C++ exception or Rust panic that reaches it aborts the process, and the binding generator wraps Rust functions to catch panics.
- Rust functions bind through the same C ABI and inline under LTO.
- Bindings to C libraries (zlib, SQLite, crypto) are how CPU-critical or security-critical pieces get done: no home-made crypto.
- Foreign code is trusted; the audit report says so plainly.

## Validation plan and kill criteria

The core is proved on four narrow programs, one per use plus compute, before any widening, each against a strong baseline. Every result records the source revision, the exact command, the machine, peak memory and build time.

| Program | Baseline | Target | Kill if |
| --- | --- | --- | --- |
| DEFLATE and CRC-32 (compute) | a C version with precomputed tables, clang -O2, on Silesia's dickens (10.2 MB), one core, median of 9 | throughput 0.9x of C or better | under 0.75x after the facts work |
| Parallel tool: parse and check a source corpus (builders, frozen pools, parallel loops) | a Rust version with the same algorithm and thread count | 0.9x of Rust's time or better, and 3x or more on 4 cores over 1 | under 0.7x of Rust, or under 2.5x scaling on 4 cores |
| Campfire-class server (a SQLite database, pages, live updates) | Burin today; the optimized Rust port | Burin's pages/s within 10%, memory within 1.2x | under 0.7x of Burin, or over 2x its memory |
| Waiting jobs (the same server with 10,000 requests suspended on a slow outside call, from fresh and from previously busy stack sets, with snapshots pinned by the running ones) | the Rust port with the same load | stated ceilings met: committed memory under 1 GB for the 10,000, address reservations within admission limits, excess requests answered with 503 | over 2x the Rust port's memory, or any crash or unbounded growth |
| Game simulation (program state, ticks) | Stasis ahead-of-time | equal speed; a small edit running again in 3 s | slower than 0.8x |
| Seeded slips (mutation harness) | crudspec's numbers | 99% of misspelled names caught at their line | under 95% |
| Refinements on the four programs | the same programs without them | at least half of bounds and overflow checks gone; no slower build than 1.2x | builds over 2x slower, or no checks removed |
| Agent changes (scenario-scored feature requests) | the same requests in Rust | equal or better correctness, fewer exchanges | worse on both (AgentLang's outcome) |

The agent study follows the lessons of AgentLang's: the outcome is scored by scenarios the agent never sees, with fresh agents and equal briefs on both sides.

## Risks, open questions and first steps

The largest risk is scope: a general-purpose language is how Hobthrush ended up building everything at once. The first steps happen in this language's own folder (D:\code\next-lang, a working name), copying from Burin's helper compiler, which already reaches 0.89x of C, without depending on Burin.

**Risks**

- *Typed ids instead of pointers* make trees and linked structures index-based. That's efficient, but needs library types (pools, arenas, graphs) so it doesn't feel clumsy.
- *Refinement errors* can baffle ("can't prove i < len(a)"). Each error must name what would prove it: a `check`, a parameter type or a loop bound.
- *Projections to every layer* tempt layer-specific special cases. Overrides change looks, never meaning.
- *Solver time* (Z3) must stay out of ordinary builds.

**Decided (2026-10-24)**

- Recursion is opt-in: only functions marked `recursive` may call themselves, directly or through a cycle. A recursive cycle can't hold a growing value across its recursive call, and its native stack use is checked against a byte budget; going past it fails the job. Everything else stays recursion-free, so stack assignment stays simple.
- Three types for text and bytes: `Text` (always valid UTF-8, lengths in code points), `Ascii` (ASCII only, one byte per character, the compact form) and `Bytes`.
- Generics are copied per type (as Rust and C++ do): full speed, and LLVM sees concrete types, at a cost in code size and build time that the 3 s target has to absorb.
- Servers, games and tools weigh equally; the validation has a program for each.
- Jobs can wait: I/O suspends a job, which keeps its own stacks, and the worker runs others meanwhile.
- Running out of a data stack (or another runtime failure) fails the job, not the program; no `Result` on every push.
- v1 targets 64-bit platforms only; WebAssembly and 32-bit come later.
- Build-then-freeze pools for large data shared read-only across threads.
- A value a loop keeps growing must have a bound the compiler knows, and each iteration's temporaries are freed when it ends.
- A failed job discards only its uncommitted batch; committed batches stay, and `transaction { }` groups changes that must succeed together.
- A transaction's checks and writes run on the writer against its latest version, with no waits inside.
- Static state is meant to be used lightly: most data lives in locals on stacks (bounded collections are ordinary values), in databases or in frozen pools; `inspect memory` warns past a globals budget.
- Full static allocation of state: globals (program and shared) are sized at build time and allocated in full at startup, never allocating after; data stacks, job state and frozen batches stay per job, reserved and committed as used.
- All state is bounded: every collection declares its capacity and each variable-size field its maximum; adding to a full collection returns `Result`.
- Only this program writes its databases in v1; other tools may read them.
- Database records have no row maximum; a deployment may set a disk quota (past it, writes return `Full`). Field maxima and query limits keep memory bounded.
- State is a tree of structs with bounded collections (`T[N]`, `list`, `pool`, `map`, `set`, `queue`, `ring`, `grid`), as in StasisLang, owned by the program (a global with a home worker), a job, or shared (`shared global`: one writer, snapshots); no standalone tables. Databases are a separate feature, not state: typed queries compiled to SQL, SQLite first.

**Open questions**

- Can development builds hold 3 s as programs grow, with per-module caching alone, or will they need a faster code generator for `-O0` (LLVM's FastISel, or splitting modules finer)?
- The language's name (the folder's is a working one).

**First steps**

1. State and typed ids: fixed arrays, `list` and `pool` (generation-checked ids) as locals and in a small global struct, laid out as one array per field, nested collections flattened.
2. Goose-style stack assignment for growing values, replacing the helper arena: stack contracts (fresh-result and append), iteration scopes, bounds per entry point; `push`, text built from pieces, `out_byte` as a store and bump. Nested growing values are refused at first.
3. Refinements on parameters and fields (range, length, membership, index), inferred through the sign analysis and emitted as LLVM facts. Measured on DEFLATE.
4. `check fast == reference` and `test` blocks with `expect`.
5. Effects inferred on helpers, with the call path in errors.
6. Builders, `freeze` and parallel loops, measured on the parallel tool.
7. The four-program validation above; then decide on widening.

**Acceptance cases for steps 1 and 2** (from review 5; both steps use explicit `Text max` and counted-loop bounds, so they don't wait for step 3's inference)

- *Step 1, program state with fixed-size fields only* (no text yet, no snapshots): a live lookup succeeds; out-of-range and stale ids return `none`; deleting a row and reusing its slot doesn't change which row any other id names, and no row ever moves between slots; a slot set up near the maximum generation is retired, not reused; an id of another pool's type is a build error; an insert at exactly the maximum succeeds and the next returns `Full` without changing the pool; a field write past its maximum returns an error and changes nothing; a collection without a capacity or a field without a maximum is a build error. With payloads (still step 1, after fixed-size rows): a text that grows into a larger class moves to a slot from that class'"'"'s free list and frees its old one, and no other row'"'"'s bytes move; moving fields across classes with the collection at capacity always succeeds, and a freed slot is reused at once; a nested `list<Item, 8>` inside a pool flattens and its count is per element; a fixed array of `Int 1..100` with a valid initialiser starts, without one is a build error, and lists and pools start with a count of zero; an initialiser reading a field of the value it builds is a build error; a completed value with `start > end` fails startup before any job runs; an `Ascii` passed to a read `Text` parameter isn't copied, and passing it to a write `Text` parameter without a conversion is a build error; refusing the startup backing or lock prevents any job from running; in a tight cgroup, state whose claim exceeds the effective limit doesn't reach job scheduling; a local list over 4 KB and a nested local list are built, returned and copied and stay valid after their source scope ends, and a loop iteration frees its scratch but not an outer local list; a job builds and uses a valid local `Span`, and an invalid completed one fails the job with no partial value visible; `inspect memory` reports globals' startup claim apart from each entry point's stack bounds, and a large local collection counts toward its job, not the startup claim; the render example works with both `view Row max 500` and a bounded `list<Row, 500>`, and an unbounded growing container is still refused; a write that would replace a field under a live view is refused at build time; a view of program state live across a may-suspend call is refused.
- *Step 2, copies and moves:* `fn f(s: Text) -> Text { s }` returns equal bytes and `s` stays usable; returning a local after reading it; a forced copy from scratch to the destination, with the peak counted while old and new coexist; `take` makes the source unusable, hands its stack slot and cleanup to the destination, and keeps the bytes alive until the destination's scope ends (a move that can't keep those rules is refused at first).
- *Step 2, append and bounds:* exact output in fresh-result and append modes, including a four-byte UTF-8 character at the declared maximum; capacity checked before any store; a failed append leaves no partial result in the builder; in `render`, `str` appends while `name` is live without a second growing temporary on its stack, and N and the reported peak match the worked example; a nested call while live values occupy separated stacks gets a window that avoids them, and N is one more than the highest index used.
- *Step 2, overlap and iteration cleanup:* `s = s + s` takes a safe fallback (or is refused); `out.append(f(out))` evaluates `f(out)` into separate scratch and finishes reading `out` before the append starts, or is refused; `continue` and `break` discard the iteration's scratch and keep the outer builder; a failed job's scratch is reset before its stack set is reused.

**Later** (each needs acceptance cases before its own step; none blocks steps 1 and 2): databases (typed queries, transactions, disk quotas and startup checks, migrations); snapshot reclamation and freed slots held for pinned versions (a case that replaces or removes a field while an old version is pinned, checks its slot isn't reused until unpin, then the whole-batch budget check); `map`, `set`, `queue`, `ring` and `grid` (including views that reach into nested collections, which must also block removing or replacing their enclosing elements, and map rehashes and ring overwrites under the overlap rule); nested storage arithmetic (multiplying enclosing capacities) with a nested `Text` case; pools nested inside repeated elements, refused until supported, with generations kept across any reset of their container; builder handoff as a stated exception to read-only captures, with batch-lifetime cases for step 6; ids and generations when local pools are copied, returned or reset (a returned pool takes its new owner's name); memory backing policies for macOS and Android; SQLite read pins and transaction staging; native-stack admission and foreign-call margins; returned views with a lifetime rule; nested growing values; several instances of one shared global; pools nested inside arrays of structs.
