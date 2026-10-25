# T30 report: locals that work against the memory theory

Implemented both T30 changes.

## In-place builder reassignment

For `buffer = f(buffer)`, the compiler now uses the assignment destination for the call result when it can prove that the direct callee has one matching `grow` or `write` parameter, the argument is the assignment's root local, the result has the same type, and every return path returns that parameter. A second aliased argument prevents the optimization. The normal pointer-overlap check still applies to other arguments. Unproven assignments keep the temporary and copy.

`inspect stacks` continues to attribute copy-down sites. `nlc build tests/run/t30_copy_down` reports the remaining general case at `main.nl:16:5`: a 40-byte temporary and an 80-byte old-plus-new peak, with the suggested `grow`/`write` rewrite. Its fixture verifies both the in-place rewrite result and the copied identity result. `nlc inspect stacks selfhost` reports no remaining copy-down sites; the five `Bytes.empty()` resets were already removed in T27.

## Local region ordering

Direct block locals are reserved at block entry in stable size groups: regions up to 64 KiB first, then larger reserve-ahead regions. The inspector uses the same plan. Scope marks still restore allocations in LIFO order, and nested block regions remain within their enclosing scope.

In `tests/run/t30_locality`, the declaration order was `before`, a 1 MiB builder, `fixed`, `after`. The old order put `after` 1,048,648 bytes from `before`. The new inspector order is `before` (22 bytes), `fixed` (40), `after` (21), `buffer` (1,048,584); the two small locals are now 64 bytes apart. The fixture runs and prints `11`.

## Benchmarks

The earlier reports note that `~/nlprobe/bench` is not present in this environment, and the repository has no standalone runtime benchmark. I added [`bench/t30_locals/main.nl`](../../bench/t30_locals/main.nl), a 10-million-iteration workload that repeatedly rewrites a builder through a `grow` parameter and calls a function with small locals and a 1 MiB reservation.

Five `/usr/bin/time` runs, output redirected to `/dev/null`:

| Compiler | Time | Maximum RSS |
| --- | --- | ---: |
| Before T30 | 0.14–0.16 s (median 0.15 s) | 1,584 KiB |
| After T30 | 0.09–0.10 s (median 0.10 s) | 1,584 KiB |

The selfhost benchmark before T30 ran in 0.26–0.29 s (best 0.26 s, 58,608 KiB RSS). After T30 it ran in 0.26–0.27 s (best 0.26 s, 58,784 KiB RSS). Both results are within normal measurement variation; the benchmark limit is 2.0 s.

## Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt --all` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — passed, including the T30 integration and language fixtures.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target scripts/update-parse-dumps.sh --update` — refreshed the T30 run-fixture snapshots.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target scripts/bench-selfhost.sh` — passed before and after T30; final best was 0.26 s.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target/debug/nlc inspect stacks tests/run/t30_locality` — lists small locals before the 1 MiB builder.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target/debug/nlc inspect stacks selfhost` — no copy-down sites.
- `git diff --check` and `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt --all -- --check` — passed.

No T30 acceptance work remains.
