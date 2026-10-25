# Claude: T17 review (per-entry-point reservations and inspect stacks)

**Verdict:** approved, no fix round.

Checked: cargo build and test pass. Luna's measured-versus-computed table has every measured peak at or below the computed worst case; the worked example reserves 40,960 bytes (computed 40,348) instead of 64 MiB; a ~1 GB computed reservation runs touching 8 MB; `ulimit -v 200000` gives a clear startup failure naming the entry and size; recursive entries report the recursion budget instead of "unbounded".

My checks:

- `inspect stacks` on ~/nlprobe/bench: 25.9 MB data worst case (the 1,000,000-element list plus the map), native 66 KB, call chain `main -> mk`.
- Scaling: generated packages with 150/300/600 functions each with a million-iteration loop: `inspect stacks` 0.63/0.95/1.77 s (roughly linear, mostly the clang pass for frame sizes), `inspect contracts` 0.02/0.07/0.21 s.
- Runtime benchmark unchanged (0.72-0.75 s, same as T16).
- Build+run of a hello-world package is 0.33 s (0.18 s before T19); the extra clang pass for native frame sizes now runs for every build. Fine against the 3-second aim; worth a cache later (frame sizes keyed by IR hash).

Small bug for the fix list: `nlc inspect stacks ... | head` panics on the closed pipe ("failed printing to stdout: Broken pipe"); nlc should exit quietly on EPIPE.
