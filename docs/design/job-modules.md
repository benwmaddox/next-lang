# Jobs as modules: refined proposal (v0.2, 2026-10-31)

Status: **decisions 1-5 below confirmed by Ben (2026-10-31); the three "Open" items are deferred.** First slice built as a
prototype generator (`tools/svc.py`, see "As built"). Refined from Ben's idea ("a job is more of a module: optional static state, a stack, an
init function, other functions like `tick` for games, and a function for each type of inbound message"). Nothing is
built. It refines `mailboxes.md` (one tagged mailbox per service, reply slots, static topology) and replaces its
"service jobs" sketch.

## Two kinds of job

The web workload shows two different jobs, and the design is simpler if they stay different.

- **A service** is event-driven: state, an inbound mailbox, one handler per message type, optionally `init` and `tick`.
  **A handler runs to completion and never waits.** It may change the service's state, `send` to another service
  (fire and forget), `reply`, or `forward` its reply handle on. Because nothing waits, a service has no stack of its
  own to keep between messages, cannot deadlock, and handlers need no re-entrancy rules. This is the cache, the
  database, a game's world, a rate limiter.
- **A task** is a sequential job with a `run` function that may wait: call a service and wait for the answer, read a
  socket, sleep. It has a stack (and so can be suspended by the scheduler). This is a connection, a batch job, `main`.
  Today's `spawn f(args)` is a task.

A task talks to services; a service talks to services and answers tasks. A service that needs something slow done
(a database read) forwards the request instead of waiting, which is what keeps one slow request from stalling the others.

## Sketch

    service Cache {
        config { db: Sender<Db> }                 // read-only, given at spawn
        state  { slots: list<Row, 4096> }         // owned by this service, bounded, zero-initialised
        mailbox 256

        init { for i in 0..4096 { slots.push(Row.empty()) } }

        on Get(key: long) -> Row? {               // `-> Row?` declares the reply
            let at = key % 4096
            if slots[at].key == key { reply(slots[at]) }
            else { forward db.load(key)  and then self.fill }   // the database answers the caller itself
        }
        on Fill(row: Row) { slots[row.key % 4096] = row }
        tick every 1 s { scrub() }
    }

    task serve(conn: long, cache: Cache) {        // a connection: waits on its socket and on the cache
        loop {
            let req = http.read(conn)?
            let row = cache.get(req.id)?          // suspends until the reply
            http.write(conn, page(row))
        }
    }

Messages and replies:

- The handlers' parameters define the service's message enum (`Cache.Message`), one variant per `on`. The compiler
  generates typed sender methods: `cache.get(key)` (send and wait, in a task), `cache.fill(row)` (send, returns
  `Result<unit, Full>`).
- **Reply handles live in the caller's own memory.** A task that calls services declares how many calls it may have
  outstanding (default 1); each is a slot inside the task's instance, found by index and generation in the message
  (`ReplySlot` of `mailboxes.md`), so there is no global pool and nothing to release. A call whose slot is busy or whose
  target mailbox is full returns `Full`: that is the "busy" answer (503).
- `forward target.message(args)` passes the caller's reply handle to another service, so the answer goes straight back
  to the original caller. A handler may also keep the handle in its state and `reply` later (a pending-request table).
- `reply` is optional in a handler without `->`; a handler declared `-> T` that returns without replying or forwarding is
  a build error.

## Instances and pools

- `service Cache` is a singleton by default. `service Conn pool 10000 { ... }` declares a pool: state (and, for a task,
  stack) for 10,000 instances is allocated once at startup in one block, and `spawn Conn(fd)` takes a free instance or
  returns `Full`. An instance goes back to the pool when its task ends or the service is told to `stop`.
- This is how `mailboxes.md`'s "jobs do not spawn jobs" and the web server's acceptor spawning a job per connection fit
  together: topology is static because the *number* of instances is declared, even though when they start is dynamic.
- `shard` (later): `service Cache x 4 by key` makes four instances and generates `cache.get(key)` to route by key.

## `tick`

- `tick every 16 ms { ... }` runs at a fixed rate. If handlers overrun, missed ticks are skipped, not queued (a counter
  tells the tick how many it missed). Needs timers in the scheduler, which deadlines need too (an epoll timeout or a
  timer wheel).
- Later, `on idle { ... }` for background work done only when the mailbox is empty; each call does bounded work.
- A game: a `World` service with `tick every 16 ms` and `on Input(...)`; a render task reads snapshots.

