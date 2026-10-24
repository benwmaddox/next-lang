# Examples

Four small programs, one per kind of use, written to the rules in [DESIGN.md](DESIGN.md) as they stand on 2026-10-24. The syntax is a proposal; the point is to see how the decided rules (bounds, no closures, C# number names, no implicit conversions, `long` indexes, scoped blocks, effects and capabilities) feel in ordinary code, and to judge how clearly the code reads. Each example ends with the open points writing it brought up. Reviews of these examples are in [reviews/](reviews/) (`codex-r20`, `codex-r21`, `claude-ex-r1` and later).

The overview's chat server (DESIGN.md, The language in one page) is a fifth.

## 1. A game: Rocks

An arcade game: a ship that turns, thrusts and fires, and rocks that split when hit. The host calls `tick` 60 times a second and `draw` when it can.

```
// rocks/state.nl
const SCREEN = Vector2(960.0, 540.0)
const TAU: float = 6.2831855                // 2π, one full turn

type Size = int 1..=3                         // 3 is a big rock, 1 the smallest
type Lives = int 0..=3

struct Ship {
    pos: Vector2 = SCREEN * 0.5
    vel: Vector2 = Vector2.zero
    angle: float 0.0..TAU wrap = 0.0       // radians; turning past 2π wraps to 0
    cooldown: int 0..=15 clamp = 0            // ticks until the next shot; counting down stops at 0
    invulnerable_ticks: int 0..=120 clamp = 0 // after a respawn: 120 ticks, 2 s
    lives: Lives = 3
}

struct Rock { pos: Vector2, vel: Vector2, size: Size }
struct Bullet { pos: Vector2, vel: Vector2, ttl: int 0..=60 }

struct Game {
    ship: Ship = Ship {}
    rocks: pool<Rock, 64>
    bullets: pool<Bullet, 32>
    score: long = 0
    rng: Random = Random.seeded(7)           // in the state, so saves and replays include it
    over: bool = false
}

// The game's state: claimed in full at startup, touched up front, never allocates.
global game: Game prefault = Game {}
```

```
// rocks/tick.nl
fn tick(input: Input) {                      // the host's entry point; it only passes the global on
    step(game, input)
}

// Everything else takes the state as a parameter, so tests can run it on a local Game.
fn step(g: write Game, input: Input) {
    if g.over { return }
    steer(g.ship, input)
    if input.held(Key.Space) && g.ship.cooldown == 0 { fire(g) }
    move_bullets(g)
    move_rocks(g)
    hit_rocks(g)
    hit_ship(g)
    if g.rocks.count() == 0 { spawn_wave(g, 4) }
}

fn steer(ship: write Ship, input: Input) {
    if input.held(Key.Left)  { ship.angle -= 0.07 }
    if input.held(Key.Right) { ship.angle += 0.07 }
    if input.held(Key.Up)    { ship.vel += direction(ship.angle) * 0.15 }
    ship.vel *= 0.99                        // drag
    ship.pos = wrap_screen(ship.pos + ship.vel)
    ship.cooldown -= 1                       // clamp: stops at 0
    ship.invulnerable_ticks -= 1
}

fn fire(g: write Game) {
    let shot = Bullet {
        pos: g.ship.pos,
        vel: g.ship.vel + direction(g.ship.angle) * 6.0,
        ttl: 60,
    }
    match g.bullets.add(shot) {
        ok(_) => { g.ship.cooldown = 15 }
        err(Full) => {}                      // 32 bullets in flight already: no shot this time
    }
}

fn move_bullets(g: write Game) {
    // Removing from a pool while looping over it would invalidate the loop's view,
    // so expired ids are collected and removed after the loop.
    var expired: list<g.bullets.Id, 32> = list {}
    for b, id in g.bullets {
        if b.ttl == 0 {
            expired.push(id)                 // can't overflow: at most one id per bullet
        } else {
            b.pos = wrap_screen(b.pos + b.vel)
            b.ttl -= 1
        }
    }
    for id in expired { g.bullets.remove(id) }
}

fn move_rocks(g: write Game) {
    for r in g.rocks { r.pos = wrap_screen(r.pos + r.vel) }
}

fn hit_rocks(g: write Game) {
    // Find every hit first, then remove all the hit rocks, then split them: that way the
    // fragments get every slot the hit rocks freed.
    var hit_rock_ids: list<g.rocks.Id, 64> = list {}
    var spent_bullet_ids: set<g.bullets.Id, 32> = set {}
    for r, rid in g.rocks {
        for b, bid in g.bullets {
            if !spent_bullet_ids.contains(bid) && distance(r.pos, b.pos) < radius(r.size) {
                hit_rock_ids.push(rid)       // each rock once: we break below
                spent_bullet_ids.add(bid)    // each bullet once: skipped above
                break
            }
        }
    }
    var broken: list<Rock, 64> = list {}     // copies of the hit rocks
    for rid in hit_rock_ids {
        let r = g.rocks.get(rid) ?? continue
        broken.push(r)
        g.rocks.remove(rid)
    }
    for bid in spent_bullet_ids { g.bullets.remove(bid) }
    for r in broken {
        g.score += points(r.size).to_long()
        split(g, r)
    }
}

fn hit_ship(g: write Game) {
    if g.ship.invulnerable_ticks > 0 { return }   // just respawned: can't be hit yet
    for r in g.rocks {
        if distance(r.pos, g.ship.pos) < radius(r.size) + 8.0 {
            if g.ship.lives <= 1 {
                g.ship.lives = 0
                g.over = true
            } else {
                g.ship = Ship { lives: g.ship.lives - 1, invulnerable_ticks: 120 }   // back to the centre, one life fewer
            }
            return
        }
    }
}

fn split(g: write Game, r: Rock) {
    if r.size == 1 { return }                // the smallest rocks just vanish
    let smaller = (Size)(r.size - 1)         // proved to fit: r.size is 2 or 3 here
    for k in 0..2 {
        let turn = g.rng.next_float(-1.0, 1.0)
        discard g.rocks.add(Rock { pos: r.pos, vel: rotate(r.vel, turn) * 1.3, size: smaller })
    }                                        // discard: a full field just drops the fragment
}

fn spawn_wave(g: write Game, n: int 1..=8) {
    for k in 0..n {
        let start = Vector2(g.rng.next_float(0.0, SCREEN.x), 0.0)   // along the top edge
        let vel = direction(g.rng.next_float(0.0, TAU)) * 1.2
        discard g.rocks.add(Rock { pos: start, vel, size: 3 })
    }
}

fn direction(angle: float) -> Vector2 { Vector2(cos(angle), sin(angle)) }   // the language's own cos and sin: repeatable on the same build and platform
fn radius(size: Size) -> float { size.to_float() * 12.0 }
fn points(size: Size) -> int { 400 / size }
fn wrap_screen(p: Vector2) -> Vector2 { Vector2(modulo(p.x, SCREEN.x), modulo(p.y, SCREEN.y)) }
```

```
// rocks/draw.nl
// At most 99 draw commands: a clear, 64 rocks, 32 bullets, the ship and the score.
fn draw(frame: Frame max 100) {              // may only read game; the compiler checks
    frame.clear(Color.black)
    for r in game.rocks { frame.circle(r.pos, radius(r.size), Color.gray) }
    for b in game.bullets { frame.dot(b.pos, Color.white) }
    frame.triangle(game.ship.pos, game.ship.angle, 10.0, Color.white)
    frame.text(Vector2(12.0, 12.0), score_line(game.score, game.ship.lives), Color.white)
}

// "Score " (6) + up to 20 for a long + "  Lives " (8) + 1 digit = at most 35.
fn score_line(score: long, lives: Lives) -> Ascii max 40 {
    "Score " + str(score) + "  Lives " + str(lives)
}
```

```
// rocks/tests.nl
test "a bullet splits a big rock in two" {
    var g = Game {}
    g.rocks.add(Rock { pos: Vector2(100.0, 100.0), vel: Vector2.zero, size: 3 }).unwrap()
    g.bullets.add(Bullet { pos: Vector2(100.0, 100.0), vel: Vector2.zero, ttl: 10 }).unwrap()
    hit_rocks(g)
    expect g.rocks.count() == 2
    expect g.bullets.count() == 0
    expect g.score == 133                   // 400 / 3, rounded down
}

test "fragments use the slots of every rock hit in the same tick" {
    var g = Game {}
    for i in 0..62 { g.rocks.add(Rock { pos: Vector2(500.0, 500.0), vel: Vector2.zero, size: 1 }).unwrap() }
    g.rocks.add(Rock { pos: Vector2(100.0, 100.0), vel: Vector2.zero, size: 3 }).unwrap()
    g.rocks.add(Rock { pos: Vector2(300.0, 100.0), vel: Vector2.zero, size: 1 }).unwrap()
    g.bullets.add(Bullet { pos: Vector2(100.0, 100.0), vel: Vector2.zero, ttl: 10 }).unwrap()
    g.bullets.add(Bullet { pos: Vector2(300.0, 100.0), vel: Vector2.zero, ttl: 10 }).unwrap()
    hit_rocks(g)
    expect g.rocks.count() == 64              // 62 untouched + both fragments of the big one
}

test "the last life ends the game" {
    var g = Game {}
    g.ship.lives = 1
    g.rocks.add(Rock { pos: g.ship.pos, vel: Vector2.zero, size: 3 }).unwrap()
    hit_ship(g)
    expect g.over && g.ship.lives == 0
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

**What it exercises:** Rust-style ranges (`int 1..=3`, `for k in 0..2`); float literals with no `f`, taking `float` from context; named refinements (`Size`, `Lives`) and a cast to one (`(Size)(r.size - 1)`); a wrapping range on the angle and clamping ones on the timers, with `+=` and `-=` applying them; removing every hit rock before adding fragments; expiring bullets before they move; a respawn grace period; `?? continue`; `discard` where dropping a value is intended; `Full` handled where it matters (`fire`); pools with typed ids; removing after a loop, not during it; a widening method (`.to_long()`); random state in the game state; a read-only `draw` with a declared draw-list capacity; tests on a local `Game`.

**Open points it raised:**

- *Restarting:* resetting the whole game (`g = Game {}`) replaces pools, which the design's Later list says needs a rule for generations.
- *Ranges:* resolved (2026-10-24): `..` excludes its end and `..=` includes it, everywhere, so `Size = int 1..=3` and `for k in 0..2` (two iterations) no longer use one spelling for two meanings.
- *`Frame max 100`* is a guess at how `draw` declares its draw-list capacity.

## 2. A tool: logsum

A command-line tool that reads a directory of web-server access logs and prints the most requested paths (among the first 20,000 distinct paths it meets) and the share of error responses. Each log can be large, so files are read line by line, never whole, and all of them are counted into one set of totals, so a path's count is exact however many files it appears in.

```
// logsum/main.nl
type UrlPath = Ascii max 200
type HttpStatus = int 100..=599

enum ToolError { Usage, Io(IoError), TooManyFiles }

struct Counts {
    lines: long = 0
    responses: long = 0                      // lines that parsed
    errors: long = 0                         // responses with status 500 to 599
    paths: map<UrlPath, long, 20_000>        // the first 20,000 distinct paths
    unparsed: long = 0                       // lines that didn't parse
    untracked: long = 0                      // responses whose path came after the map filled
}

fn main(env: Env) -> Result<(), ToolError> {
    let dir = env.args().get(1) ?? return err(ToolError.Usage)
    let files = match env.fs.list(dir, max 500) {
        ok(found) => found
        err(Full) => return err(ToolError.TooManyFiles)
        err(e) => return err(ToolError.Io(e))
    }
    var totals = Counts {}
    for path in files { count_file(env.fs, path, totals)? }
    report(env.out, totals)
    ok(())
}

fn count_file(fs: Fs, path: Path, counts: write Counts) -> Result<(), ToolError> {
    let file = tool_result(fs.open(path))?
    for read in file.lines(max 4096) {       // each line is a temporary, freed every iteration
        let line = tool_result(read)?        // a read error ends the run with the error
        counts.lines += 1
        match parse(line) {
            some(entry) => count(counts, entry)
            none => { counts.unparsed += 1 }
        }
    }
    ok(())
}

// The one place an I/O error becomes a ToolError.
fn tool_result<T>(r: Result<T, IoError>) -> Result<T, ToolError> {
    match r {
        ok(value) => ok(value)
        err(e) => err(ToolError.Io(e))
    }
}

struct Entry { path: UrlPath, status: HttpStatus }

// A line looks like: 203.0.113.9 - - [24/Oct/2026:10:12:01 +0000] "GET /r/12 HTTP/1.1" 200 512
// Anything that doesn't fit the format, or a path that isn't ASCII or is over 200 bytes,
// makes the line unparsed.
fn parse(line: Bytes max 4096) -> Option<Entry> {
    let request = line.between('"', '"') ?? return none     // GET /r/12 HTTP/1.1
    let raw_path = request.word(1) ?? return none            // /r/12
    let ascii_path = raw_path.to_ascii().ok() ?? return none
    let path = ascii_path.fit<UrlPath>() ?? return none      // fit: a checked cast that gives an Option

    let response = line.after_last('"') ?? return none       //  200 512
    let status_word = response.word(0) ?? return none        // 200
    let status_number = status_word.parse_int() ?? return none
    let status = status_number.fit<HttpStatus>() ?? return none
    some(Entry { path, status })
}

fn count(counts: write Counts, entry: Entry) {
    counts.responses += 1
    if entry.status >= 500 { counts.errors += 1 }
    let seen = counts.paths.get(entry.path) ?? 0
    // set fails only for a new path once the map holds 20,000
    if counts.paths.set(entry.path, seen + 1).is_err() { counts.untracked += 1 }
}

fn report(out: Out, counts: Counts) {
    out.line("lines      " + str(counts.lines))
    out.line("errors     " + percent(counts.errors, counts.responses))
    out.line("unparsed   " + str(counts.unparsed))
    out.line("untracked  " + str(counts.untracked))
    for top, rank in counts.paths.top_by_value(20) {   // the 20 biggest counts, as {key, value} pairs
        out.line(pad(str(rank + 1), 3) + " " + pad(str(top.value), 10) + " " + top.key)
    }
}

// At most 25 characters, for the most extreme longs.
fn percent(part: long, whole: long) -> Ascii max 32 {
    if whole == 0 { return "0%" }
    str_fixed(part.to_double() * 100.0 / whole.to_double(), 1) + "%"
}
```

```
// logsum/tests.nl
test "parses a normal line" {
    let entry = parse("203.0.113.9 - - [24/Oct/2026:10:12:01 +0000] \"GET /r/12 HTTP/1.1\" 200 512".bytes())
    expect entry == some(Entry { path: "/r/12", status: 200 })
}

test "skips a line without a request" {
    expect parse("garbage".bytes()) == none
}

test "a full path map counts what it can't track" {
    var counts = Counts {}
    for i in 0..20_001 { count(counts, Entry { path: "/p/" + str(i), status: 200 }) }
    expect counts.paths.count() == 20_000
    expect counts.untracked == 1
}

// The bug this guards against: counting each file in its own map and merging after,
// which drops a path that a file meets only after its own map is full.
test "a path's count is exact across files" {
    let fs = Fs.memory()
    fs.write("a.log", log_line("/shared"))
    var b = Text.builder(max 2 MB)
    for i in 0..20_000 { b.append(log_line("/b/" + str(i))) }      // file B fills a map on its own
    for i in 0..1_000 { b.append(log_line("/shared")) }
    fs.write("b.log", b.text())
    var counts = Counts {}
    count_file(fs, "a.log", counts).unwrap()
    count_file(fs, "b.log", counts).unwrap()
    expect counts.paths.get("/shared") == some(1_001)
    expect counts.untracked == 1                    // the last /b/ path: one shared map has 20,001 distinct paths
}

fn log_line(path: Ascii max 200) -> Ascii max 300 {
    "203.0.113.9 - - [24/Oct/2026:10:12:01 +0000] \"GET " + path + " HTTP/1.1\" 200 512\n"
}
```

**What it exercises:** named refinements (`UrlPath`, `HttpStatus`); a bounded directory listing; line-by-line reading with each line freed per iteration; one set of totals passed down in `write` mode; a small generic function (`tool_result`) for the single error conversion; a parser that takes one step per line, each ending in `?? return none`; `fit`, the `Option` form of a checked cast; a bounded `map` whose overflow is counted separately (`untracked`) from bad input (`unparsed`); `+=` on `long` counters with no literal suffixes; widening methods (`.to_double()`); a regression test that reads real (in-memory) files.

**Open points it raised:**

- *Error conversion:* `tool_result(...)?` converts an `IoError` by hand; Rust does this automatically with `From`. One explicit helper per program reads fine here, but a larger program would want the rule in the language.
- *`?.` on a method that already returns an `Option`:* `line.after_last('"')?.word(0)` would give an `Option` inside an `Option`, since `?.` wraps its result. The parser avoids it by taking one step per line; the design should say whether `?.` flattens such results (most languages with `?.` do).
- *Reading files in parallel:* this version reads the files one after another, which keeps every count exact and uses one map. Counting in parallel (one spawned job per file) would need a first pass to choose the 20,000 paths and a second to count them; `parallel for` bodies can't do I/O, so it would use `spawn` and `join`. Worth doing only if measurements say reading is the bottleneck.
- *The busiest paths, really:* keeping the first 20,000 distinct paths can miss one that becomes popular late; a bounded "heavy hitters" structure (approximate counts for the most frequent keys, in fixed space) would fix it, and the standard library could provide one.

## 3. A server API: messages with a rate limit

A JSON API over the chat server's database: list a room's messages a page at a time, and limit how often one address may call it.

```
// chat-api/limits.nl
// Uses the chat server's data (Room, Message, Name, Body) from DESIGN.md's overview.
//
// One token a second, up to 60 saved up. Exact: every request goes through the
// writer (decided 2026-10-24 for v1; measured on the server benchmark).
type Address = Ascii max 45                  // IPv6 text is at most 45 characters

struct Bucket {
    tokens: int 0..=60 = 60
    refilled_through: Instant                // tokens have been added for all time up to here
}

struct Limits { by_address: map<Address, Bucket, 100_000> }

shared global limits: Limits = Limits {}

// The refill rule, on its own: pure, so it's easy to test. One token per whole second
// since refilled_through, at most 60 in all. refilled_through moves on by whole seconds
// only, so a part-second already waited still counts next time.
fn refill(bucket: Bucket, now: Instant) -> Bucket {
    let elapsed_seconds = (now - bucket.refilled_through).whole_seconds()
    let added_tokens = (int)min(elapsed_seconds, 60)
    Bucket {
        tokens: min(60, bucket.tokens + added_tokens),
        refilled_through: bucket.refilled_through + Duration.seconds(elapsed_seconds),
    }
}

// May this address make a call now? Runs on the writer, against the latest version.
// The time is read there, from the monotonic clock (which never jumps back), so a
// request that waited in the queue can't make time run backwards.
fn take_token(address: Address, clock: Clock) -> bool {
    let result = transaction {
        let now = clock.monotonic()
        let known = limits.by_address.get(address) ?? Bucket { refilled_through: now }   // a new address starts full
        var bucket = refill(known, now)
        let allowed = bucket.tokens > 0
        if allowed { bucket.tokens -= 1 }
        limits.by_address.set(address, bucket)?   // a full map ends the transaction with err(Full)
        ok(allowed)
    }
    match result {
        ok(allowed) => allowed
        err(Full) => false                   // 100,000 addresses tracked: refuse until pruned
    }
}

// Every minute, forget addresses that have been quiet for a minute (their bucket
// would be full again anyway), so the map doesn't stay full.
task every 60s prune_limits(clock: Clock) {
    transaction {
        let cutoff = clock.monotonic() - Duration.seconds(60)
        limits.by_address.remove_where(.refilled_through < cutoff)
    }
}
```

```
// chat-api/routes.nl
struct MessageOut { key: Message.Key, author: Name, body: Body }   // the JSON shape

enum ApiError { NotFound, TooMany }

api get_messages(room_key: Room.Key, before: Option<Message.Key>, req: Request,
                 db: Db<Chat>, clock: Clock) -> Result<list<MessageOut, 100>, ApiError> {
    if !take_token(req.address, clock) { return err(ApiError.TooMany) }
    let rows = db.read {
        if Room.get(room_key).is_none() { return err(ApiError.NotFound) }   // leaves get_messages
        match before {
            none => Message.where(.room == room_key).order(.key desc).limit(100)
            some(k) => Message.where(.room == room_key && .key < k).order(.key desc).limit(100)
        }
    }
    var out: list<MessageOut, 100> = list {}
    for m in rows { out.push(MessageOut { key: m.key, author: m.author, body: m.body }) }   // can't overflow: limit(100)
    ok(out)
}

// How errors become responses: one place, so every api answers the same way.
fn respond(e: ApiError) -> Response {
    match e {
        NotFound => Response.status(404)
        TooMany => Response.status(429).header("Retry-After", "1")
    }
}
```

```
// chat-api/tests.nl
// Each scenario starts from the program's initial state (empty limits, a fresh
// in-memory database) and runs with a frozen clock that moves only when it advances it.

test "refill tops up one token a second and keeps the fraction" {
    let t0 = Instant.at_ms(0)
    let empty = Bucket { tokens: 0, refilled_through: t0 }
    let later = refill(empty, t0 + Duration.ms(2_500))
    expect later.tokens == 2
    expect later.refilled_through == t0 + Duration.seconds(2)    // the half second carries over
    expect refill(empty, t0 + Duration.seconds(90)).tokens == 60
}

test "the fraction survives a long wait too" {
    let t0 = Instant.at_ms(0)
    let full = refill(Bucket { tokens: 0, refilled_through: t0 }, t0 + Duration.ms(60_500))
    expect full.tokens == 60
    let drained = Bucket { tokens: 0, refilled_through: full.refilled_through }   // 60 calls at once
    expect refill(drained, t0 + Duration.ms(61_000)).tokens == 1   // refilled through 60 s, so at 61 s a whole second has passed
}

scenario "a reader pages back through history" {
    let db = Db.memory(Chat)
    let room = db.transaction { Room.add(Room { name: "General" }) }.unwrap()
    for i in 0..250 { db.transaction { Message.add(Message { room, author: "ann", body: "m" + str(i) }) }.unwrap() }
    let first = call get_messages(room, none) from "198.51.100.1" with db
    expect first.status == 200 && first.json.len() == 100
    let second = call get_messages(room, some(first.json.last().key)) from "198.51.100.1" with db
    expect second.json.len() == 100
    expect second.json.first().key < first.json.last().key
}

scenario "one address is slowed down, another isn't, and recovers" {
    let db = Db.memory(Chat)
    let general = db.transaction { Room.add(Room { name: "General" }) }.unwrap()
    for i in 0..60 { expect (call get_messages(general, none) from "203.0.113.9" with db).status == 200 }
    expect (call get_messages(general, none) from "203.0.113.9" with db).status == 429
    expect (call get_messages(general, none) from "198.51.100.1" with db).status == 200
    advance 3s
    for i in 0..3 { expect (call get_messages(general, none) from "203.0.113.9" with db).status == 200 }
    expect (call get_messages(general, none) from "203.0.113.9" with db).status == 429
}
```

**What it exercises:** a pure helper (`refill`) split out of a transaction so it can be tested directly; a `shared global` updated in a transaction on its writer; the clock as a capability, read inside the transaction from its monotonic side; `Instant` and `Duration`; the 60-token cap written where it's computed (`min`), not left to a range far away; a scheduled task that prunes quiet addresses; a bounded `map` that fails closed when full; a database read bounded by `limit(100)` and paging by key; a JSON result type generated from a struct; one function mapping errors to responses, headers included; scenarios that start fresh, with a frozen, advanceable clock.

**Open points it raised:**

- *Clocks:* `clock.monotonic()`, `Instant` and a scenario's `advance 3s` are new; DESIGN.md's Later list has the monotonic clock, and this suggests its shape. Reading a capability inside a writer transaction should be allowed explicitly for the clock (it doesn't wait), even though other I/O isn't.
- *Scheduled tasks:* `task every 60s` is new syntax for a recurring job; the design has jobs but not how they're scheduled.
- *`call … from … with db`:* the scenario syntax for calling an `api` as a client would is a guess.

## 4. Compute: CRC-32

The checksum zlib and PNG use, with its 256-entry table computed at compile time, and a slow bit-by-bit version that the fast one must agree with.

```
// crc/crc32.nl
const POLY: uint = 0xEDB88320u

// Evaluated at compile time: the table is data in the binary, so a call on 64 bytes
// costs the loop only (Burin measured 683 ns down to 75 ns from this one change).
const TABLE: uint[256] = make_table()

fn make_table() -> uint[256] {
    var table: uint[256] = fill(0)
    for i in 0..256 {                        // an index: a long, from its use below
        var remainder = (uint)i
        for k in 0..8 {
            remainder = if (remainder & 1) != 0 { POLY ^ (remainder >> 1) } else { remainder >> 1 }
        }
        table[i] = remainder
    }
    table
}

pub fn crc32(data: Bytes) -> uint {
    var crc = 0xFFFFFFFFu
    for b in data {
        let i = (crc ^ b.to_uint()) & 0xFF   // below 256, so the lookup needs no bounds check
        crc = TABLE[i.to_long()] ^ (crc >> 8)
    }
    crc ^ 0xFFFFFFFF
}

fn crc32_bitwise(data: Bytes) -> uint {
    var crc = 0xFFFFFFFFu
    for b in data {
        crc ^= b.to_uint()
        for k in 0..8 {
            crc = if (crc & 1) != 0 { POLY ^ (crc >> 1) } else { crc >> 1 }
        }
    }
    crc ^ 0xFFFFFFFF
}

check crc32 == crc32_bitwise                // on generated inputs and the boundary cases: empty, one byte, long

test "the standard check value" {
    expect crc32("123456789".bytes()) == 0xCBF43926
}
```

**What it exercises:** compile-time evaluation of a constant table; `uint` and bit operations; widening methods (`b.to_uint()`, `i.to_long()`) where a cast used to be; unsuffixed literals taking `uint` from context; `^=`; `if` as an expression; a reference check; a known-answer test.

**Open points it raised:**

- *Loop counter types:* resolved (2026-10-24): a counter takes its type from its bounds and use, so `i` in `for i in 0..256` is a `long` because it indexes `table`.
- *The last expression of a block is its value* (`table`, `crc ^ 0xFFFFFFFF`), while other examples use `return`; DESIGN.md lists this as open.
