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
