# B1 builders for compiler output

Status: in progress on `work/selfhost-simple-path`. Prioritize self-hosting
with bounded storage, length metadata, and checked append. Ben permits
simplifying the earlier full-builder proposal when its complexity is not
needed (2026-10-28). Implementation is Luna/max; Sol coordinates and reviews.

## Goal and boundaries

Support the compiler's output builder and source assembly. The current IR
writer uses `Bytes.push`; package/core ingestion also uses `try_append`.
Source-used operations are the current self-hosting path. Append-mode call
variants and general argument
semantics migration must not delay B1 when the compiler does not need them.

The fresh pre-task self-build probe still stops without IR at
`collections.nl:107:1: generic or recursive functions`. That is a concrete
recursive helper. Ben has reopened recursion for self-hosting; review its
smallest implementation alongside independent builder work. Builder completion
alone is not B1.

Use the existing bounded `Ascii`, `Text`, and `Bytes` forms for Stage0 bootstrap
compatibility. This does not require a GC, borrow checker, owner type parameters,
or developer-accessible addresses. Numeric length facts and ordinary scope
planning are compiler work, not an ownership system.

The older E3d1 prep bundles moves and T30 optimization with builders. They are
not automatically included: keep `take`, moved-local analysis, function values,
and unrelated optimizations gated. Arena caps, job exceptions, scheduler jobs,
mailboxes, and general interfaces are not prerequisites for this task.

## Phase 1: builder foundations

- Caller-backed `grow` parameters for the three bounded kinds, including field
  arguments and forwarding. Require matching kind and exact maxima; for Text,
  respect both its byte and code-point limits. Reuse existing place checks.
- `Bytes.push`, checked `try_append` for all three kinds, and proven-fitting
  `Ascii +=`, preserving the existing `Result<(), Full>` bootstrap contract.
  New code and fixtures use explicit handling, not new unwraps or hidden
  equivalents. A general capacity-API redesign remains a separate review.
- Caller-backed parameters are live views: after later argument mutations,
  read the current storage and metrics. Scalars and explicitly copied values
  keep their evaluation-time values. Capture indexes once, and refresh arena
  addresses after calls. Handle overlap/self-append safely and publish metrics only
  after success. Rollback covers the failed append, not earlier successful
  operations or unrelated persistent writes.
- Keep builder descriptors relative to their arena; derive addresses again
  after calls that may relocate it. Initialize empty metadata, not every byte
  of the declared maximum (the compiler's IR bound is 3,403,497,472 bytes).

The live-view rule is the agreed target. Its general read-argument migration
is deferred while the compiler-used builder path is completed; do not broaden
this task into formatter or unrelated aggregate snapshot changes.

Primary files: `selfhost/compiler.nl`, `deferred_text.nl`, `params.nl`,
`text.nl`, `regions.nl`, and, where needed, the existing proof helpers in
`collections.nl`. No core context layout, C ABI, or link metadata change is
planned. Frozen `compiler/src` is an oracle and must not be edited.

## Later: append-mode direct calls

Consider this only when a compiler source dependency or measured benefit
justifies the complexity. It is not a B1 requirement or an automatic task
after B1 merely because it is in E3d1.

Add eligible direct-call variants returning `Ascii` or `Result<Ascii, E>` that
write into the caller's destination. Keep safe ordinary result construction
and copying when a call cannot use append mode; keep indirect calls gated.

Save the append checkpoint before producer writes. On failure restore the
destination's accepted length, Text metrics where applicable, and the correct
arena top. Nested appends have independent checkpoints. Existing block-level
temporary reservations must not be rewound over other live values; inspect
their actual lifetimes rather than assuming per-expression allocation.

## Acceptance

Expanding text replacement may construct a new value in the arena and copy
the result back. In-place replacement optimization is not required, and no
replacement feature is added without a compiler dependency. Frozen Stage0
only needs to bootstrap this compiler; do not expand it for feature parity.

- Focused O1/O3 behavior and diagnostics for local/field/forwarded builders,
  zero/exact/full capacity, smaller/equal/larger argument bounds, UTF-8 byte and
  point limits, self-append, snapshots, and loop exits.
- Per-append rollback and a callee whose earlier successful append remains
  published after a later error. The later append-mode phase adds producer-failure and nested
  append-mode cases; do not call Phase 1 the complete builder feature.
- Forced relocation after a populated builder is passed to a helper, followed
  by mutation and reads through its descriptor. Initial growth alone is not
  evidence for that case.
- Preserve existing fixture inputs and behavioral oracles. Review promotions
  against actual results and add focused packages under `tests/e3/d1_builder_*`.
- Fresh source-keyed seed, focused differential/relocation checks, applicable
  diff/format checks, and the installed full staged O1/O3 suite before push.

After builders: implement compiler support for the source-used argument/file/
output operations using the existing C runtime. Ben explicitly chose C reuse
for the first self-hosted compiler (2026-10-28); the core I/O port is deferred.
Then run the stage-2/stage-3 chain with exact IR/binary identity and corpus
correctness, without Rust checking, emission, or linking after the seed.
