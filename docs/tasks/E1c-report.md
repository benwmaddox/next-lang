# E1c report: next-lang core library

## Result

The E1 subset now builds with either the existing C runtime or an embedded next-lang core library. The core library provides process startup, Linux system-call wrappers, test selection, failure reporting, buffered output, environment setup, integer formatting, and the five internal memory functions. The selfhosted compiler embeds generated sources in `selfhost/core_files.nl`; the freshness test and IR header check pin the embedded source hash (`82ed2b13a01435cbe1995bf17ee4df78e92251f6cb50bd28f3a2d0125df1d143`). The IR v2 header selects `c` or `core`, and core links use the freestanding static entry point.

The compiler accepts int/long casts and `-> never` in ordinary packages, and limits the `sys` operations and `sys.Addr` to the embedded core unit. `--runtime=c` remains available for the reference leg. No external crates were added.

## Reference comparison

The build comparison passed at O1 and O3, including its C-runtime third leg and seeded cases, with zero mismatches. The final E1 classification is 35 build, 42 diagnose, and 405 unsupported packages.

This differs from the E1c task's stated 34/39/409 counts. The binding design note explicitly makes int/long casts and `-> never` ordinary language features, so `tests/run/bad_cast` moved to build and three T26 `never` cases moved to diagnose. This follows the task's instruction that the design note takes precedence over the count in the task text. Other `never` cases that need unsupported function-type features remain unsupported.

## Runtime and memory checks

- `scripts/test-core-output.py` passed partial-write handling, EINTR retries, broken-pipe behavior, `/dev/full` flush failure, line buffering, and output ordering on pipes and shared/separate terminals.
- `scripts/check-core-test-index.py` found matching C/core output and status for empty, whitespace, signed, negative-zero, malformed, trailing-character, and overflowing `NLC_TEST_INDEX` values.
- `scripts/check-core-startup.py` found matching C/core behavior at 64/65 arguments and 4096/4097-byte argument limits, with `NLC_STACK_PREALLOC=1`, and on root-directory open failure.
- `scripts/check-core-memory.py` passed sizes 0–300, source/destination alignments 0–15, and both overlap directions for `memmove`, at O1 and O3.
- The linked O1 and O3 core binaries passed `scripts/check-core-binary.py`: no undefined symbols, `INTERP` header, or `NEEDED` entry; all five memory functions were local; and no transitive call path returned to a memory function.

The design note defers data-stack growth, `mremap`, and stack-address system operations until E3 because E1 does not allocate data-stack regions. Therefore the forced-relocation-during-syscall-argument test described for the later stack-growth path cannot run in E1c and is deferred to E3. The E1c environment contract covers `NLC_TEST_INDEX` and `NLC_STACK_PREALLOC`; the test-build temporary root and stack/memory instrumentation variables are also deferred as the note specifies.

## Benchmarks

Both benchmark scripts ran under the WSL lock at `/home/ben/linuxbench/bench.lock`, on an Intel Core Ultra 9 185H with Ubuntu clang 18.1.3. The E1 build benchmark used seven compile samples after building the stage-zero executable once; both generated programs returned output `4`.

| E1 workload | C runtime | Core runtime |
| --- | ---: | ---: |
| Median compiler time | 1597.088 ms | 1633.403 ms |
| Link time | 4736.409 ms | 4799.176 ms |
| Binary size | 761,344 bytes | 683,664 bytes |

The embedded core added 36.316 ms to median compiler time (2.3%). The trivial C binary was 92,960 bytes with a 446.617 ms link; the trivial core binary was 15,056 bytes with a 183.470 ms link. Median process startup was 1981.967 μs for C and 2001.862 μs for core in this noisy WSL measurement, effectively similar. The one-time stage-zero build took 14,427.865 ms.

The quick memory benchmark compared out-of-line core calls with the glibc shim at O1 and O3, using seven samples and three alignments. Representative O1 results, in ns/call for smaller sizes and total time for the largest size:

| Size | Core `memcpy` | glibc `memcpy` | Core `memset` | glibc `memset` |
| --- | ---: | ---: | ---: | ---: |
| 0 bytes | 1.65 ns | 2.08 ns | 3.63 ns | 1.91 ns |
| 8 bytes | 1.67 ns | 1.96 ns | 2.76 ns | 2.07 ns |
| 16 bytes | 2.04 ns | 1.92 ns | 1.70 ns | 1.96 ns |
| 64 bytes | 2.08 ns | 1.69 ns | 1.93 ns | 1.67 ns |
| 256 bytes | 4.8 ns | 1.98 ns | 4.55 ns | 1.90 ns |
| 4 KiB | about 120–130 ns | about 120–130 ns | about 120–130 ns | about 120–130 ns |
| 16 MiB | about 1.16 ms | about 0.54 ms | about 0.37 ms | about 0.37 ms |

O3 showed the same pattern: 64-byte `memcpy` was about 2.2 ns versus 1.68 ns, 256-byte `memcpy` about 5.1 ns versus 1.94 ns, and 16 MiB `memcpy` about 1.16 ms versus 0.53 ms. Results at 64 KiB and 1 MiB were close to glibc. The 256-byte results miss the design's 1.25x target, and 16 MiB `memcpy` is about 2.1x slower. The implementation uses 128-bit moves for medium sizes and `rep movsb` for large forward copies; it does not use AVX-width copies, which explains the large-copy gap against glibc on this CPU. `memset` at 16 MiB was comparable to glibc. These misses are recorded for review rather than treated as meeting the speed target.

## Validation and limits

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` and `cargo build --release`: passed.
- `ulimit -v 8000000; timeout 1800s env NLC_FRONTEND=rust CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test`: passed.
- The same bounded full `cargo test` with `NLC_FRONTEND=selfhost`: passed. The cross-frontend lexer/parser/build comparison took about 708 seconds in each suite.
- Python syntax compilation for the added scripts and `git diff --check`: passed.

`qemu-aarch64` and `strace` are not installed in this WSL environment, so arm64 execution and syscall-count observation were unavailable. The executable runtime checks and benchmarks were performed on native x86-64 Linux under WSL.
