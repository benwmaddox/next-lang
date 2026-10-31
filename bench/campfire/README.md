# Campfire room page (slice 1)

`apps/campfire` serves the Campfire room page straight from SQLite, one job per connection, no cache. Measured on the real
Rails snapshot from the recorded benchmark (`AgentLang/.agentlang/campfire-bench/private/*/production.sqlite3`: 11 rooms, 10
users, 169 messages; room 486777696 has 131), as David with his session cookie, `GET /rooms/486777696`: the last 40 messages,
oldest first, message bodies from `action_text_rich_texts`, the sidebar of David's rooms.

Method: `bench/web/loadgen.c` (keep-alive connections, `LOADGEN_PATH` and `LOADGEN_COOKIE`), server pinned to vCPUs 8-11, load
generator on 12-19, WSL2, 8 s windows. `bash` driver in the session notes; the page is not byte-identical to the references'.

| connections | req/s | p50 | p99 |
| --- | ---: | ---: | ---: |
| 16 | 52,400 | 0.30 ms | 0.39 ms |
| 32 | 52,100 | 0.61 ms | 0.76 ms |
| 64 | 51,800 | 1.2 ms | 1.5 ms |
| 128 | 47,200 | 2.7 ms | 3.5 ms |

At 64 connections: 85 microseconds of CPU per request (4 cores saturated), resident memory 7 MB after the load (peak 13.7 MB).

## What this is and is not comparable to

The recorded references (crudspec's `bench/README.md`, uncached, same four cores): Rails 24 req/s (967 MB), the Rust port 1,481
(98 MB), crudspec 1,893 (131 MB). **Those pages are 366-464 KB; this one is 14 KB.** The reference pages carry each message's
avatar, menus, boost form and Turbo markup (about 9 KB per message); slice 1 writes the author, time and body (about 350 bytes of
markup per message). In bytes per second this is 52,000 x 14 KB = 730 MB/s against crudspec's 1,893 x 366 KB = 690 MB/s, so
per byte written the two are about level, and the reference servers' cached figures (14,861 and 31,942 req/s) are the fairer
yardstick for this page's size. The honest comparison comes when the page carries the same markup (slices 3 and 4 add the
controls and live-update attributes); until then this number says only that reading from SQLite per request is not the
bottleneck for a page of this size, and that a job per connection with a bounded page buffer needs 7 MB.

What the slice does not do yet: sign in, redirect, the composer, boosts, unread state, live updates, anything that writes.
