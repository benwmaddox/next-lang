# Mailboxes, host grant and service jobs (decided 2026-10-30)

Decisions by Ben, in answer to the proposal of the same day. They refine DESIGN.md "Threads and data stacks";
nothing here is implemented yet.

## Host information in `main`

- `main(env: Env)` gets read-only host data from `env.host()`: flat values with fixed maxima.
  - `cores_granted`: how many worker threads the program may run (a count, not a list of cores).
  - `cores_total`, `ram_bytes_granted`, `page_size`, `os`.
  - an opaque pin list (one entry per granted core) that the runtime uses for affinity; `main` never sees core numbers.
- **The thread grant is enforced by the runtime.** It never starts more workers than granted, and pins them when the
  platform allows. **The RAM grant is advisory**: `main` can read it to size things, the runtime does not police it.
- Args and environment variables stay as they are today.

## Mailbox

- `mailbox<T, N>`: a ring of `N` slots of a flat, bounded record `T`, plus head and tail counters. Storage is
  allocated once at startup (like shared state) and never grows.
- Created in `main`; it gives out one `Sender<T>` and one `Receiver<T>`. **One sender per mailbox for now**
  (single producer, single consumer), so a send needs no compare-and-swap, only ordered stores.
- A send copies the record in and returns `Result<unit, Full>`; a full mailbox returns `Full` (nothing is overwritten,
  nothing blocks implicitly). A message is ordered with respect to the same sender only.
- `recv()` returns `Option<T>`; a service job's loop uses `recv_wait()`, which suspends the job so its worker can run
  others.
- The implementation is generated IR using LLVM atomics. The only operating-system pieces are parking an idle worker
  and waking it (futex on Linux, `WaitOnAddress` on Windows).

## Fan-out across cores

- **Static topology:** jobs are spawned from `main` only (service jobs). The scoped form for short tasks comes later
  with `scope { }`; jobs do not spawn jobs.
- Round-robin distribution: a sender holds a set of mailboxes (one per service job) and `pick()` chooses the next
  one in turn. **No work stealing in v1.** Several senders to one job means several mailboxes, not shared ones.
- A service job is pinned to the worker it starts on and owns its stacks for its lifetime.

## Runtime and C

- The C runtime provides only thread creation (with a requested stack size), affinity, and park/wake. Everything else
  (rings, atomics, scheduling decisions, the grant checks) is next-lang or generated IR.

## Failure

- When a job fails, its mailbox ends are closed: the receiver side sees `none` after draining, and a sender gets a
  closed error. The program does not stop on its own; `main` decides what to do.

## Testing

- A deterministic single-worker mode (`NLC_WORKERS=1`, or the test harness setting) runs every service job on one
  worker in a fixed order, so tests do not depend on timing. Multi-worker behaviour is covered by separate stress
  tests with a time limit.

## First slice

1. `env.host()` with the grant (this document's first section).
2. `mailbox<T, N>` with `send` and `recv` for one sender and one receiver, single worker first.
3. `spawn service` pinned to a worker, and the park/wake runtime calls.
4. A benchmark: `main` shards work across the granted cores with round-robin mailboxes; the result checksum matches
   the single-core run.

## Not decided here

Several senders to one mailbox (MPSC), receive-from-many, scoped `spawn`/join, cancellation and deadlines, and
`parallel for`. They build on this and come later.
