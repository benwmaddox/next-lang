# E3c generated selfhost corpus

`scripts/generated_selfhost_cases.py` exposes the extraction API
`generate_seeded_cases(root: Path, work: Path, count: int) -> list[tuple[str, str]]`.
Importing the module does not create files or run commands. The count range is
0 through 1000.

## Corpus

The original scalar and diagnostic generator remains byte-for-byte unchanged
in behavior. It still uses `random.Random(0xE1)`, keeps the same package paths,
random draws, diagnostics shuffle, case order, and classifications. The new
text packages are appended under `generated/text/valid` and
`generated/text/invalid`, using an independent `random.Random(0xE3C)`.

For each count, the generator adds one valid and one invalid text package.
Valid programs cover Unicode and escaped NUL literals, exclusive code-point
slices, `Text`/`Ascii` comparisons, Text struct fields and `Option` payloads,
Ascii arguments to read-Text parameters, owned Text returns, effectful
concatenation and slice receiver snapshots, and formatting with constant bounds.
Invalid programs cycle through Text capacity, read-Text parameter capacity,
statically out-of-range `byte`, oversized `Bytes` literals, and storing a
temporary `.bytes()` view. Generated invalid programs use only forms that
Stage0 rejects with status 2.

The standalone deterministic check is:

```sh
wsl -d Ubuntu -- python3 scripts/generated_selfhost_cases.py --selftest --count 8
```

It reports `generated selfhost cases deterministic: count=8, total=32`.
An independent count-8 comparison against the original generator confirmed
that the first 16 package paths, classes, and source files match byte-for-byte.

## Stage0 probes

The frozen Stage0 Rust frontend accepted and ran all eight generated text-valid
packages with status 0 and no stderr. It rejected all eight generated
text-invalid packages with status 2, empty stdout, and real diagnostics.
Representative diagnostics were:

- Text maximum exceeded: `text literal exceeds Text max 1 bytes max 4; increase its code-point or byte maximum`
- Read-Text parameter maximum mismatch: `cannot combine Text max 2 bytes max 8 and Text max 1 bytes max 4`
- Static `byte` range: `cannot prove this value fits byte`
- Static Bytes capacity: `byte literal has 2 bytes, exceeding Bytes max 1; increase the byte maximum`
- Escaped Bytes view: `a .bytes() view is temporary and cannot be stored or returned`

The explicit byte cast form `(byte)oversized` was not used because Stage0
rejects that syntax before type checking. The generated static range case uses
the supported uncast form `let invalid: byte = 300`, which Stage0 rejects.

## Selfhost O1/O3 comparison

The integrated harness ran with `NLC_E1_GENERATED_COUNT=64`,
`NLC_LONG_TESTS=1`, and `NLC_TEST_JOBS=4` as part of the full selfhost
integration suite on the final compiler source key
`7d963a47d2d217d00b56cdd413b2f4da6c96c55484cfb0fadf8bddad4b616a85`.
The build-comparison test passed: all 256 generated packages (128 builds and
128 diagnostics) matched at both O1 and O3, together with the 728 registered
packages. The complete integration suite subsequently exited 0, including long-mode
relocation and UTF-8 checks.

The first generated audit exposed a method-receiver difference: a slice must
capture lengths before effectful arguments but borrow the payload bytes from
the original storage afterward, matching the frozen compiler. Deep-copying the
receiver hid those writes. The compiler fix preserves function read-argument
and binary-expression snapshots; `e3c_receiver_order` separately pins the
receiver behavior. The generated expressions were retained unchanged and the
final O1/O3 audit passed.

## Larger audit

Explicit generated counts run independently of `NLC_STAGE0_PARITY`. A larger
audit can use:

```sh
CARGO_TARGET_DIR=/home/ben/.cache/next-lang/target \
NLC_E1_GENERATED_COUNT=128 NLC_TEST_JOBS=4 \
scripts/compare-selfhost.sh --build \
  --reference /home/ben/.cache/next-lang/target/release/nlc
```

This generates 512 packages across the preserved scalar and new text corpora.
