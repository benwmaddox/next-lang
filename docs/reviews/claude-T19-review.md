# Claude: T19 review (recursion)

**Verdict:** approved after two fix rounds.

Checked: cargo build and test pass (Luna also ran the suite at NLC_OPT_LEVEL=3). Probes in ~/nlprobe:

- fib(30) = 832,040 at runtime; depth(100,000) runs; depth(100,000,000) fails with `recursion budget exhausted` at the call's line, exit 1, no crash.
- A recursive function keeping a `long[1000]` local alive across its recursive call is refused, naming the value.
- Build time for a small recursive program: 0.4 s (two clang passes, one to read frame sizes) against 0.18 s without recursion.

Fix round 1: a recursive `const` overflowed the compiler's own stack at depth 40 (below Luna's 64-call cap). The limit is now 10,000 calls.

Fix round 2: round 1's fix needed a 4 GiB evaluation thread (250 KB of Rust stack per evaluated call in debug, 2.36 GB RSS), and the checker overflowed at about 96 levels of nesting, so a 64-level expression limit had been added, which made a 65-term `a + b + ...` a build error. Now: the compiler's recursive frames were split (debug bytes per level: parser 61 KB to 12 KB, checker 80 KB to 15 KB, evaluator 250 KB to 26 KB), the whole compile runs on one 1 GiB-stack thread (reserved, not touched), and the nesting limit is 1,000. My probes: 1,000 nested parentheses, a 1,000-term sum and 500 nested calls each build in 0.2-0.35 s with 99 MB peak; a 10,000-call constant peaks at 281 MB in debug (97 MB release).

Notes:

- Debug nlc frames are still 5-25 KB per level; fine with the 1 GiB thread, but S2's self-hosted checker should be designed with explicit work stacks rather than deep recursion.
- Frame-size extraction is Linux/ELF only, as T19 allows.
