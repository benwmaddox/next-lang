# Web workload

`main.nl` is a small web service built from jobs and mailboxes: four worker jobs accept connections and serve
`GET /item/<id>`; each request goes to a cache job (direct-mapped, 4096 slots), which asks a database job (SQLite,
`env.db_query`) on a miss and answers with `{"id":..,"v":..}`.

    python3 bench/web/make-db.py /tmp/items.db
    scripts/nlc build bench/web -o web_bin
    NLC_DB=/tmp/items.db ./web_bin &
    gcc -O2 -o loadgen bench/web/loadgen.c -lpthread
    ./loadgen 18081 64 5

Workers block while serving a connection, so at most four connections are served at once; the rest wait to be
accepted (the loadgen's maximum latency shows it). Suspend-on-I/O (step 4 of docs/design/web-app-plan.md) lifts that.

## Result (2026-10-30, WSL, server on cores 8-11, loadgen on 12-19, 5 s runs, two rounds)

| | req/s | p50 | p99 |
| --- | --- | --- | --- |
| next-lang (worker -> cache job -> db job) | about 54,500 | 70 us | 147 us |
| Rust baseline (4 blocking threads, mutex cache, rusqlite) | about 82,500 | 43 us | 86 us |

Ratio 0.66. The shapes differ on purpose: next-lang sends every request through the cache job's mailbox and back
(two park/wake hand-offs), where the Rust baseline reads a mutex-protected array inline. Both serve four connections
at a time (four blocking workers). Baseline: `bench/web/rust-baseline` (`cargo build --release`, port 18082).

## Where the mailbox hop's time goes (same day)

- Worker answering without the cache job (HTTP layer alone): about 84,000 req/s, p50 43 us, the same as the Rust baseline.
  So the cost is the cache hop: worker -> cache job -> worker.
- The hop's latency was the cache job's thread being woken from a futex sleep (about 25 us in this VM), not the ring:
  4 clients send one request every ~12 us, so the cache job emptied its mailbox and parked between most messages.
- `recv_wait` now spins on the ring before parking. Spin length vs result (4 connections):
  none: 54.5k req/s p50 70 us; 3,000 iterations: 55k, 69 us; 15,000: 55k on 4 cores but 67k on 6 cores, p50 55 us
  (p99 118 us); 100,000: p50 41 us (the hop is free) but 33k req/s and p99 700 us, because six jobs spinning on four
  cores starve each other.
- Reading: a service job that parks costs a wake-up per request; a spinning one costs a core. Spinning needs the
  jobs to have cores to themselves (the host grant says how many), so the next step is to let main say which jobs
  are hot (spin) and which are not, and to size the spin from the grant.

## Placement (NLC_JOB_PIN) and spin (NLC_SPIN), 4 connections, 4 s runs

`NLC_JOB_PIN`: `rr` pins job i to the i-th granted core (the default), `same` puts every job on the first granted
core, `none` leaves placement to the kernel. `NLC_SPIN` sets the receiver's spin in ring checks.

| granted cores | pin | spin | req/s | p50 us | p99 us |
| --- | --- | --- | --- | --- | --- |
| 4 | rr | 0 | 54,300 | 70 | 153 |
| 4 | rr | 15000 | 56,000 | 57 | 306 |
| 4 | same | 0 | 62,200 | 61 | 103 |
| 4 | same | 15000 | 15,100 | 245 | 491 |
| 4 | none | 0 | 49,100 | 75 | 154 |
| 4 | none | 15000 | 67,700 | 45 | 219 |
| 8 | rr | 15000 | 68,000 | 54 | 116 |
| 8 | same | 0 | 62,400 | 61 | 103 |
| 8 | none | 15000 | 67,800 | 54 | 116 |

- All six jobs on one core without spinning gives 62k req/s, 14% above round-robin without spin, because a wake-up
  on the same core is a context switch instead of a cross-core interrupt. It also has the best p99. Spinning on a
  shared core is the worst case (15k): the spinner holds the core its sender needs.
- Spinning with kernel placement on four cores matches round-robin on eight (67.7k): round-robin pinning on a core
  count equal to the worker count fights the kernel for no gain.
- Rust baseline on four cores: 82k req/s, p50 43 us.

## Suspend on I/O (jobs are coroutines on a few worker threads)

`spawn` now starts a coroutine (Linux). A pool of worker threads (one per granted core, or `NLC_WORKERS`) runs ready
jobs; a job that waits switches back to its worker. What suspends a job: `recv_wait` with nothing to receive, a full
mailbox on `send` (it yields before reporting Full), `net_accept` / `http_read` / `http_write` that would block
(epoll, one-shot). Wake-ups: `nl_wake` from senders, epoll events. Plain threads (main, `nl_thread_start`) still use
futexes and poll(). Each job has a 1 MiB native stack and a 64 MiB data-stack reservation (`NLC_JOB_STACK_RESERVE_BYTES`),
touched only as used. `main.nl` now has an acceptor job spawning one `serve` job per connection.

Server on 4 cores (8-11), load generator on 10 other cores, 4 s runs:

| connections | req/s | p50 | p99 | max |
| --- | --- | --- | --- | --- |
| 4 | 68,900 | 46 us | 155 us | 6 ms |
| 64 | 107,600 | 496 us | 1.3 ms | 6 ms |
| 1000 | 88,200 | 11 ms | 16 ms | 57 ms |

Every connection is served; before, connections beyond the fourth waited for a worker (maximum latency 5 s). The Rust
baseline is a thread-per-worker server that also serves four at a time (82k req/s at 4 and 64 connections); an
async Rust server would be the fairer comparison for 64+ connections and is not measured yet.
Limits: a job that computes without waiting holds its worker (cooperative scheduling); SQLite calls block their
worker for their duration; a mailbox's memory is not returned when its job ends.

## Correction: spinning is wrong for coroutines (default NLC_SPIN is now 0)

With jobs as coroutines the 15,000-iteration spin in `recv_wait` held a worker while the job it waited for sat in the
ready queue. Process CPU during the 64-connection run: 10.2 core-seconds of user time in 4 s (tokio: 2.5), almost all
of it spinning. With `NLC_SPIN=0` (now the default), plus a stack-switching routine in assembly (no signal-mask system
calls) and no futex call in `nl_wake` unless a plain thread is sleeping, same machine and method as above:

| connections | next-lang req/s | p50 | p99 | tokio (4 workers) req/s | p50 | p99 |
| --- | --- | --- | --- | --- | --- | --- |
| 4 | 58,000 | 66 us | 128 us | 69,000 | 55 us | 117 us |
| 64 | 314,000 | 194 us | 384 us | 285,000 | 213 us | 481 us |
| 1000 | 248,000 | 4.0 ms | 5.8 ms | 300,000 | 2.1 ms | 11.7 ms |

(two rounds each; the tokio server is `bench/web/rust-async`, one task per connection, mutex cache, one SQLite
connection behind a mutex.) At 64 connections next-lang is 10% faster; at 1000 it is 17% slower at the median but has
half the p99; at 4 connections it is 15% slower (spinning helps there: `NLC_SPIN=15000` gave 72k).

## Rows from SQLite, JSON and HTML (version 2 of main.nl)

The service now reads real rows: `items(id, v, name, price)`. `env.db_text(sql, key, out)` returns a text column into a
`Bytes`; `env.db_query` the numbers. The cache holds whole rows. Routes: `/item/<id>` JSON with the name escaped for
JSON and the price as dollars; `/page/<id>` HTML with the name escaped for HTML and 8% tax added to the price. A
missing row is 404; if the cache job's mailbox is full the connection answers 503 at once. Each connection gives its
reply mailbox back (`release()`) when it ends. `tests/py/test_web.py` checks all of it against a small SQLite file.

Throughput on `/item` with these richer rows (4 cores, same method): 59-64k req/s at 4 connections, 278-281k at 64,
225-238k at 1000 (p99 at 1000: 6 ms).

## Should the cache be a job behind a mailbox?

Four ways to cache, same service, same method (4 cores; variants in `bench/web/variants`):

- **job** (`main.nl`): one cache job holds rows; connection jobs ask it through mailboxes.
- **nocache**: every request reads SQLite itself.
- **sharded**: four cache jobs, key % 4 picks one.
- **shared**: a process-wide table in the runtime (`env.cache_get` / `env.cache_put`, direct-mapped, one tiny lock per
  slot), holding the *rendered response body*; a hit never leaves the connection job. (It also skips rendering on a hit,
  which the other variants do not; part of its gain is that.)

| connections | job | nocache | sharded | shared |
| --- | --- | --- | --- | --- |
| 4 | 59.9k | 62.3k | 58.6k | 58.2k |
| 64 | 275k (p50 222 us) | 144k (434 us) | 267k (229 us) | **331k** (189 us) |
| 1000 | 226k | 130k | 216k | 222k |

- The cache matters: without it throughput halves (144k at 64).
- Sharding the cache job gains nothing: the single cache job was not the bottleneck at these rates.
- A shared table in the runtime is 20% faster at 64 connections (no hop, no render on a hit) and equal at 1000, where
  the kernel's socket work and the scheduler dominate for all variants. At 4 connections everything is latency bound.
- Reading: use the shared table for plain memoizing of small values (reads dominate, no policy). Keep a cache *job*
  when the cache has logic: eviction or expiry policy, invalidation, write-behind, ordering with other messages, a
  value too big to copy per hit. The job's cost is one park/wake round trip per request, about 20% at medium load.

## Is a lookup by key efficient? (shared cache, 100-byte value, 4 cores)

The table is direct-mapped: the key picks one slot (key modulo the slot count), so a lookup touches one slot, with no
searching and no allocation. Measured with a loop of `cache_get` calls in jobs:

| | one job | four jobs, aggregate per lookup |
| --- | --- | --- |
| first version, a lock per slot | 15 ns | spread over 4096 keys: 7 ns; **one hot key: 103 ns** |
| seqlock (readers never write the slot) | 11 ns | spread: 3.1 ns; one hot key: **2.9 ns** |

With a lock, jobs reading the same hot key took turns and bounced the slot's cache line between cores (6 times slower
than one job alone). Now readers only read; a writer makes the slot's sequence number odd while it copies, and a reader
that overlapped a writer copies again. `tests/py/programs/cache_race` checks that two writers and two readers on one
key never produce a half-written value. Known weaknesses of the design: a collision evicts (direct-mapped, no
associativity), a value is at most 512 bytes and is copied out (not borrowed), and nothing expires.

