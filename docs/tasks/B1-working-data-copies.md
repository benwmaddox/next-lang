# B1 compiler working-data copy checkpoint

Status, 2026-10-28: the O3 Stage2 self-source IR-emission command fell from
347.759 to 26.353 seconds across revisions (one run per revision). The latest
own-source IR-only pilot measured Stage3 at 25.21 seconds vs Rust Stage0 at
1.87 seconds (13.4813x, above the 3x gate); the IR hash matched. The staged
suite passed in 806 seconds for `27256a3`, and C-runtime goldens passed at
O1/O3; the latest corpus run completed with 16 mismatches. See the
[raw pilot](B1-working-data-pilot.json).

## Recorded O3 checkpoints

Each `stage3-compiler` value is Stage2 compiling that revision's `selfhost`
package to Stage3 C-runtime IR; clang is separate. Every chain passed Stage2/
Stage3 IR and binary identity.

| Checkpoint | Source SHA-256 prefix | Stage2 emits Stage3 IR | IR bytes | Chain report |
| --- | --- | ---: | ---: | --- |
| Baseline | `da110929d75b` | 347.759 s | 112,832,295 | `.selfhost-stage-chain-85a_5o6y/` |
| Two wrapper lookup hoists | `d0fa151f1b1a` | 190.151 s | 112,825,864 | `.selfhost-stage-chain-m70u8np_/` |
| Five collection lookup hoists | `6858eef542b6` | 109.784 s | 112,805,686 | `.selfhost-stage-chain-5d9ie7mf/` |
| Normal-type, parser, and table-query hoists | `69bb106028d8` | 32.827 s | 112,718,262 | `.selfhost-stage-chain-1s0ymidk/` |
| Working-data copy cleanup | `e13bc4336c82` | 26.353 s | 112,465,703 | `.selfhost-stage-chain-g80f6tmw/` |

Final O1 chain `.selfhost-stage-chain-gl72tbk2/` passed: identical
112,465,703-byte IR (SHA-256 `f43219edb8841e93a441b4faeb582c47514ebf99d9d7f44b04093677f870d211`)
and binary (SHA-256 `b0bd9afe1cb9ce9fabd08dd2601d5d012fea2a54c9b3789ac1b5b17ef9d15234`).
Stage2 self-source emission took 28.995 s; seed emission 8.611 s and separate
Stage2/Stage3 clang commands 18.929/18.348 s.

The single command duration decreased about 13.2x across these revisions. This
is a useful progress signal, not a controlled performance result: source
changed between checkpoints, each duration is one run, and no medians or
cold/warm samples were collected. For the last checkpoint, Stage3 IR SHA-256 is
`f43219edb8841e93a441b4faeb582c47514ebf99d9d7f44b04093677f870d211`, and the
Stage3 binary SHA-256 is
`da530b8c56a29259fa92cda764ae880b20c6d24062374591d7a5052876866f0a`. Clang's
Stage3 link command took 21.874 seconds at baseline and 19.714 seconds on the
last run; these times are reported separately. The O3 chain reports record
clang 18.1.3, rustc 1.93.0, and Python 3.12.3.

The Rust comparison compiled the same `selfhost` package with
`compile_package_with_frontend(package, Frontend::Rust)` from the fresh release
rlib used by the reference `nlc`; `package_link_description` selected
`LinkRuntime::C`. Rust used pointer mode and Stage3 used offset mode, both at
O3 with C runtime, pinned to CPU 0, with no warmups. This was IR generation
only, without clang. Rust measured 1.87 seconds wall/1.73 CPU; Stage3 measured
25.21 seconds wall/25.63 CPU, or 13.4813x. Stage3's generated IR SHA-256
matched the chain artifact above. Observed maximum resident set during the
samples was 270,640 KiB for Rust and 304,656 KiB for Stage3. Input fingerprints
were unchanged. The exact child and wrapper commands, environment, source and
binary hashes, and measurements are in the raw JSON linked above. The chain
report records tool versions; the timing report identifies GNU `time` and
`timeout`, but does not record their versions.

## Copy-site audit

A fresh 784-function census found zero whole-file call sites to `nl.copy.52`
(`CompilerTables`), `nl.copy.68` (`ParseTables`), `nl.copy.80` (`SourceBytes`),
`nl.copy.81` (`Tokens`), and `nl.copy.82` (`SourceFiles`). Their helper
definitions remain. The static
`CompilerTables` call-site count went from 48 at baseline to 46, 41, 29, then 0
across the checkpoints above. The source work consists of pure lookup hoists
and centralizing the kind/id lookup sequence in
`aggregate_source_location_for_node`; no cache was added.

The wider source is not globally copy-free: the census still reports 3,338
direct copy calls across 142 helper IDs, plus 103 helper-to-helper calls.
These include small record/value copy paths. The audit covered the five largest
working-data state types; it does not show that all implicit copies are gone.
Fixed-capacity layout ceilings include 2,762,171,552 bytes for
`CompilerTables`, 680,912,064 for `ParseTables`, 80,000,008 for `Tokens`, and
67,108,864 for `SourceBytes`. These are capacity ceilings, not measurements of
bytes copied or resident memory.

Independent review found no blockers and confirmed semantic guards and lazy
paths remain. No language or emitter semantics, error behavior, or purity rules
changed. The request to make silent snapshots impossible or explicit/error is
still a scope question: compiler-only or all Next programs. This checkpoint
does not claim enforcement or adopt a broader language rule.

## Correctness evidence and remaining blockers

The latest Stage3 corpus run covered the selected 791 registered and 256
generated cases at O1 and O3. Its struct IR bounds and enum scaling checks
passed; enum checks took 0.527 seconds for 1,600, 1.558 seconds for 3,200, and
5.264 seconds for 6,400 constructors. The run reported eight mismatches at
each optimization level, with no mismatches among the 256 seeded cases. The
16 mismatches were: `t19_expression_chain_limit` was accepted and emitted
`1002` despite the 1,000 nesting limit; `t06_size_overflow` reported unsupported
nested collections instead of the overflow diagnostic; and six
`b1_consts_unsupported_*` cases returned a generic unsupported-construct
diagnostic instead of their explicit oracle. A follow-up comparison reproduced
all eight mismatching cases on the earlier Stage3 compiler, while the Stage0-
built seed matched all eight explicit diagnostic oracles. These failures
predate the working-data cleanup; this does not establish one shared cause.
Corpus logs: `.selfhost-stage-chain-g80f6tmw/corpus.stdout` and `.selfhost-stage-chain-g80f6tmw/corpus.stderr`.

Small and large Rust-versus-Stage3 timings remain unmeasured; the single
own-source failure is not full benchmark coverage or 3x gate acceptance.
