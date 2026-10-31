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
