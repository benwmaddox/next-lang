# Self-hosted `.unwrap()` audit — 2026-10-28

**Status:** source audit plus validated core cleanup. Future job-failure policy
is recorded separately in Revision 2.

## Scope and count

Counted literal `.unwrap()` occurrences in non-generated `selfhost/*.nl`,
excluding `selfhost/core_files.nl`. Sixteen source files were searched; nine
contain matches. The counts below are occurrences, not matching lines.

```powershell
rg --count-matches --glob '*.nl' --glob '!core_files.nl' '\.unwrap\(\)' selfhost
rg -o --no-filename --glob '*.nl' --glob '!core_files.nl' '\.unwrap\(\)' selfhost | Measure-Object -Line
```

| File | Occurrences |
|---|---:|
| `selfhost/compiler.nl` | 135 |
| `selfhost/dump.nl` | 51 |
| `selfhost/parse_output.nl` | 19 |
| `selfhost/source.nl` | 5 |
| `selfhost/parser.nl` | 3 |
| `selfhost/collections.nl` | 1 |
| `selfhost/const_diagnostics.nl` | 1 |
| `selfhost/deferred_text.nl` | 1 |
| `selfhost/text.nl` | 1 |
| **Total** | **217** |

| Operation | Occurrences |
|---|---:|
| Bounded collection or `Bytes` `push` result | 215 |
| `Option` extraction from `fit<byte>()` | 2 |
| Other | 0 |

The generated `core_files.nl` is excluded from this inventory. The baseline
core sources had 10 guarded `Result.unwrap()` calls; the cleanup replaces all
10 with exhaustive matches. Two appearances of “unwrap” in failure-diagnostic strings
remain unchanged; they are text, not calls.

## Representative callsites and proof scope

1. `selfhost/parser.nl:337,438-440` fills `seen`, whose list capacity is exactly
   `GENERIC_HASH_CAPACITY`. The loop adds one element per capacity slot. Its
   emptiness is a caller condition: `main.nl:96-98` passes a fresh table, and
   `compiler.nl:13327-29` resets before initialization (`parser.nl:472` clears
   `seen`). The count proof is local; freshness depends on those call paths.
   A violated precondition makes `unwrap` fail the job.
2. `selfhost/compiler.nl:453,653,656-659` guards line-index growth and calls
   `fail_parse_limit` at capacity before the subsequent `push().unwrap()`. The
   expected capacity error has a specific diagnostic; a `Full` despite the
   guard becomes a job failure instead. The guard does not change `push`'s
   static `Result` type.
3. `selfhost/dump.nl:68,71-105` appends JSON headers, bytes, and escapes to a
   bounded output buffer. Flush margins (`64` before a header, `12` before an
   escape, then per-byte checks) make individual pushes fit; the escape budget
   also relies on the formatted byte representation staying bounded. If a
   margin/helper changes and a push is full, `unwrap` fails the job rather than
   returning the function's `IoError`.
4. `selfhost/source.nl:127-139` builds an unexpected-character spelling in
   `Bytes max 2`: the branches append one or two bytes. That capacity proof is
   local. An unexpected `Full` aborts diagnostic output.
5. `selfhost/parse_output.nl:935,942` unwraps `fit<byte>()` after masking with
   `255L`, so each converted value is in `0..255`. These are the two `Option`
   extractions in the count; changing the mask/range assumption makes `none`
   fail the job.

## Why these calls use `unwrap`

The API requires handling the result, not specifically writing `.unwrap()`:
list and byte-buffer `push` return `Result<(), Full>` ([T06 contract](../tasks/T06-arrays-lists-pools.md)).
`unwrap` chooses job failure if the result is `Full`
([T14](../tasks/T14-ascii-values.md)). A guard does not change the call's
result type; the compiler's count proof is narrower. T06
allows a proven unused push to be discarded, but that special case is itself
under review. This audit does not recommend `discard` broadly or mass-rewriting
the 215 calls. Nor should a helper merely hide an `unwrap`.

New unwraps or equivalent hidden failure paths require discussion with Ben of
the failure case and simpler alternatives. This audit does not authorize them.

Where `Full` is recoverable, use explicit result handling or propagation if the
caller has a compatible error type. Where capacity is proven, use a proven form
only after its rules are settled. Keep an `unwrap` visible only when failing
the job is the intended response to a violated invariant.

`Full`, an OS `errno`, and arena-cap exhaustion are different outcomes. OS
errors such as `EINTR` carry useful information that may guide retry behavior.
`Full` reports bounded-storage capacity; its API policy remains under review.
Ben selected a typed, job-boundary-only exception for arena-cap exhaustion,
with completed persistent writes kept (see [Revision 2](../design/job-failures-revision-2.md)).
Cap implementation is deferred. Current core has no configured hard arena cap;
it checks arithmetic and OS allocation failures while growing. The cleanup
does not implement a cap, job-level catches, or another error feature; it
preserves the existing behavior.

## API question for the next revision

A possible checked capacity API would let ordinary code say:

```text
if try_push(buffer, value) == FULL { return false; }
```

The name/status representation is illustrative, not selected or implemented.
Another choice is a documented ordinary `push` that fails the run at capacity,
alongside a checked form for recovery. That policy requires user discussion;
wrapping today's `push().unwrap()` in a helper is not a substitute. Neither
choice requires ownership tracking, a collector, or a new propagation operator.

## Validation

The audit itself was read-only. The subsequent core cleanup passed five focused
tests after exact-script regeneration of the embedded core and a current
release reference build:

```sh
NLC_FRONTEND=selfhost cargo test --offline --release -q \
  --test core_embed --test core_wrapper_audit \
  --test core_environment --test selfhost_context_offsets
```

Independent Sol review found no change to cleanup, diagnostics, terminal probes,
clock fallback, or remap timing. The generated core hash is
`f2af19c6668777119ef279ca1cf80842b3c05193ed0b970845390854f49ee071`.
Source commit `f59f2b8` passed the installed full staged hook in 729 seconds:
762 registered comparison packages plus 256 generated packages at O1/O3,
forced relocation, and the remaining integration contracts. The hook used
`NLC_LONG_TESTS=1`, `NLC_E1_GENERATED_COUNT=64`, and `NLC_TEST_JOBS=4` with:

```sh
NLC_FRONTEND=selfhost cargo test --offline --release -q --test '*'
```

An initial hook invocation stopped before tests because `cargo` was absent
from its non-login PATH. The passing rerun explicitly supplied the Linux Rust
toolchain path. These are correctness checks, not benchmarks; no performance
improvement is claimed.
