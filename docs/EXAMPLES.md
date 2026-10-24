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
    hit_ship(g)
    if g.rocks.count() == 0L {
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
    for b, id in g.bullets {             // b is a writable view of each bullet
        if b.ttl == 0 {
            expired.push(id)               // expires before moving: a 60-tick bullet moves 60 times
        } else {
            b.pos = wrap_screen(b.pos + b.vel)
            b.ttl = b.ttl - 1
        }
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
        let r = match g.rocks.get(rid) {          // a copy of the rock, so it can be removed first
            some(r) => r
            none => continue
        }
        g.score = g.score + (long)points(r.size)
        g.rocks.remove(rid)                        // free its slot before adding the fragments
        split(g, r)
    }
    for bid in spent { g.bullets.remove(bid) }
}

fn hit_ship(g: write Game) {
    for r in g.rocks {
        if distance(r.pos, g.ship.pos) < radius(r.size) + 8.0f {
            if g.ship.lives == 1 {
                g.over = true
            } else {
                g.ship = Ship { lives: g.ship.lives - 1 }   // back to the centre, one life fewer
            }
            return
        }
    }
}

fn split(g: write Game, r: Rock) {
    if r.size == 1 { return }                       // the smallest rocks just vanish
    let smaller = (int 1..3)(r.size - 1)            // checked: r.size is 2 or 3 here, so this fits
    for k in 0..2 {
        let turn = g.rng.next_float(-1.0f, 1.0f)
        let child = Rock { pos: r.pos, vel: rotate(r.vel, turn) * 1.3f, size: smaller }
        if g.rocks.add(child).is_err() {}           // the field is full: the fragment is dropped
    }
}

