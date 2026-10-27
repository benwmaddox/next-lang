# A general-purpose language: correct, easy, efficient

Oct 23, 2026 · Ben Maddox. Working copy, refined with Codex; reviews and replies are in [reviews/](reviews/). The two diagrams are in the original shared doc: https://claude.ai/artifact/AfD3gnVW8QqwrVXomjv48H

## Goals and non-goals

One language that is hard to get wrong, quick to work in, and within about 10% of C on CPU and memory, first for servers (web apps and APIs) and tools (CLIs), then games once that foundation is solid (Ben, 2026-10-27: games will come, foundation first). Each goal has a test, not an adjective:

- **Correct:** the compiler enforces a stated set of properties (no null, no data races, no dangling ids, exhaustive matches, refinements, effects), and the language's own tests catch most of the rest. Measured by seeded slips caught at build time, scenarios passing, and fast-versus-reference checks. No language catches every wrong program; this one aims to catch the common ones before production.
- **Easy:** a small edit to a small or medium program is running again within about 3 s (an aspiration, not a promise for every program), a release builds in under 30 s, and every error names the fix. Measured by edit-to-running time and the mutation harness's "did you mean" rate.
- **Efficient:** no garbage collector, no allocation in steady state, compute at 0.9x of C or better, servers within 1.2x of the optimized Rust port's memory. Measured on DEFLATE, a Campfire-class server, a game simulation and a parallel tool (see Validation).

**Where it fits** (Ben, 2026-10-27): a concise language for work where stack and arena allocation pay off: web apps and APIs, CLIs and tools, and other request-shaped programs that create many short-lived values and free them together, with long-lived state kept as bounded trees (a server's live data, and later a game's world). Programs whose core is a large, long-lived, constantly rewired graph of objects (a GUI object tree, an in-memory graph database, a general-purpose garbage-collected heap) are not the target; they can be written with pools and typed ids, but other languages suit them better.

Non-goals for the first version:

- Full dependent types or proofs of arbitrary properties (refinements stay decidable, see Types).
- Pointer graphs with arbitrary aliasing; long-lived links are typed ids.
- 32-bit and WebAssembly targets: v1 is 64-bit only (Windows, Linux, macOS, 64-bit Android), because the stack design relies on large address reservations. WebAssembly comes later with its own stack design (decided 2026-10-24), which also needs stack switching for suspended jobs (Open questions under Threads).
- Replacing Burin or the other languages: Burin continues as its own web language, and this is a separate project in its own folder that borrows their ideas and code.
- A package ecosystem or governance model before the core proves itself.

## The language in one page

A summary of the whole design, with a small complete program. Each piece points to the section that designs it. The syntax here is a first proposal (2026-10-24), meant to make the design concrete; details will change.

**What it is.** One language for servers, games and tools that compiles through LLVM to native code, with no garbage collector. Most of what can go wrong is a build error: no null, no data races, no dangling ids, exhaustive matches, bounded memory, declared effects. The rest is caught by tests that are part of the language.

**The pieces.**

