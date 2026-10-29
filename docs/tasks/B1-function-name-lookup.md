# B1 function-name presence lookup checkpoint

Status, 2026-10-29: the compiler now answers function-name presence queries
with `function_name_present`, replacing a full AST scan per query with O(1)
lookup. The existing full-node resolution and semantic checks remain intact.
The O3 stage chain passes with identical Stage2/Stage3 IR and binaries. Eight
actual Stage3 C-bootstrap golden runs pass at O1/O3. A single own-source
comparison is 5.1055x Rust Stage0 time, above the 3x gate. The required
precommit suite is still running; no performance acceptance pass is claimed.

## Storage and semantics

The presence index has capacity for 4,000,000 boolean entries plus an 8-byte
list header. These are declared capacity ceilings, not observed RSS or a claim
that all capacity is resident. The map changes the presence-query path only;
full-node lookup behavior is preserved. No snapshot syntax, compile-error
policy, or enforcement change was made.

## O3 chain evidence

The source fingerprint is
`f83ce6d9ae7cfb473e84bc4dbc294459fd530caa3b5a4fa043d576ff6f43bf61`. The
Stage2 and Stage3 IR artifacts are byte-identical at 113,892,521 bytes (SHA-256
`170ad49a63ca66d27879e667c254f0a4ced511c10e0e67cfc613f6ff28119315`); their
binaries are identical (SHA-256
`db4780e6f6a0f503da4c6aa9754268f9d63727626660610a5c5d528b1df569e3`). Stage2
emitted Stage3 IR in 9.962 seconds. Seed emission took 3.819 seconds; clang
compiled Stage2 and Stage3 separately in 21.452 and 20.062 seconds. These are
single chain-command durations, not a Rust comparison.

## Isolated own-source comparison

One O3, single-sample, no-warmup pair was pinned to CPU 0 and generated LLVM IR
only, excluding clang. Both compiled the same `selfhost` package with C runtime.
Rust Stage0 called `compile_package_with_frontend(package, Frontend::Rust)`
from the same fresh release rlib as the reference `nlc`; its
`package_link_description` selected `LinkRuntime::C`. Rust used pointer mode;
Stage3 used offset mode. Rust took 1.99 seconds wall/1.82 CPU, and Stage3 took
10.16 seconds wall/9.71 CPU: 5.1055x. Stage3 IR
matched the chain artifact. Observed maximum resident set during these samples
was 270,776 KiB for Rust and 306,240 KiB for Stage3. Input fingerprints were
unchanged. Exact child/wrapper commands, environments, hashes, and measurements
are preserved in [the raw pilot record](B1-function-name-pilot.json), copied
byte-for-byte from the original report.

This sample fails the per-case 3x threshold; it is not a median or a full
benchmark. The earlier PR13 sample measured 13.4813x on a different source
revision, so it is not a controlled before/after comparison.

## Corpus status

The actual Stage3 corpus attempt stopped before functional package comparisons:
the enum constructor lookup exceeded its per-enum linear-growth bound at 6,400
enums (4.632 seconds; 0.000724 seconds per enum). This run overlapped the
required precommit suite; no cause is inferred from that overlap. An idle retry
with unchanged guards and thresholds is pending suite completion. No corpus
correctness result is claimed yet.
