# H1 implementation report

## Result

Implemented the selectable self-hosted frontend while keeping `rust` as the
default. The Rust compiler can now invoke the self-hosted lexer/parser, read its
versioned binary AST, and continue through the existing Rust checker and code
generator. The wire format and field mapping are documented in
[`tree-binary-format.md`](../tree-binary-format.md).

The reader validates section bounds, arithmetic, tags and flags, source and
token ownership, UTF-8, spans and positions, child counts and roles, subtree
partitions, roots, references, and decoded-string metadata before rebuilding
AST values. AST equality is derived across the AST types. Self-host metadata
preserves fields the earlier parser only computed for dumps, including grouped
callee spans, type child roles, decoded literals, effects, expect sources,
synthetic defaults, and ignored pattern bindings. The added
`h1_ast_metadata` fixture has a frozen dump for those cases.

Frontend selection works through `--frontend=rust|selfhost` and
`NLC_FRONTEND`; the CLI flag overrides the environment. The self-host build is
always bootstrapped through the Rust frontend in pointer mode. Its cache key
covers the compiler binary, runtime, sorted selfhost sources and manifest,
target, optimization, code generation mode, toolchain versions, and wire
version. Cache publication is locked and atomic, and cached binaries are
checked against their artifact hash.

The parent runs the child from the canonical package's parent, writes its
buffered binary output to a unique temporary file, waits for success, then
validates and rebuilds the tree. Syntax diagnostics are forwarded once with
status 2; launch, signal, and malformed-tree errors are tool failures. Rust
and selfhost source selection use the same rooted symlink boundary.

## Validation

Both full suites passed on the final tree:

- `ulimit -v 8000000 && timeout 1800s env CARGO_TARGET_DIR=$HOME/.cache/next-lang/target NLC_FRONTEND=rust cargo test`
- `ulimit -v 8000000 && timeout 1800s env CARGO_TARGET_DIR=$HOME/.cache/next-lang/target NLC_FRONTEND=selfhost cargo test`

These cover the run, test, and parse fixtures, the full S1a lexer/parser
differential corpus, mutation and boundary cases, compiler tests, snapshots,
and stack contracts. The AST equality test rebuilt and compared all 376
Rust-valid fixture packages under `tests/run`, `tests/test`, and
`tests/parse/cases`, including checker-invalid packages.

Additional focused coverage checks malformed wire fixtures, every cache-key
input, concurrent cold starts, missing and corrupt cache artifacts, syntax
diagnostic forwarding, a signaled child, truncated child output, and symlink
parity. Compile-mode tests compare both frontends on invalid UTF-8 and verify
successful builds at 16 MiB + 1 byte per file and 64 MiB + 1 byte per package.
The self-host stack contract is 999,311,589 bytes worst-case with a
999,313,408-byte data-stack reservation; the native stack worst-case is
8,054,080 bytes and recursive.

## Measurements

Measurements ran in WSL on the generated benchmark: 13 files, 54,145 lines,
and 1,152,008 source bytes. Warm runs used `nlc parse <package> --tokens
--tree`, with output redirected to `/dev/null`; the selfhost figure includes
the subprocess, binary write, read, validation, AST rebuild, and text dump.
Times are medians of three runs. RSS was sampled from `/proc` at 1 ms
intervals.

| Workload | Rust frontend | Selfhost frontend |
| --- | ---: | ---: |
| Benchmark parse, wall time | 0.578 s | 2.210 s |
| Benchmark parent peak RSS | 73,256 KiB | 408,408 KiB |
| Benchmark parser-child peak RSS | — | 64,592 KiB |
| Three small packages, 30 calls: mean | 7.52 ms | 253.53 ms |
| Three small packages, 30 calls: median | 7.21 ms | 253.08 ms |

The small-package set was `tests/run/arithmetic`, `tests/run/loops`, and
`tests/parse/cases/h1_ast_metadata`, each parsed ten times per frontend. The
selfhost mean is about 34 times the Rust mean, and its median is about 35
times the Rust median. On the benchmark the selfhost frontend is about 3.8
times slower end to end.

The benchmark's binary tree was 46,814,983 bytes. Running the cached parser
child directly to write that wire took 0.296 s. An empty target cache took
12.392 s for the first small parse; the same command took 0.256 s warm, so
bootstrap added about 12.136 s. The cold build's parent peak RSS was 55,300
KiB and its largest descendant was clang at 150,096 KiB. The published
selfhost executable was 576,256 bytes.

## Command-policy note

The task describes distinct current package limits for Rust parse and compile
paths. In this checkout, the parse limits are enforced in
`package_dump_on_worker`, while the Rust compile path reads each source,
lexes it, and parses it without package-level file, byte, token, node, or work
limits. The per-file lexer token limit and parser nesting limit still apply.
H1 therefore sends an explicit parse or compile policy: parse keeps the
existing package limits, and compile skips those parse-only limits. Invalid
UTF-8 remains a parse diagnostic in parse mode and a status-3 tool failure in
compile mode; compile failures now use the same stable message for both
frontends.

The selfhost implementation uses fixed-capacity buffers. Compile policy can
accept the tested byte-limit N+1 cases, but its current physical limits are
4096 files, 16 MiB + 1 byte per file, and 64 MiB + 1 byte total source; token
and node storage also have finite capacities. Rust compile has no matching
file or source-byte caps. This is the simplest implementation consistent with
the inspected compiler path and the existing sub-1-GB selfhost stack contract;
inputs beyond those selfhost capacities can therefore behave differently from
Rust compile. The wire reader's independent source cap is 256 MiB.

## Recommendation

Keep `rust` as the production default for now. The AST and command comparisons
pass, but the selfhost path is substantially slower on both benchmark and
small-package workloads, uses about 399 MiB in its parent on the benchmark,
and has the physical compile-input caps described above. Reconsider the
default after reducing tree transport and reconstruction costs and aligning
the compile input bounds with the Rust path.
