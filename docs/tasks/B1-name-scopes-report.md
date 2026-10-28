# B1 name scopes report

Date: 2026-10-28.

## Status

The B1 name-scope prerequisite advances past the original `count` name
conflict, and the focused checks pass. A fresh selfhost compiler reaches the
next known unsupported feature, constant declarations in
`selfhost/collections.nl:7`. A nested-match scope false positive found during
review has also been fixed and covered. This does not mean the compiler can
yet build its own source.

## Behavior and implementation

Local names may share names with user functions, built-in functions, types,
and constants, as specified in `docs/DESIGN.md`. Bare names resolve to local
bindings, while direct calls resolve to the named function or built-in. Local
variables still cannot shadow visible variables or enum cases that can be
written bare. Every user enum case name is reserved for variables, including
cases duplicated across enums; a typed match pattern using an ambiguous case
remains valid.

`selfhost/compiler.nl` now finds the owning function and nearest containing
block from the postorder node table, then checks declarations inside that
owner. The package shadow pass no longer reserves function, built-in, type, or
constant names. The local-reference walk also accounts for both `for`-each
item and index bindings, so a local with the same name as a function is not
mistaken for a function value inside the loop body. Pattern bindings use only
their nearest enclosing `MatchArm` as their visibility scope; a binding from a
nested match no longer leaks into the rest of its outer arm.

The bounded mechanical source renames needed to compile the selfhost package
were:

- `selfhost/collections.nl`: the local `source` serial in the list-pop emitter
  is now `source_serial`, avoiding its `source` parameter. Emitted LLVM names
  and suffixes are unchanged.
- `selfhost/compiler.nl`: `OptionalCall`'s local `result_ty` is now
  `optional_result_ty`; the empty-text branch uses `method_result_ty`; the
  concat branch uses `concat_result_ty`; and the nested optional-call payload
  source is `payload_receiver_source`. These locals shadowed visible values
  in their owning functions.
- `selfhost/compiler.nl`, `selfhost/lexer.nl`, `selfhost/parser.nl`, and
  `selfhost/source.nl`: unused `err(Full)` payload bindings now use `_`. The
  parser represents an identifier in `err(...)` as a variable binding, so
  `Full` shadowed the bare enum case. None of these arms read the payload; the
  error handling is unchanged.

No emitted LLVM identifiers, Rust compiler sources, or core ABI files were
changed for B1.

## Acceptance fixtures

The six new packages under `tests/e3/b1_names_*` cover:

- shared local names with a function, the built-ins `print` and `max`, and a
  type; loop item and index names that also match functions;
- direct calls to a same-named user function and to `print`, while bare uses
  resolve to the local;
- rejection of a variable named after an enum case shared across enums;
- a typed match on a duplicate case name;
- reuse of a nested match binding's name after that arm ends and in a sibling
  arm;
- the `max` same-name call reaching the existing unsupported built-in-call
  gate. Stage0 instead rejects that call as a local integer value; the exact
  Stage0 and selfhost diagnostics are recorded separately.

Constant declarations remain unsupported, so this change does not claim to
verify a local sharing a `const` name through execution.

## Validation

The final focused comparison used the explicit release Stage0 reference and
passed 55 packages: 28 builds, 12 intentional rejections, 14 unsupported
packages, and 1 expected-output package, with 0 mismatches. It covered
`tests/run/*shadow*`, `tests/run/*noshadow*`,
`tests/e1/functionshadow`, `tests/e2/reference_default_shadow`, and all
`tests/e3/b1_names_*` fixtures. The six new B1 packages alone also passed with
0 mismatches.

Commands:

