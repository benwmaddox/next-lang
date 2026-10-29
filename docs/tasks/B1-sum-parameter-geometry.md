# B1 indexed sum-parameter geometry checkpoint

Status, 2026-10-29: commit `5067d85` fixes sum-valued fields of indexed records
through read/write parameters and helper forwarding. The required staged suite passed
in 758 seconds. The actual Stage3 corpus now passes at O1/O3 with 792 registered
and 256 seeded cases and zero mismatches. The O3 chain passes; its own-source
emission time is a pipeline diagnostic, not a new Rust comparison. Performance
acceptance remains open.

## Geometry correction

The regression exercised `Kind`, `Payload`, `Option`, and `Result` sum-valued
fields of indexed records, including read/write parameter forwarding and
reads/writes after arena growth. The existing four-field argument descriptor
(`anchor`, `offset`, `copies`, `index`) is unchanged. On indexed use, the
compiler computes the row address with `index * full_sum_size`, preserving null
handling, offset relocation, and the generic non-contiguous layout guard. No
snapshot or language-rule change was introduced.

## O1/O3 chain artifacts

Source fingerprint: `46140bec11559bd3a21b76d10076e1ca827fdefc2e6bd75b3f6c85f2aa321aa6`.
At O3, the Stage2 and Stage3 IR artifacts are byte-identical (SHA-256
`d06be75e218f4c15b7ba4bf1aa92c761b4dabbef6bae763b10c10b1167bd1b37`) and
their binaries are identical (SHA-256
`1e2c1cfe2b3146217d62d78499c5c27f183d841ffebd782e51f7d05c4f550531`). The
O1 chain in `.selfhost-stage-chain-w0adtmno/` also passed: its Stage2 and Stage3
IR artifacts are byte-identical at 112,648,479 bytes with the same SHA-256; its
binaries are identical (SHA-256
`eaac18cfdcf7d3d0546889ec4c1f22a7ee2c2abfc6286328175506d1204a8d09`). O3
Stage2 self-source IR emission took 25.4 seconds; O1 took 28.41 seconds.
Clang ran separately (O3 Stage2/Stage3: 19.882/19.739 seconds; O1:
17.49/17.982 seconds). These are single chain-command durations, not an
end-to-end benchmark or a matched-input Rust comparison. The earlier 13.4813x
Rust comparison measured a previous source revision and does not establish the
current revision's ratio.

## Validation

- Eight prior-package diagnostic oracles match exactly. The new
  `tests/e3/b1_sum_parameter_geometry` fixture passed 33 exact stdout checks
  across normal and forced-move modes at O1/O3. Core runs observed two growths
  and two relocations; C-runtime runs observed one growth and one relocation.
  Eight actual Stage3 C-runtime golden runs passed at O1/O3.
- The required staged suite passed for commit `5067d85` in 758 seconds.
- The actual Stage3 compiler corpus passed with 792 registered and 256 seeded
  cases at O1/O3, two workers, and zero mismatches. The previous eight corpus
  mismatches are fixed.
- The focused corpus attempt stopped at its scaling precheck. The idle full
  retry passed with the same guard and thresholds: 1,600/3,200/6,400 enum
  checks took 0.455/1.323/4.617 seconds. No semantic bypass or threshold change
  was used. Full logs are in `.selfhost-stage-chain-yu8cxnl6/corpus.stdout` and
  `.selfhost-stage-chain-yu8cxnl6/corpus.stderr`.
- The latest large-state copy-call audit found no calls to `nl.copy.52`,
  `nl.copy.68`, `nl.copy.80`, `nl.copy.81`, or `nl.copy.82` in Stage2 IR.

## Remaining work and scope

No new Rust-versus-Stage3 benchmark was run, so the 3x performance gate is not
accepted. The profiling/read-only plan identified a full AST
function-existence scan per name as a hotspot candidate; no change for it has
been implemented.

The request to make silent snapshots impossible or explicit/error remains a
separate scope question: compiler-only or all Next programs. This fix changes
neither that policy nor compile-error enforcement.
