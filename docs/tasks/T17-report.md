# T17 implementation report

## Implemented

- Data-stack reservations are computed per `main` and per test entry. The bound includes live caller storage, callee scratch, result destinations, gathered structure-of-arrays values, copy-down temporaries, loop growth, and the runtime helper margin. Reservations add the 256-byte helper margin and round up to 4 KiB pages. Bounded reservations have no 64 MiB ceiling; an analysis result that is unknown uses the 64 MiB default.
- Each test selects its own reservation before starting. A reservation that cannot be mapped fails at startup with the entry name and requested size. The existing T13 runtime exhaustion path remains separate from T17's refusal of an undersized reservation.
- `nlc inspect stacks <package>` reports the data bound and reservation, optimized native-stack bound and call chain, recursive status, source lines, loop growth, copy-down sites, and all reserved regions (marking regions over 64 KiB). A test-only runtime hook reports reserved bytes, resident/touched bytes, and data-stack high-water use.
- `expect stack_peak(function) < limit` parses binary byte units and checks the conservative data-plus-native bound without page rounding. Large returned `Ascii.empty()` builders now use the caller-owned result region directly, matching the emitted storage and avoiding a duplicate region in the analyzer.
- The stack analyzer now includes structure-of-arrays gather temporaries, copy-down replacement values, and collection storage created by `fill`. These were needed to keep computed bounds above measured peaks in existing collection fixtures.
- Native bounds use optimized LLVM frame sizes, a per-frame overhead, and the helper margin. They are reported and used by `stack_peak`; T17 does not reserve a separate native stack. Recursive entries use the T19 recursion budget and are reported as recursive.

## Worked example

`nlc inspect stacks tests/run/t17_worked_reservation` reports:

```text
entry point main
  data stack worst case: 40348 bytes
  data stack reservation: 40960 bytes
  data stack touched: measured at runtime (test hook available)
  native stack worst case: 66136 bytes
  native stack: nonrecursive
  native stack call chain: main -> render -> line
  data region: main.nl:2 upper (76 bytes)
  loop at main.nl:8: growth per iteration 80 bytes; at most 500 iterations
  data region: main.nl:15 output (40016 bytes)
  source lines driving bound: main.nl:1, main.nl:14, main.nl:15, main.nl:2, main.nl:6, main.nl:8
  unbounded components: none
```

The output is `2890`. The 40,016-byte caller result region holds the returned builder; the `line` temporary and helper margin bring the computed data peak to 40,348 bytes.

## Measured versus computed data-stack use

`peak_used` is the runtime data-stack high-water mark. `touched` is the resident-page measurement from the test hook; the large reservation shows why the two measurements are separate.

| Workload | Computed worst case | Reservation | Measured peak use | Touched pages | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| Worked reservation, run through a test wrapper | 40,348 B | 40,960 B | 40,172 B | 8,192 B | Pass |
| T17 startup-reservation test | 16,640 B | 20,480 B | 8,192 B | 8,192 B | Pass |
| T17 large-reservation test | 1,000,000,264 B | 1,000,001,536 B | 1,000,000,008 B | 8,003,584 B | Pass |
| T16 collections run, through a test wrapper | 134,442 B | 135,168 B | 131,016 B | 102,400 B | Pass |

The large-reservation entry reports a 1,000,000,008-byte region for `values`. It reserves 1,000,001,536 bytes, while the test touches about 8 MB and pushes one million of the 125 million available `long` elements.

## Other acceptance checks

- `stack_peak` passes for the 2 MB budget and fails the 1 KB budget with `stack_peak(bounded_work) exceeded 1024 bytes`.
- Setting `NLC_TEST_DATA_STACK_BYTES=1024` for the T17 startup test refuses to start it with `test reservation is below the computed worst case`. T13's separate shrunken-stack test still reaches runtime exhaustion when explicitly allowed.
- Building the large-reservation package and launching it under `ulimit -v 200000` exits before `main` with: `nlc: data stack startup failure for entry 'main' (reservation 1000001536 bytes): could not reserve the requested address range`.
- T19 recursion inspection reports a 256-byte data bound and a 327,832-byte recursive native bound with a 262,144-byte recursion budget; it does not report the entry as unbounded.
- The unknown-bound fallback is covered by the analysis unit test (`None` reserves 64 MiB). The current language has no legal C-binding stub that can produce an unknown source contract, so no running source fixture was added for this analysis-only case.
- A generated package with 600 functions, each containing a counted million-iteration loop, completed `inspect stacks` in 4.26 seconds with 126,560 KiB maximum RSS in this WSL environment.

## Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — passed, including the run and test fixture harnesses, parser snapshots, T13 exhaustion test, and T17 reservation tests.

No external crates were added.