fn spawn_wave(g: write Game, n: int 1..8) {
    for k in 0..n {
        let edge = Vector2(g.rng.next_float(0.0f, SCREEN.x), 0.0f)   // rocks start at the top edge
        let vel = direction(g.rng.next_float(0.0f, TAU)) * 1.2f
        if g.rocks.add(Rock { pos: edge, vel, size: 3 }).is_err() {}
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

**What it exercises:** removing a hit rock before adding its fragments (so its slot is free), expiring bullets before they move, ship collisions with lives and game over, waves; a `prefault` global with defaults in the struct definitions; a wrapping range on the ship's angle (`float 0.0f..TAU wrap`) and a clamping one on its cooldown (`int 0..15 clamp`); pools with typed ids; removing after the loop, not during it; `Full` handled at every `add`; parameter modes (`write`); a range cast that the compiler can prove (`(int 1..3)(r.size - 1)`); explicit casts (`(long)`, `(float)`); random state kept in the game state; a read-only `draw`; tests on a local `Game`.

**Open points it raised:**

- *Parameter modes:* decided (2026-10-24): written before the type, `g: write Game` or `out: grow Text`; read is the default and isn't written.
- *Pushes the compiler can prove safe:* DESIGN.md already lets a push or add that the compiler proves can't overflow skip the `Result` (Collections); `hit.push(rid)` and `spent.add(bid)` rely on it, and the compiler has to prove each holds at most as many ids as its pool.
- *Element views in loops:* now in DESIGN.md: a loop variable over a collection the function may write (`for r in g.rocks`) is a writable view of each element, under the usual view rules (no removing from the collection inside the loop).
- *Two meanings of `..`:* in a plain refinement (`int 0..100`) the range includes its end, a wrapping float range (`float 0.0f..TAU wrap`) excludes it; in a loop (`for k in 0..2`) it stops before it. The design should either say so plainly or use two spellings (Rust has `..` and `..=`).
- *Restarting:* resetting the whole game (`g = Game {}`) replaces pools, which the design's Later list says needs a rule for generations.

## 2. A tool: logsum

A command-line tool that reads a directory of web-server access logs and prints the most requested paths (among the first 20,000 distinct paths it meets) and the share of error responses. Each log can be large, so files are read line by line, never whole.

```
// logsum/main.nl
enum ToolError { Usage, Io(IoError), TooManyFiles }

struct Counts {
    lines: long = 0
    responses: long = 0                            // lines that parsed
    errors: long = 0                               // responses with status 500 to 599
    paths: map<Ascii max 200, long, 20_000>        // counts for the first 20,000 distinct paths met; later new paths are counted in skipped
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
        let c = j.join()?                  // join gives the job function's own Result; a crashed job fails the run
        merge(total, c)
    }
    report(env.out, total)
    ok(())
}

fn count_file(fs: Fs, path: Path) -> Result<Counts, ToolError> {
    var c = Counts {}
    let file = fs.open(path).map_io()?      // IoError to ToolError: see the open points
    for line in file.lines(max 4096) {         // each line is a temporary, freed every iteration; a read error ends the loop with err, passed up like open's
        c.lines = c.lines + 1L
        match parse(line) {
            some(entry) => { c.responses = c.responses + 1L; add(c, entry) }
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
    let ascii_path = match path.to_ascii() { ok(p) => p, err(_) => return none }   // a non-ASCII path: skipped
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
    total.responses = total.responses + part.responses
    total.errors = total.errors + part.errors
    total.skipped = total.skipped + part.skipped
    for path, n in part.paths {
        let m = total.paths.get(path) ?? 0L
        if total.paths.set(path, m + n).is_err() { total.skipped = total.skipped + n }
    }
}

fn report(out: Out, c: Counts) {
    let top = c.paths.top_by_value(20)                   // a list<map.Pair<Ascii max 200, long>, 20>: {key, value}
    out.line("lines   " + str(c.lines))
    out.line("errors  " + percent(c.errors, c.responses))
    out.line("skipped " + str(c.skipped))
    for pair, i in top {
        out.line(pad(str(i + 1L), 3) + " " + pad(str(pair.value), 10) + " " + pair.key)
    }
}

fn percent(part: long, whole: long) -> Ascii max 32 {      // long enough for any long, a decimal point and %
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
- *Tuples:* `report` uses a named `{key, value}` pair from the map, since the design has no tuples; whether to add them is open.
- *The busiest paths, really:* the map keeps the first 20,000 distinct paths and counts the rest as skipped, so a path that only becomes popular late can be missed. A real tool would use a bounded "heavy hitters" structure (one that keeps approximate counts for the most frequent keys in fixed space); the standard library could provide one.
- *`try_as`:* the Option form of a checked cast needs a declared contract in the standard library.

## 3. A server API: messages with a rate limit

A JSON API over the chat server's database: list a room's messages a page at a time, and limit how often one address may call it.

```
// chat-api/limits.nl
// One token a second, up to 60 saved up. Exact: every request goes through the
// writer (decided 2026-10-24 for v1; measured on the server benchmark).
struct Bucket {
    tokens: int 0..60 clamp = 60
    since: Instant                 // when the tokens were last topped up, by the writer's clock
}

struct Limits {
    by_address: map<Ascii max 45, Bucket, 100_000>     // IPv6 text is at most 45 characters
}

shared global limits: Limits = Limits {}

// Returns true if the call may go ahead. Runs on the writer, against the latest version.
// The time is the writer's own monotonic clock (one that never jumps back), read when the
// transaction is applied, so a request that waited in the queue can't make time run backwards.
fn take_token(address: Ascii max 45) -> bool {
    let result = transaction {
        let now = writer_clock()
        let b = limits.by_address.get(address) ?? Bucket { since: now }
        let whole = (now - b.since).whole_seconds()           // a long, never negative
        let tokens = b.tokens + (int)min(whole, 60L)          // clamp keeps it at 60 at most
        // Advance `since` by the whole seconds used, not to `now`, so the fraction
        // of a second already waited isn't lost.
        let since = if tokens >= 60 { now } else { b.since + Duration.seconds(whole) }
        if tokens == 0 {
            limits.by_address.set(address, Bucket { tokens: 0, since })?
            ok(false)
        } else {
            limits.by_address.set(address, Bucket { tokens: tokens - 1, since })?
            ok(true)                   // `?` above: a full map ends the transaction with err(Full)
        }
    }
    match result {
        ok(allowed) => allowed
        err(Full) => false             // 100,000 addresses tracked: fail closed until pruned
    }
}

// A task the server runs every minute: forget addresses that have been quiet for a
// minute (their bucket would be full again anyway), so the map doesn't stay full.
task every 60s prune_limits() {
    transaction {
        let now = writer_clock()
        limits.by_address.remove_where(.since < now - Duration.seconds(60))
    }
}
```

```
// chat-api/routes.nl
struct MessageOut { key: Message.Key, author: Name, body: Body }   // the JSON shape

enum ApiError { NotFound, TooMany, BadRequest }

api get_messages(room_key: Room.Key, before: Option<Message.Key>, req: Request,
                 db: Db<Chat>) -> Result<list<MessageOut, 100>, ApiError> {
    if !take_token(req.address) { return err(ApiError.TooMany) }
    let rows = db.read {
        if Room.get(room_key).is_none() { return err(ApiError.NotFound) }   // leaves get_messages
        match before {
            none => Message.where(.room == room_key).order(.key desc).limit(100)
            some(k) => Message.where(.room == room_key && .key < k).order(.key desc).limit(100)
        }
    }
    var out: list<MessageOut, 100> = list {}
    for m in rows {
        out.push(MessageOut { key: m.key, author: m.author, body: m.body })   // can't overflow: limit(100)
    }
    ok(out)
}

// How errors become responses: one place, so every api answers the same way.
fn respond(e: ApiError) -> Response {
    match e {
        NotFound => Response.status(404)
        TooMany => Response.status(429).header("Retry-After", "1")
        BadRequest => Response.status(400)
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

scenario "one address is slowed down, another isn't, and recovers" {
    // Scenarios run with a frozen clock; time moves only when the scenario advances it.
    for i in 0..60 { expect (call get_messages(general, none) from "203.0.113.9").status == 200 }
    expect (call get_messages(general, none) from "203.0.113.9").status == 429
    expect (call get_messages(general, none) from "198.51.100.1").status == 200
    advance 3s
    for i in 0..3 { expect (call get_messages(general, none) from "203.0.113.9").status == 200 }
    expect (call get_messages(general, none) from "203.0.113.9").status == 429
}
```

**What it exercises:** a `shared global` updated in a transaction on its writer; a monotonic writer clock (`Instant`, which never jumps back) and `Duration`, keeping the fraction of a second already waited; a `clamp` range on the token count; a scheduled task that prunes quiet addresses; a bounded `map` that fails closed when full; a database read with the query bounded by `limit(100)` and paging by key; a JSON result type generated from a struct; one function mapping errors to responses, headers included (`Retry-After`); a cursor that branches on `none` instead of using a maximum key; scenarios against an in-memory database with a frozen, advanceable clock.

**Open points it raised:**

- *Every request writes shared state:* decided for v1 (2026-10-24): rate limits stay exact, through the writer, and the server benchmark measures what that costs. Per-worker approximate counts are the fallback if the writer becomes the bottleneck.
- *A transaction that returns a value:* now in DESIGN.md: a transaction's value is its block's value, and `?` inside one aborts it (its changes are discarded) with the error.
- *`return` inside a scoped block:* now in DESIGN.md: a `return` in a scoped block leaves the enclosing function, carried out through the generated helper.
- *`api`:* decided (2026-10-24): JSON endpoints are their own kind, `api`, next to `page` (HTML) and `action` (form posts), with a typed result and one error-to-response function.
- *Clocks:* `writer_clock()`, `Instant` and a scenario's `advance 3s` are new; DESIGN.md's Later list has the monotonic clock, and this suggests its shape.
- *Scheduled tasks:* `task every 60s` is new syntax for a recurring job; the design has jobs but not how they're scheduled.

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
