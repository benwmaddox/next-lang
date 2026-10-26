# Claude: E1c review (the next-lang core library replaces the C runtime for E1)

**Verdict:** approved, no fix round. Programs built by the self-hosted compiler now link no C library.

What it is: core/ (the core library in next-lang: start-up, Linux system-call wrappers, environment, test selection, failure reporting, buffered output, integer formatting, the five memory functions), embedded into the self-hosted compiler as selfhost/core_files.nl with a freshness test and a source hash in each IR header; `sys` operations and `sys.Addr` usable only from the embedded core; IR header v2 selects `c` or `core`; core programs link freestanding and static.

Checked: Luna ran the build comparison at -O1 and -O3 with the C-runtime third leg (zero mismatches; 35 build, 42 diagnose, 405 unsupported, since int/long casts and `-> never` became ordinary features as the design note says), the output, test-index, start-up and memory-function scripts, the binary checks (no undefined symbols, no INTERP, no NEEDED, memory functions local, no call path back into them), and both full suites. My probe (a sum of squares with an int-to-long cast, the minimum long, a division by zero): built by the self-hosted compiler with the core library, output, message, position and exit status identical to Rust nlc; the executable is a 15,120-byte static ELF with no undefined symbols. A package using `.to_long()` is refused whole with the unsupported diagnostic, as it should be.

Measurements (Luna, under the bench lock): a trivial program is 15 KB with the core library against 93 KB with the C runtime, linking in 0.18 s against 0.45 s; start-up is the same; the E1 benchmark compiles 2% slower with the embedded core.

Follow-ups (PLAN small fixes):

- Core `memcpy` is 2.4x slower than glibc at 256 bytes and 2.1x at 16 MiB (128-bit moves only; glibc picks AVX at run time). Tune it, using DESIGN's function multiversioning (`versions(x86-64-v3, ...)`) for wide moves, and measure against the note's 1.25x target.
- The self-hosted build comparison inside `cargo test` now takes about 12 minutes per suite (482 packages, two optimisation levels, three legs). Keep one optimisation level and the core leg in the default run; the full matrix under `NLC_LONG_TESTS=1`.
- Deferred by the design to E3: data-stack growth, `mremap`, stack-address system operations, and the forced-relocation test.