## Typed rows: `env.db_row` (one statement instead of three)

`load_row` now fills a struct from one statement: `env.db_row("from items where id = ?1", key, data)` where `data` is an
`ItemData { v, price, name }`. The compiler writes `select v,price,name` from the struct's fields (the struct is the
projection), the query must be a literal, and each call site prepares its statement once. Same machine and method:

| connections | variant | before (3 calls) | after (1 row) |
| --- | --- | --- | --- |
| 64 | nocache (every request reads SQLite) | 144k req/s | **211k** (+46%) |
| 1000 | nocache | 130k | **174k** (+34%) |
| 64 | cache job (misses only) | 275k | 321k (+17%) |
| 1000 | cache job | 226k | 241k (+7%) |

## Queries are checked when the program is built

`bench/web/schema.sql` holds the tables. `scripts/nlc build` and `run` prepare every `env.db_row` query against it
(`runtime/querycheck.c`, using the same SQLite): an unknown table or column, a column whose declared type does not
fit the struct field (integer for `long`/`int`/`bool`, text for `Bytes`), or a different number of columns than fields
is a build error, and a plan that reads a whole table is a warning with the query. A package with queries and no
`schema.sql` gets a warning that they are unchecked. (`tests/py/test_query_check.py`.)

## Templates (`pages.tpl`)