## What the compiler can then do (compile-time principle)

- Know every instance's size: state + stack (from the handlers' call graph, no recursion) + mailbox ring. Printed by
  `inspect memory`; a program that does not fit its grant is a build error.
- Draw the message graph: which service sends what to which. Blocking edges exist only from tasks, so deadlock can only
  involve tasks; fire-and-forget cycles between services are fine if mailboxes are sized (checked by a bound on
  fan-out per message, when it can be computed).
- Check that every `Result<_, Full>` from a `send` is handled, every `-> T` handler replies or forwards, every message sent
  has a handler, and every mailbox end is closed when its owner stops.

## Testing

- A service can be tested alone: `let cache = Cache.test(config)`, `cache.send(Get(...))`, `cache.step()` (handle one
  message), then read replies and state. No threads, deterministic. This is the single-worker test mode, per service.

## Failure

- A trap in a handler or task marks the instance failed and closes its mailbox ends; the parent sees it (`watch`) and
  `main` decides (restart, shut down). No automatic restart in v1.

## How to start

1. **Front end only.** `service` desugars to what exists: a state struct, a message enum, a dispatch function, a loop
   `recv_wait` + `match`, typed sender wrappers; `-> T` becomes a reply mailbox in the caller. No runtime change.
2. Rewrite `bench/web`'s cache and database jobs as services; compare code size and throughput (no regression expected,
   the code is generated from the same pieces).
3. Reply slots inside task instances and `forward`.
4. Timers and `tick`.
5. Pools (also removes the per-connection stack setup and mailbox leak).
6. Stackless services in the scheduler (no stack held between messages), then event-style connections (`on Readable`) as an
   option for very high connection counts.

## Decisions (confirmed 2026-10-31)

1. Two kinds of job, service and task, with the rule that service handlers never wait. (Replaces the earlier sketch where a
   handler could call another service and block.)
2. Connections are tasks to begin with; readiness-as-messages is a later optimisation.
3. `tick` is fixed rate with skipped (not queued) overruns; `on idle` later.
4. Pools are in the first version of anything used for connections (declared capacity, `Full` when exhausted).
5. Reply slots belong to the calling instance, sized by a declared limit.

## Open

- Syntax for `forward ... and then`: how a service learns the answer of a forwarded request (here: the forward target
  also sends `self.fill`). Alternative: a `pending` table with `reply_later`.
- Whether a service's `state` may hold other services' sender handles directly (yes in `config`), or must pass them through
  messages.
- A service that needs to wait on I/O of its own (a logger writing a file): a task that owns the file and receives
  messages? Probably a task with an inbox, which suggests tasks may also have `on` handlers; to decide with a second
  example.

## As built: step 1, services as a generated front end (2026-10-31)

