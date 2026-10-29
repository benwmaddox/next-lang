# B1 Stage2/Stage3 checkpoint report

Status, 2026-10-28: the Stage2-to-Stage3 chain passes at O1 and O3. The Stage2
and Stage3 LLVM IR artifacts and binaries are byte-identical at each
optimization level. The required staged-tree suite passed in 839 seconds for
commit `23a7e64`. The Stage3 corpus run timed out in its scaling precheck before
package comparisons began. A one-sample Stage3 own-source timing pilot exceeded
the 3x gate by a timeout lower bound; B1 is not accepted. The raw pilot record
is [B1-stage-chain-pilot.json](B1-stage-chain-pilot.json).

## Stage-chain result

The recorded runs used the same Rust Stage0 reference and source fingerprint
`da110929d75bae90f2242f983705550f11813cc780f74b05d7dc770dd4723f50`.
Both stages emit C-runtime, offset-stack IR. Timings below are measured command
durations from the chain reports; the first emission builds Stage2 from the
Stage0-built seed compiler, and the second is Stage2 compiling its own source
to produce Stage3.

| Optimization | Seed compiler emits Stage2 IR | Stage2 emits Stage3 IR | Stage2 clang link | Stage3 clang link | Total chain |
| --- | ---: | ---: | ---: | ---: | ---: |
| O1 | 8.517 s | 349.013 s | 18.809 s | 19.105 s | 398.79 s |
| O3 | 8.619 s | 347.759 s | 20.782 s | 21.874 s | 402.39 s |

At both levels, the Stage2 and Stage3 LLVM IR artifacts are 112,832,295 bytes
and have SHA-256 `d266ebfc364eecbc03772f4ae51460e41c896eccf013c59291bf7d366aa80b05`.
The matching binary SHA-256 is `52a3a90fc2956270401cb1b70652999e72d5e841b7c8cb730c8a23bc304754e6`
at O1 and `8b522f4748978c3daa23cfa6267c16c43962cf70311dfd6f92a1a04c22fc8a80`
at O3. Both compiler-emission commands exited successfully without stdout or
stderr.

Machine reports and artifacts are in `.selfhost-stage-chain-s9flmyvq/` (O1)
and `.selfhost-stage-chain-85a_5o6y/` (O3).

## Correctness evidence

- The actual Stage3 compiler passed eight C-runtime golden runs at O1 and O3.
  The tiny Stage2 smoke-parse check passed.
- `tests/e3/b1_enum_call_field` and `tests/e3/b1_enum_index_field` match their
  Rust Stage0 expected-output oracles at O1 and O3 with the current seed. The
  pre-fix seeds reproduced the dropped call and indexed enum-field errors.
- The O1/O3 Stage2-to-Stage3 IR and binary identity checks both passed.
- The required staged-tree suite passed in 839 seconds for commit `23a7e64`.

The actual Stage3 compiler-corpus run was invoked with selectors covering 791
registered and 256 generated packages at two workers. Struct IR-bound
prechecks passed (depth 20: 750,202 bytes; depth 40: 803,562 bytes), then the
3,200-enum scaling precheck timed out at 180 seconds. Package comparisons never
started, and the reference cache recorded zero hits and zero misses. This is a
performance blocker before package coverage, not a package correctness result.
Logs are in `.selfhost-stage-chain-85a_5o6y/corpus.stdout` and
`.selfhost-stage-chain-85a_5o6y/corpus.stderr`.

## Performance and design status

The chain durations above are pipeline timings. A separate isolated own-source
pilot compiled the same `selfhost` package to LLVM IR only, without clang. It
used one sample, no warmups, CPU affinity 0, O3, and C runtime mode. Rust Stage0
used the Rust frontend API `compile_package_with_frontend(package,
Frontend::Rust)` from the same fresh release rlib as the reference `nlc`; its
`package_link_description` selected `LinkRuntime::C`, and `NLC_STACK_MODE` was
`pointer`. Stage3 used the passing O3 chain binary in offset mode with
`--runtime=c`. This is the supported representation difference: Rust Stage0
does not support offset mode for this compiler source.

Rust Stage0 emitted IR in 1.80 seconds wall time (1.76 seconds CPU). Stage3 was
terminated at its 30-second deadline (30.87 seconds in GNU `time`, 30.58
seconds CPU) and did not complete IR emission. The raw report computes a 16.6667x
lower bound from the 30-second deadline and 1.80-second Rust time; allowing for
the displayed-time precision, this is at least 16x and already exceeds the 3x
per-case failure threshold. Observed maximum resident set during these samples
was 270,080 KiB for Rust and 489,280 KiB for Stage3. No completed Stage3 IR
hash, median, or acceptance pass is claimed.
The input fingerprints were unchanged. Exact measured child commands, wrapper
commands, environment, hashes, and measurements are in the raw JSON linked
above. Its chain report identifies clang 18.1.3, rustc 1.93.0, and Python
3.12.3; the timing runner used `/usr/bin/time` and `/usr/bin/timeout` (their
versions were not recorded).

This single own-source case fails the 3x gate by lower bound. Small and large
compile cases and full compiler-corpus package coverage remain incomplete; the
corpus run timed out in its scaling precheck before package comparisons began.
The chain and pilot measurements separate IR emission from clang time.

A five-sample GDB trace showed repeated `CompilerTables` copies on the own-source
compilation path, motivating a compiler-implementation preference to avoid
snapshots or copies of working tables unless no other reasonable option remains.
Before choosing one for a concrete case, review its cost and clearer code,
dataflow, or helper alternatives; this records no blanket language policy and
changes no emitted-program snapshot semantics.
