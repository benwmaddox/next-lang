# Claude: T30 review (locals that work against the memory theory)

**Verdict:** approved, no fix round.

Checked: cargo test passes (19 groups, no failures). `buffer = f(buffer)` is compiled in place when the direct callee has exactly one matching `grow`/`write` parameter that is the assignment's root local and every return path returns it (a second aliased argument blocks it); other cases keep the copy and the build names the site with the suggested rewrite. Locals: small regions (up to 64 KiB) are reserved before reserve-ahead regions at block entry, still freed last in, first out; in the fixture two small locals went from 1,048,648 bytes apart to 64. Luna's bench/t30_locals (10 million iterations) went from 0.15 s to 0.10 s; the selfhost benchmark is unchanged (0.26 s); `inspect stacks selfhost` lists no copy-down sites.