`tools/svc.py` compiles a package's `*.svc` files to `services.gen.nl` (ignored by git; `scripts/nlc` runs it, as it does
`tools/tmpl.py`). Syntax: `service Name`, `config field: type` (numbers, `Env`, mailbox handles, or another service's name),
`state field: type = initial`, `mailbox N`, `init { ... }`, and `on Message(params) [-> Reply] { ... }`; a block ends with a `}` at
the start of a line. The generator writes the handle struct (`Name`), the message enum (`NameMessage`, a variant per
handler plus `Stop`), the state and config structs, `Name_on_<handler>` functions, the run loop, `Name_start(config)`, a
sender per handler (`Name_get(service, args) -> Option<Reply>` waits for the reply; `Name_fill(service, args) -> bool`),
and `Name_stop`. Handlers see `state` (write), `config`, `me`, their parameters and, with `->`, `reply` (and `reply(value)`).
Calls use a reply mailbox made and released per call. `forward` is the handler passing its `reply` handle on as an argument.

Used in `bench/web`: `cache.svc` and `database.svc` replace about 80 lines of job loops and message structs; a cache miss
forwards the caller's reply handle to the database service, which answers the caller directly and then fills the cache
(one fewer hop than before). Throughput on four cores: 340-350k req/s at 64 connections (was 314k), 261-275k at 1000
(was 249k), 58k at 4.

Not built yet: `tick`, pools, reply slots inside the caller's instance (a reply mailbox is allocated per call), method
syntax (`cache.get(k)`), stackless services, build-time checks of the message graph. Found on the way: `spawn` rejected
an aggregate handle that was a function parameter or a struct field (fixed in `selfhost/jobs.nl`).

## As built: step 2, checks, timers and `tick` (2026-10-31)

- **Checks in `tools/svc.py`:** a handler that calls another service's waiting sender (`Other_get(...)`) is an error ("a
  service handler never waits"; pass `reply` on instead); a handler declared `-> T` must call `reply(...)` or pass `reply`
  on; `reply` in a handler without `->` is an error. The message graph (which handler sends to which service) is appended to
  `services.gen.nl` as comments.
- **Timers in the scheduler:** a min-heap of deadlines; an idle worker's `epoll_wait` times out at the earliest one. A
  job that parks with a timeout is both a waiter and a timer (whichever finds it first resumes it; a wait serial makes a
  timer for an earlier wait harmless). `Env.now_ms()` is a monotonic clock.
- **Mailbox:** `Receiver.recv_for(ms)` waits at most that long (none on timeout; `is_closed()` tells timeout from the end,
  and works on a `Sender` too).
- **`tick every N ms { ... }` in a `.svc`** (needs `config env: Env`): the run loop waits `recv_for` until the next tick,
  handles at most one message per turn, and runs the tick when due. Overruns are skipped, not queued; the body sees `missed`
  (how many ticks it skipped). Tested at 20 ms for about 210 ms: 7 to 11 ticks, under 3 missed.
- Coroutine records are now reused rather than freed (so a stale timer entry never touches freed memory).
Still not built: pools, caller-owned reply slots, method syntax, `on idle`.

## As built: the context pool (2026-10-31)

Not the instance pool of this design (declared capacity, `Full` when exhausted) but the part of it that cost something on
the web path: a finished job's data-stack context goes to a pool (up to 4096) and the next job takes it, so starting a
job maps nothing. See `bench/web/README.md`. The declared instance pool still needs the language side.

## As built: `idle` (2026-10-31)

`idle { ... }` in a `.svc`: runs when the mailbox is empty and returns a bool (the last expression): true when it has more
to do. A turn polls the mailbox first (messages always come first), runs the idle step when it is empty, and waits only when
the step says it is done (with a `tick`, the wait is limited to the next tick). One step should do bounded work. Tested with
a backlog of 5000 steps worked off between five messages.

## Status after the first implementation round (2026-10-31)

Built: services front end (`tools/svc.py`), the checks (handlers never wait, replies answered or passed on, message graph),
timers and `tick`, `idle`, `recv_for` / `is_closed` / `now_ms`, the pooled job contexts.

Not built, with the reason:
- **Method syntax** (`cache.get(k)` for `Cache_get(cache, k)`). A general rule "`x.m(args)` on a struct calls `Type_m(x, args)`"
  would be tidy, but the checker resolves calls by the name token in a long state machine (`compiler_check_bodies.nl`), so it is
  not a small change; it wants its own piece of work in the compiler, not another generator.
- **Declared instance pools** (`service Conn pool 10000`, `Full` when exhausted): needs a language-level instance count and
  `spawn` returning a result; the context pool already removes the mapping cost they were meant to save.
- **Caller-owned reply slots**: a reply mailbox is allocated and released per call (about 160 bytes, one `calloc`/`free`);
  fixing that needs state that belongs to a task, which tasks do not have yet.
- **Stackless services**: the scheduler still gives every service a stack.

## As built: method syntax (2026-10-31)

`x.m(args)` on a value of a user struct `T` calls the function `T_m(x, args)` when it exists (`selfhost/struct_methods.nl`).
It is only a spelling: the checker records the node as a direct call (`FACT_STRUCT_METHOD`, the function id in the node's
fact, call-graph edge, argument and write-mode checks of an ordinary call), and the emitter treats the node as a call with
the receiver as the first argument. Chains work (`p.scaled(3).sum()`), receivers may be fields (`config.db.load(...)`), and
the generated service senders read as `cache.get(id)` instead of `Cache_get(cache, id)`; the old form still works. A name
with no matching function, or a wrong argument count or type, is an ordinary error. `tools/svc.py` finds waiting calls in
handlers in both spellings (receivers `me` and `config.<service field>`). Not covered: a method name that equals a built-in
method of the receiver's own type is not possible for structs (they have none), mailbox handles are structs without a name
and so have no user methods, and enums and other types do not get methods yet.
