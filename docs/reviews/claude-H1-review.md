# Claude: H1 review (the self-hosted front end feeding the Rust compiler)

**Verdict:** approved as a working, selectable front end; Rust stays the default. Follow-up H1b (speed, wire size, one input policy) before any default switch.

Checked: Luna ran the full suite with `NLC_FRONTEND=rust` and with `NLC_FRONTEND=selfhost` (both pass), and the differential AST equality test over all 376 Rust-valid packages. My check: `nlc --frontend=selfhost run tests/run/arithmetic` prints the same as the Rust front end. The wire format is documented in docs/tree-binary-format.md; the reader validates before allocating; the self-hosted build is always bootstrapped through the Rust front end, cached under a full key, published atomically.

Problems for H1b:

1. **Speed:** the 54,145-line benchmark takes 2.21 s through the self-hosted front end against 0.58 s for Rust, and a small package 253 ms against 7 ms, though the parser child alone writes the benchmark's tree in 0.30 s. So the cost is around the parser: a fixed ~250 ms per call (likely the cache-key check, which hashes the compiler binary, runtime and sources on every call, or child startup), and reading and rebuilding the tree.
2. **Wire size and memory:** the binary tree is 46.8 MB for 1.15 MB of source (about 40 bytes of wire per source byte), and the parent peaks at 408 MB.
3. **Two input policies (a divergence):** the Rust compile path applies no package-level file, byte, token, node or work limits, while the self-hosted path has fixed capacities (4,096 files, 16 MiB + 1 per file, 64 MiB + 1 total, finite token and node storage), so inputs beyond them behave differently. One policy should apply to both front ends and both commands.
