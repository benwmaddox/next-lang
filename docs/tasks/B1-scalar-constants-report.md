# B1 scalar constant prerequisite

Status: implementation and validation in progress. This prerequisite does not
complete self-hosting or the B1 reproducibility gate.

## Scope and implementation

The previous self-build stopped at `collections.nl:7:1`, reporting unsupported
constant declarations. The baseline compiler had 207 declarations, all explicit
`long`: literals, references, and arithmetic. Four constant-fact flags and one
layout-overflow state constant bring the current source census to 212 declarations.

Constants are registered before type interning in both the normal package and
embedded-core pipelines, so capacity annotations see checked values. Existing
per-node facts hold declaration visitation state and memoized values; no new
fixed-capacity table or mutable runtime storage is introduced. Forward and
cross-file references use the same evaluator, and a visiting declaration detects
a dependency cycle.

Only explicit scalar `long` declarations with integer literals, unary negation,
constant references, and checked `+`, `-`, `*`, `/`, `%` are admitted. Arithmetic
checks happen before potentially overflowing operations. Signed literal endpoints
are handled explicitly; `LONG_MIN / -1` is an error and `LONG_MIN % -1` is zero,
matching the frozen reference. The capacity evaluator shares these safe helpers.

Layout arithmetic uses a separate proven-overflow state instead of conflating
overflow with the `LONG_MAX` oversized-layout sentinel. Checked products,
header additions, and alignment propagate through collections, structs, and
sums. Zero outer arrays avoid a false overflow and retain the existing nested
collection gate. The old `t06_size_overflow` fixture remains a real diagnostic.
Representable exact-`MAX` values reach body checking before their unsupported
gate, which still runs before helper/IR planning in both compilation pipelines.
Derived text headers and Option/Result tags are checked before writing type
facts, including negative sizes and the proven-overflow state.

Ordinary name lookup gives locals priority. Constant expression facts have a
distinct flag, and LLVM uses the immediate value without a global or local load.
Collection values/indexes, slice bounds, field locations, and scalar match phi
operands use the shared value-reference helper too; they cannot assume that a
constant Name has an SSA temporary.
Valid future constant forms keep their unsupported gate. The aggregate
`.bytes()` diagnostic remains separate from scalar constant admission.
Written capacity annotations retain package-constant lookup; typed runtime
expressions respect local bindings. Unsupported const dependencies leave their
capacity type unresolved until eligibility, allowing name-shadow checks to run
first rather than turning a valid future form into a malformed-capacity error.

Stage0 implementation sources and existing fixture contents/oracles are unchanged.

## Validation

The generated dependency regression reverses a 40-level shared graph to require
forward references. It bounds compilation with a 30-second timeout, checks a
direct `ret i64` immediate, and asks clang to verify the emitted LLVM IR. A naive
recursive evaluator would revisit this graph over a trillion times.

An O1 regression audit of 21 existing packages selected by `tests/run/*const*`
and `tests/e3/e3c_values_const_bytes` passed without reclassification: one build,
two diagnostics, 17 unsupported gates, and one expected rejection. Existing
oracles were preserved. An additional operand audit found direct SSA references
in collection, slice, field-location, and match emitters. A preserved pre-fix
compiler emitted an undefined `%v5` for `[K]`, confirmed by clang rejection.
Those consumers now use the shared helper, including the location helper in
`params.nl`. The positive fixture covers all affected contexts, including
Ascii and multibyte Text slices. Independent final review found no further
concrete operand hole. The interrupted pre-fix staged run is not passing
validation evidence.

The final combined O1/O3 selection passed 31 packages with zero mismatches:
three builds, 14 diagnostics, three intentional rejections, and 11 unsupported
gates. It includes all 21 new packages, the existing `t06_size_overflow`, both
`t06_core` shadow rejections, and capacity/zero cases. All 20 new error/gate
stderr oracles are exact and checked against selfhost output, rather than copied
from Stage0 diagnostics.
The reference accepts the const/type name collision, but DESIGN requires unique
package names, so that fixture is an intentional selfhost rejection.

Temporary probes checked multiplication, list header/addition, alignment,
nested struct/sum propagation, representable boundary layouts, and zero outer
arrays against the reference. The positive fixture separately prints local
`BASE = 3` while an array using static capacity `BASE` has package-constant
length 10. Its collection/slice/field/match cases execute with matching output.
The earlier 506-second staged attempt found the size-overflow diagnostic
regression; it is not counted as passing evidence.
The next attempt passed the full matrix and relocation checks but found a later
text-capacity contract failure. The corrected source passes all 11 cases in
`selfhost_text_capacity`, including conversion, tag, padding, and concat bounds.
That earlier 636-second attempt is not full-suite acceptance evidence.

The dependency/immediate regression passes on final source, and Rust formatting
and diff checks pass. The exact staged full-suite result will be recorded here
before landing.

## Actual self-build gate

The parent-run source-keyed compiler
`55ab67000f1545d44d53a6a89a22fbad180427bcccfd3a4c664ec519b51c4555`
evaluates the current compiler constants, then exits 2 at:

```text
collections.nl:18:12: error: not supported by the self-hosted compiler yet: text in collections
```

This is the `files: list<SourceFile, MAX_SOURCE_FILES>` parameter. `SourceFile`
contains a bounded Bytes name, making source-used byte fields in collections
the next demonstrated gate. Builder support remains another B1 dependency.
The exit status was captured directly with Python subprocess, avoiding the
PowerShell wrapper's generic failure status. No IR artifact was written.

Commands use the WSL toolchain and the explicit release reference:

```sh
export CARGO_TARGET_DIR=/home/ben/.cache/next-lang/target-takeover-e3c-20261028
scripts/compare-selfhost.sh --build \
  --reference "$CARGO_TARGET_DIR/release/nlc" --only 'tests/e3/b1_consts_*'
NLC_FRONTEND=selfhost cargo test --offline --release \
  --test selfhost_scalar_constants -- --nocapture
cargo fmt --all -- --check
git diff --check
```

No compiler benchmark result is claimed for this prerequisite. Formal compiler
benchmarks follow the stage-2/stage-3 identity and corpus-correctness gate.
