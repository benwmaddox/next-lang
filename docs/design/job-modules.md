# Avenue to explore: jobs as modules (proposed by Ben, 2026-10-31)

Status: an idea to explore, not decided. Nothing is built.

## The idea

A job is more of a module: a collection of optional static state, a stack, an `init` function, other functions such as
`tick` (for games), and one function for each type of inbound message. The runtime owns the loop; the programmer writes
the handlers.

## Why it fits

- `bench/web` repeats one loop in three jobs (`recv_wait`, `match some/none`, an `if msg.kind == ...` chain, `break`) and
  makes reply mailboxes by hand (a `Reply` struct, a one-slot mailbox per connection, `release()`). A module generates it.
- It is the "one tagged mailbox per service" decision in `mailboxes.md`, with the dispatch checked for completeness.
- The module declares its state, stack size and mailbox capacity, so its memory is known when the program is built (the
  compile-time principle in `web-usability.md`), and the message graph (who sends what to whom) is known for the topology
  check.
- Testing: a test can call `init` and feed messages one at a time with no threads (the deterministic single-worker mode).
- State is owned by one job, which agrees with "no mutable globals" (`next-lang-no-mutable-globals`).

## A sketch

    service Cache {
        state { slots: list<Row, 4096>  db: Sender<DbRequest> }
        mailbox 256
        stack 16 KiB

        init(db: Sender<DbRequest>) { ... }

        on Get(key: long) -> Row? { ... }     // a reply type: the reply slot is managed
        on Fill(row: Row) { ... }
        tick every 1 s { evict_expired() }    // optional
    }

A caller writes `cache.get(42)` and gets a typed reply.

## Where it gets harder

1. **Connections are not message-driven.** A `serve` job waits on a socket. Either socket readiness is a message type
   (`on Readable`), or a module may have a `run` loop instead of handlers. Probably both, with today's `spawn f()` being a
   module that has only `run`.
2. **Reply slots.** A handler that returns a value needs a bounded pool of reply slots; the pool size is also the "busy"
   (503) limit.
3. **`tick`.** Needs timers in the scheduler (which deadlines also need). Missed ticks should coalesce, not queue.
4. **Run to completion.** A module whose handlers never suspend needs no stack of its own and is much cheaper;
   handlers that call `db_row` or wait on a reply must suspend. Allow suspension; offer a no-suspension marker later.
5. **Instances.** Singletons are easy; `Conn` needs thousands. A declared instance pool (`Conn x 10000`) would allocate
   state and stack once at startup (no per-connection `mmap`, no leaked mailbox memory).
6. **Failure.** A trap in a handler closes the module's mailbox and tells the parent; `main` decides (already decided).

## How to start

Make `service` a front end that desugars to today's `spawn`, mailbox and loop (a state struct, a message enum, a dispatch
loop), so the runtime does not change. Rewrite the cache and database jobs of `bench/web` as services and compare code
size and speed. Then reply slots, then timers and `tick`, then instance pools.

## Open questions for Ben

1. A connection: a module with a `run` loop, or readiness delivered as messages?
2. `tick`: a fixed-rate timer, "run when idle", or both?
3. The instance pool in the first version, or after the basics work?
