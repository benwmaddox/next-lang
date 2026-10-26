# Claude: E2a review (self-hosted structs)

**Verdict:** approved, no fix round (E2 was split into E2a/E2i/E2b/E2c after the first E2 session ran out of context).

Luna's checks: `NLC_LONG_TESTS=1 scripts/compare-selfhost.sh --build` at O1 and O3 with the core and C runtime legs, zero mismatches (519 classified packages: 48 build, 64 diagnose, 407 unsupported); both full suites; cargo fmt. Structs: byte-slot layout with one addressing helper, shared per-type copy/equality/print/default/fill helpers, declaration-scope defaults, field shorthand and paths, read parameters and fresh hidden result destinations, evaluation-point snapshots, iterative memoised sizing saturating at 4,097 with cycle and unknown handling, and the 1 MiB native aggregate-slot budget (scalar frames, spills, inlining and core frames remain a recorded limitation). The helper IR grows linearly (depth 20 to 40: +39,784 bytes). The 10,000-function benchmark compiles in 1.16 s (C runtime) and 1.18 s (core), about 27% faster than at E1.

Notes: the self-hosted compiler's computed data-stack worst case is now 5.1 GB of address range (its tables); that becomes a growth limit with offsets, but keep watching it. A small struct program's IR is dominated by the embedded core library's fixed IR (272 KB against Rust's 19 KB); emitting only reachable functions (E3e) addresses that.