The hand-written `push_*` and `render_*` functions are gone. `bench/web/pages.tpl` holds the two bodies:

    json template item(row: Row) max 512
    {{"id":{row.key},"name":{row.name},"price":{row.price|money},"v":{row.v}}}
    html template page(row: Row, taxed: long) max 512
    <!doctype html><html><body><h1>{row.name}</h1><p>item {row.key}</p><p>price with tax: ${taxed|money}</p></body></html>

`tools/gen/tmpl` (a next-lang program, built and cached and run by `scripts/nlc` when a package has `.tpl` files) turns them into `render_item` and `render_page`
in `templates.gen.nl`, straight-line appends into the bounded body. At build time it: works out each template's largest
output (here 285 bytes for the JSON) and refuses one that could overflow its buffer; chooses the escaping from the place
each hole is in (HTML text, quoted attribute, URL attribute, JSON string, JSON value); and refuses a hole in a script,
an event attribute, an unquoted value, between attributes, or at the start of a URL. Throughput is unchanged
(314k req/s at 64 connections, 249k at 1000). The generator is a Python prototype of the template language; the plan is
to move it into the compiler.

## Services (`cache.svc`, `database.svc`)

The cache and database jobs are now services (docs/design/job-modules.md): state and one handler per message, no loops,
no message structs. A miss forwards the caller's reply handle to the database service, which answers the caller and
fills the cache. Same machine and method: 340-350k req/s at 64 connections (before: 314k), 261-275k at 1000 (249k), 58k
at 4. The connection is a task that calls `Cache_get`, and gets none (the 503) when the cache's mailbox is full.

