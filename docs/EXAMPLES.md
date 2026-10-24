# Examples

Four small programs, one per kind of use, written to the rules in [DESIGN.md](DESIGN.md) as they stand on 2026-10-24. The syntax is a proposal; the point is to see how the decided rules (bounds, no closures, C# number names, no implicit conversions, `long` indexes, scoped blocks, effects and capabilities) feel in ordinary code. Each example ends with the open points writing it brought up.

The overview's chat server (DESIGN.md, The language in one page) is a fifth.

## 1. A game: Rocks

An arcade game: a ship that turns, thrusts and fires, and rocks that split when hit. The host calls `tick` 60 times a second and `draw` when it can.

```
// rocks/state.nl
const SCREEN = Vector2(960.0f, 540.0f)
const TAU: float = 6.2831855f            // 2π, one full turn

struct Ship {
    pos: Vector2 = SCREEN * 0.5f
    vel: Vector2 = Vector2.zero
    angle: float 0.0f..TAU wrap = 0.0f   // radians; turning past 2π wraps to 0 (and below 0 to just under 2π)
    cooldown: int 0..15 clamp = 0        // ticks until the next shot; counting down stops at 0
    lives: int 0..3 = 3
}

struct Rock { pos: Vector2, vel: Vector2, size: int 1..3 }
struct Bullet { pos: Vector2, vel: Vector2, ttl: int 0..60 }

struct Game {
    ship: Ship = Ship {}
    rocks: pool<Rock, 64>
    bullets: pool<Bullet, 32>
    score: long = 0
    rng: Random = Random.seeded(7)     // in the state, so saves and replays include it
    over: bool = false
}

// The game's state: claimed in full at startup, touched up front, never allocates.
global game: Game prefault = Game {}
```

```
// rocks/tick.nl
fn tick(input: Input) {                 // the host's entry point; it only passes the global on
    step(game, input)
}

// Everything else takes the state as a parameter, so tests can run it on a local Game.
fn step(g: write Game, input: Input) {
    if g.over { return }
    steer(g.ship, input)
    if input.held(Key.Space) && g.ship.cooldown == 0 {
        fire(g)
    }
    move_bullets(g)
    move_rocks(g)
    hit_rocks(g)
    if g.rocks.count() == 0 {
        spawn_wave(g, 4)
    }
}

fn steer(ship: write Ship, input: Input) {
    if input.held(Key.Left)  { ship.angle = ship.angle - 0.07f }
    if input.held(Key.Right) { ship.angle = ship.angle + 0.07f }
    if input.held(Key.Up)    { ship.vel = ship.vel + direction(ship.angle) * 0.15f }
    ship.vel = ship.vel * 0.99f        // drag
    ship.pos = wrap_screen(ship.pos + ship.vel)
    ship.cooldown = ship.cooldown - 1        // clamp: never below 0, no check needed
}

fn fire(g: write Game) {
    let shot = Bullet {
        pos: g.ship.pos,
        vel: g.ship.vel + direction(g.ship.angle) * 6.0f,
        ttl: 60,
    }
    match g.bullets.add(shot) {
        ok(_) => { g.ship.cooldown = 15 }
        err(Full) => {}                // 32 bullets in flight already: this shot just doesn't happen
    }
}

fn move_bullets(g: write Game) {
    // Removing from a pool while looping over it would invalidate the loop's view,
    // so the ids are collected first. The list can't overflow: it holds at most
    // as many ids as the pool has elements, and the compiler can prove it.
    var expired: list<g.bullets.Id, 32> = list {}
    for b, id in g.bullets {
        b.pos = wrap_screen(b.pos + b.vel)
        if b.ttl == 0 { expired.push(id) } else { b.ttl = b.ttl - 1 }
    }
    for id in expired { g.bullets.remove(id) }
}

fn move_rocks(g: write Game) {
    for r in g.rocks { r.pos = wrap_screen(r.pos + r.vel) }
}

fn hit_rocks(g: write Game) {
    var hit: list<g.rocks.Id, 64> = list {}       // each rock at most once: the inner loop breaks
    var spent: set<g.bullets.Id, 32> = set {}     // a bullet stops at the first rock it hits
    for r, rid in g.rocks {
        for b, bid in g.bullets {
            if !spent.contains(bid) && distance(r.pos, b.pos) < radius(r.size) {
                hit.push(rid)
                spent.add(bid)
                break
            }
        }
    }
    for rid in hit {
        let r = g.rocks.get(rid) ?? continue
        g.score = g.score + (long)(points(r.size))
        if r.size > 1 { split(g, r) }
        g.rocks.remove(rid)
    }
    for bid in spent { g.bullets.remove(bid) }
}

fn split(g: write Game, r: Rock) {
    for k in 0..2 {
        let turn = g.rng.next_float(-1.0f, 1.0f)
        let child = Rock {
            pos: r.pos,
            vel: rotate(r.vel, turn) * 1.3f,
            size: (int 1..3)(r.size - 1),      // checked: r.size > 1 here, so this fits
        }
        if g.rocks.add(child).is_err() {}      // the field is full: the fragment is dropped
    }
}

fn direction(angle: float) -> Vector2 { Vector2(cos(angle), sin(angle)) }   // the language's own cos and sin: exact everywhere
fn radius(size: int 1..3) -> float { (float)size * 12.0f }
fn points(size: int 1..3) -> int { 400 / size }
fn wrap_screen(p: Vector2) -> Vector2 { Vector2(modulo(p.x, SCREEN.x), modulo(p.y, SCREEN.y)) }
```

```
// rocks/draw.nl
fn draw(frame: Frame) {                 // may only read game; the compiler checks
    frame.clear(Color.black)
    for r in game.rocks { frame.circle(r.pos, radius(r.size), Color.gray) }
    for b in game.bullets { frame.dot(b.pos, Color.white) }
    frame.triangle(game.ship.pos, game.ship.angle, 10.0f, Color.white)
    frame.text(Vector2(12.0f, 12.0f), score_line(game.score, game.ship.lives), Color.white)
}

fn score_line(score: long, lives: int 0..3) -> Ascii max 40 {
    "Score " + str(score) + "  Lives " + str(lives)
}
```

```
// rocks/tests.nl
test "a bullet splits a big rock in two" {
    var g = Game {}
    g.rocks.add(Rock { pos: Vector2(100.0f, 100.0f), vel: Vector2.zero, size: 3 }).unwrap()
    g.bullets.add(Bullet { pos: Vector2(100.0f, 100.0f), vel: Vector2.zero, ttl: 10 }).unwrap()
    hit_rocks(g)
    expect g.rocks.count() == 2
    expect g.bullets.count() == 0
    expect g.score == 133
}

test "the bullet limit holds" {
    var g = Game {}
    for i in 0..40 {
        g.ship.cooldown = 0
        fire(g)
    }
    expect g.bullets.count() == 32
}
```

**What it exercises:** a `prefault` global with defaults in the struct definitions; a wrapping range on the ship'"'"'s angle (`float 0.0f..TAU wrap`) and a clamping one on its cooldown (`int 0..15 clamp`); pools with typed ids; removing after the loop, not during it; `Full` handled at every `add`; parameter modes (`write`); a range cast that the compiler can prove (`(int 1..3)(r.size - 1)`); explicit casts (`(long)`, `(float)`); random state kept in the game state; a read-only `draw`; tests on a local `Game`.

**Open points it raised:**

- *Parameter-mode syntax:* `g: write Game` is a guess; the design names the modes (read, write, grow) but not how to write them.
- *Pushes the compiler can prove safe:* `hit.push(rid)` and `spent.add(bid)` can't overflow (each holds at most as many ids as its pool), so the design should let a proven push skip the `Result`; otherwise every one of these needs handling that can never run.
- *Element views in loops:* `for r in g.rocks { r.pos = … }` writes through the loop variable. The design allows writing fixed-size fields of the element a view is on; it should say loop variables over a writable collection are writable views.
- *Two meanings of `..`:* in a plain refinement (`int 0..100`) the range includes its end, a wrapping float range (`float 0.0f..TAU wrap`) excludes it; in a loop (`for k in 0..2`) it stops before it. The design should either say so plainly or use two spellings (Rust has `..` and `..=`).
- *Restarting:* resetting the whole game (`g = Game {}`) replaces pools, which the design's Later list says needs a rule for generations.

## 2. A tool: logsum

A command-line tool that reads a directory of web-server access logs and prints the busiest paths and the share of error responses. Each log can be large, so files are read line by line, never whole.

```
// logsum/main.nl
enum ToolError { Usage, Io(IoError), TooManyFiles }

struct Counts {
    lines: long = 0
    errors: long = 0                               // status 500 to 599
    paths: map<Ascii max 200, long, 20_000>        // the 20,000 busiest distinct paths per file
    skipped: long = 0                              // lines that didn't parse, or paths past the map's capacity
}

fn main(env: Env) -> Result<(), ToolError> {
    let dir = env.args().get(1) ?? return err(ToolError.Usage)
    let files = match env.fs.list(dir, max 500) {   // a bounded listing
        ok(f) => f
        err(Full) => return err(ToolError.TooManyFiles)
        err(e) => return err(ToolError.Io(e))
    }

    // One job per file, so files are read and counted in parallel; each job has its
    // own stacks and waits on its own reads.
    var jobs: list<Job<Counts>, 500> = list {}
    for path in files {
        jobs.push(spawn count_file(env.fs, path))
    }

    var total = Counts {}
    for j in jobs {
        let c = j.join()?                  // a failed file fails the run, with its error
        merge(total, c)
    }
    report(env.out, total)
    ok(())
}

fn count_file(fs: Fs, path: Path) -> Result<Counts, ToolError> {
    var c = Counts {}
    let file = fs.open(path).map_io()?
    for line in file.lines(max 4096) {         // each line is a temporary, freed every iteration
        c.lines = c.lines + 1L
        match parse(line) {
            some(entry) => add(c, entry)
            none => { c.skipped = c.skipped + 1L }
        }
    }
    ok(c)
}

struct Entry { path: Ascii max 200, status: int 100..599 }

// A line looks like: 203.0.113.9 - - [24/Oct/2026:10:12:01 +0000] "GET /r/12 HTTP/1.1" 200 512
fn parse(line: Bytes max 4096) -> Option<Entry> {
    let request = line.between('"', '"') ?? return none
    let path = request.split_at(' ', 1) ?? return none
    let after = line.after_last('"') ?? return none
    let status = after.trim().take_until(' ').parse_int() ?? return none
    let ascii_path = path.to_ascii() ?? return none          // a non-ASCII path: skipped
    let short = ascii_path.limit(200) ?? return none         // a path longer than 200 bytes: skipped
    let code = status.try_as<int 100..599>() ?? return none  // the Option form of a checked cast
    some(Entry { path: short, status: code })
}

fn add(c: write Counts, e: Entry) {
    if e.status >= 500 { c.errors = c.errors + 1L }
    let n = c.paths.get(e.path) ?? 0L
    if c.paths.set(e.path, n + 1L).is_err() {      // set fails only for a new key in a full map
        c.skipped = c.skipped + 1L
    }
}

fn merge(total: write Counts, part: Counts) {
    total.lines = total.lines + part.lines
    total.errors = total.errors + part.errors
    total.skipped = total.skipped + part.skipped
    for path, n in part.paths {
        let m = total.paths.get(path) ?? 0L
        if total.paths.set(path, m + n).is_err() { total.skipped = total.skipped + n }
    }
}

fn report(out: Out, c: Counts) {
    let top = c.paths.top_by_value(20)                   // a list<(Ascii max 200, long), 20>
    out.line("lines   " + str(c.lines))
    out.line("errors  " + percent(c.errors, c.lines))
    out.line("skipped " + str(c.skipped))
    for pair, i in top {
        out.line(pad(str(i + 1L), 3) + " " + pad(str(pair.1), 10) + " " + pair.0)
    }
}

fn percent(part: long, whole: long) -> Ascii max 16 {
    if whole == 0L { return "0%" }
    str_fixed((double)part * 100.0 / (double)whole, 1) + "%"
}
```

```
// logsum/tests.nl
test "parses a normal line" {
    let e = parse("203.0.113.9 - - [24/Oct/2026:10:12:01 +0000] \"GET /r/12 HTTP/1.1\" 200 512".bytes())
    expect e == some(Entry { path: "/r/12", status: 200 })
}

test "skips a line without a request" {
    expect parse("garbage".bytes()) == none
}

test "a full path map counts what it drops" {
    var c = Counts {}
    for i in 0L..20_001L { add(c, Entry { path: "/p/" + str(i), status: 200 }) }
    expect c.paths.count() == 20_000L
    expect c.skipped == 1L
}
```

**What it exercises:** a bounded directory listing; one spawned job per file instead of a parallel loop, because the work does I/O; line-by-line reading with a declared line maximum, each line freed per iteration; `Bytes` to `Ascii` checked conversions; `Option`-returning parsing with `?? return none`, including a checked cast's `Option` form (`try_as`); a bounded `map` with its overflow counted, not lost silently; `long` counters and explicit casts to `double`.

**Open points it raised:**

- *Parallel I/O:* `parallel for` bodies may have no effects, so a tool that reads many files uses `spawn` and `join`. That's fine, but the design should say so, and say how many spawned jobs can run at once (admission).
- *Large fixed values:* each `Counts` holds a 20,000-entry map, several megabytes, and every job has one, then `join` copies it out. That's bounded and correct, but heavy; a tool like this may want each job to write into its own slot of a frozen batch instead.
- *`.map_io()?`* converts an `IoError` into `ToolError`; the design has no rule yet for converting error types when passing them up with `?` (Rust uses a `From` conversion).
- *Tuples:* `pair.0` and `pair.1` assume tuples exist; the design doesn't mention them.

## 3. A server API: messages with a rate limit

A JSON API over the chat server's database: list a room's messages a page at a time, and limit how often one address may call it.

```
// chat-api/limits.nl
struct Bucket { tokens: int 0..60 = 60, refilled: Time }

struct Limits {
    by_address: map<Ascii max 45, Bucket, 100_000>     // IPv6 text is at most 45 characters
}

// Every request reads and updates this, so it's shared state with one writer.
shared global limits: Limits = Limits {}

// Returns true if the call may go ahead. Runs on the writer, against the latest version.
fn take_token(address: Ascii max 45, now: Time) -> bool {
    let result = transaction {
        let b = limits.by_address.get(address) ?? Bucket { refilled: now }
        let waited = (now - b.refilled).seconds()                      // a long
        let tokens = min(60L, (long)b.tokens + waited)
        if tokens == 0L {
            ok(false)
        } else {
            limits.by_address.set(address, Bucket { tokens: (int 0..60)(tokens - 1L), refilled: now })?
            ok(true)                   // `?` above: a full map ends the transaction with err(Full)
        }
    }
    match result {
        ok(allowed) => allowed
        err(Full) => false             // 100,000 addresses tracked already: fail closed
    }
}
```

```
// chat-api/routes.nl
struct MessageOut { key: Message.Key, author: Name, body: Body, sent: Time }   // the JSON shape

enum ApiError { NotFound, TooMany, BadRequest }

api get_messages(room_key: Room.Key, before: Option<Message.Key>, req: Request,
                 db: Db<Chat>, clock: Clock) -> Result<list<MessageOut, 100>, ApiError> {
    if !take_token(req.address, clock.now()) { return err(ApiError.TooMany) }
    let rows = db.read {
        if Room.get(room_key).is_none() { return err(ApiError.NotFound) }
        Message.where(.room == room_key && .key < (before ?? Message.Key.max))
               .order(.key desc)
               .limit(100)
    }
    var out: list<MessageOut, 100> = list {}
    for m in rows {
        out.push(MessageOut { key: m.key, author: m.author, body: m.body, sent: m.sent })
    }
    ok(out)
}

// How errors become responses: one place, so every route answers the same way.
fn status(e: ApiError) -> HttpStatus {
    match e {
        NotFound => HttpStatus.NotFound            // 404
        TooMany => HttpStatus.TooManyRequests      // 429, with Retry-After
        BadRequest => HttpStatus.BadRequest        // 400
    }
}
```

```
// chat-api/tests.nl
scenario "a reader pages back through history" {
    let db = Db.memory(Chat)
    let room = db.transaction { Room.add(Room { name: "General" }) }.unwrap()
    for i in 0..250 { db.transaction { Message.add(Message { room, author: "ann", body: "m" + str(i) }) }.unwrap() }
    let first = call get_messages(room, none) from "198.51.100.1"
    expect first.status == 200 && first.json.len() == 100L
    let second = call get_messages(room, some(first.json.last().key)) from "198.51.100.1"
    expect second.json.len() == 100L
    expect second.json.first().key < first.json.last().key
}

scenario "one address is slowed down, another isn't" {
    for i in 0..60 { expect (call get_messages(general, none) from "203.0.113.9").status == 200 }
    expect (call get_messages(general, none) from "203.0.113.9").status == 429
    expect (call get_messages(general, none) from "198.51.100.1").status == 200
}
```

**What it exercises:** a `shared global` updated in a transaction on its writer; `Time` and `Duration`; a bounded `map` that fails closed when full; a database read with the query bounded by `limit(100)` and paging by key; a JSON result type generated from a struct; one function mapping errors to HTTP statuses; scenarios against an in-memory database.

**Open points it raised:**

- *Every request writes shared state:* the rate limiter sends a transaction to the writer on every call, so the writer's speed caps the whole API. A per-worker limiter (a plain global on each worker's home, approximate but writer-free) may be the better idiom; the design should say which.
- *A transaction that returns a value:* `take_token`'s transaction returns `Result<bool, Full>`, and `?` inside it ends the transaction (discarding its changes) with the error. The design should state both: what a transaction's value is, and that `?` inside one aborts it.
- *`return` inside a scoped block:* `return err(...)` inside `db.read { }` leaves the function from inside the block; the design should allow it explicitly (the block is lowered to a helper, so the compiler has to carry the return out).
- *`api` vs `action`:* the overview has `page` and `action`; JSON endpoints suggest a third kind, `api`, or one `route` kind with a result type deciding HTML or JSON.

