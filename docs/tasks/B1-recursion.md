# B1 prerequisite: ordinary direct recursion

Status: reopened by Ben, 2026-10-28. The previous unmerged prototype was removed.
This plan replaces its recursion budgets, measured-frame linker pass, and ban on
live arena regions across a recursive call. Implementation has not landed.

## Chosen behavior

Support concrete direct recursive calls used by the compiler. Retain the
existing `recursive fn` marker for frozen Stage0 bootstrap compatibility;
every function participating in a cycle must be marked. Generic functions,
function values/indirect calls, and language-level const-function evaluation
remain outside this slice.

Ben explicitly chose the ordinary OS process stack for B1. Native-stack
exhaustion may terminate the compiler process through the OS. There is no
controlled diagnostic, job recovery, measured-frame patching, recursion budget,
or depth counter. Controlled stack-overflow handling is deferred. Do not
relabel arbitrary segmentation faults as stack exhaustion.

The existing v2 link header keeps `nlc.recursion none` to select linking
without measured recursion-target records. Under this policy it does not
assert that the LLVM call graph is acyclic. This supersedes E1's stronger
acyclic assumption; the frozen link driver simply invokes clang without a
recursion probe. The final stage chain invokes clang directly.

The movable arena is separate. Each activation uses ordinary per-call and
per-block scopes. Caller-owned values remain live below the callee's incoming
top, and the callee restores that top on return. There is no size-dependent
prohibition on holding an arena value across recursion, no GC, and no borrow
checker. Arena caps and job exceptions remain deferred.

## Minimal implementation

1. In `selfhost/compiler.nl`, admit the parsed `FLAG_RECURSIVE` on concrete
   top-level functions while retaining generic-function gates. The flag is
   already stored on the syntax node; no new function-record field is needed.
2. Keep the existing iterative cycle search, starting from unmarked functions.
   Every invalid cycle has an unmarked member; a search from that member can
   find a path back to it. Preserve default-initializer cycle checking and
   deterministic errors for unmarked self, mutual, and overlapping cycles.
3. Make native-frame path estimates explicitly unknown for marked functions
   and propagate that state to callers. Stop traversal at marked functions;
   after cycle validation the remaining graph is acyclic. Preserve the current
   finite 1 MiB admission check for entries/tests with finite paths. A marked
   function without an actual cycle is conservatively unknown too. Do not
   pretend a recursive path has a finite byte bound by reading zero/stale
   values at a back edge. Keep this analysis separate from arena sizing.
4. Reuse `selfhost/regions.nl` scope reservation/restoration and the descriptor
   ABI in `selfhost/params.nl`. Fix only demonstrated integration defects.
   Calls already pass the current arena top; large values use arena offsets,
   and hidden results belong to the caller. No new region ownership rules,
   context ABI, stack mapping, or signal runtime are planned.

No full strongly connected component framework is needed for these checks.
No frozen Rust edits or new `.unwrap()` failure paths are authorized by this
plan. Implementation is Luna/max; Sol coordinates, debugs, and reviews.

## Acceptance and validation

- Marked self and mutual recursion work. Unmarked self/mixed/overlapping
  cycles retain real errors. A marked function without a cycle is valid.
- Caller-owned read/write/grow values survive recursive growth and forced
  relocation. Per-level large arena values remain independent across calls.
  Hidden aggregate results, nested returns, and `?` exits restore the right top.
- Existing acyclic native-frame admission fixtures retain their behavior.
  Keep mixed generic/indirect/budget fixtures gated rather than promoting
  whole packages that contain unsupported forms.
- Preserve frozen Stage0 baselines. Where its historical live-region rule
  rejects an intended B1 example, use an explicitly reviewed target-output
  fixture, with the difference documented.
- Run fresh seed construction, focused O1/O3 comparison and forced relocation,
  existing cycle/frame tests, diff checks, and the full staged pre-commit suite.
  Probe the compiler's own source and report the next actual gate.

Use `scripts/build-selfhost-cached.py --reference <frozen-nlc>`,
`scripts/compare-selfhost-build.py --reference <frozen-nlc> --only <fixture-glob>`,
and `scripts/check-selfhost-relocation.py --reference <frozen-nlc> --only <fixture-glob>`
with `NLC_LONG_TESTS=1`. After the seed, the final B1 stage chain uses clang
directly with the existing C runtime, without Rust checking, emission, or linking.
Require stage-2/stage-3 IR and binary identity and compiler-corpus correctness
before calling the compiler self-hosted or publishing self-built benchmarks.