## Connection churn and the context pool

A job's data-stack context (a 64 MiB reservation) used to be mapped when the job started and unmapped when it ended, so a
server taking many short connections spent its time in `mmap`/`munmap`. Finished jobs now give their context to a pool
of up to 4096 (zeroed first: the used part is cleared, or handed back to the system if it passed 256 KiB), and a new job
takes one. Loadgen with a new connection every N requests (`loadgen port 64 4 5000 N`), 64 connections, four cores:

| requests per connection | before | after |
| --- | --- | --- |
| 1 | 19.1k req/s, p50 2.3 ms | 21.1k req/s, p50 **0.44 ms** |
| 10 | 150k | 168k |
| keep-alive | 298k | 323k |

What is left in the one-request-per-connection case is mostly the kernel's connect, accept and close work.

## Fewer allocator calls (pooled blocks)

Job arguments and mailbox rings come from size-class free lists instead of `calloc`/`free`; a connection's HTTP buffer
stays with its descriptor. Counting the system allocator's calls over about 900,000 requests (keep-alive, then a burst on
new connections): frees 970,666 before, 17 after. Throughput, 64 connections, four cores: keep-alive 282k to 303k req/s
(+7%), a new connection every 10 requests 169k to 194k (+15%).

## SQLite on a block of memory

SQLite is compiled with its own allocator (`SQLITE_ENABLE_MEMSYS5`) and, when the first connection opens, is given one block
(`NLC_DB_HEAP_BYTES`, default 128 MiB of address space taken with `MAP_NORESERVE`, so only the part used becomes memory;
anything under 1 MiB is ignored and SQLite uses the system allocator). From then on it calls the system allocator never. A
query that needs more than the block fails with `SQLITE_NOMEM`, which `db_row` reports as no row. System allocator calls over
the same 900,000-request run: 459 mallocs and 17 frees before, 147 and 6 now, the remaining ones from startup.
