# Compiler-source emission checkpoint

Status, 2026-10-28: the language-written compiler emits LLVM IR for its own
source using the existing C runtime. A runnable self-built compiler and
stage-2/stage-3 identity have **not** been established. Rust Stage0, the C
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
this case. The full compiler rebuild chain still requires a successful rerun.

These are diagnostic timings from different compiler revisions, with different
outcomes. They are **not** a self-built compiler benchmark or a claimed ratio
against Rust Stage0. Ben's maximum 3x Rust-implemented Stage0 compile-time gate
remains pending.

Ten supported programs covering nested loop exits, relocation, and recursion
produced byte-identical LLVM IR before and after scope caching. C bootstrap
checks passed eight golden runs at O1/O3 with the nested-field SSA regression.
The first staged suite exposed stale unsupported classifications and missing
Byte assertion operands. The Byte assertion widening was corrected; all 16
affected packages then passed focused O1/O3 comparison. Seven historical
recursion policies now use explicit B1 oracles, with all 21 previous Rust
oracle files preserved byte-for-byte as `stage0.*`. The formatting append-proof
limitation remains an explicit rejection, not a new language rule.

The complete 789-package comparison plus 256 generated packages passed at
O1/O3. Forced-relocation checks separately passed 249 packages and 322 runs at
each level, with 57 packages actually relocating. The two deliberate native
stack-exhaustion cases remain in ordinary comparisons but are excluded from
relocation statistics, because OS termination cannot print final statistics.

The installed staged-tree suite, including the C I/O integration test, must
pass before this checkpoint is pushed.
