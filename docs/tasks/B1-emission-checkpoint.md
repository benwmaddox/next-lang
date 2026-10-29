# Compiler-source emission checkpoint

Status, 2026-10-28: the Stage2-to-Stage3 chain passes at O1 and O3. The Stage2
and Stage3 C-runtime/offset LLVM IR artifacts and binaries are byte-identical
at each level. Eight actual Stage3 C-runtime golden checks passed at O1/O3, and
the tiny Stage2 smoke-parse check passed. The Stage3 corpus run was invoked with
selectors covering 791 registered and 256 generated cases. Its struct IR-bound
checks passed, but the 3,200-enum
scaling precheck timed out after 180 seconds before package comparisons began.
The required staged-tree suite passed in 839 seconds for commit `23a7e64`. A
separate Stage3 own-source pilot timed out at 30 seconds against a 1.80-second
Rust Stage0 run, exceeding the 3x gate by a computed 16.6667x lower bound (at
least 16x accounting for reported-time precision). This is an observed failure
for the own-source case; small/large comparisons and package coverage remain
incomplete. See the [Stage-chain checkpoint report](B1-stage-chain-report.md)
and [raw pilot record](B1-stage-chain-pilot.json). Rust Stage0, the C
runtime, and core sources remain unchanged; core I/O replacement is postponed.
Release publishing remains manual.

## Changes

- Add the compiler-used bounded builder operations and ordinary explicitly
  marked recursion. Native stack exhaustion remains an OS process failure.
- Reuse C argument/file/output services through narrow compiler adapters.
  Handle the existing C/native Path and directory-entry layout differences.
- Support source-used Ascii branch bounds, Byte ordering/widening, and checked
  `int.fit<byte>()`. Keep broader arithmetic, builder optimizations, and language
  parity work deferred.
- Simplify generated embedded-source selection with early returns, preserving
  every embedded byte and hash. Explicit ignored success values and long loop
  counters are bootstrap checker workarounds, not new language requirements.
- Classify temporary scopes once and retain each block's assigned end and
  alignment. Reuse those results during emission without changing slot order.

## Evidence and limits

Before the scope cache, an own-source attempt failed after 181.525 seconds
with the overloaded IR-buffer diagnostic. It was an unsupported C storage
lowering, not evidence that the 3.4 GB IR bound had filled. C record-field and
forwarded writable-list/buffer lowering were corrected without relaxing the
shared noncontiguous-pointer guard.

With those changes and the cache, seed
`0456dac250cca2f8f74fc7b7df6ba4edfe2037f5dc96864b9e9ecbdec5001aa4`
wrote **112,756,501 bytes** of compiler IR in **8.858 seconds**. The command was:

```sh
python3 scripts/check-selfhost-stage-chain.py --reference /path/to/rust/nlc --opt-level 1
```

Clang rejected an undefined descriptor SSA accumulator at that checkpoint.
The source fix changes its reference to the previous `coll.desc.group.add`
value; the C record fixture now includes a nested multi-field prefix to cover
this case. This was a historical checkpoint; the later O1/O3 chain results are
recorded in [the Stage-chain checkpoint report](B1-stage-chain-report.md).

These are diagnostic timings from different compiler revisions, with different
outcomes. They are **not** a self-built compiler benchmark or a claimed ratio
against Rust Stage0. Ben's maximum 3x Rust-implemented Stage0 compile-time gate
has an observed own-source failure by lower bound; the broader benchmark and
corpus coverage remain incomplete.

Ten supported programs covering nested loop exits, relocation, and recursion
produced byte-identical LLVM IR before and after scope caching. C bootstrap
checks passed eight golden runs at O1/O3 with the nested-field SSA regression.
The first staged suite exposed stale unsupported classifications and missing
Byte assertion operands. The Byte assertion widening was corrected; all 16
affected packages then passed focused O1/O3 comparison. Seven historical
recursion policies now use explicit B1 oracles, with all 21 previous Rust
oracle files preserved byte-for-byte as `stage0.*`. The formatting append-proof
limitation remains an explicit rejection, not a new language rule.

An earlier 789-package comparison plus 256 generated packages passed at O1/O3.
Forced-relocation checks separately passed 249 packages and 322 runs at each
level, with 57 packages actually relocating. The two deliberate native
stack-exhaustion cases remain in ordinary comparisons but are excluded from
relocation statistics, because OS termination cannot print final statistics.

The required staged-tree suite, including the C I/O integration test, passed
in 839 seconds for commit `23a7e64`. The Stage2/Stage3 chain pass is a bootstrap
checkpoint, not full B1 acceptance: Stage3 package coverage did not begin after
the enum scaling timeout, and the own-source pilot exceeded the 3x timing gate
by timeout lower bound. Small/large timing cases remain unmeasured.
