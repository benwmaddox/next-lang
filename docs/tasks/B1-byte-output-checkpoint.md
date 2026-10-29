# B1 byte-output checkpoint

Current source commit: `4744334`, pushed as PR #15. It changes
`selfhost/compiler.nl`, `selfhost/text.nl`, and `selfhost/c_runtime.nl` for
source fingerprint `f5ac405ca8b3c3dba6ec83ca647c65d46a3fbe0776d8c80c3700d33849fec692`.

## Changes in the source snapshot

- `function_name_present` is a boolean index over interned names, populated in
  one AST scan. Function-name existence queries are now O(1), rather than
  rescanning the AST.
- `ir_write_ascii`, `ir_write_bytes`, and `ir_write_number` use bulk append on
  the normal path. A `Full` result keeps the existing byte fallback, preserving
  the accepted prefix and overflow behavior.
- Four generated text payload copies now call existing `memmove`: Bytes views,
  literal payloads, Text slice payloads, and concat operand ranges. Text byte
  lengths and codepoint counts remain explicit.
- The C interface emits this LLVM declaration:

```llvm
declare ptr @nl_context_base(ptr readonly) nounwind willreturn memory(argmem: read)
```

  This matches the Clang 18 C-source attributes; it does not claim `nocapture`
  or `memory(none)`. Stack growth can update the base pointer, so the
  post-growth base reload remains necessary.

## Correctness evidence

- The Stage2-to-Stage3 chains passed at `O1` and `O3`. Stage2 and Stage3 emitted
  identical IR and binaries at both levels; the IR SHA-256 is
  `6d77f5573e33376026a3f6886371f76a88c151bddb367664b6487522732748d9`.
  Reports: `.selfhost-stage-chain-0ndaets7/report.json` and
  `.selfhost-stage-chain-9qs1db0k/report.json`.
- The full Stage3 corpus passed at `O1` and `O3`: 792 registered plus 256 seeded
  cases, with zero mismatches. The enum scaling guard also passed at 1,600 /
  3,200 / 6,400 enums (0.174 / 0.354 / 1.026 seconds). See
  `target/b1-current-validation/stdout.log`.
- The writer-body probe passed 15 independent byte/overflow goldens at `O1` and
  `O3`, with old/new outputs matching across four binaries. This is targeted
  writer evidence, not full compiler coverage
  (`target/b1-ir-writer-probe/report.md`).
- Two forced-relocation fixtures passed at `O1` and `O3` with exact expected
  output; observed relocation counts were 1 and 3
  (`target/b1-c-getter-relocation/report.md`).
- The required staged-tree selfhost suite passed in 754 seconds and the hook
  allowed source commit `4744334` to be created
  (`target/b1-current-validation/stderr.log`).

## Timing evidence and limits

The final warm IR-generation matrix used one warm-up and three measured samples
per frontend and case, paired on CPU 0. Both frontends ran through the same
GNU-time/timeout wrapper; primary wall time used a monotonic clock at 1 ms
resolution. Inputs and output checks passed, fingerprints were unchanged, and
emitted IR hashes stayed stable across samples.

| Case | Rust Stage0 median wall | Stage3 median wall | Stage3 / Stage0 |
|---|---:|---:|---:|
| Self-host compiler | 1.895 s | 3.752 s | 1.979947x |
| Generated package, 128 functions | 0.046 s | 0.093 s | 2.021739x |
| Generated package, 2,048 functions | 0.219 s | 0.413 s | 1.885845x |

The current user goal is at most 1.1x Rust Stage0. All three measured ratios
exceed 1.1x, so none passes the current per-case target. The raw matrix's
`threshold_stage3_over_rust: 3.0` and `status: passed` describe the earlier 3x
gate; retain that report unchanged as historical evidence. PR #15 is a
correctness and incremental-optimization milestone, not achievement of the
updated speed goal. These are `O3`, C-runtime IR-only measurements; Rust Stage0
used pointer mode and Stage3 used offset mode. That describes the measured
implementations, not a permanent arena requirement. Cold-start, end-to-end
compile-and-link, and broader stack benchmarks also remain incomplete. See the
byte-exact [final matrix report](B1-byte-output-matrix.json).

The earlier one-pair [pilot record](B1-byte-output-pilot.json) is historical:
its 1.9167 ratio is wall time, not CPU time, and it also exceeds the current
1.1x goal. Use the final matrix as the current timing evidence; its raw record
still reports the historical 3x threshold.

## Smallest next compiler step

Prioritize the direct scalar field-projection opportunity in the
[Stage1-versus-Stage2 comparison](B1-stage1-stage2-comparison.md): improve
general indexed-field lowering such as `rows[i].field`, avoiding full aggregate
materialization where practical. Selfhost compilation is a stress workload for
shared parser/checker/emitter paths; any fix should benefit varied packages,
not special-case selfhost. The cited `files[file_index].base` comparison used
pointer-mode Stage1 and offset-mode Stage2; it does not establish offset mode as
mandatory or rule out a different correct, faster arena strategy. No language
change is needed. Preserve the core data-stack intent: stack allocation, scoped
lifetimes, and bulk reclamation. Other arena address strategies are
implementation choices within that model; heap, GC, and ownership redesigns
are out of scope. Benchmark varied inputs against the updated 1.1x goal.

Core I/O replacement and copy-language/syntax enforcement remain deferred.