## 4. Compute: CRC-32

The checksum zlib and PNG use, with its 256-entry table computed at compile time, and a slow bit-by-bit version that the fast one must agree with.

```
// crc/crc32.nl
const POLY: uint = 0xEDB88320u

// Evaluated at compile time: the table is data in the binary, so a call on 64 bytes
// costs the loop only (Burin measured 683 ns down to 75 ns from this one change).
const TABLE: uint[256] = make_table()

fn make_table() -> uint[256] {
    var t: uint[256] = fill(0u)
    for i in 0L..256L {
        var c = (uint)i
        for k in 0..8 {
            c = if (c & 1u) != 0u { POLY ^ (c >> 1) } else { c >> 1 }
        }
        t[i] = c
    }
    t
}

pub fn crc32(data: Bytes) -> uint {
    var crc = 0xFFFFFFFFu
    for b in data {
        crc = TABLE[(long)((crc ^ (uint)b) & 0xFFu)] ^ (crc >> 8)
    }
    crc ^ 0xFFFFFFFFu
}

fn crc32_bitwise(data: Bytes) -> uint {
    var crc = 0xFFFFFFFFu
    for b in data {
        crc = crc ^ (uint)b
        for k in 0..8 {
            crc = if (crc & 1u) != 0u { POLY ^ (crc >> 1) } else { crc >> 1 }
        }
    }
    crc ^ 0xFFFFFFFFu
}

check crc32 == crc32_bitwise          // on generated inputs and the boundary cases: empty, one byte, long

test "the standard check value" {
    expect crc32("123456789".bytes()) == 0xCBF43926u
}
```

**What it exercises:** compile-time evaluation of a constant table; `uint` and bit operations; casts that can't fail (`(uint)b` from a `byte`, `(long)` for an index), written anyway since there are no implicit conversions; `if` as an expression; a reference check; a known-answer test. The index `(crc ^ (uint)b) & 0xFFu` is provably below 256, so the table lookup carries no bounds check.

**Open points it raised:**

- *Casts that can't fail* (`(uint)b`, `(long)(... & 0xFFu)`) are noise in bit-heavy code. No implicit conversions is decided; a shorter spelling for "widen, can't fail", such as `b.u32`, may be worth it.
- *`0L..256L`:* because indexes are `long`, the loop counter is `long`, while `0..8` is an `int` range. Ranges might take their type from what they index.
- *The last expression of a block is its value* (`t`, `crc ^ 0xFFFFFFFFu`) in these examples, while the overview uses `return` and `ok(())`; one style should be chosen.
