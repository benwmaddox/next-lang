# Claude: T23 review (touch only live collection elements)

**Verdict:** approved, no fix round.

Checked: cargo build and test pass (new compiler/tests/stack_reuse.rs and the dirtied-page fixtures; the T20 I/O test gained prefilled-buffer and failure-count cases, which is the intended runtime change). All my earlier probes in ~/nlprobe (d1, d2, e1-e7, s1, b20, c25, g1, a1, w2, n2, m1) give the same output as before.

Memory (Luna's fresh-process measurements, matching the task's targets): a local `list<long, 6000000>` holding one element, the same as a struct field, a returned `list<long, 2000000>` and a 2M-slot pool each run at 176 KB above an empty program (48 MB, 48 MB, 16 MB and 42 MB before); an empty million-slot map touches its 9 bytes per slot of buckets and flags (8.8 MB), as decided.

Runtime speed: a benchmark (~/nlprobe/bench, -O3) with 150,000 map inserts and 30 million lookups, 200,000 calls returning an 8 KB list, 300 rounds of 100,000 pool add/get/remove, and a one-million-element sort gives identical output on df1cc24 (before) and T23, at 0.75 s vs 0.73 s (three interleaved runs, one 1.97 s outlier on T23 that the others bracket), 25.9 MB vs 24.8 MB.

Found while writing the benchmark (not T23): matching `ok(_)` on a value that isn't a `Result` (`pool.remove` returns an `Option`) says "unknown enum case 'ok'; did you mean 'ok'", which names nothing useful. Logged in PLAN's small fixes.
