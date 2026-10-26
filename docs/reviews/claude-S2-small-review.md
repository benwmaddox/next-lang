# Claude: review of the stage-0 small fixes (frame sizes, faster selfhost comparison)

**Verdict:** approved, no fix round. Last change to stage 0 before the freeze.

Luna ran all four full suites (both front ends, default and NLC_LONG_TESTS=1). Correction to my earlier reading of the profile: a build without recursion already ran clang once; the second build happened for `inspect stacks` and recursive programs. Now frame sizes are cached by a fingerprint of the IR, clang flags and version, target and runtime source (a recursive program builds in 0.45 s instead of 0.92 s warm). The self-hosted build comparison's default run (O1, core runtime) takes 175 s instead of 403 s; the long mode keeps O1 and O3 with both runtimes.

With the freeze: `cargo fmt --all` applied (formatting had drifted in several files), and rust-toolchain.toml pins Rust 1.93.0.