- **Values and bounds:** records, enums, `Option` and `Result`; numbers with ranges (`int 0 to 100`); text with a maximum (`Text max 80`, `Ascii max 32`). Everything that can grow has a bound the compiler knows (Types; Loops can't quietly fill a stack).
- **Where data lives:** locals on a job's stacks, freed when their scope ends; a database for records; frozen pools for big shared read-only data; shared state for live data many jobs read and one writer changes; program state (passed as a parameter) for a game's world (Memory).
- **Collections** are bounded values: `T[N]`, `list`, `pool` (stable slots with ids), `map`, `set`, `queue`, `ring`, `grid` (Memory, Collections).
- **Jobs:** `main`, each request and each spawned task is a job on a worker thread, with its own stacks; it can wait for I/O without `async`. A function that may be started as a job is marked `@[job]` (Threads and data stacks, Function attributes).
- **Effects:** what a function may touch (the database, the network, the clock) is part of its type and comes from capabilities the program's entry point hands down (Effects and capabilities).
- **One declaration, every layer:** a field's `max 80` is also the database's check, the form's limit and the API's schema (One declaration, every layer).
- **Tests in the language:** `test` blocks with `expect`, scenarios, `check fast == reference` (Correctness tools).

**A small program: a chat server.** More examples (a game, a command-line tool, a JSON API with a rate limit, and a CRC-32 routine) are in [EXAMPLES.md](EXAMPLES.md). A package is a directory; every file in it sees every other, with no imports. Each line here is meant to be one the compiler, as designed, would accept; comments say what it relies on.

```
// chat/model.nl: the data
type Body = Text max 2000          // one declaration, used by the record, the action and the form
type Name = Ascii max 32

database Chat: sqlite {
    record Room { name: Text max 80 }
    record Message { room: Room.Key, author: Name, body: Body }
}

struct Viewer { name: Name }       // put in place by the server from the session, never from a form

enum PostError { Empty, Full }     // Full: the disk quota is used up, or the record's keys have run out

struct Presence { who: map<Room.Key, set<Name, 200>, 1000> }
// created once in main (`shared Presence {}`) and passed to the jobs that read it

// chat/pages.nl: what people see
@[page]
fn room(room_key: Room.Key, db: Db<Chat>, online: shared Presence) -> Html {
    let found = db.read {                      // reads only the room; Messages may see a newer version
        Room.get(room_key)
    }
    let r = found ?? return not_found()        // no such room: answer 404 and stop
    let here = online.who.get(room_key)?.count() ?? 0   // ?. : call only if present
    <h1>{r.name}</h1>
    <p>{here} here</p>
    <Messages room_key={room_key} db={db} live/>
    <form action={post(room_key)}>
        <input name="body">        // a code-point counter and the server check come from Body
    </form>
}

// A page piece. `live` on its use above means: when this room is signalled,
// open pages re-run this piece, which loads the current rows itself.
@[piece]
fn Messages(room_key: Room.Key, db: Db<Chat>) -> Html {
    let recent = db.read {
        Message.where(.room == room_key).order(.key desc).limit(50)   // newest 50, by key
    }
    <ul>
        for m in recent { <li><b>{m.author}</b> {m.body}</li> }
    </ul>
}

// chat/actions.nl: what changes data
@[action]
fn post(room_key: Room.Key, body: Body, me: Viewer, db: Db<Chat>) -> Result<(), PostError> {
    if body.trim() == "" { return err(PostError.Empty) }
    let added = db.transaction {
        Message.add(Message { room: room_key, author: me.name, body })
    }
    match added {                              // every error the insert can return, by name
        ok(_) => {}
        err(DbError.Full) => return err(PostError.Full)   // disk quota used up, or keys run out
    }
    signal Messages(room_key)                  // open pages showing this room's messages refresh
    ok(())
}

// chat/tests.nl
test "a post shows up for others" {
    let db = Db.memory(Chat)
    let online = shared Presence {}
    let room_key = db.transaction { Room.add(Room { name: "General" }) }.unwrap()
    let ann = Viewer { name: "ann" }
    expect post(room_key, "hello", ann, db) == ok(())
    expect room(room_key, db, online).contains("hello")
    expect post(room_key, "   ", ann, db) == err(PostError.Empty)
}

// chat/main.nl: the entry point grants capabilities
fn main(env: Env) -> Result<(), StartError> {
    let db = env.open(Chat, "chat.db")?        // fails startup, not a request
    let http = env.http(8080)?
    let online = shared Presence {}            // shared state: one writer, read through snapshots
    serve(http, sessions: env.sessions(Viewer), routes {
        get  "/r/{room_key}"      => room(room_key, db, online)
        post "/r/{room_key}/post" => post(room_key, form.body, session.viewer, db)
    })
}
```

What the compiler knows from this, without being told more:

- **Effects** (what a function may do outside itself, tracked by the compiler) and **capabilities** (the values that grant them): `room` reads the `Chat` database and reads the `online` snapshot (a snapshot read isn't an effect; `online` is an ordinary `shared` parameter, so the input is visible in the signature); `Messages` reads `Chat`; `post` reads and writes `Chat` and sends a live signal (the `signal` effect, granted by `serve` to the pages and actions it routes). The change review flags any new effect.
- **Bounds:** every query is bounded (`limit(50)`), so each request's memory is too, and a rendered page's size is bounded by its inputs plus its markup and escaping.
- **One declaration:** `Body`'s 2,000 code points are the form's counter, the server's check and the database's CHECK. The browser's own `maxlength` isn't used for `Text`, since it counts something else (UTF-16 units).
- **Trust:** `Viewer` comes from the session, which `main` set up, so a form can't claim to be someone else; `room_key` comes from the URL and is checked like any input.
- **Shared state:** `online` is shared, so its reads come from a snapshot and its writes go through its writer.
- **Tests:** the test runs against an in-memory database with the same declarations.

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

**The theory being tested** (Ben, 2026-10-25): a stack-and-arena design, not a copy of how Rust, C++ or a garbage-collected runtime manage memory, should win on four things, and every memory decision is judged against them first:

1. **Data locality:** values used together sit together, in one contiguous range per job, freed last in, first out; no scattering across a heap.
2. **Modest bookkeeping:** a top (and, if the stack moves, a base) per job; no per-object headers, reference counts, ownership metadata or general allocator.
3. **Compactness:** stored data is inline or index-based, with no addresses inside stored values; references are as small as they can be.
4. **Ease of cleanup:** leaving a scope resets the top; a failed job resets its stack; nothing is freed one object at a time.

**The standard library needs no C library** (Ben, 2026-10-25): the runtime and standard library of programs built by the self-hosted compiler don't require a C library (no C runtime of ours, no libc). On Linux, a small fixed set of built-in system operations (`sys.write`, `sys.map`, `sys.remap`, `sys.openat2`, `sys.getdents64`, `sys.exit_group` and the like) lowers to the `syscall` instruction; a next-lang **core library**, compiled with every program, implements what the C runtime does today (the stack mapping and its growth, buffered output, number formatting, UTF-8 and the Unicode table, files beneath the root, failure messages, test mode) and the `memcpy`/`memmove`/`memset` that LLVM may call; the core library maps the job's native stack itself, so its bounds are known without pthreads. Only the core library may use `sys` operations; programs use capabilities (`Fs`, `Out`, `Env`) that the core library implements, and still have no raw pointers. On macOS and Windows, where raw system calls aren't a stable interface, the platform layer is next-lang code calling the operating system's required library (libSystem, kernel32/ntdll). clang (LLVM) only turns IR into machine code and links.
- **External libraries are fine:** a program may link external libraries, C or otherwise, through foreign bindings (Foreign code). Only the standard library must not depend on one.
- **Entry and linking follow from that:** a program with no foreign C libraries is built freestanding (`-nostdlib -static`) with a compiler-emitted `_start` that reads the arguments and environment from the initial stack. A program that links a C library that needs libc gets libc's own start-up (its `main` calls into next-lang), because such libraries rely on libc being initialised (its allocator, thread-local storage); the core library runs unchanged on top and still makes its own system calls, never calling libc itself.
- **File I/O in the core library** (2026-10-25): reads open beneath the root (`openat2` with `RESOLVE_BENEATH`), size the file, and `read` in a loop (short reads and `EINTR` handled) straight into the destination's bytes, validating UTF-8 there; writes `openat2` with create and truncate, then `write` in a loop. Negative error numbers become the same `IoError` values as today. Two additions: an **atomic write** (write a temporary name beneath the root, `fsync`, `rename`, so a reader sees the old file or the new one, never half) as its own operation; and a **streaming file writer** capability that opens once, appends chunks from a buffer region on the job's data stack, flushes when the buffer is full and on close, with no heap, for outputs too large to build in one buffer (the self-hosted compiler's IR, logs).
- **The stack is pinned while the kernel holds an address into it:** only the core library turns offsets into raw addresses, immediately before a system call. A blocking call can't overlap growth, because the job isn't running. Asynchronous I/O (the scheduler's suspended jobs, for example with `io_uring`) can let the kernel write into a buffer after the call returns; then either the job's stack stays pinned until the I/O completes (growth is deferred, and a job that needs to grow waits for its I/O first), or the I/O buffers live in a separate pinned I/O arena. The scheduler milestone decides which, with a measurement.
- The C runtime (runtime/nl_runtime.c) stays only with Rust nlc, the stage-0 reference, until it is frozen; the two runtimes are kept behaviourally identical by the compiler comparison tests.

**Allocation calls are for arenas only** (Ben, 2026-10-25): with this design, a call that allocates memory should only make an arena or a stack (at startup or when a job starts) or grow one (the slow path when a region doesn't fit). Taking space is an inline bump of the cached top, freeing is resetting it, and nothing in generated code or the runtime calls `malloc`, `calloc`, `realloc`, `strdup` or `free` per operation (a read, a listing, a format, a copy). Any other allocation call needs a stated reason and review; debug and test-only paths (`NLC_STACK_VERIFY`, test hooks) are listed as such. A test counts heap calls during a program run to keep it that way.

A proposal that gives up one of these (a general heap, per-object allocation, chunked arenas that scatter a job's data, pointers stored in data) needs a stated reason and a measurement. One place already leans that way and is kept under review: size classes with free lists for collection text lanes over 64 bytes (stored text outside collections is inline at every bound; see Layout). Large values are not an exception: they are accessed through borrowed locations and caller-owned destinations rather than copied as whole aggregates, and those locations cross generated calls as offsets, with a transient address derived only for an access or a pinned foreign call (References into the data stack are offsets; O3 and O4 in PLAN.md retire today's raw-pointer call paths).

**Where data lives** (decided 2026-10-24: static state is meant to be used lightly). Most data should live as locals. In order of how often a program should reach for each:

| Data | Where it lives |
| --- | --- |
| What one request, task or tick computes, including its lists, sets and maps | locals on its job's stacks (bounded collections are ordinary values, see Collections), freed when their scope ends |
| A server's records, anything that must survive a crash or outgrow RAM | a database (see Databases) |
| Big read-only data built in parallel (syntax trees, an index) | frozen pools, freed with the scope that built them |
| Live data many jobs read while it changes (presence, counters, a live cache) | shared state, passed to jobs as a `shared` parameter, with one writer changing it in transactions |
| A game's world or other data the program owns for its whole run | program state, a local in `main` (or the entry point), passed as `write` to functions that need it |

The program's state is part of the job's data stack for the whole run, so its worst case is counted in the entry point's stack bound; `inspect memory` reports it separately (Static allocation, below).

**State** holds in-memory data that outlives a call. Whether it's program state, shared state or a local, it's organised the way StasisLang organises it (decided 2026-10-24): one tree of structs, whose fields are values, nested structs and bounded collections. There are no standalone tables; what earlier drafts called a table is a `pool`, one kind of collection. Data kept in a database (SQLite, later others) isn't state; it's a separate feature (see Databases).

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
    hp: int 0 to 1000
    inventory: list<Item, 8>                 // up to 8, inside each unit
}

fn main() {
    var app = App { ... }                    // program state, passed as write to functions
    // ... run game, passing app as write
}
```

*Why a state tree:* with no garbage collector and no borrow checker, data that outlives a call, keeps changing and has many items needs a home. The usual answers are owned heap objects with borrow rules (Rust), reference counting (Swift), manual freeing (C) or pools of items named by ids (game engines' entity systems, Burin's and crudspec's entities, Stasis's pools). This design takes the last, and Stasis's way of organising it: one root, nested structs, every collection with a capacity in its type. So:

- **Every value's maximum size is in its type.** Declared capacities and field maxima let the compiler work out each value's bound. The program's state is a local on the entry point's data stack with a fixed worst-case bound; shared state is claimed at startup with its worst-case bound (Static allocation); locals have fixed bounds on the job's data stack, which starts small, grows as needed up to its cap and commits only what's used; the compiler adds those bounds up per entry point for inspection, warnings and admission estimates (The job's data stack). That's the "every table is bounded" decision (2026-10-24), now applying to all state.
- **Everything has a path.** `app.world.units[id].hp` names one value. `inspect` can read any path between steps, and a replay or a save snapshots the tree, as Stasis's `stasis inspect` and record and replay do.
- **One concept, not several.** Structs, fixed arrays and collections nest freely; a pool is just a field.

**Collections** (all bounded; the capacity is part of the type)

- **Collections are ordinary values.** A bounded collection has a fixed worst-case size (its capacity, with its text's size classes), so it can be a local, a field, a parameter (as a view, or in write or grow mode) or a result, like any fixed-size value. A local one over 4 KB gets its own region on the job's data stack (The job's data stack), is committed only as it's used, and is freed with its scope. Pushing into a local `list` never moves a stack top: its space was set aside when it was declared, so it isn't a growing value and needs no stack of its own. A loop variable over a collection the function may write (`for r in g.rocks`) is a writable view of each element, under the usual view rules: the loop may change the element's fields, but not remove elements from the collection or shift it.

| Type | What it is | Elements named by |
| --- | --- | --- |
| `T[N]` | a fixed array: always N elements | index `0 <= i < N` |
| `list<T, N>` | up to N elements in order, with a count; push, pop, insert, remove | index, valid until the list changes shape |
| `pool<T, N>` | up to N elements in stable slots (what tables were) | a typed id with a generation |
| `map<K, V, N>`, `set<K, N>` | up to N keys, hashed | the key |
| `queue<T, N>`, `ring<T, N>` | first in, first out; a ring overwrites its oldest | position |
| `grid<T, W, H>` | a W × H fixed array with 2-D indexing | `(x, y)` |

Adding to a full collection returns `Result`, which the code must handle (an unused `Result` is a build error; `main` and tests may return `Result`, and an `err` there prints the error and exits 1), unless the compiler proves it can't happen there (a loop pushing at most 500 items into a fresh `list<T, 500>`, say). A failed add leaves the collection unchanged. A ring is the exception: it overwrites, by definition. Writing a field is different: an ordinary assignment has no `Result`, so it must satisfy the field's refinement and maximum size at build time (The refinement contract), and a value that may be wider is a build error. Where failure is meant to be handled as a value, the code uses a checked conversion or `fit`, or a fallible capacity operation such as `try_append`. Updates stage fallible work before publishing it, so a failed checked operation leaves the old fields unchanged. When dropping the value is the intended outcome, `discard g.rocks.add(fragment)` says so (decided 2026-10-24): it accepts only the built-in capacity operations whose only error is `Full` (a collection's push, insert, add or set, and `try_append` on `Ascii`, `Text` and `Bytes`, and `Bytes.push`), never an arbitrary `Result`, even one whose error type is `Full`, and it's a word, never silent.

**Layout: structure of arrays, as Stasis lowers it**

- A collection of structs is stored as one array per field, so a loop that reads two fields streams through just those two arrays. `app.world.units[id].hp` reads the array `World_units_hp` at the id's slot.
- **Nested fixed-capacity collections flatten** (the target layout): each unit's `inventory: list<Item, 8>` becomes arrays of 4,096 × 8 items plus one count per unit, as Stasis flattens nested fixed arrays. So a collection inside a collection needs no pointers and no growing values; it's just more lanes. The current compiler still stores each nested collection's lanes inline per enclosing element (T06); PLAN.md's L1 flattens them before M4.
- **Fixed-size fields** (numbers, ids, enums, small records) sit in their array directly.
- **Variable-size fields** (text, bytes) can't sit in a fixed-width array, and nothing that stores them ever shifts bytes in use to close gaps: there's no compaction, which would be a contained garbage collector, with pauses that grow with the data (decided 2026-10-24). Instead:
  - *Stored values are inline at every bound:* an ordinary stored `Ascii`, `Text` or `Bytes` value (a local, a struct field, an enum or `Option` payload) holds its length, its code-point count for `Text`, and its bytes inline at their full maximum size (T29). Reading one gives a transient descriptor that borrows those bytes.
  - *Small collection lanes inline:* in a collection, a text or byte field whose maximum is 64 bytes or less (`Text max 16` is up to 64 bytes) sits in its lane at full size, with its length. Map and set `Ascii` keys are inline copies at every bound. No garbage, ever.
  - *Larger collection lanes in size classes:* the field's bytes go in a slot of the smallest class that fits: 128 bytes, 256, 512 and so on up to the class that holds the field's maximum. Each class has equal slots and its own free list, as a memory allocator keeps, and all classes' slots lie in one flat byte region after the collection's metadata. The lane holds a handle (the class and the slot's byte offset from the collection's base, T31), the length and, for `Text`, the code-point count; no address. A new value that fits the current slot is written in place; one that needs another class takes a slot from that class's free list and returns the old slot to its own. Nothing else shifts, and no write ever waits for a cleanup.
  - The cost is the space left unused inside slots. A value newly placed in a class uses more than half its slot (for values over 64 bytes), but a value shrunk in place can use less (a 300-byte text cut to 100 bytes in a 512-byte slot), and a 1-byte value in a 128-byte slot wastes almost all of it. The storage bound below (Bounds) holds either way.

**Pools and their ids**

- **Typed ids:** a pool's elements are named by ids, 64 bits: a 32-bit slot and a 32-bit generation counter. The id's type names its pool (`units.Id`, written `Id<app.world.units>` where that's ambiguous), so an id from one pool can't be used with another, even of the same element type. Removing an element bumps its slot's generation, so an old id no longer matches. Looking up an id returns `Option`: `none` for a stale id, never a dangling pointer. A slot whose generation reaches its maximum is retired, never reused, so wraparound can't make a stale id match again.
- **A slot is a fixed position, never moved:** a pool's arrays are indexed by slot, with holes where elements were removed. Each slot has an occupied flag and its generation, and the pool keeps a list of free slots for reuse. A lookup checks the slot is in range, occupied, and of the id's generation before reading any field. Elements are never moved to fill holes (moving the last one into a removed one's place would silently change which element an id names; Stasis's plain `pool` does that swap, and its `stable_pool` doesn't). Flags and generations are arrays like any other, so snapshots carry them.
- **Owner parameters in reusable definitions** (decided 2026-10-24; options in docs/reviews/sol-ids-r1.md). A definition that holds ids of its own kind of element takes an *owner parameter*, a compile-time name for one particular pool or batch, which is never stored in the data:

  ```
  struct Node<P> { parent: Option<Id<P>>, first_child: Option<Id<P>> }
  var nodes: pool<Node<nodes>, 4096>          // the pool is its own owner
  fn parent<P>(nodes: pool<Node<P>, 4096, P>, id: Id<P>) -> Option<Id<P>> {
      let node = nodes.get(id) ?? return none
      node.parent
  }
  ```

  - `Id<P>` is the same 64 bits as today (slot and generation; for a frozen batch, partition and row), with no owner bits and no extra comparison: the owner is checked by the compiler. `nodes.Id` stays as shorthand for `Id<nodes>`.
  - Each pool, local pool, builder and batch is a fresh owner, even when made repeatedly at one line (a loop that makes a pool each iteration makes a new owner each time). Owners can't be cast or attached to another collection, so mixing two pools' ids is a build error naming both: `expected nodes.Id, got other.Id`.
  - Helpers take owner parameters like type parameters, and the compiler infers them at call sites, so they're written mostly in definitions. A helper may return ids of a pool its caller owns, never of a pool that ends when it returns.
  - A definition with no self-links (a plain `Rock`) needs no parameter, and two pools of `Rock` just work.
  - Copying a self-contained pool makes a fresh owner for the copy and keeps the id bits, so its internal links still work; ids kept outside still name the original. Copies that would need external links rewritten are refused for now.
  - Resetting a pool under the same owner must keep its generation history (or is refused), since zeroing generations would bring stale ids back to life.
  - Frozen batches use the same model: every builder in a batch shares the batch's owner (`Node<b.Node>`), so cross-file links work, and freezing keeps the ids unchanged.
- A pool nested inside an array of structs (a pool per world in `worlds: World[4]`) would need its ids to carry the outer index; that's left for later. Frozen pools and database rows have ids of their own (see Frozen pools, Databases), and no id of one kind can be used as another.
- Invariants are declared on state and checked on every write (see Correctness).

**Who owns state**

- **The program:** a local declared in `main` (or the selected entry point), passed as `write` to any function that needs it. It lives on the entry point's data stack for the whole run. Its worst-case size is counted in that entry point's stack bound, and it may not be returned or stored; a function receives it as a parameter. A game's simulation is the typical case.
- **A function or a job: locals.** A struct or collection declared as a local (`let seen: set<units.Id, 500>`) lives on that function's stacks and is freed when its scope ends; one declared in a job's entry function lasts the whole job, which is all "job state" is (a type checker's cache, a request's working set). A local pool's ids are typed by the local (`seen.Id`, `cache.types.Id`), so they can't leave its scope or mix with another's. Locals aren't part of the startup claim: a local collection is a fixed-size value on the job's stacks (in its own region when it's over 4 KB), so it counts toward that job's computed stack bound and admission estimate, and `inspect stacks` reports it. Returning or copying a local collection copies its contents to the destination (or builds it there), so it stays valid after the source scope ends.
- **Shared state:** created in `main`, passed to jobs as a parameter with a `shared` type (e.g., `chat: shared Chat`). Many jobs on any workers read it while one writer changes it; jobs send it changes and `transaction { }` blocks (Thread kinds and jobs), and readers get an immutable snapshot, pinned once per read phase, never per element (Burin's model; details in Shared state across threads). Everything about snapshots, pins, blocks, reclamation and transactions applies only to shared state; the other kinds pay none of it. It is claimed once at startup with its worst-case bound.
- Several instances of one shared state (one per tenant, say) would need an instance field in its ids, and are left for later.

**Bounds**

- **Declared:** every collection has a capacity and every variable-size field a maximum; a missing one is a build error that names it. How all state together fits the process's memory is the admission budget's job.
- **In bytes:** `Text` maxima count code points, and a code point takes up to 4 bytes in UTF-8, so `body: Text max 2000` is up to 8,000 bytes: 100,000 messages can hold 800,000,000 live bytes of text. `Ascii` maxima count bytes, one per character, so `code: Ascii max 2000` is 2,000 bytes; fields known to be ASCII (codes, slugs, hex, identifiers, many names in games) should use it. The compiler works in bytes from here on.
- **Storage:** for each collection, capacity × fixed fields (with flags, generations, counts and inline fields), plus, for each variable-size field, every size class reserved for every element. The classes double, so one element's class slots add up to less than twice the largest class, and a field's class payload is under capacity × 2 × its largest class, however lengths shift between classes over time. That bounds payload bytes only: the full storage also counts the lane metadata (handles, lengths, code-point counts), each class's counters and free-slot indexes, alignment, the collection's header and every enclosing capacity, so bounds and `inspect memory` use the checked complete layout, not the payload estimate. A class can't run out while a legal write needs a slot in it: an element moving into a class came from another one, so at most capacity − 1 others are in it. How this memory is claimed is in Static allocation, below.
- **Relative positions are stable:** growing never compacts a collection's elements or moves them between its arrays or classes, so each element keeps its position relative to its collection. Shared state's storage never moves at all. A collection on a job's data stack moves with the whole stack when the stack grows (The job's data stack), so generated code holds offsets and derives addresses again after any call that may grow the stack.
- **Shared state's bound** is laid out the same way, plus slots and blocks freed but still visible to a pinned old version (returned to their free lists only when no pinned version can see them, capped by the budget for old versions) and one transaction's scratch, the blocks it copies and the new slots it fills (capped by a per-global transaction budget, so a transaction whose whole batch would pass it is refused before anything is published). It lives in RAM and is lost on a crash unless the program saves it (or keeps the data in a database instead).

**Static allocation** (decided 2026-10-24)

- **Shared state is allocated in full at startup.** Shared state (with all its collections, size classes, flags and generations, and budgets for old versions and transaction scratch) is sized by the compiler and claimed from the operating system in one piece when the program starts: reserved and committed. After startup the state never allocates and never grows its claim; a full collection is a `Result`, never an allocation failure. How firmly the operating system backs that claim depends on the platform, so the runtime checks at startup and refuses to start rather than rely on a promise the system may not keep:
  - *Windows:* committing charges the memory against RAM plus the page file, so a successful commit is a guarantee that the memory will be there.
  - *Linux:* committing is only a guarantee in strict overcommit mode (`vm.overcommit_memory = 2`); in the default mode the kernel can promise more than it has and kill a process later. And in a container, the kernel's per-group limit (cgroup `memory.max`, plus its swap limit) is separate again: a mapping can succeed and the group still be unable to pay for the pages, so the process is killed when they're first used. So at startup the runtime reads the overcommit mode and the effective cgroup limits, requires the state's claim plus the configured job headroom to fit them, and touches the state's pages before scheduling any job, which charges them to the group; outside strict mode, or if anything doesn't fit, it locks the state in RAM (`locked`, below) or refuses to start, by configuration. The guarantee holds while those limits stay as they were at startup; the operating system killing the process for other reasons is outside it. macOS and Android need their own policies, left for later. As in Stasis, the layout is known at compile time and `inspect state` prints it.
- **Touching is separate from claiming:** committed pages still cost physical RAM only when first written. `prefault` can be used on shared state at startup, which moves first-touch page faults to startup, but the operating system can still page memory out later. A deployment that must never take a page fault on shared state asks for `locked` too: the pages are locked in RAM (`VirtualLock` on Windows, `mlock` on Linux), and if the lock fails the program refuses to start. `inspect memory` reports the state claim and what is locked separately. Program state is part of the entry point's stack and is committed as used. Ordinary growable job stacks are committed as used and never locked; a `strict_stack` entry point may also ask for `prefault` and `locked` on its preprovisioned stacks (The job's data stack), and failing to get the backing or the lock refuses startup.
- **Initialised before use** (decided 2026-10-24). Every field gets its starting value in one of two ways, for locals and shared state alike:
  - *A default in the struct definition:* `struct Unit { hp: int 0 to 1000 = 100, … }`, as Stasis allows. Every value of that struct starts there unless told otherwise.
  - *Values given when the variable is initialised:* `var app = App { cfg: Config { level: 3 } }` in the entry point, or `let seen = set<units.Id, 500> {}` in a function. Given values override the struct's defaults; fields not mentioned keep them. Shared state's initialiser is evaluated at compile time when it depends only on constants, so the starting state is data in the binary; otherwise it runs once at startup, before the first job is scheduled, and may read configuration but do no other I/O.

  `list`, `pool`, `map`, `set`, `queue` and `ring` start empty unless the initialiser fills them; fixed arrays (`T[N]`, `grid`) need every element's value, from the element type's defaults or a fill (`Tile[64 * 64] = fill(Tile.grass)`). A field whose type has no valid zero (an `int 1 to 100`) and gets no default and no initial value is a build error that names it. The value is built unpublished: an initialiser can't read a field of the value it's building (`App { a: 1, b: a + 1 }` is a build error; compute it first with a `let`), each field's refinement is checked as it's given, and rules relating fields (`invariant start <= end`) are checked once on the completed value, before it's usable. For shared state that's at startup, before any job is scheduled; for a local (`let s = Span { start: 10, end: 20 }`) it's at its declaration, inside the running job, and a completed value that fails fails the job without anyone seeing it partly made. Defaults and state restored from a save get the same completed-value check, so a program never runs with invalid state; once a value is usable, the every-write invariant rule applies as usual.
- **Stacks are not static.** Data stacks, native stacks, job state and frozen batches belong to jobs, and jobs come and go, so their address ranges are reserved as needed and committed as they're used: a data stack starts small and grows up to its cap (The job's data stack), and the others stay within their bounds (Loops can't quietly fill a stack). Admission limits how many jobs exist at once. The difference: a global's worst case is paid once, for the whole run; a job's worst case would be paid per job, and most jobs use a fraction of it.
- **Foreign code** keeps its own allocation unless configured: SQLite can be handed a fixed memory region at startup (its `SQLITE_CONFIG_HEAP` option, which needs SQLite built with one of its fixed-heap allocators, `MEMSYS3` or `MEMSYS5`), and the binding generator does so and checks that the configuration call succeeded before starting. Other C libraries' allocation is outside the guarantee, and the audit report lists them.
- **Reported:** `inspect memory` prints the startup claim (shared state budgets, foreign fixed regions) and, separately, the per-entry-point worst case (program state's part of it) and per-job worst cases. It warns when shared state's startup claim passes a configured budget (64 MB by default), so heavy shared state is a visible choice, not an accident; a deployment that needs more raises the budget in configuration.
- **Reported:** `inspect state` lists, per path, the byte bound, the reserved address space and the committed memory, separately; for shared state also the budget for old versions, and for frozen batches their totals.
- **Shared state isn't on a data stack:** its memory comes from the startup claim. Program state is a local, so it is on its entry point's data stack and counted in that stack's bound, like any other local. A job uses a stack only when it copies something out of state; reading through a view copies nothing.

| | Program state | Locals (and job state) | Shared state | Database (separate feature) |
| --- | --- | --- | --- | --- |
| Lives in | entry point's data stack | job's data stack | RAM | the database (disk) |
| Who changes it | passed as `write` to functions on the same entry point | the function or job that owns it | one writer | the database, through transactions |
| Who reads it | functions receiving it as `write` or `read` | its function or job | any job, through a snapshot | any job, through queries |
| Bound | capacities and field maxima, part of entry point's stack | the same, reserved when created, committed as used | the same, plus old versions | disk, plus an optional quota per deployment |
| Survives a crash | no (unless saved) | no | no (unless saved) | yes |
| Extra cost | none | none | snapshots, pins, transaction scratch | a query per read |
| Typical use | a game simulation's world | a cache, a request's working set | live data many workers need: presence, a shared game world | a server's records |

**Stacks** hold temporaries.

- Each job (a request, a tick, a task) runs on one data stack (The job's data stack): an address range that starts small and grows by moving, with a bump pointer, holding its values in regions.
- A growing value that may keep growing while other values are placed above it gets a region of its whole declared maximum, reserved ahead (see How the compiler places values). So growth is the value's length moving up inside its region: nothing is copied, and the value keeps its offset in the stack even when the whole stack moves.
- Fixed-size values sit in registers or the native stack; small arrays too (up to 4 KB, as Burin's helpers do).
- A scope's memory is freed by setting its stacks back: one store each. Kept pages stay mapped for the next job (time over memory).
- **Growth is bounded by design** (see Loops can't quietly fill a stack): every value a loop keeps growing has a maximum the compiler knows, so most entry points have a worst-case stack size computed at build time.
- **Growing past a stack's cap fails the job** (decided 2026-10-24), which bounded growth makes rare: the request, tick or task ends with an error and goes through the job-failure steps (see Types, Failures). The program keeps running. Code doesn't handle a `Result` on every push; the check is one predictable compare.

**References** exist only as parameters: a function may read, write or grow what it is handed, but cannot store or return a reference. So no lifetime annotations are needed, and Goose's "roots" check reduces to a call-graph rule.

**No overlapping arguments:** a call may not pass two arguments whose memory could overlap when either is written or grown. The check works on what each argument is part of (its owner: a local, a parameter, a row) and the fields or index ranges it covers, not on how the expressions look: passing a record for reading and one of its own fields for writing is refused, while two different fields of one record, or `a[0..n]` and `a[n..m]`, are allowed because they're provably apart. Where the compiler can't prove two arguments apart it refuses the call and says so. That proof, and only that proof, is what lets it give LLVM `noalias` (a promise that two pointers never refer to the same memory).

**Copies and moves of growing values:**

- `let b = a` copies `a`'s bytes; both stay usable. `let b = take a` moves it instead: no copy, and `a` can't be used after. Passing a growing value to a read parameter neither copies nor moves.
- Returning a local moves it. When the local was built on the caller's destination (the usual case, which the compiler arranges when it can prove it safe) the move costs nothing; otherwise the result is copied from scratch onto the destination, and the bounds count both while the copy runs.
- Returning a read-only parameter, or anything read from state, copies it, since the function doesn't own those bytes. Views can be passed in but, like any reference, not returned in v1; returning a view would need a lifetime rule, which is left for later.
- Three cases the first implementation tests: `fn f(s: Text) -> Text { s }` copies; `fn f() -> Text { let t = build(); t }` builds `t` on the destination, no copy; and `acc = merge(acc, x)` in a loop updates `acc` in place when the compiler proves `merge` qualifies, and otherwise copies down over `acc` (Loops can't quietly fill a stack).

Between the two: a value moves from a stack into state by copy (`app.world.units.add(Unit { … })`), and from state onto a stack by reading fields. Reading a large field needn't copy: a function can take a read-only view of it (see Frozen pools). (One current exception: an element of a collection of large structs passed to a function is gathered into contiguous scratch and, for `write`, scattered back after the call; O4 in PLAN.md replaces that with the collection's offset plus the element's index, read in place.) Database rows have no views: a query's result is copied onto the stack (see Databases).

**Views of state that can change:** a snapshot's or a frozen pool's storage never changes, so views of them are safe for the whole read phase. Program state, job state and builders are mutable. Adding an element can't shift a collection's elements or its arrays relative to it (they're reserved at its capacity; a view holds offsets, so a move of the whole stack doesn't invalidate it), but removing an element or replacing a text field can invalidate what a view points at, and so can any change that shifts a `list`'s elements (an insert or remove in the middle). So a view's owner is the collection's storage, not the element, and while any view of a mutable collection is live, the compiler refuses the changes that can invalidate it: removing elements (which frees their slots), shifting a list, and replacing a variable-size field (which writes over its slot or frees it). Adding elements to a pool, or pushing onto the end of a list, is allowed. Writing a fixed-size field of a different element is allowed, because the overlap check proves it apart. The view must end first. And a view of mutable state can't be live across a call that may suspend: while a job waits, another job on the same worker may change shared state. The compiler refuses such a view and names the call.

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

A fixed set of threads, one per core. Each job owns one data stack that only it touches while it runs. So the common operations (push, free a scope, read state) take no locks and no atomic operations (the special CPU instructions threads use to update shared memory safely, each costing far more than an ordinary store), and nothing mutable is shared.

### How a program divides into jobs

A **job** is the unit that owns stacks: its own data stack and native stack, isolated from every other job's. A new job starts only where work may run at the same time as its caller or outlive it. Everything else is an ordinary call on the caller's stacks, whose scratch is freed when it returns.

| Piece | What it is | Its stacks | What it receives |
| --- | --- | --- | --- |
| `main` | the program's first job: creates program state, shared state and capabilities, then runs or hands off | its own, for the whole run | `env` and configuration |
| A call | ordinary code | the caller's | parameters: read, `write`, `grow`, `take` |
| A request job (`page`, `action`, `api`) | one per request | its own, from the worker's pool, reset afterwards | the request's values, capabilities from `serve`, `shared` handles |
| A spawned job | concurrent or background work | its own | see "Spawning" below |
| A service job | a long-lived job that loops over a queue and owns its state as locals | its own, for its lifetime | copies of flat values, capabilities, `shared` handles, queue ends |
| A parallel loop's chunk | one piece of a `parallel for` | its own scratch, freed at the join | read-only views of the caller's values; it writes only its slice of the result |
| The writer | one per shared value | its own | change batches and `transaction` blocks |

- **Program state** is a local in `main`, passed down as `write` (one state struct, so a deep call chain passes one parameter). It can't be handed to another job: two jobs would then share mutable memory, and the compiler refuses it. Live data other jobs need is a `shared` value or the database.
- **A game** runs inside main's job: the host's loop calls `tick` and `draw` (The game host), so frames cost no job start or copy.
- **A server's** `main` opens the database, creates its `shared` values and calls `serve`; each request is a job with its own stacks, so its memory is bounded per request and freed by resetting its stack.
- **A service job** is how a component keeps mutable state of its own that isn't shared and isn't in `main` (a cache, a log writer, a game's audio mixer): other jobs reach it only by queue. The writer for shared state is the built-in case of this pattern.
- **Choosing a form:** CPU work over data is a `parallel for` (structured, chunks read without copying, results in a fixed order); independent concurrent tasks are spawned jobs; I/O concurrency is straight-line code, since a waiting job suspends and its worker runs others; data many jobs read while it changes is a `shared` value; large read-only data built once is a frozen pool.
- **Entry points:** the functions that may start jobs are `main` and those marked `@[job]` (or a server kind that implies it; Function attributes), each with its own stack cap, `strict_stack` and time limit, which the manifest can override per deployment. With no globals, a job's inputs are exactly its parameters, which is what the compiler's per-entry-point stack bounds and `inspect stacks` are computed from.
- **Spawning** (open question, below): the direction is structured concurrency. A spawned job lives inside a scope that waits for all of them, cancels the others when one fails and passes its deadline down; because the parent waits, children may take read-only views of the parent's values without copying, as parallel loops do. Jobs that outlive their starter (services) are started with an explicit form and take only copies and queue ends.

### Thread kinds and jobs

- **Workers,** one per core, pinned. Each runs jobs: `main`, requests, spawned and service jobs, and parallel loop chunks.
- **Jobs can wait** (decided 2026-10-24). A job that waits for I/O (a call to another service, a slow file, a timer) is suspended and the worker runs other jobs meanwhile; when the I/O completes, the job resumes on the same worker where it stopped. Code reads straight-line, with no `async` in source (Go's goroutines work this way). A suspended job keeps its own native stack and its own one data stack; that's what makes resuming possible.
  - Only some calls can suspend, and the compiler knows which: every function has a *may suspend* property, inferred across calls like an effect. The calls that suspend directly are I/O (`net`, `fs`), `clock` sleeps, `spawn` joins, a parallel loop's join, and sending a change to a shared set's writer (it waits for the reply), and database queries and transactions. Before a call that may suspend, a function writes its cached stack tops back to memory, as it does before any call that can reach those stacks. `spawn f(...)` starts a job and returns a `Job<T>` for f's result type; `join` waits for it and gives f's own return value (a `Result` if f returns one), and a job that fails (a crash, not an error value) fails its joiner too. How many spawned jobs run at once is under admission. Scoping and the form for long-lived jobs are an open question (How a program divides into jobs).
  - Each worker keeps a pool of free data stacks (one per job), so starting a job takes one from the pool, not a system call (The job's data stack: stacks are pooled per worker and keep their memory while it's used, trimmed by recent peaks).
  - A job doesn't move between workers in v1. That keeps every stack single-threaded, with no locks.
  - **A snapshot pin never spans a wait,** with one exception below. Before a call that can suspend, the job's views of the snapshot must have ended (the compiler refuses a view live across such a call) and the runtime releases its pin. After the wait the job pins the then-current snapshot, so what follows is a new read phase that may see newer data. A waiting job therefore never holds old versions of shared state alive, and can't stall the writer.
  - **The exception, a parallel loop's join:** the chunks read the snapshot the caller had pinned, so the caller's pin is held, structured, until every chunk has stopped. Chunks use that root, never a newer one, and don't pin on their own. That retention counts against the slow-reader budget like any pin, and it's bounded by the loop's time limit.
  - **Time limits are enforced on waiting jobs too:** a job past its deadline is cancelled by the runtime, whether running or suspended (its pending I/O is cancelled), and goes through the job-failure steps. A running job notices at its next cancellation poll: loops that keep a step budget check it there, and loops that provably end (and so drop the budget) still poll a cancellation flag in the job's context every few thousand iterations, one load and compare. A foreign call that doesn't return can delay this; the deadline is enforced when it does.
  - **Admission:** a worker starts a new job only while committed memory (plus headroom) stays under the configured limits; past them, a request gets a "busy, retry" response (HTTP 503 with `Retry-After` for servers) and other jobs wait in a bounded queue.
- **The writer,** one per shared state. It applies change batches in order and publishes snapshots (Burin's model). Workers send it change requests on a queue and wait (suspended) for the reply.
- **Transactions** (decided 2026-10-24): each change request is one batch, applied all or nothing. Changes that must succeed together go in one `transaction { … }`, which is sent as a single batch. Once the writer has committed a batch it stays committed: a job that fails later doesn't undo it, just as an email it sent can't be unsent. A transaction's value is its block's value, so it can return a result (`ok(true)`); `?` inside one aborts it, discarding its changes, and the transaction's value is that error.
- **A transaction decides on the writer** (decided 2026-10-24; this is for shared state, and databases have their own transactions, see Databases). If two jobs read the same snapshot showing one item in stock and each sends "set stock to zero, record a sale", both sales succeed. So a transaction's body, its checks as well as its writes, runs on the writer against the writer's latest version, as Burin's actions do. Inside it, reads see that latest version, not the job's snapshot. A transaction body can't suspend (no I/O, no waits) and has a step budget, so it can't stall the writer. Values the job computed earlier go in as arguments. The alternative, version-checked writes that reject a decision made on stale data and make the job retry, is left for later if writer time becomes the bottleneck.
- **Inside a transaction:** the writer builds the batch as a private tentative version. Reads in the body see the latest published version plus the body's own earlier writes. If a check fails or the body fails, the tentative version is discarded and nothing was changed; on success the writer publishes it, then replies to the job. In v1 a transaction touches one shared global.
- **Sending vs writing:** a job sending a change or a transaction to the writer suspends until the reply (a may-suspend call). Writes inside a transaction body run on the writer itself and never suspend.
- **Reads, two kinds:** ordinary reads of a shared set see the job's pinned snapshot; reads inside a transaction see the writer's tentative version. (Program and job state are read directly by their owner; databases are read through queries, see Databases.)
- **Batch states:** queued, applying, then committed or aborted. If the sending job fails while its batch is queued, the batch is cancelled; if it's being applied, the writer finishes or aborts it and acknowledges before the job's cleanup frees the buffers the batch was sent from.
- **Parallel loops** borrow the workers (fork and join) rather than starting threads.
- The thread count is fixed at start (configured; the number of cores by default).

### The job's data stack

**One data stack, reserve ahead** (decided 2026-10-24; Ben chose this after comparing three options, and it replaces both "N stacks, one per growing value" and the interim "build above, then slide down" rule; the review behind it is docs/reviews/sol-fewstacks-r1.md).

- **Each job has one data stack:** an address range with a bump pointer and a guard page (an unmapped page that traps if touched) at its end; it starts small and moves to a larger range when it needs to grow (below). Pages are committed on first touch and kept between jobs (time over memory) until trimmed. v1 has no second data stack.
- **Values live in regions:** a region is a byte range on the stack, freed last in, first out with its scope, like an ordinary stack frame. Fixed-size values over 4 KB (a big local collection, a sort's scratch) get regions too; under 4 KB they stay in registers or on the native stack.
- **Reserve ahead:** a growing value that may keep growing while other values are placed above it (a builder like `render`'s `out`) gets a region of its whole declared maximum, reserved when it's created. Later values go above that region, and the builder grows inside it, so nothing is ever trapped underneath and nothing is copied. Reserving costs address space, not memory: the operating system only provides pages that are written, so a 40,000-byte region holding 2,000 bytes uses one page of RAM. Three independent builders open at once just sit in three regions, one after another. Within a block, the compiler plans the regions of the block's own locals at block entry: those up to 64 KiB first, then the larger reserve-ahead regions, so small values stay close together (T30); scopes still free them last in, first out.
- **Tight packing where it's safe:** a growing value that's provably finished before anything is placed above it (a temporary built and consumed in one expression) needs no reservation beyond what it uses; the compiler packs it at the top. Sliding a finished piece down over dead temporaries (with a `memmove`, a copy that's safe when source and target overlap) is an optimisation the compiler may use for small builders that are provably built nested, not a rule; `inspect stacks` lists where it does.
- **Budget:** the stack's worst case for an entry point is the sum of the regions and temporaries that can be live at once, which the bounds already give (Loops can't quietly fill a stack). The compiler computes this conservative bound for each entry point for inspection, warnings, admission estimates and `stack_peak`; it doesn't size the stack. Ordinary stacks start small and grow to their cap, including when the bound is unknown; only `strict_stack` provisions the full computed bound at startup (below). A program that reserves a 1,000,000-byte region for a value usually holding 10 bytes pays a megabyte of address space and one page of memory, and values above that region are a megabyte away in memory, which matters a little for the CPU cache; `inspect stacks` lists regions over 64 KB so that's visible.
- **References into the data stack are offsets, not addresses** (decided by Ben 2026-10-25; X1 measured it: with the base cached in a register, tight list loops, struct-of-arrays loops, calls and builders run within noise of pointer addressing at -O1 and -O3, and a move costs a few microseconds; see The theory being tested). Every reference the generated code keeps into a job's data stack (a region, a collection's lanes, a text or byte payload, a view, a `write` parameter, a hidden result destination, the cached top) is an offset from the job's stack base, which the job context holds and the compiler keeps in a register like the top. An access is `base + offset`. Because nothing refers to the stack by address, the stack can move: when a region or an append doesn't fit, the runtime moves the whole stack to a larger range (on Linux with `mremap`, which moves page mappings without copying bytes and leaves untouched pages untouched; on Windows by copying only committed chunks), starting small (see Starting size, below) and at least doubling each time. Rules that make this safe:
  - a raw address derived from the base lives only between growth points: after any call that may grow the stack, the base is reloaded, and the checker refuses holding a derived address across such a call;
  - foreign calls and runtime I/O get raw addresses and pin the stack (it can't grow until they return);
  - offsets belong to one job's stack; they never go into shared state, other jobs' data or results that outlive the stack (the existing escape rules already forbid that);
  - parallel chunks get offsets into their parent's stack, which can't grow while the parent waits at the join.
  Offsets are 64 bits. A 32-bit form scaled by 8 (32 GiB per job) is only a possible later proposal: X1 didn't measure it, and it would have to state its alignment rules, how it fits the 64 GiB default cap, and its overflow checks before any decision (O8 in PLAN.md). Stored data stays inline or index-based (T29), so offsets are only in what running code holds and in descriptors of values that refer to bytes elsewhere on the same stack. The rules below describe this one design; the compiler reaches it through the offset milestone (Implementation status, below).
- **Start small, grow by moving, commit only what's used** (decided 2026-10-25; this is the single data-stack design, combining Ben's reservation and offset decisions):
  - **Starting size** (Ben, 2026-10-26): the compiler computes a **typical-run estimate** per entry point with the same analysis as the worst case (T17), except that every loop is assumed to run at most 5 times (looped data: collections filled in a loop, builders appended to in a loop, any per-iteration growth) and recursion at most 5 levels deep; values not built in a loop count at their computed size (a `Text max 10000` built from one `str(n)` counts its digits, not 10,000 bytes). A stack's first job starts at that estimate rounded up to the next power of two, at least the platform's page size (4 KB on x86-64, up to 64 KB on some arm64 systems), plus the guard page. Later jobs start at 1.25 times the entry point's recent allocation high-water (from the pool's history, below) when that is larger. A reserve-ahead builder still claims its declared maximum as address range when it's created, so the stack may move to a larger range at that moment; that costs a move, not memory. The worst case (T17) doesn't decide the starting size; it is what `inspect stacks`, `stack_peak` and the build warnings report, and `inspect stacks` also shows the typical-run estimate.
  - **Growth:** when a region, a reserve-ahead builder or an append doesn't fit, the runtime moves the stack to a range at least twice as large (or large enough for the request), as the offsets bullet describes; nothing refers to it by address, so nothing needs fixing up. Reserve ahead still gives each growing value a region of its declared maximum, but that region is address range inside a stack that can keep growing, not something the whole stack must reserve up front.
  - **Growth limit (the cap):** a stack may grow to at most its cap, default 64 GiB (chosen by Ben 2026-10-25), set per entry point in the manifest (`stack_reserve.main = "8 GiB"`). Past it, the job fails with `data stack range exhausted` (through the job-failure steps), never a crash. A single region larger than the cap can never be placed, so the build warns about it, and about a computed worst case above the cap (naming the entry point and the critical path). An unknown or overflowing bound simply grows until the cap.
  - **Commit:** pages are committed only as written. Linux: anonymous mappings backed on first write; under strict overcommit (`vm.overcommit_memory = 2`) a growth that the commit limit refuses fails the job like the cap. Windows: `MEM_RESERVE` for each range and commits in 64 KB chunks wherever a range is first written (region initialisation, appends, copies, runtime I/O destinations), with checks hoisted where the compiler proves the range, benchmarked in tight loops first; a move copies only committed chunks. A growable list, map or builder touches only its live part (T23).
  - **Measures kept apart:** *reserved* (address range), *committed* (charged or backed), *resident* (in RAM now, which `mincore` samples), and two measures of a job's own demand, never one number: its *allocation high-water* (the highest offset it allocated) and its *written pages* (the pages it wrote, not counting commitment it inherited from earlier jobs on a pooled stack). A sparse job, such as one with a large reserve-ahead region it barely uses, has a high allocation high-water and few written pages. Admission, trimming, clearing and reports each name which measure they use.
  - Running out of host or container memory while touching pages is not a recoverable job failure on Linux (the kernel or the cgroup's `memory.max` may kill the process); admission (below) and `strict_stack` are the defences. The build-time bound sizes nothing at runtime except under `strict_stack`; it drives warnings, admission and `stack_peak` tests.
  - **`strict_stack`** in the manifest (per entry point): start the stack at the full computed worst case, committed at startup (so it never grows or moves during a run), and refuse to start if that doesn't fit, as shared state does (Static allocation). It guarantees data-stack capacity and backing, not freedom from page faults or paging: combine it with the separate `prefault` and `locked` policies for that. A strict entry point with an unknown bound, or a bound past its cap, is a build error. Strict stacks are never trimmed; with the job scheduler, a strict entry point declares how many may run at once, and that many are provisioned at startup.
- **A rows layout as an opt-out** (Ben, 2026-10-26; low priority, after the self-hosted compiler works end to end): a collection of structs is stored as split fields (one lane per field) by default; a collection may instead ask for rows (each element's fields together), spelled per collection (for example `list<Record, 1000, rows>`; the final spelling is decided when it is built). It is a property of the collection, not the struct, so one struct can be stored either way. Meaning is identical (indexing, loops, `write` parameters, equality, printing); only speed, padding and foreign compatibility differ: rows suit code that uses whole elements, random access to whole elements and foreign arrays of structs (which require rows), and a `write` parameter on a rows element is simply its offset. `inspect memory` shows each collection's layout and the padding rows cost. Grouping hot and cold fields is left until needed.
- **Unbounded collections grow at the stack's tail** (Ben, 2026-10-26): a local collection or a local `Text`/`Bytes` builder may declare its capacity as `unbounded` (`list<Entry, unbounded>`, `Text max unbounded`). It is opt-in and never the default, and it isn't allowed in shared state, struct fields, elements of other collections, or `strict_stack` entry points. Its storage is the top region of the job's data stack, and it grows by bumping the top, so it stays contiguous and is never copied; when the stack needs more room it moves (offsets). Rules the checker enforces:
  - it may grow only while it is the topmost live region: at every growth point (`push`, `try_append`, `+=`), no region created after it is still alive. Temporaries are freed before the growth (a call's regions are gone when it returns, and an element being pushed is built straight into the next slot at the top);
  - growing it after a longer-lived region was created above it is a build error naming both values, suggesting finishing the collection first or creating the other value earlier;
  - if a second unbounded value is opened while the first is alive, the first is frozen at its length until the second's scope ends (last in, first out);
  - a function may build an unbounded collection at its top and return it: the region becomes the caller's top region without a copy, and the caller may keep growing it under the same rule.
  The entry point's computed worst case reads "unbounded" in `inspect stacks` and the build warnings, naming the collection; at run time growth is capped by the stack's growth limit (`data stack range exhausted`), and a manifest can forbid `unbounded`. Appending costs the same inline bump and compare as any stack allocation. **An unbounded collection of structs is stored as rows** (Ben, 2026-10-26): whole elements together in one contiguous lane, since several split-field lanes can't all grow at the tail without moving bytes; bounded collections keep split fields by default.
- **Stacks are pooled per worker and keep their memory while it's used.** Each worker thread owns a small pool of data stacks, one data stack per job. A job takes one when it starts and owns its allocation, base and top exclusively until it finishes or fails (parallel chunks may still read and write disjoint, caller-owned slices of it within a join, as Parallel loops describe; the stack can't move while the parent waits at the join). Suspended jobs and parents awaiting a join keep their stacks; only a stack whose job has finished cleanup (Failures, steps 2 to 5: I/O, chunks and writer access stopped) returns to the pool. A pooled stack keeps its current size; the next job's own cap is enforced on it. Pages a stack committed stay committed when it returns (time over memory) until trimmed by the rule below. Reused pages aren't cleared between jobs, which is safe because the language never reads memory it hasn't written (T23's dirtied-page tests cover this); `clear_stacks_between_jobs` in the manifest, for servers that want no leftovers between tenants, discards every page the job could have written, from the base to its allocation high-water mark, including failed appends, dead temporaries and its native frames (`MADV_DONTNEED` on Linux, so later touches see zero pages; decommit and recommit on Windows), never zero-filling the whole range.
- **Trimming follows recent demand, per entry point.** The runtime records each job's allocation high-water and written pages (not the stack's inherited commitment, which would hide a small job's real need), keyed by entry point within the process (a request handler and a nightly report differ, and one worker runs both), keeping the last 16. Commitment is trimmed by written pages: when a pooled stack's last 16 written-page counts for the entry points it served were all under half of its committed bytes, and at least 16 samples exist, committed pages beyond 1.25 times the largest of those counts (rounded to pages, never below a 256 KB floor, the guard page untouched) are given back: `madvise(MADV_DONTNEED)` on Linux (contents discarded, later touches zero-filled), `MEM_DECOMMIT` on Windows. Which pages a sparse stack keeps (written pages spread far above the base) is still to be specified. The address range is shrunk by allocation high-water: a pooled stack whose range is far larger than its recent allocation high-water may be shrunk or replaced by a smaller one, since nothing points into it while it's pooled. A later bigger job just grows again, paying first-touch faults and a move (measure that first-job latency). A pooled stack unused for 5 minutes is trimmed to the floor, and spare pooled stacks beyond a worker's warm minimum (one per worker) are released; suspended jobs' stacks are never trimmed. The numbers are defaults a manifest can change. Trimming runs off the hot path.
- **Admission** (Thread kinds and jobs) counts committed memory once across pooled, running and waiting stacks, plus shared state, snapshots, frozen batches, native stacks and runtime overhead, against the process or container limit, with a configured headroom; jobs that grow after admission are bounded by their caps and the headroom, so admission is a strong heuristic, not a guarantee (`strict_stack` is the guarantee). Job count and reserved address space have their own limits. Memory history may change when a resource failure happens or how long a job takes, never a successful result, a parallel reduction's order or replay.
- **Implementation status (2026-10-26):** stage 0 (Rust nlc, frozen, PLAN.md "Stage 0 freeze") addresses the data stack by pointer, reserves each entry point's computed worst case up front (T17) and runs one job per process; it keeps that, with only its O1 offset slice, and is not converted further. The self-hosted compiler implements this design: it emits offset addressing only, and its core library gains the moving, growing stack when E3 first needs data-stack regions. Pooling, demand histories, trimming, clearing between jobs and admission belong to the scheduler milestone; Windows commitment and `strict_stack` are separate later tasks; until each lands, its manifest settings are rejected.
- **Address space, worked out:** 64-bit Windows and Linux give a process up to 128 TiB of user address space (less on some kernels and configurations, other mappings use part of it, and `RLIMIT_AS`/`ulimit -v` can limit it further). Because stacks start small and grow only as needed, address space follows real demand: 10,000 waiting jobs that each used 256 KB hold about 2.5 GB of address space, and typical-run estimates for small handlers are often a few KB. The 64 GiB cap bounds how far one job can grow. Only touched pages use memory: the self-hosted parser touches about 60 MB on a 54,000-line package. The 256 KB floor applies to warm pooled stacks; suspended jobs cost only what they touched; the validation target for 10,000 waiting jobs is measured with fresh and with previously busy stacks.

### How the compiler places values

The compiler gives every function a **stack contract**, computed from its body and its callees, the way a type is:

- **Byte requirement:** the most bytes the function and its callees can need above where it's called (its temporaries, regions and their callees'), and whether it needs a reserved region from its caller. A caller passes the current top as a hidden argument; the callee places everything above it. Function types carry the requirement, and a call through a function value uses the largest over every function that fits the type.
- **Inputs:** each reference parameter's mode, read, write or grow, written before the type (decided 2026-10-24: `g: write Game`, `out: grow Text`; read is the default and unwritten). A `grow` parameter is a builder in its own reserved region; the callee grows it within that region.
- **Output, two contracts:**
  - *Fresh result:* a function returning a growing value builds it into a destination region its caller reserves (the result's declared maximum), passed as a hidden argument. The destination takes part in the overlap check like a parameter. A result built there is returned with no copy.
  - *Append:* when a call's result goes straight into a builder (`out += line(r)`), the callee runs in append mode: it gets the builder's region, its accepted length (what's already part of the value) and its remaining capacity, writes past the accepted length, and returns how much it wrote. The caller publishes the new length only on success. Each append saves a **checkpoint** (the builder's length and, for text, its code-point count, and the stack top) first; a failure (`Full`, or an error from a fallible producer) restores it, even after part of the output was written, and nested appends each restore their own checkpoint, so an inner success disappears if an outer step then fails. A function that can't run in append mode (it reads the builder, say) builds its result in a temporary region and copies it.
- **No aliasing between regions:** distinct regions never overlap, which is what lets the compiler give LLVM `noalias` for them; it does so only where it's proved.
- **Moves:** `take` transfers ownership and cleanup, not position: the bytes stay in their region until the new owner's scope ends. A move that would have to outlive the region's enclosing scope is refused for now.
- **A worked example.** `render(rows)` returns an `Ascii` and calls `line(r)`, which also returns an `Ascii`. The bounds are part of the example, since the loop rule needs them:

  ```
  struct Row { name: Ascii max 60, count: int 0 to 999999 }
  // report: shared Report, passed to the job; struct Report { rows: pool<Row, 10000> }

  // rows: a read-only view of up to 500 rows of report.rows in the job's
  // snapshot; a bounded list<Row, 500> copied onto the stack would also be
  // legal, but the view avoids copying the rows
  fn render(rows: view Row max 500) -> Ascii max 40000 {  // a fresh result: the caller reserves 40,000 bytes
      var out = Ascii.empty()          // out is the result, built in that region directly
      for r in rows {                  // r: a view of one row
          out += line(r)               // line runs in append mode: it writes into out's region
      }
      return out
  }
  fn line(r: view Row) -> Ascii max 80 {  // 60 + 2 for ": " + up to 6 digits = 68, within 80
      let name = ascii_upper(r.name)      // a temporary placed above out's region
      return name + ": " + str(r.count)   // streamed into out's region past its accepted length
  }
  ```

  The caller reserves `render`'s 40,000-byte destination region; `out` is built in it. Each call to `line` places `name` (at most 60 bytes) above that region, then streams `name`, `": "` and the digits straight into `out`'s region past its accepted length; `render` publishes the new length, and `name`'s space goes back at the end of the iteration. One data stack, no copies. The worst case is 40,000 bytes for `out`'s region plus 60 for `name`, plus small descriptors and alignment.

  The bounds add up, and each helper's result bound is part of its contract. `ascii_upper` changes only the letters a to z, so its result has exactly its input's length, and `": "` and `str`'s digits are ASCII too, so `line`'s result is `Ascii`. 500 rows × at most 80 bytes is 40,000 bytes, `render`'s declared maximum.

  The same example with `name: Text max 60` shows what `Ascii` saves. Text maxima count code points of up to 4 bytes, so `out`'s region would be 160,000 bytes. And a full Unicode `upper` can lengthen text (`ß` becomes `SS`, so 60 of them become 120); its contract says so (at most 3 times the input's code points), which would make `line` need `Text max 200` and the region 400,000 bytes.
- **Recursion** (opt-in, on functions marked `recursive`, decided 2026-10-24): a recursive cycle may not keep a region alive across its recursive call (neither a builder nor a large fixed value), so each level frees what it placed before recursing; the compiler refuses the function otherwise and names the value. Every recursive call checks the native stack against a byte budget (one compare); passing it fails the job.
- **The native stack** (the ordinary call stack that holds return addresses, locals and small arrays): each job has its own, reserved from its entry point's worst case. Without recursion that worst case is known at build time, because every function's frame size is (LLVM reports it, from the optimised code actually built) and the deepest call chain is in the call graph. With recursion it's that plus the recursion budget. Before a foreign call it checks for a fixed margin (64 KB by default, configurable per binding), since C's use is unknown. The native reservation and its touched pages count in admission and in the waiting-jobs measurement.

### Loops can't quietly fill a stack

A bump stack frees nothing until its scope ends, so a careless loop can fill one: a temporary per iteration that piles up, rebuilding an outer value (`s = s + piece`) so each old copy is trapped under the new one (memory that grows with the square of the size), or appending to an outer value with no limit. The language rules out all three (decided 2026-10-24):

- **Every iteration is a scope.** Temporaries made in a loop body are freed when the iteration ends, including on `continue` and `break`. Only the iteration's own temporaries go back: builders that live outside the loop (`out` in the worked example) keep the length they've grown to inside their reserved regions, and the stack top returns to where the iteration started, which costs a register move. Nothing made in an iteration survives it unless it's written into a value that lives outside the loop.
- **Results go straight to where they're kept.** `out += f(x)` runs `f` in append mode (see the append contract in How the compiler places values), so keeping a result costs no copy and leaves no temporary to collapse.
- **Rebuilding an outer value never traps the old one.** `s = s + piece` compiles to an append in place. A reassignment from a direct call (`buffer = f(buffer)`) also updates in place when the callee has one matching `write` or `grow` parameter, the argument is the assigned local itself, the callee returns that parameter on every path, and no other argument aliases it (T30). Any other reassignment of an outer growing value (`acc = merge(acc, x)` where `merge` doesn't qualify) builds the new value in a temporary region above and copies it into the old value's region. The memory stays bounded by two values, the old and the new, during the copy, never by the sum of all iterations; the compiler counts that two-value peak in the bounds and reports the copy in `inspect stacks` with a suggested `write` or `grow` rewrite, since it costs time per iteration.
- **A value a loop keeps growing must have a bound.** Either its type says so (`list<Hit, 10000>`, `Bytes max 1 MB`, `Text max 4000`), or the loop is counted over a bounded input and each iteration's growth is bounded (`for r in rows` with `rows: view Row max 500`, appending a `line(r): Text max 80` each time, is 500 × 80 code points). The bound is on what each iteration adds, so a helper that formats a piece declares its own result's maximum, separators included. Without either, it's a build error that names the value and the loop, and offers both fixes. At run time, an append past a declared maximum returns a `Result` the code must handle (`out.try_append(x)`), or is proved impossible.
- **Bounds come from where data enters.** Request bodies, files, and state and database fields have declared maxima (`Text max N`, `Bytes max N` on the input or field; state's and databases' are required), so a bound found at the edge carries through the code.
- **The compiler adds it up.** From the bounds it computes each entry point's worst case for its data stack and its native stack, for inspection, warnings, admission estimates and `stack_peak` (The job's data stack; only `strict_stack` sizes a stack from it). `inspect stacks` lists, per entry point, the data-stack and native-stack worst cases and the lines that drive them, and every loop's growth per iteration. An entry point with something still unbounded (an untyped external call, say) is listed as such; its stack grows as needed up to its cap.
- **Tests can pin it:** `expect stack_peak(handler) < 2 MB` fails a test when a change raises the worst case past a budget.
- **Tools that read whole projects** bound their inputs too: a source tool declares the most files and bytes per batch it accepts, and a budget for the trees it keeps, rather than growing to its cap and failing.
- **Nested growing values wait:** in v1 a growing value can't contain growing values on a stack (an unbounded list of texts built by appending, a record with two growing fields; a bounded `list<Text max 40, 100>` is not one of these, see Collections). The first implementation refuses them with an error suggesting a bounded collection instead (`list<Ascii max 40, 100>` as a local, say), which isn't a growing value: it has a fixed worst-case size and nests freely, since collections flatten into arrays. Supporting nested unbounded growing values later would need a separately reviewed extension to the one-data-stack design; none is adopted.

### Keeping it fast

- **A context pointer, not thread-locals.** Every function takes one hidden pointer to its job's context: the data stack's base, top and limit, the native-stack limit and the step budget. Hot code never looks up thread-local storage (Burin's helpers do today; that goes).
- **Base and top in registers** (Goose's top caching): a function keeps the data stack's base and top in registers, reloads the base only after a call that may grow the stack, and writes the top back only before a call that can reach the stack (or suspend), and at exits. A loop that pushes is a store, an add and one compare. Native-stack accounting is separate.
- **No aliasing between regions:** distinct regions on the data stack never overlap, so LLVM knows a write to one doesn't change what's read from another. Alias metadata and `noalias` are emitted only where the separation is proved: distinct regions, or parameters the call-site rule keeps apart.
- **Freeing a scope** puts saved tops back: register moves, with memory written only at function exit.
- **No locks, no atomic operations on stacks,** since a job's stacks belong to it alone.

### Crossing threads

Nothing mutable is shared. Values cross in four ways:

1. **Queues of flat values.** A flat value is one contiguous block with no pointers in it (data inline, typed ids instead of pointers), so sending is one copy into the queue and one onto the receiver's stack. Queues are bounded rings: one producer and one consumer where possible, with no locks; many producers to one consumer for workers sending to the writer.
2. **Snapshots** of shared state (Shared state across threads).
3. **Frozen pools** (below).
4. **Parallel loop inputs and results** (Parallel loops).

A typed id means an element of a pool, not a memory address, so it stays valid in any thread reading the same snapshot.

### Parallel loops

- `parallel for t in texts { … } collect`, or `parallel for i in 0..n reduce sum`: the runtime splits the work into chunks that idle workers take (work stealing: an idle worker takes chunks from a busy one's queue). Each chunk runs on stacks of its own.
- **Inputs:** the loop is scoped (the caller waits until every chunk is done), so the caller's stacks stay alive and unchanged for the whole loop. Chunks get read-only views of what the body reads from the caller (`texts` here), with no copy; the views end at the join, before the caller can change anything again. Chunks may also read the caller's pinned snapshot, which stays pinned until the join (Thread kinds and jobs).
- **The body** may have no effects, and may write only what it owns: its own scratch and its slot of the result. The caller values it reads (a scoped block's context, Functions as values) are read-only views; a body that tries to write or grow a captured value is refused, whatever its effects. So there are no data races.
- **Outputs:** `collect` writes into a result buffer the caller owns, on its destination stack. When the output sizes are known up front (one value per item, fixed size) each chunk writes its slice directly. Otherwise each chunk builds its output on its own stack and the join copies the pieces in index order before those stacks are reset. `reduce` combines chunk results in a fixed tree order, whatever the scheduling, so floating-point sums come out the same on every run.
- **No nesting in v1:** a `parallel for` reached from inside another runs sequentially, so workers can't all end up waiting for work nobody can run. A worker waiting at a join runs other chunks of the same loop meanwhile.
- Small loops run sequentially below a cost threshold, so a fork never costs more than it saves.

### Shared state across threads

This section is about shared state only.

- **One writer per shared state.** Workers send change requests on a queue and get a reply (Burin's model); writes are batched.
- **Snapshot cost proportional to what changed:** each collection's arrays and payload are stored in fixed blocks (4,096 rows, say). The blocks hang off a small tree (a radix tree: each level indexes into the next by part of the row number). A write copies the blocks it touches and the tree nodes on the path to them, and shares everything else with the previous version. Publishing is proportional to the blocks changed, not the state's size.
- **One version per shared state:** everything in it is published together under one root, so a reader never mixes one collection's new elements with another's old ones. Shared state is lost on a crash unless the program saves it.
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
| Start a job (stack from the pool) | under 200 ns |
| Suspend and resume a job | under 1 µs |
| Send a 64-byte value through a queue | under 100 ns |
| Parallel loop overhead (fork and join) | under 5 µs |
| Independent chunks of one parallel loop, 4 cores | at least 3.5× one core (hardware reported with every timing) |
| Publish a snapshot | proportional to blocks changed, not state size |
| Freeze a builder | constant, whatever its size |

### Open questions

- Parallel loops inside a game tick, keeping ticks deterministic and within their time budget.
- The block size for snapshots of shared state.
- Whether jobs should ever move between workers (better balance, but stacks would then need to be safe to hand over).
- **Spawning and waiting** (open, 2026-10-26). The design keeps stackful jobs with implicit suspension and no `async` colouring; still open:
  - *Scoped spawn:* whether `spawn` is allowed only inside a `scope { }` that joins its children, cancels siblings on failure and passes deadlines down (the direction above), and the exact form for jobs that outlive their starter (`start service(rx)` or similar).
  - *Marking suspension:* whether calls that may suspend carry a keyword at the call site (`wait fetch(x)`: no futures and no two kinds of function, but a marker on most lines of server code), or only an editor marker, with the compiler errors that depend on suspension (views across a wait, transactions, ticks) naming the call. A keyword can be added later without breaking anything, since the compiler already knows every such call.
  - *Wide fan-out:* each spawned job costs at least a page of data stack plus its native stack. Measure thousands of small concurrent I/O tasks first; if that is too costly, add a batch form over leaf I/O (`all(urls, fetch)`) issued from one job, not state machines.
  - *Against `async`/`await`:* stackless futures have compile-time sizes (a good fit for bounded memory), make suspension visible and need no stack switching on WebAssembly; they cost function colouring, two kinds of function values and cancellation at every `await`. WebAssembly support for implicit suspension needs stack switching (JavaScript promise integration now, the stack-switching proposal later), recorded as that target's cost.

*(Diagram in the shared Claude Doc: threads · workers with their own stacks, one writer, snapshots.)*

Workers grow and free their jobs' stacks without locks; changes go to the writer through queues, and every job reads a pinned snapshot. A parallel loop's chunks run on these same workers.

## Types, and refinement types

**No name shadowing** (Ben, 2026-10-26). Within a function, a name refers to exactly one thing, so a reader (or an AI) never has to work out which declaration wins. A name declared by `let`, `var`, a parameter, a loop variable or a `match` binding may not be the same as:
- any local, parameter, loop variable or binding visible where it is declared (an enclosing block, the function's parameters, an outer loop);
- a package-level name: a function, a type, a `const`, or a case of any enum that can be written bare (`Red`, and the built-in `some`, `none`, `ok`, `err`);
- a built-in function (`print`, `str`, `min`, ...).

Sibling scopes may reuse a name (two loops after each other may both use `i`), and qualified or field names don't count (`Color.Red`, `s.x`). Package-level names must differ from each other too, except that cases of different enums may share a name (`Color.Red`, `Light.Red`); a bare `Red` then needs an expected type, as now. The error names both declarations and suggests a new name. Stage 0 allows shadowing; the self-hosted compiler refuses it (PLAN "Stage 0 freeze").

Refinement types are the design's best lever: one declaration serves correctness, efficiency and every layer at once, if they stay small enough to check quickly.

**The base:** values with no null; `Option` and `Result`; records; enums with payloads and exhaustive `match`; generics with static traits; newtypes (a `UserId` is not an `int`). Arithmetic is checked: an overflow is a failure, and wrapping is spelled `+%`.

**Failures** that aren't values: an overflow, an integer divisor of 0 (float division by zero gives infinity; see Numbers), an index the compiler couldn't prove in range and that turns out not to be, a data stack or the native-stack budget exhausted, the step budget spent (an unbounded loop's limit), a time limit passed. Each fails the job, as a stack limit does (see Memory): the job ends with an error carrying the source line. A function returning plain `T` therefore never returns a half-made value.

**What failing a job does,** in this order, so nothing can touch memory after it's reused:

1. Stop scheduling the job: no more of its code runs.
2. Cancel its pending I/O and its unstarted parallel-loop chunks; wait until running chunks have stopped (a chunk notices at its next cancellation poll: a step-budget check, or the periodic poll in a loop that has no budget) and the event loop has confirmed no I/O will write into the job's buffers. A pin held for a join is released only after this.
3. Settle its change batches: one not yet sent is dropped; one queued at the writer is cancelled; one the writer is applying is waited for, until the writer acknowledges that it aborted or committed it, since the writer reads the batch from the job's buffers until then. Batches the writer committed stay committed (decided 2026-10-24, see Transactions).
4. Release its snapshot pin and any frozen batches or builders it owns.
5. Reset its stacks and return its data stack to the worker's pool. These steps run on the worker's own scheduler stack, not the job's, so a job that failed because its native stack ran out can still be cleaned up.
6. Report the failure: to the client (a 500 for a request), to the log, and to the parent if it was a parallel-loop chunk, which fails the parent job with the chunk's error. Code that wants to handle one of these locally uses the checked form that returns `Option` (`checked_add(a, b)`, `a.get(i)`), or a refinement that proves the failure can't happen.

**Sizes, indexes and time** (decided 2026-10-24: lengths and indexes are `long`)

- `len()`, counts, capacities, offsets and `Index(a)` are refined `long`s, so a collection can pass 2^31 elements on 64-bit targets, and the compiler still knows each one's real range (a `list<T, 500>`'s length is `long 0 to 500`). With no implicit conversions, indexing with an `int` is written `a[(long)i]`, or `i` is declared `long` in the first place. Capacity products (outer × inner capacity of nested collections, Memory) are computed in 64 bits and checked.
- A refinement's bounds must fit its base type: `int 0 to 5_000_000_000` is a build error naming `long`.
- Sums that may pass 2^31 use a `long` accumulator, and operands are cast before the arithmetic, not after (casting an overflowed `int` is too late; the overflow already failed the job). The worked example's 500 counts total at most 499,999,500, which fits an `int`; 10,000 of them could reach 9,999,990,000, which needs `long`, and the compiler's range analysis reports which.
- Time has its own types over `long`: `Time` (a moment, in milliseconds since 1970, UTC) and `Duration` (milliseconds), so a timestamp can't be mixed up with a count; `Duration` literals carry units (`60s`, `5min`).

**`?.` and `??`** (proposed 2026-10-24)

- `x?.f()` evaluates `x` once; if it's `none` the call is skipped and the result is `none`, otherwise it's the call's result, wrapped in `some` unless it's already an `Option` (decided 2026-10-24: `?.` flattens, as in C#, Swift and Kotlin, so `line.after_last('"')?.word(0)` is one `Option`). The result is an `Option`; `x?.f(a)` calls `f(value, a)`.
- `x ?? d` gives `x`'s value if it's present, and evaluates `d` only if it isn't. `d` may be a default value, `return …` (leave the function), or `continue` or `break` in a loop (decided 2026-10-24): `let r = g.rocks.get(rid) ?? continue`. Both work on `Option` only; a `Result` is handled with `match`, or passed up with `?`, so an error can't be silently replaced by a default.

**Numbers** (names decided 2026-10-24: C#'s, exactly; the rest proposed except where marked decided)

- **Names, as in C#:** lowercase keywords, with C#'s widths. Signed: `sbyte` (8-bit), `short` (16), `int` (32), `long` (64). Unsigned: `byte` (8), `ushort` (16), `uint` (32), `ulong` (64). Floats: `float` (32-bit), `double` (64-bit). `bool` is lowercase too; `Text`, `Ascii`, `Bytes` and declared types stay capitalised. An integer literal is an `int` unless its context needs another type, so code that needs 64 bits says `long` (a running total, a timestamp, a file size).
- **Ranges pick storage:** a field declared `hp: int 0 to 1000` is stored in 16 bits in state's arrays (one array per field, so this halves the memory a loop streams through), while arithmetic on it follows its declared type, here 32-bit `int` (its overflow and shift rules included), and is narrowed, checked, on the way back. Storage width never changes what a calculation means: `ulong` keeps unsigned 64-bit arithmetic wherever it's stored.
- **Arithmetic is checked, unlike C#'s default:** an overflow fails the job (Failures), where C# would silently wrap unless told `checked`. Wrapping is spelled `+%`, `-%`, `*%`, as hashes and checksums need; `checked_add` and friends return `Option`. Bit operations (`&`, `|`, `^`, `<<`, `>>`, and `~` for bitwise not; Ben, 2026-10-27) work on any integer; a shift by n needs `0 <= n < width` (shifting an `int` by 32 fails). Integer division truncates toward zero; dividing by zero fails, and so does the one division that overflows, the most negative value divided by −1. Compound assignment (decided 2026-10-24): `+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `|=`, `^=`, `<<=`, `>>=`, and `+%=`, `-%=`, `*%=` for wrapping; `x += 1` means exactly `x = x + 1`, checks included, and a `wrap` or `clamp` range applies on the store.
- **No implicit conversions** (decided 2026-10-24; C# allows widening implicitly, this language doesn't): every conversion between number types is written as a cast. Widening (`(long)n` for an `int` n) can't fail and costs nothing, but it's still written, so a reader always sees where a value changes type, and mixed arithmetic (`int + long`) is a build error that says which side to cast. Narrowing is a cast, `(byte)x`, which fails the job if `x` doesn't fit (C# would truncate); `unchecked((byte)x)` keeps only the low bits, as C# does by default. A range refinement that proves the value fits makes the checked cast free. Integer to float and back are casts too; a float cast to an integer fails if it's out of range or not finite. For widening there are also short methods, `n.to_long()`, `b.to_uint()`, `i.to_double()` (decided 2026-10-24), which exist only where the conversion can't fail; narrowing stays a checked cast.
- **Floats:** `double` is 64-bit IEEE, `float` 32-bit, for games and measurement. Ranges apply (`double 0.0 to 1.0`). A plain `double` or `float` never holds NaN (the "not a number" value from `0.0 / 0.0` or `sqrt(-1.0)`; decided 2026-10-24): an operation that would produce one fails the job at that line, as an integer overflow does, so the bug shows up where it was made, not frames later. `double nan` (and `float nan`) allows it for code that wants IEEE behaviour, written like a refinement, and a `fast { }` block may produce it inside; converting back to plain `double` is checked. Infinities are allowed unless a range excludes them, so `1.0 / 0.0` is infinity, and only a result that would be NaN fails; the "dividing by zero fails" rule is for integers. `double nan` follows IEEE exactly: nothing about it fails.
- **Deterministic by default:** float code compiles without fast-math flags and without contraction (no fused multiply-add unless written), in a fixed floating-point environment, and `sin`, `exp` and friends come from the language's own implementations, so the same binary gives the same results on every run (see Targets and CPU features), which game replays and `check fast == reference` rely on. A `fast { }` block allows reordering for speed where exact repeatability doesn't matter. It uses only the fast-math permissions that keep NaN and infinity meaningful (LLVM's `reassoc`, `contract` and `arcp`: reorder, fuse a multiply and add, use a reciprocal), never the ones that assume no NaN or infinity. Its results keep their precision and become NaN-allowing: `float` operations give `float nan`, `double` operations `double nan`, each checked on the way back to the matching plain type. A game's `fast` results may be used for drawing but not stored in the state `tick` changes or used to decide what it does, which the compiler checks, since replay compares that state exactly.
- **Vectors, as in C#'s System.Numerics:** `Vector2`, `Vector3`, `Vector4` (of `float`) with operators, for games. Loops over state's arrays are where most speed comes from: one array per field means LLVM's auto-vectorizer (which turns a loop into instructions working on 4 or 8 values at once) usually applies on its own. An explicit `simd<float, 8>` type exists for code that needs to control it.
- **Fixed-point:** `Fixed<2>` is an integer counting hundredths, for money and other exact decimals; it never rounds silently. (C#'s `decimal` is a different thing, a 128-bit decimal floating point; this language has no `decimal`.) Adding two `Fixed<2>` gives a `Fixed<2>`; multiplying gives an exact `Fixed<4>` (1.23 × 1.23 = 1.5129), computed in 128 bits; getting back to hundredths takes an explicit rounding (`.round_to<2>(half_even)`). Division needs a rounding mode too.
- **Literals, with C#'s suffixes:** `1_000_000`, `0xFF`, `0b1010`, `5L` (a `long`), `5u`, `5UL`, `1.5` (a `double`), `2.0f` (a `float`). A suffix fixes a literal's type; an unsuffixed literal takes the type its context needs (so `count += 1` on a `long` needs no `1L`, and suffixes are rare in practice), or `int` (`double` with a decimal point) if nothing says, and one that doesn't fit its type is a build error.

**Functions as values, no closures** (decided 2026-10-24)

- **Functions can be passed:** a named function is a value of a function type, `fn(int, int) -> bool`, so it can be an argument, a field or an element of a collection: `sort_by(units, by_hp)`, a table of handlers, a callback list.
- **No closures:** there are no anonymous functions and nothing captures local variables. A function value is just a pointer to a named, top-level function. That keeps the memory model simple (nothing can hold a reference past its scope, Memory), keeps every call's effects and stack needs visible, and costs no allocation.
- **Context is passed explicitly:** where another language would capture a variable, the callee takes it as a parameter, and generic helpers pass it along: `for_each(units, ctx, update)` calls `update(ctx, unit)`. The context is an ordinary argument, so the usual rules apply (read, write or grow mode, no overlapping arguments).
- **A function type is a full contract:** everything the compiler needs to check and compile a call without knowing which function it is. That's its parameters' types and modes (read, write, grow), its result and whether it can be built in append mode, its effects, whether it may suspend, whether it reads a snapshot or program state, and its stack contract with its data-stack and native-stack byte bounds (How the compiler places values). A function whose contract exceeds the type's isn't accepted for it, and the error names the difference (`fn(Unit) -> int` with no effects can't be given one that writes to the database). The analyses that walk the call graph (stack assignment, recursion cycles, effects) follow indirect calls through every function that can be stored in a value of that type, so a call through a value is checked and compiled as tightly as a direct one.
- A `writes P` effect bound also covers reads of `P` and paths under `P`; a `reads P` bound does not cover writes.
- **Function values in saves:** a function value is stored as a symbolic id (the function's name and its contract's hash), checked against the running build when a save or replay is loaded, never as a memory address.
- **Scoped blocks aren't closures** (decided 2026-10-24): the built-in blocks `db.read { }`, `db.transaction { }`, `transaction { }`, route tables, `parallel for` bodies and a page's `for` and `if` may read the surrounding locals. The compiler turns each into a named helper whose context (the locals it reads, copied or viewed under the usual rules) is passed explicitly and bounded. A block can't be stored, returned or called later, which is what would make it a closure; it runs where it's written (or, for a transaction, on the writer or the database connection, with its context copied there). A `return` inside a scoped block leaves the enclosing function, as it reads; the compiler carries it out through the generated helper.
- **Bindings aren't closures either:** `<form action={post(room_key)}>` and `signal Messages(room_key)` name a function and give some of its arguments now. They're declarative: the compiler records the function's id and a bounded copy of those arguments, and when the form is posted or the signal fires, the server supplies the rest (form fields, the session's viewer, capabilities). They can only name actions and page pieces.
- **Query predicates aren't closures:** `Message.where(.room == room_key)` reads like one, but it's a query expression the compiler turns into SQL (or an in-memory scan), with `room_key` passed as a parameter; it can't be stored or called.
- **Iteration is `for`:** with no closures there are no `map`/`filter` chains taking lambdas; loops (`for x, i in list`) and named helper functions do that work, which also keeps every loop visible to the loop-growth rules.
- **Patterns without closures:**
  - *Sorting:* `sort_by(items, ctx, compare)`, where `compare(ctx, a, b)` is a named function and `ctx` a read-only context, apart from the items being sorted.
  - *Callbacks:* a call that uses its callback before returning passes the context along. A callback kept for later stores a bounded record or an id, not a reference, and is cancelled before what it refers to goes away. C callbacks go through a generated wrapper that dispatches the named handler on its owner's worker.
  - *Events:* a queue of `{handler, target id, bounded payload}`; the dispatcher calls the named handler and supplies the world and capabilities, so events can be saved and replayed.
  - *Parallel work:* a named or scoped body, a read-only context, and one output slot per item, joined before the caller's storage ends (Parallel loops).
  - *Page pieces:* top-level pieces with bounded plain arguments; `serve` supplies capabilities afresh on every render and refresh.


**Generics and interfaces** (decided 2026-10-24). Generic code says what it needs from a type through a named interface, and a type provides it with an explicit `impl`, as in C# and Rust:

```
interface Ordered {
    fn less(a: Self, b: Self) -> bool
}
impl Ordered for Unit {
    fn less(a: Unit, b: Unit) -> bool { a.hp < b.hp }
}
fn sort<T: Ordered, N>(xs: write list<T, N>) { ... }
```

- **Static only:** a generic function is copied per type (decided earlier), so a call to `less` is a direct call the compiler can inline, never a lookup at run time. There are no interface-typed values (no `list<Ordered, 10>` holding mixed types); a function value (Functions as values) covers the cases where behaviour has to be chosen at run time.
- **Explicit:** a type satisfies an interface only through an `impl`, so it can't happen by accident, and a missing one is an error that names the interface, the type and the missing function.
- **Coherence:** an `impl` lives in the package of the interface or of the type, so two packages can't give conflicting `impl`s for the same pair.
- The built-in interfaces `Eq`, `Hash` and `Ordered` let maps, sets and sorting work on declared types; until they exist, those are compiler built-ins over structural types (T09, T12).
- Interfaces carry the same contract as function types: an `impl`'s functions may have no more effects than the interface allows.
- Generic expansion has its own limit (a count of copies), not a source-size bound.
**Text, ASCII and bytes** (decided 2026-10-24): `Text` is always valid UTF-8; `Ascii` is text known to hold only ASCII characters (bytes 0 to 127), the compact form, one byte per character; and `Bytes` is raw data (DEFLATE's output, files, the network). An `Ascii` value is a valid `Text` too, so passing one to a *read* parameter of type `Text` costs nothing. A write or grow parameter is different: the function could store a non-ASCII character, or need up to 4 bytes for a character where `Ascii max N` owns exactly N, so passing `Ascii` there needs an `Ascii` parameter, a proof that the function writes only ASCII within the bound, or an explicit checked conversion into `Text` storage of the right size; going from `Text` or `Bytes` to `Ascii`, or from `Bytes` to `Text`, is a checked step that returns `Result`. For `Ascii`, a character, a code point and a byte are the same thing, so `Ascii max N` is exactly N bytes, its length is O(1) and indexing by character is direct; operations like `ascii_upper` and comparisons skip UTF-8 decoding. Text lengths count Unicode code points (what a person would call characters, roughly); byte lengths are written on `Bytes`, or as `Text bytes max N` when a byte budget is what matters.

**Interpolated strings** (Ben, 2026-10-26): `$"{id}:{value}={name}"`. Plain `"..."` literals have no holes, so braces in them need no escaping (generated code, JSON); the `$` prefix marks interpolation, as in C#, and holes are `{expr}`, as in HTML pages. Literal braces inside an interpolated string are `{{` and `}}`.
- **The type comes from the holes:** each hole has a maximum length known from its type (`long` 20 characters, `int` 11, `bool` 5, `Ascii max 32` 32, a struct or enum its printed maximum), so `$"{id}:{value}={name}"` is `Ascii max 62`, or `Text` with the summed maximum if any hole or literal piece isn't ASCII. It's an ordinary bounded value: assigning it to `Ascii max 40` is a build error unless the bound fits (or it goes through `fit` or `try_append`).
- **It costs what concatenation costs:** built in one pass straight into its destination: literal pieces are byte copies, each hole calls its type's own formatter (the integer formatter, a copy for text, the generated print helper for structs and enums; the same text `print` produces). No format string is read at run time, no dynamic calls, no temporary buffers. `out += $"..."` appends straight into the builder, with no intermediate value.
- **Format options,** a small fixed set: `{n:8}` (pad to width 8), `{n:08}` (zero-pad), `{n:x}` and `{n:b}` (hexadecimal, binary). A width larger than the type's maximum raises the bound.


**Refinements** are a type plus a predicate the compiler understands, a closed set kept decidable:

| Kind | Written | Example use |
| --- | --- | --- |
| Range | `int 0 to 100`, `int >= 0` | quantities, percentages, indexes |
| Wrapping or clamping range | `float 0.0f..TAU wrap`, `int 0 to 359 wrap`, `int 0 to 100 clamp` | angles and other cycles; health, volume and other values pinned at their ends |
| Length | `Text max 80`, `list<T, 20>` with at least 1 (`list<T, 1 to 20>`) | names, bounded lists |
| Membership | `Text in ["low", "high"]`, an enum | states, options |
| Pattern (a regular-language subset) | `Text matches slug` | slugs, codes, emails as syntax only |
| Index | `Index(a)`, a `long` with `0 <= i < len(a)` | array positions with no bounds check |
| Linear relation between fields | `invariant start <= end` | intervals, budgets |

**Wrapping and clamping ranges** (decided 2026-10-24). A plain range never takes a value outside it: storing one the compiler can't prove fits needs a checked cast or `fit` (The refinement contract), and a checked cast that meets an out-of-range value fails the job, which is what catches bugs. Two written options change that, for values where going past an end is expected:

- **`wrap`** reduces the value into the range when it's stored (assigned to a variable or field, passed as an argument, or returned): for integers `lo + (x - lo) mod (hi - lo + 1)`, so `heading: int 0 to 359 wrap` takes 365 to 5 and −10 to 350; for floats the same with the exact float `modulo`. A wrapping float range is half-open, `0.0f..TAU wrap` meaning 0 ≤ angle < 2π, as suits a cycle (2π is the same direction as 0), and a result that rounds to exactly `TAU` becomes `0.0f`. Arithmetic in between happens normally (`ship.angle = ship.angle + 0.07f`), and since float `modulo` is exact, replays stay deterministic. It's the refinement form of `+%`, which wraps over a whole type's range.
- **`clamp`** pins a stored value to the nearest end instead: `hp: int 0 to 100 clamp` makes healing past 100 stop at 100 and damage below 0 stop at 0.
- Both are part of the type, so readers see them where the field is declared, and the projections follow (a form field for `int 0 to 359 wrap` accepts 0 to 359 and the server wraps nothing it receives: input from outside is checked, never silently wrapped or clamped). The overflow of the arithmetic itself is still checked: `int 0 to 359 wrap` wraps a stored `int`, but an `int` sum that passes 2^31 still fails first.

**Ranges: `..` and `to`** (decided 2026-10-24; inclusive spelling changed from Rust's `..=` to `to` by Ben, 2026-10-27, because `0..=1000` reads as an assignment, especially next to a default: `hp: int 0 to 1000 = 500`). `a..b` always stops before `b`, and `a to b` always includes it, wherever a range appears: in a refinement (`int 0 to 100`, `int 1 to 3`), a loop (`for i in 0..8` runs eight times) or a slice (`a[2..5]`, three elements). A wrapping float range is written with `..` because it excludes its end (`float 0.0f..TAU wrap`: 0 ≤ angle < 2π); a wrapping integer range usually reads best inclusive (`int 0 to 359 wrap`).

**Loop counters take their type from their bounds and use** (decided 2026-10-24), as an unsuffixed literal does: in `for i in 0..256` where `i` indexes an array, `i` is a `long`; bounds of a declared type set it (`for k in 0..n` with `n: int 1 to 8` makes `k` an `int`); with nothing to say, it's an `int`. A counter can be typed explicitly, `for i: long in 0..count`.

**Named refinements** (decided 2026-10-24): a refinement used in more than one place gets a name, `type Size = int 1 to 3` or `type UrlPath = Ascii max 200`, and code uses the name; it's the same type, not a new one, so a `Size` is an `int` with that range wherever it goes. Casting to a refinement uses its name like any other cast: `(Size)(r.size - 1)`, checked unless the compiler proves it fits. (A `newtype`, by contrast, makes a distinct type: a `UserId` isn't an `int`.)

**The refinement contract** (decided 2026-10-24, before M1). When a value goes into a refined type, whether assigned, passed as an argument, returned or stored in a field:
- if the compiler proves it fits (from ranges, earlier checks or control flow: `r.size - 1` after `if r.size == 1 { return }` fits `Size`), it costs nothing and nothing is written;
- if it can't prove it, that's a build error asking for one of two explicit forms: a cast, `(Size)(x)`, checked at run time (a value that doesn't fit fails the job), or `x.fit<Size>()`, which returns an `Option`. There's never a hidden check on a line that doesn't show one;
- a `wrap` or `clamp` type accepts any value of its base type, since wrapping or clamping is what it's for;
- literals and constants are checked at compile time;
- arithmetic on refined values produces the plain base type (`int`), with the range the compiler worked out kept for later proofs.

**How they are checked:**

- Every assignment, argument, return and field store into a refined type is either proved or written as one of the contract's explicit forms: a checked cast or `fit` (The refinement contract). External decoding (parsing input, reading a column) builds checked refined values at its boundary. Inside, operations keep or prove the refinement. Parse, don't validate.
- The compiler infers refinements by interval and sign analysis (Burin's sign analysis is a first version): `x: int 0 to 100` plus `y: int 0 to 100` is `int 0 to 200`, with no overflow check. A preceding condition can establish a proof (`if r.size == 1 { return }`).
- Where it can't prove a refinement, the build error names what would prove it or fix it: a preceding condition, a stronger parameter type, a rewrite, or one of the explicit forms (a checked cast, or `fit` with its `Option` to handle). It never assumes silently.
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
| `int 0 to 100` | CHECK range | rejected on parse | `min`/`max` input | `minimum`/`maximum` | -1, 0, 100, 101 | no overflow check |
| enum `State` | CHECK IN | one of the names | a select | `enum` | every case | exhaustive `match` |
| `invariant start <= end` | CHECK on the row | rejected on parse | the form's error | described in the schema | generated pairs | solver proof per writer |
| permission `read Item: owner == actor` | WHERE on queries | 404, not 403 | hidden rows and links | the tool can't see them | an outsider scenario | change review flags widening |
| error `Result<_, OutOfStock>` | none | status 409 + code | a message | an error code | the failing path | must be handled |
| effect `db.write` | transaction | none | none | marked as a write tool | effect assertion | capability required |
| a query's `limit 50` | `LIMIT 50` | a page size | paging controls | `maxItems` | 0, 50, 51 rows | the result's byte bound |

The Database column applies to database records. State (program, job or shared) enforces the same rules in memory instead, with no SQL involved: a field's maximum and range are proved at build time or go through a checked cast or `fit` (The refinement contract), and invariants are checked on every write.

**Rules for the projections:**

- A projection is generated only where the layer's rule means the same thing as the declaration. Where a layer counts differently (HTML's `maxlength` counts UTF-16 units, not code points), the generated code checks it the declaration's way instead of using the layer's near-miss.
- Layers are compiler back ends, not libraries, so each projection is checked. A form can't drop a field an action needs; a page can't show a row a permission hides.
- A layer may override how a declaration looks (a label, a message, a widget), attached to the same declaration and flagged by the change review. It may not override what it means.
- The projections are generated, never hand-edited (crudspec's rule). Hand code goes in typed extension functions with declared effects.
- Tests come out too: every refinement yields boundary cases, every enum its cases, every permission an outsider scenario. These run with the scenarios.

This is also where refinement types pay twice: the same `int 0 to 100` that a form enforces is the fact that removes an overflow check.

## Function attributes

Decided 2026-10-26 (Ben). There is one way to declare a function, `fn`. What kind of function it is, and how the runtime may start it, is written as attributes in front of it, `@[name]` or `@[name(arguments)]`, several separated by commas or on separate lines:

```
@[page]
fn room(room_key: Room.Key, db: Db<Chat>, online: shared Presence) -> Html { ... }

@[job(stack_cap = 8 GiB, time_limit = 2 s)]
fn nightly_report(db: Db<Chat>, fs: Fs) -> Result<(), ReportError> { ... }

@[versions(x86-64-v3, x86-64-v4)]
fn blur(pixels: write Bytes) { ... }
```

- **A fixed set, defined by the language and checked.** No user-defined attributes and no macros. An unknown or misspelt attribute is a build error with a "did you mean". An attribute adds rules and meaning to a function; it never changes how its body is read.
- **The set:**
  - `@[job]`: the function may be started as a job (spawned, started as a service, or a route target). Called directly it is an ordinary call on the caller's stacks, so tests and reuse are unchanged. Only `@[job]` functions can be started as jobs; `spawn f(x)` on an unmarked function is a build error naming the fix. Its parameters are checked once, at the declaration: copies of flat values, capabilities, `shared` handles and queue ends (read-only views only where spawning is scoped; Open questions under Threads). Its arguments set the job's own settings: `stack_cap`, `strict_stack`, `time_limit`, with the manifest able to override them per deployment. The compiler's per-entry-point stack bounds and `inspect stacks` cover exactly `main` and the job functions.
  - `@[page]`, `@[action]`, `@[api]`, `@[piece]`: the server kinds (Pages and live updates). Each checks its result type and its parameters' sources, makes the function a route target or page piece, and `@[page]`, `@[action]` and `@[api]` imply `@[job]`. `main` is always a job.
  - `@[versions(...)]`: compile once per listed CPU level plus a fallback, chosen at startup (Performance model).
- **What stays keywords:** parameter modes (`write`, `grow`, `take`), `const`, the `shared` type, and `test "name" { }` blocks (they aren't callable functions, and their name is a sentence).

## Effects and capabilities

What a function may touch is part of its type, inferred across calls, and granted only by the program's entry point (Hobthrush's model).

- A closed effect set: `db.read`, `db.write`, `fs.read`, `fs.write`, `net`, `clock`, `random`, `env`, `secret`, `log`, `spawn`, `signal` (telling open pages to refresh a live piece; `serve` grants it to the pages and actions it routes, and the manifest lists it), `out` (writing to standard output and error; `print` is an `out` effect). No effects means pure.
- **Pure** means deterministic (the same inputs give the same result) with no effects. A pure function may still change or grow what it's handed through a write or grow parameter; those modes are part of its type, so callers and the compiler see them.
- **Cacheable** is narrower than pure: no effects, every parameter read-only, and a result the function owns. Only cacheable functions may be cached, evaluated at compile time or used by cached page pieces, since skipping a call to one changes nothing but the time taken. A pure function that appends to its caller's list isn't cacheable: reusing a saved result would skip the append.
- **Reading a snapshot is pure,** because the snapshot is an input: a function that reads shared state takes the shared value as an explicit `shared` parameter and reads the snapshot pinned for its read phase, and its result depends on that version. Reading program or job state isn't: it's the owner's current state, which can change between two calls, so a function that reads it isn't cacheable in v1 (a test checks that changing a row between calls can't reuse an old cached result). Database reads are effects (`db.read`). Parallel loop bodies and cached pieces may read the snapshot; a cache keys its entries by the snapshot's version, so a cached result never outlives the data it came from.
- Effects are inferred. A function may state an upper bound; exceeding it is an error that shows the shortest call path to the effect.
- Capabilities are values the entry point hands down (`Clock`, `Db`, `Http`), granted in the package manifest. A library can't reach the network unless a caller passes it a capability.
- Burin's rule "pages call only pure functions" falls out of cacheability. Database queries are effects, so a page runs its queries first, with bounded, owned results, and its cached pieces take those results as inputs; a `db.read` can never sit inside a cached piece.
- Time and randomness come only through capabilities, so tests and replays can supply fixed ones.
- C functions declare their effects at the binding (`fn crc(b: Bytes) -> uint = c "crc32_z" from "z" effects none`). The declaration is trusted, and the audit report lists it as such.
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

- **Facts for LLVM:** refinements and inferred ranges as `assume` and `range` attributes, non-negative values, `noalias` where it's proved (distinct regions, parameters the call-site rule keeps apart), `smin`/`smax` for `min`/`max`, plain `add nsw` (an add LLVM may assume doesn't overflow) where overflow is ruled out. Every fact comes from a proof; none is assumed. In Burin these took DEFLATE from 0.70x to 0.85x of C (0.89x after later work).
- **`while` loops** (Ben, 2026-10-27, after porting LangArena and Osprey showed bounded `for` + `break` workarounds everywhere): `while cond { … }` runs while `cond` is true; `break` and `continue` work as in `for`, every iteration is a scope (Loops can't quietly fill a stack), and a value it keeps growing needs a bound like any loop's. A `while` the compiler can't prove ends carries the step budget below, so a runaway loop fails the job at its time limit instead of hanging it.
- **Loops that provably end** carry no step budget: counted up or down, or any counted part of an `and`. Long ones still poll for cancellation every few thousand iterations (one load and compare), so deadlines hold.
- **Compile-time evaluation:** statements that depend only on constants run in the compiler; their tables become read-only data.
- **Layout:** collections as one array per field, nested collections flattened (L1 in PLAN.md; today they are inline per element); fixed-size data inline; stored text and bytes inline at every bound, and in collections inline up to 64 bytes, larger in size classes; enums sized to their largest case; typed ids 64 bits in v1 (narrower ids would weaken the generation check, so they wait for measurements).
- **No steady-state allocation:** shared state is claimed once; warmed pooled stacks reuse their storage on measured steady-state paths, and a test asserts zero allocations on chosen paths, as Burin's hot-path test does. Creating, growing and trimming a stack are explicit cold resource events, reported apart from those zero-allocation assertions.
- **Load what is used:** queries and loads guarded by the conditions around their uses; a per-request piece rendered once per page. Burin's +27% to +50%.
- **Work at write time where reads dominate:** derived values and rendered pieces kept up to date by the writer, behind the same purity rules (a library, as Burin's caching becomes).
- **One release pipeline:** LLVM with cross-language LTO, so the runtime's helpers inline into generated code.

**Targets and CPU features** (proposed 2026-10-24, corrected by review 16)

LLVM runs the same optimization passes for every architecture, but their choices depend on the target: inlining and vectorizing ask the target what instructions exist and what they cost (LLVM's TargetTransformInfo), and the back end picks instructions from what the target allows. An ahead-of-time build normally targets a baseline every CPU of its family has, so it runs anywhere; for x86-64 that baseline has SSE2 but no AVX2 and no fused multiply-add (FMA: `a * b + c` with one rounding instead of two). How much a newer level gains depends on the workload: compute-heavy loops can gain a lot, memory-bound code little or nothing, and wide vector instructions can even lose on some CPUs by lowering clock speed. So the design doesn't promise a number; the validation programs measure each level on named workloads (Validation). The build closes the gap with a JIT four ways:

- **x86-64 builds default to v2; v3 is opt-in** (decided 2026-10-24, replacing a same-day v3 default). Every x86-64 build, development or release, has a *minimum target* (the lowest CPU level the whole program may require) of `x86-64-v2` unless told otherwise. v2 (SSE4.2 and POPCNT, on CPUs since about 2009) is the floor Windows 11 24H2, Red Hat Enterprise Linux 9 and Android's x86-64 interface already require, so it costs almost no reach. Precedence: a build flag (`build --target-level x86-64-v3`, or `x86-64` for the oldest machines) over the manifest's setting for that platform over the v2 default, and never below the platform's own floor (Android x86-64: v2). A build at another level is a distinct build, with its own identity for caches and replays.
  - *What v3 adds over v2:* AVX (256-bit float vectors), AVX2 (256-bit integer vectors), BMI1 and BMI2 (bit-manipulation instructions), F16C (conversion between 16-bit and 32-bit floats; no 16-bit arithmetic), FMA (fused multiply-add), LZCNT (count leading zeros), MOVBE (byte-swapped load and store), and OSXSAVE (the operating system saving the wider registers). A 256-bit vector holds eight 32-bit values or four 64-bit ones, so eight-wide game arithmetic is for `float` (four-wide for `double`).
  - *What it can buy:* the instructions are capacity, not a promise; code has to be written or vectorized to use them. Where it is, they suit text scanning (escaping, UTF-8 checks, parsing) and integer loops over state's arrays (AVX2), bit-level decoding such as DEFLATE's Huffman codes and match lengths, and free-slot bitmap scans (BMI1/2, LZCNT), network byte order (MOVBE) and compact game data (F16C). The validation programs measure what it actually gains.
  - *Why it's opt-in:* most desktop and laptop CPUs from the last several years have it, but not all: some budget Intel chips (Pentium, Celeron and Atom-class parts) sold until about 2021 lack AVX2, and some cloud machine types still run older CPUs (Google Cloud's N1 family includes pre-AVX2 Sandy Bridge and Ivy Bridge machines). How many of a game's players lack it isn't something a single survey figure shows (Steam reports each feature separately, not the whole v3 set); so v3 is a choice for programs that know where they run. Servers you deploy, and tools for a known team, opt in with the flag or manifest; public games and tools stay at the v2 default and mark their hot functions `versions(x86-64-v3, x86-64-v4)`, which gives v3 machines the fast path without leaving the others out.
  - *Floats at v3:* exact float code still doesn't fuse multiply-adds or reorder sums (Numbers), so FMA is used where code writes `fma(a, b, c)` or inside `fast { }`. `fma` gives the same one-rounding result at every level: the hardware instruction where the level has it, an exact software fallback where it doesn't.
  - *Caution:* AMD chips before Zen 3 (2020) run BMI2's `PDEP` and `PEXT` very slowly, so code relying on them is measured there or given a fallback.
  - *Where a build that opts into v3 won't run,* and what to do: continuous-integration (CI) runners and older developer laptops without v3; virtual machines and emulators that expose fewer features than their host (QEMU's default `qemu64` CPU model is below v3; the Android x86-64 emulator follows its host and Android's v2 floor); Windows on ARM running x86-64 programs through its Prism emulator, whose recent versions emulate AVX, AVX2, BMI, FMA and F16C but older ones don't. The startup check tests the full feature set the process actually sees, so each of these refuses cleanly instead of crashing. The refusal names the required level and each missing CPU feature or missing OS register support, and says to get, or rebuild, the whole program, its runtime and its dependencies with `build --target-level x86-64-v2` (or `x86-64`). There's no run-time switch around the check. The compiler itself is built to run on older machines, so the older-level rebuild is possible there. Tests cover the refusal with features masked in a virtual machine and with the OS's vector-register support unavailable.
- **A declared target, per platform.** A target is more than CPU features: it's an operating system, an ABI (the binary rules for calls and data layout), an executable format, a minimum OS version and a CPU feature set. The manifest names one per platform it ships; the defaults are v2 on x86-64 (above) and each platform's baseline on arm64. The levels:
  - *x86-64:* `x86-64` (the baseline), `x86-64-v2`, `x86-64-v3` (a bundle including AVX2, FMA, BMI1/2 and MOVBE; first in 2013's Haswell, but some newer low-end CPUs lack it) or `x86-64-v4` (a particular AVX-512 subset). Android's x86-64 ABI requires at least v2.
  - *arm64:* Android's `arm64-v8a` starts at Armv8.0-A, with Neon vectors and FMA; macOS on arm64 starts at the M1's feature set; Linux and Windows on arm64 default to Armv8.0-A. Higher levels (`armv8.2-a`, `neoverse-v1`) are opt-in.
  - *macOS* with both Intel and Apple silicon needs two builds (one per architecture), joined into one universal binary.
- **`native` is an opt-in for local runs.** It means the machine doing the build, which may differ from a colleague's laptop or a test server, so it's never the default and never used for a build that will be shared or deployed; those use the v2 default or an explicit level. The resolved feature set, OS and ABI, compiler version and flags are part of every cache key and artifact identity, so a change of build machine can't reuse objects built for different features.
- **A safe start.** Startup code, the feature check, the dispatcher, the refusal message and anything that can run before the check (dependency initialisers included) are compiled for the platform's *safe-start baseline*, which is no higher than the selected minimum target: x86-64 v1 (Android x86-64: v2, which is also its minimum), and link-time optimization (LTO, which inlines across modules) is kept from moving newer instructions into them. The check uses what the operating system says is usable, not the CPU's name: on x86, CPUID plus whether the OS saves the wider vector registers (OSXSAVE and XGETBV); on Linux and Android arm64, the kernel's HWCAP flags. A binary started where its features are missing refuses with a message naming them. On machines with mixed cores or in virtual machines, only features usable on every core count.
- **Multiple versions of hot functions.** For any minimum target, a function marked `@[versions(x86-64-v3, x86-64-v4)]` is compiled once per listed level above the minimum, plus a fallback copy (a *clone*) at the minimum, and one is chosen at startup. So a default v2 build can add v3 and v4 (AVX-512) paths, and a v3 build a v4 path; no clone lets a v3 build run on a v2 machine. Automatic selection (LLVM's function multiversioning) depends on the platform's linker and executable format, so the design tests it per platform (Windows PE, Linux and Android ELF, macOS Mach-O) and falls back to a dispatcher that sets a function pointer at startup. Every version keeps the same calling interface, and tests and benchmarks can force each one, as long as the machine supports it (forcing never skips the feature check). Only marked functions are copied; `inspect build` lists them and their sizes.
- **Profile-guided builds.** A release build may take a profile recorded from running real workloads (which branches and calls are hot), which LLVM uses to lay out code, inline and predict branches. Gains vary by program and are measured, not assumed. For builds to stay reproducible, a profile is a file in the repository, keyed by the source, compiler, flags, dependencies and the workload it came from; a profile that no longer matches is rejected with a message, not silently used. BOLT, which reorders a linked program's code from a profile, is a later option mainly for Linux servers on x86-64 and arm64.
- **LTO,** already above: whole-program inlining across modules and the runtime.

What a JIT can still do that this can't: watch the running program and adapt, to the types a call site sees, but also to loop lengths, data alignment, branch behaviour and values only known at startup (a configuration number in a hot loop). Static types and per-type generics remove the first; the rest remain. An ahead-of-time build can cover the common ones with guarded fast paths (a check, then a specialised loop); which ones the first implementation adds is decided by measurement, not assumed small.

**Floats across feature levels.** Different levels could give different float results, because FMA rounds `a * b + c` once instead of twice. LLVM itself gives the same result, bit for bit, for each basic float operation (add, subtract, multiply, divide, square root, conversions) on every machine and optimization level, as long as the code carries no fast-math flags and runs in the default floating-point environment: round to nearest, no traps, status flags unread, and very small numbers (subnormals) kept rather than flushed to zero. So for exact code the compiler:
- emits no fast-math flags and turns off contraction (Clang's default "precise" mode allows fusing a multiply and an add into an FMA, so "no fast-math" alone isn't enough);
- keeps sums and other reductions in source order: a vectorized reduction must use LLVM's ordered form, which gains less, or not vectorize;
- sets the floating-point environment at startup and restores it after every foreign call, since C code may change rounding or flush subnormals;
- keeps NaN values out of plain `double` and `float` (Numbers); `double nan` results carry no promise about which NaN bit pattern they hold.

Matching results don't mean identical instructions: a v3 version and the baseline may use different instructions and still agree bit for bit on these operations.

Functions like `sin`, `exp` and `pow` are a different matter: they're library code, and C libraries pick an implementation at run time by CPU (glibc's `sin` does), and LLVM may swap in a vector math library. So the exactness promise covers them only through the language's own implementations, written in the language, compiled like any exact code and the same on every level; calling the platform's C library is allowed but outside the promise. A replay records the target level, the function versions picked at startup and the runtime's identity, and "the same platform" in the replay rule includes them.

## Development experience

One compiler target, LLVM, for development and release alike: no JIT, no interpreter, no live swap, so nothing can drift between two back ends. The aim is about 3 s from a small edit to running again (decided 2026-10-24). It's an aspiration, meant to hold for small changes to small and medium programs: a Campfire-sized server, a game or a tool up to roughly 50,000 lines. Larger programs and wide changes (an edited interface many modules use) may take longer, and that's accepted; `inspect build` shows where the time went.

- **Development builds:** LLVM at `-O1`, no LTO, one object file per module cached by a hash of its source, its dependencies' interfaces, the generic copies it contains (each per-type copy is compiled into the module that first needs it, and its key includes the generic's source), and whatever compile-time evaluation read, so a one-function change rebuilds one object and relinks. Aim: about 3 s from save to running for a one-function change in a Campfire-sized program; release builds (`-O3`, LTO) under 30 s.
- **Restart, not swap:** a change restarts the program. Database records survive, and a changed schema's migration, planned from the diff (crudspec), runs at start; program and shared state start from their defaults and initialisers (or from what the program saved, checked the same way).
- **What you test is what ships:** tests run on the same code generator as release, at the development optimization level, and in release mode in CI.
- **Compile-time evaluation** covers some of what a REPL would: constant code runs in the compiler.
- **One way to write each thing:** small syntax, inferred types, no imports inside a package (an app or library is a directory), one formatter.
- **Errors that name the fix:** "did you mean" for names, keywords and attributes, the error at the slip's own line. Their quality is measured by seeding slips, as crudspec's mutation harness does (99% of misspelled names caught there).
- **For agents:** `inspect` reports in JSON (API, effects, refinements, state, call graph), and a change review that lists what a change widens: effects, permissions, refinements loosened, invariants dropped.
- **Editor:** a language server from the start, sharing the compiler's code (Stasis's VS Code extension is the model).

## Packages, pages and the game host

How code is organised, how servers produce pages, and how games talk to the screen and input. Proposed 2026-10-24; the page model and the game host's shape were then confirmed by Ben the same day.

### Packages

- **A package is a directory.** Every file in it sees every other's declarations, with no imports (crudspec's rule); files are read in name order only for error messages.
- **Using another package:** a package lists its dependencies in its manifest (`package.toml`: name, version, dependencies, and the capabilities it may be granted). Their declarations are reached by package name, `chat.Room`, never by file. A manifest without a `capabilities` key (or no manifest at all) grants `out` only, so a program can print without one; `fs`, `env` and the rest are listed explicitly, and an explicit list replaces the default (decided 2026-10-24).
- **Visibility:** a declaration is private to its package unless marked `pub`. A `pub` declaration's whole interface (types, effects, refinements, the stack contract) is what other packages compile against, and what a module's cache key hashes (Development experience). A module, the unit the build compiles and caches, is a file; its cache key includes the interfaces of the private declarations it uses from sibling files (and their stack contracts, effects and refinements), so changing a private declaration in one file rebuilds the files that use it, along with the generic copies and compile-time inputs already in the key (Development experience).
- **The standard library** is a package written in the language where possible (`std`), with C bindings for crypto, compression and SQLite (no home-made crypto).
- **Versions:** v1 resolves exact versions from a lock file; no package registry yet (a non-goal).

### Pages and live updates (servers)

- **Pages are functions that return `Html`** (decided 2026-10-24). JSON endpoints are their own kind, `@[api]`, with a typed result and one function mapping errors to responses (decided 2026-10-24), next to `@[page]` and `@[action]` (Function attributes). Their body is HTML with `{expression}` holes, as in crudspec: `<p>Hello {name}!</p>`. Holes are escaped for where they appear (text, an attribute, a URL), so a value can't inject markup. Escaping alone doesn't make a link safe (a `javascript:` address escapes cleanly), so `href` and `src` holes take a `Url` value, whose parsing allows only `http`, `https`, `mailto` and relative addresses unless a page declares more. `for` and `if` work inside the HTML.
- **Defaults follow HTML:** plain lowercase tags are HTML elements; a capitalised tag is a page piece declared in the language (`<MessageList room={id}/>`).
- **Forms are bound to actions:** `<form action={post(id)}>` generates the route, the field names and the checks. Field limits come from the action's parameter types (One declaration, every layer), so the form and the server can't disagree.
- **Caching:** a page piece that is cacheable (no effects, read-only inputs; Effects and capabilities) is rendered once and kept, keyed by its inputs and their snapshot version; per-request pieces are rendered once per page (Burin's render-once).
- **Live updates:** a page piece used with `live` (`<Messages room_key={k} db={db} live/>`) re-runs when it's signalled: `signal Messages(k)` tells open pages showing that piece with that argument to refresh it. The re-run is a new job that loads current data itself, through the piece's own parameters, so nothing from the original request (no stack value, no view, no snapshot pin) survives to the refresh. An open page's subscription keeps only bounded copies of the piece's plain arguments (`room_key`); capabilities such as `Db` are supplied again by `serve` for the new job, never stored with the page. Each piece reads in its own read transaction, so two pieces on one page may see different versions; a page that needs them consistent reads once and passes the result down. Updates go over one stream per open page (Burin's server-sent events). Notices are numbered, repeats for the same piece are combined, and a page that reconnects reloads its live pieces, so a lost notice (a commit that succeeded before the signal was sent, a dropped connection) costs at most a stale view until the next notice or reconnect. Each open page's queue of notices is bounded; when it's full, its oldest notices are combined into "reload everything". A piece's rendered size is bounded by its inputs plus its markup and escaping, and request bodies are checked against their byte limits before any decoding.
- **Pages and actions are entry points:** each is a job (Threads and data stacks); a route table in `main` connects URLs to them.

### The game host (games)

Games run as StasisLang games do: the host owns the window, input, audio and timing, and calls the game.

- **Two entry points** (decided 2026-10-24, StasisLang's model): `tick(game: write Game, input: Input)` advances the simulation by one fixed step (60 per second by default); `draw(game: Game, frame: write Frame)` reads state and draws. `main` creates the game state and hands it to the host with the two functions (`env.game_host().run(game, tick, draw)`). The host's loop runs inside main's job: each tick and draw is an ordinary call whose scratch sits above the game state and is freed when it returns, so there is no job start or copy per frame, and they run one at a time, so a draw never sees a tick half done. `draw` takes the state read-only, so its parameter type enforces that it only reads. `tick` can't call anything that may suspend (no I/O, no waits). A game that wants parallel simulation uses a parallel loop inside `tick`.
- **Input is a value:** keys, pointer, touch and gamepad for this step, plus the step's time. Nothing else in a game reads the clock or randomness except through capabilities (`Random` seeded at start, its state kept in the game state so saves and replays include it; `draw` gets a separate random source, so how often frames are drawn can't change what later ticks do), so a recording of the inputs replays the game exactly (Correctness tools, Determinism).
- **Drawing goes through a capability:** `frame.sprite(...)`, `frame.text(...)`, `frame.rect(...)`, recorded into a draw list that the host renders. The list's capacity is declared (`frame max 20000`), and a draw past it is dropped and counted, with the count shown in development builds. Assets (images, sounds, fonts) are declared in the package and loaded at startup into frozen pools that live for the whole run, so play never loads or allocates.
- **Saves:** a save is the program state tree, written by path, including the simulation's random state; loading checks it like any initial value (Static allocation).
- **A failed tick stops the game** (decided 2026-10-24): an overflow, a full collection the code didn't handle, or any other failure in `tick` ends the game with the error and the recorded inputs, so it can be replayed to the failing line. There's no staging, so ticks cost nothing extra. A failure can't be caught and continued from, since the tick's state may be partly changed; a game that wants to survive a condition checks for it first, with the forms that return a value instead of failing: handling a collection's `Full` result (ignoring it is a build error anyway) or using `checked_add` and the other `Option`-returning operations.
- **Replays are exact on the same build and platform** (decided 2026-10-24): a recording stores the build's identity, its target level and the function versions picked at startup (Targets and CPU features), the initial state and assets, the random seed and the random generator's version, and the inputs. Replaying on another build or machine is best effort.
- **Tools for free:** because the whole game's state is one tree, `inspect` reads any path between ticks, and a recorded run replays tick by tick and stops at the first tick whose state hash differs (as `stasis replay` does).

## Concurrency and interop

Threads share nothing mutable; C is reachable through typed bindings that declare their effects.

**Concurrency**

- Threads, data stacks, queues, snapshots and parallel loops are designed in Threads and data stacks, above.
- No locks in the language: nothing mutable is shared, so data races can't happen.
- I/O waits suspend the job, and an event loop per worker resumes it (Thread kinds and jobs): no `async` colouring in source.

**Interop**

- C functions bind with a declared C prototype and effects. The ABI (the binary calling rules both sides follow) is the platform's C calling convention, with these mappings:
  - Each number as its declared width in the C prototype (`int` as C's `int32_t`, `long` as `int64_t`, `float` and `double` as themselves, `bool` as a byte); a mismatch is a build error and conversions are explicit casts. State's packed storage is never handed to C directly: C gets a value or a buffer in C's own layout.
  - `Text` and `Bytes` as a pointer and a length, valid only during the call; C must not keep the pointer.
  - Records as a pointer to a C struct with the same field order and C's alignment rules; enums as a 32-bit tag followed by the largest payload.
  - Results that grow (text, bytes) written through a runtime buffer function the call is handed (Burin's and AgentLang's ABI).
  - Errors as a return code the binding maps to `Result`; C never returns `none` by convention.
  - No unwinding across the boundary: a C++ exception or Rust panic that reaches it aborts the process, and the binding generator wraps Rust functions to catch panics.
- Rust functions bind through the same C ABI and inline under LTO.
- Bindings to C libraries (zlib, SQLite, crypto) are how CPU-critical or security-critical pieces get done: no home-made crypto.
- Foreign code is trusted; the audit report says so plainly.

## Validation plan and kill criteria

The core is proved on four narrow programs, one per use plus compute, before any widening, each against a strong baseline. Every result records the source revision, the exact command, the machine, its CPU model and the target level built for, peak memory and build time; compute and game results are reported for the baseline and for `x86-64-v3` (or the arm64 equivalent), so the gain from a target level is measured, not assumed.

| Program | Baseline | Target | Kill if |
| --- | --- | --- | --- |
| DEFLATE and CRC-32 (compute) | a C version with precomputed tables, clang -O2, on Silesia's dickens (10.2 MB), one core, median of 9 | throughput 0.9x of C or better | under 0.75x after the facts work |
| Parallel tool: parse and check a source corpus (builders, frozen pools, parallel loops) | a Rust version with the same algorithm and thread count | 0.9x of Rust's time or better, and 3x or more on 4 cores over 1 | under 0.7x of Rust, or under 2.5x scaling on 4 cores |
| Campfire-class server (a SQLite database, pages, live updates) | Burin today; the optimized Rust port | Burin's pages/s within 10%, memory within 1.2x | under 0.7x of Burin, or over 2x its memory |
| Waiting jobs (the same server with 10,000 requests suspended on a slow outside call, from fresh and from previously busy stacks, with snapshots pinned by the running ones) | the Rust port with the same load | stated ceilings met: committed memory under 1 GB for the 10,000, address reservations within admission limits, excess requests answered with 503 | over 2x the Rust port's memory, or any crash or unbounded growth |
| Game simulation (program state, ticks) | Stasis ahead-of-time | equal speed; a small edit running again in 3 s | slower than 0.8x |
| Seeded slips (mutation harness) | crudspec's numbers | 99% of misspelled names caught at their line | under 95% |
| Refinements on the four programs | the same programs without them | at least half of bounds and overflow checks gone; no slower build than 1.2x | builds over 2x slower, or no checks removed |
| Agent changes (scenario-scored feature requests) | the same requests in Rust | equal or better correctness, fewer exchanges | worse on both (AgentLang's outcome) |

The agent study follows the lessons of AgentLang's: the outcome is scored by scenarios the agent never sees, with fresh agents and equal briefs on both sides.

## Risks, open questions and first steps

The largest risk is scope: a general-purpose language is how Hobthrush ended up building everything at once. The first steps happen in this language's own folder (D:\code\next-lang, a working name), copying from Burin's helper compiler, which already reaches 0.89x of C, without depending on Burin.

**Risks**

- *Typed ids instead of pointers* make trees and linked structures index-based. That's efficient, but needs library types (pools, arenas, graphs) so it doesn't feel clumsy.
- *Refinement errors* can baffle ("can't prove i < len(a)"). Each error must name what would prove it (a preceding condition, a parameter type or a loop bound) or the explicit checked cast or `fit` to write.
- *Projections to every layer* tempt layer-specific special cases. Overrides change looks, never meaning.
- *Solver time* (Z3) must stay out of ordinary builds.

**Decided (2026-10-24)**

- Recursion is opt-in: only functions marked `recursive` may call themselves, directly or through a cycle. A recursive cycle can't keep any region alive across its recursive call (a growing value or a large fixed one, also through indirect cycles), and its native stack use is checked against a byte budget; going past it fails the job. Everything else stays recursion-free, so stack assignment stays simple.
- Three types for text and bytes: `Text` (always valid UTF-8, lengths in code points), `Ascii` (ASCII only, one byte per character, the compact form) and `Bytes`.
- `Text` is valid UTF-8 by construction, so it's checked once, where bytes become `Text` (a `Bytes`-to-`Text` conversion, `validate_utf8`, a file read into `Text`, a foreign value arriving), and never again (2026-10-25, Ben): operations on `Text` trust the invariant. Building `Text` from `Text` or `Ascii` pieces sums their code-point counts instead of re-reading the bytes; finding a code-point position counts lead bytes (those that aren't `10xxxxxx` continuation bytes) instead of decoding with validation; printing, comparing, copying and writing `Text` check nothing. Every way to make a `Text` either can't produce invalid bytes (literals refuse `\xNN` above 0x7F, slices can't split a character, `upper` keeps validity) or validates at that boundary.
- The 3 s build is an aspiration for small changes to small and medium programs (up to roughly 50,000 lines), not a guarantee for every program or change.
- Generics are copied per type (as Rust and C++ do): full speed, and LLVM sees concrete types, at a cost in code size and build time that the 3 s aim has to absorb.
- Servers, games and tools weigh equally; the validation has a program for each.
- Jobs can wait: I/O suspends a job, which keeps its own stacks, and the worker runs others meanwhile.
- Running out of a data stack (or another runtime failure) fails the job, not the program; no `Result` on every push.
- v1 targets 64-bit platforms only; WebAssembly and 32-bit come later.
- Build-then-freeze pools for large data shared read-only across threads.
- A value a loop keeps growing must have a bound the compiler knows, and each iteration's temporaries are freed when it ends.
- A failed job discards only its uncommitted batch; committed batches stay, and `transaction { }` groups changes that must succeed together.
- A transaction's checks and writes run on the writer against its latest version, with no waits inside.
- Generic constraints are named interfaces with explicit `impl`s (C#/Rust style), static only: copied per type, no interface-typed values.
- Reusable definitions that hold their own ids take an owner parameter (`struct Node<P> { parent: Option<Id<P>> }`), checked at compile time; ids stay 64 bits.
- Ranges: `a..b` excludes `b` and `a to b` includes it, everywhere (`int 0 to 100`, `for i in 0..8`; `to` replaced Rust's `..=` on 2026-10-27; `..=` still works, deprecated, with a warning); loop counters take their type from their bounds and use.
- `while` loops and the bitwise-not operator `~` are part of the language (2026-10-27).
- Clarity: compound assignment (`+=` and the rest, same checks); unsuffixed literals take their type from context; `??` may `continue` or `break`; `discard` drops `Full` on purpose, from the built-in capacity operations only (collection adds, `try_append`, `Bytes.push`), never from an arbitrary `Result`; named refinements (`type Size = int 1 to 3`, cast as `(Size)(x)`); widening methods like `.to_long()`.
- Parameter modes are written before the type (`write T`, `grow T`; read unwritten). JSON endpoints are an `@[api]` function. Rate limits stay exact through the writer in v1.
- Ranges may be `wrap` (stored values wrap around into the range; float wrapping ranges are half-open) or `clamp` (pinned to the nearest end); plain ranges fail on out-of-range values, and input from outside is always checked, never wrapped or clamped.
- Functions are values (named functions only); there are no closures, and context is passed as an explicit parameter; built-in scoped blocks (`db.read`, `transaction`, routes, `parallel for` bodies) may read locals but can't be stored or returned. Lengths, counts and indexes are `long`.
- Numbers use C#'s names and widths (`int` is 32-bit, `long` 64-bit, `float` and `double`), lowercase like C#'s keywords. No implicit conversions between number types: every one is a cast, and narrowing casts are checked. A plain `double` or `float` never holds NaN; an operation that would produce one fails the job (`double nan` allows it).
- x86-64 builds target `x86-64-v2` by default; v3 and above are opt-in with a build flag or manifest setting, and public software adds v3/v4 clones of hot functions.
- Game replays are exact on the same build and platform; a failed tick stops the game with its recorded inputs. Pages are HTML with `{…}` holes, `live` elements and `signal`; games have a fixed-step `tick(input)` and a read-only `draw(frame)`, as in StasisLang.
- No name shadowing (2026-10-26, Types): a local, parameter, loop variable or binding can't reuse a visible local's name, a package-level name or a built-in's.
- Interpolated strings use a `$` prefix, `$"{x} items"`, with the bound computed from the holes and the same one-pass, in-place building as concatenation (2026-10-26, Text, ASCII and bytes).
- One function form, `fn`, with a fixed, checked set of attributes (`@[job]`, `@[page]`, `@[action]`, `@[api]`, `@[piece]`, `@[versions(...)]`) in place of function keywords (2026-10-26, Function attributes); only `@[job]` functions can be started as jobs.
- Mutable globals are removed from the language (2026-10-26): program state is a local in `main` (or the entry point), passed as `write app: App`; shared state is passed to jobs as a `shared` parameter; `const` stays for immutable named values and tables. By-name access to mutable state was a hidden effect that forced effect inference on globals, created write-argument overlaps and evaluation-order bugs; now all state changes are visible at the call site.
- Static state is meant to be used lightly: most data lives in locals on stacks (bounded collections are ordinary values), in databases or in frozen pools; `inspect memory` warns past a shared-state budget.
- Shared state is sized at build time and allocated in full at startup, never allocating after; program state is part of the entry point's stack; data stacks, job state and frozen batches stay per job, reserved and committed as used.
- Data-stack references are offsets from the job's stack base, not addresses (2026-10-25, Ben; confirmed by measurement in X1), so a stack can start small and move to a larger range when it grows; raw addresses live only between growth points and during pinned foreign calls.
- Data stacks start small, grow by moving (offsets) up to a cap, and commit only what's used (2026-10-25), replacing an interim "reserve generously" rule of the same day: each stack starts at 256 KB or 1.25 times its entry point's recent allocation high-water, moves to a larger range when it needs to grow, up to a per-stack cap (64 GiB default, set per entry point in the manifest), commits pages as touched, and is pooled per worker, keeping its pages while recent runs use them and trimming commitment to 1.25 times recent written pages (per entry point, last 16 runs all under half, 256 KB floor, 5-minute idle trim). The computed worst case sizes no ordinary stack; it drives inspection, warnings, admission estimates and `stack_peak`. Past the cap a job fails at runtime; `strict_stack` commits the full computed worst case at startup, guaranteeing capacity (with `prefault`/`locked` for latency). Admission counts committed pages, not reservations.
- All state is bounded: every collection declares its capacity and each variable-size field its maximum; adding to a full collection returns `Result`.
- Only this program writes its databases in v1; other tools may read them.
- Database records have no row maximum; a deployment may set a disk quota (past it, writes return `Full`). Field maxima and query limits keep memory bounded.
- State is a tree of structs with bounded collections (`T[N]`, `list`, `pool`, `map`, `set`, `queue`, `ring`, `grid`), as in StasisLang, owned by the program (a local passed as `write`), a job, or shared (passed as `shared`, one writer, snapshots); no standalone tables. Databases are a separate feature, not state: typed queries compiled to SQL, SQLite first.

**Open questions**

- How far past medium-sized programs the 3 s aim holds with per-module caching alone, and what to add when it doesn't (a faster code generator for `-O0`, LLVM's FastISel, or splitting modules finer). Measured, not promised: larger programs may simply take longer.
- Operators on declared types (whether and how a type customises `+`, `==` or `<`) still need a design. Generic constraints (named interfaces with explicit `impl`s) and passing errors up (`?` on `Option` and `Result`; `?.` and `??` on `Option` only) follow the contracts above; a fuller reference section on error handling is documentation work, not an open choice.
- Syntax in general: the overview's program is a first proposal, written to make the design concrete. One point the examples raised: a block's last expression is its value (`fn f(s: Text) -> Text { s }`) while `return` also works, which the grammar should state.
- The language's name (the folder's is a working one).

**First steps**

1. State and typed ids: fixed arrays, `list` and `pool` (generation-checked ids) as locals and in a small program-state struct passed as `write`, laid out as one array per field, nested collections flattened.
2. Goose-style stack assignment for growing values, replacing the helper arena: stack contracts (fresh-result and append), iteration scopes, bounds per entry point; `push`, text built from pieces, `out_byte` as a store and bump. Nested growing values are refused at first.
3. Refinements on parameters and fields (range, length, membership, index), inferred through the sign analysis and emitted as LLVM facts. Measured on DEFLATE.
4. `check fast == reference` and `test` blocks with `expect`.
5. Effects inferred on helpers, with the call path in errors.
6. Builders, `freeze` and parallel loops, measured on the parallel tool.
7. The four-program validation above; then decide on widening.

Steps 1 and 2 were built as PLAN.md's M2 and M3 (with `map`, `set`, `queue`, `ring`, `grid` and bounded text in collections), each completing the sequential cases assigned to it; their reports and reviews are listed in PLAN.md "Done". Still open from the cases below: flattened nested lanes (L1 in PLAN.md), reusing a stack across jobs and resetting a failed job's scratch before reuse (the scheduler milestone), and `locked` state, which is refused as unsupported today. Copying, resetting and returning pools are refused for now and listed under Later.
**Acceptance cases for steps 1 and 2** (from review 5; both steps use explicit `Text max` and counted-loop bounds, so they don't wait for step 3's inference)

- *Step 1, program state with fixed-size fields only* (no text yet, no snapshots): a live lookup succeeds; out-of-range and stale ids return `none`; deleting a row and reusing its slot doesn't change which row any other id names, and no row ever moves between slots; a slot set up near the maximum generation is retired, not reused; an id of another pool's type is a build error; an insert at exactly the maximum succeeds and the next returns `Full` without changing the pool; a field assignment whose value may pass the field's maximum is a build error, and a failed checked conversion or `try_append` into a field returns its error and leaves the old fields unchanged; a collection without a capacity or a field without a maximum is a build error. With payloads (still step 1, after fixed-size rows): a text that grows into a larger class moves to a slot from that class's free list and frees its old one, and no other row's bytes move; moving fields across classes with the collection at capacity always succeeds, and a freed slot is reused at once; a nested `list<Item, 8>` inside a pool has its count per element (and flattens, with L1); a fixed array of `int 1 to 100` with a valid initialiser starts, without one is a build error, and lists and pools start with a count of zero; an initialiser reading a field of the value it builds is a build error; a completed value with `start > end` fails startup before any job runs; an `Ascii` passed to a read `Text` parameter isn't copied, and passing it to a write `Text` parameter without a conversion is a build error; refusing the startup backing or lock prevents any job from running; in a tight cgroup, state whose claim exceeds the effective limit doesn't reach job scheduling; a local list over 4 KB and a nested local list are built, returned and copied and stay valid after their source scope ends, and a loop iteration frees its scratch but not an outer local list; a job builds and uses a valid local `Span`, and an invalid completed one fails the job with no partial value visible; `inspect memory` reports globals' startup claim apart from each entry point's stack bounds, and a large local collection counts toward its job, not the startup claim; the render example works with both `view Row max 500` and a bounded `list<Row, 500>`, and an unbounded growing container is still refused; a write that would replace a field under a live view is refused at build time; a view of program state live across a may-suspend call is refused.
- *Step 2, copies and moves:* `fn f(s: Text) -> Text { s }` returns equal bytes and `s` stays usable; returning a local after reading it; a forced copy from scratch to the destination, with the peak counted while old and new coexist; `take` makes the source unusable, hands its stack slot and cleanup to the destination, and keeps the bytes alive until the destination's scope ends (a move that can't keep those rules is refused at first).
- *Step 2, append and bounds:* exact output in fresh-result and append modes, including a four-byte UTF-8 character at the declared maximum; capacity checked before any store; a failed append leaves no partial result in the builder; in `render`, `line` streams into `out`'s reserved region while `name` sits above it, on one data stack with no copies, and the reported peak matches the worked example; three builders open at once each grow in their own reserved region, and a nested call places its temporaries above all of them.
- *Step 2, overlap and iteration cleanup:* `s = s + s` takes a safe fallback (or is refused); `out.append(f(out))` evaluates `f(out)` into separate scratch and finishes reading `out` before the append starts, or is refused; `continue` and `break` discard the iteration's scratch and keep the outer builder; a failed job's scratch is reset before its stack is reused.

**Later** (each needs acceptance cases before its own step; none blocks steps 1 and 2): databases (typed queries, transactions, disk quotas and startup checks, migrations); snapshot reclamation and freed slots held for pinned versions (a case that replaces or removes a field while an old version is pinned, checks its slot isn't reused until unpin, then the whole-batch budget check); pools nested inside repeated elements, refused until supported, with generations kept across any reset of their container; builder handoff as a stated exception to read-only captures, with batch-lifetime cases for step 6; ids and generations when local pools are copied, returned or reset (a returned pool takes its new owner's name); memory backing policies for macOS and Android; route lifetime (whether `serve` copies a route block's context or borrows it until shutdown); synchronous C callbacks that need an answer at once (a direct call on the owner's worker, or refused); time arithmetic (`Time - Time` gives a `Duration`, `Time + Duration` a `Time`, overflow rules) and a monotonic clock for elapsed-time limits, apart from calendar time; SQLite read pins and transaction staging; native-stack admission and foreign-call margins; returned views with a lifetime rule; nested growing values; several instances of one shared global; pools nested inside arrays of structs.