```sh
NLC_TEST_JOBS=1 scripts/compare-selfhost.sh --build \
  --reference /home/ben/.cache/next-lang/target-takeover-e3c-20261028/release/nlc \
  --only 'tests/run/*shadow*' --only 'tests/run/*noshadow*' \
  --only tests/e1/functionshadow --only tests/e2/reference_default_shadow \
  --only 'tests/e3/b1_names_*'

CARGO_TARGET_DIR=/home/ben/.cache/next-lang/target-takeover-e3c-20261028 \
NLC_FRONTEND=selfhost NLC_TIMING=1 \
cargo test --offline --release --test selfhost_name_scopes -- --nocapture

cargo fmt --all -- --check
```

The source-hash-keyed selfhost executable used for validation was
`next-lang-test-selfhost/3625741c213c79bd1e4206442c0890b945634db8763534bebc321c7d4ef01df3/selfhost`.
Running that compiler against the complete `selfhost` package advances to the
expected gate:

```text
collections.nl:7:1: error: not supported by the self-hosted compiler yet: constant declarations
```

The scale regression uses the existing `scripts/gen-selfhost-bench.py`
repeated-parameter workload, warms each size, and compares three samples by
median. A manual run before the nearest-`MatchArm` refinement, under the
shared benchmark lock, recorded these raw samples:

| Functions | Samples (seconds) | Median |
| ---: | --- | ---: |
| 1,000 | 0.1048, 0.1046, 0.1053 | 0.1048 |
| 2,000 | 0.1650, 0.1668, 0.1681 | 0.1668 |

The integration test after the final source edit reported medians of 107.9 ms
and 168.7 ms. These are unlocked, unpinned local regression timings, not a
formal benchmark result. The test allows 2,000 functions up to four times the
1,000-function time plus 500 ms, avoiding a fragile absolute-time target while
catching the prior cubic regression. The test passed.

## Full staged validation

The required pre-commit hook passed the exact final source snapshot in 635
seconds before source commit `a18eb70`:

```sh
NLC_LONG_TESTS=1 NLC_E1_GENERATED_COUNT=64 NLC_TEST_JOBS=4 git commit ...
```

The hook runs `NLC_FRONTEND=selfhost cargo test --offline --release -q --test '*'`
under the 8,000,000 KiB address-space limit and one-hour timeout. This passed
the complete O1/O3 comparison of 734 registered and 256 generated packages,
O1/O3 forced relocation, the new scaling regression, and the existing budget,
capacity, UTF-8/corruption, memory, interface, and runtime contracts. Formatting
and diff checks passed. The earlier interrupted and failed attempts are not
counted as passing evidence. Stage0/Rust implementation sources are unchanged.

## Next task

Constant declarations are the next selfhost source blocker. The source-closed
[scalar constant task](B1-scalar-constants.md) is ready next: the compiler's
207 declarations are all long-valued literals, references, or arithmetic.
The [critical path](B1-critical-path.md) prioritizes this before builders;
selfhosting and B1 are not yet complete.

## Complete intentional-rejection audit

A parent-run O1 `--class rejects` audit checked all 43 then-classified rejects.
26 remained genuine rejections; 17 stale rows had been rejected only by the
old overbroad naming rule. `reference_unit_erasure`, `div_min_div_neg_one`, and
`mod_min_div_neg_one` now build and match the frozen compiler exactly. Fourteen
other packages reach their existing unsupported feature gates (aliases,
grow/builders, pool, Env/Args, function types, constants, or test parameters).
The parent reclassified those packages from actual results; existing test
contents and oracles remain unchanged. Together with the six earlier build
promotions and const-shadow gate, 24 old reject rows move: nine to build and
15 to unsupported. The registry now has 734 packages: 201 build, 204 diagnose,
26 rejects, 280 unsupported, 22 expected, and one expected-reject.

The first staged long-suite attempt matched every build, intentional reject,
expected output, and generated case at O1/O3. It found one further stale row:
`t20_args_without_grant` now reaches the existing unsupported Env-type gate,
which precedes capability diagnostics at this milestone. That row moves from
diagnose to unsupported; its source and expected files are unchanged. The hook
stopped with that classification failure; the corrected final snapshot then
passed the complete hook as recorded above.
