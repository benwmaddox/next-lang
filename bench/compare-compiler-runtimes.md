# Compare compiler runtimes

`compare-compiler-runtimes.py` runs the LangArena, Osprey, and `vs-rust`
programs through Stage 0, Stage 1, Stage 2, and Stage 3. It checks the exact
stdout bytes before timing. Every generated LLVM module is linked with the
same `clang -O3` and `runtime/nl_runtime.c`; offset-stack IR also receives
`-DNLC_STACK_MODE_OFFSET=1`.

Run it from Linux or WSL. The output directory must be new or empty and
repository-relative. The example smoke run uses the Osprey `fib` case and one
measured sample:

```bash
python3 bench/compare-compiler-runtimes.py \
  --stage0-ir-helper target/compiler-runtime-benchmarks/stage0-ir-helper \
  --stage0-nlc target/release/nlc \
  --stage1 target/b1-performance-matrix/run-rysdz1w_/bin/selfhost/rust-stage0.exe \
  --stage2 .selfhost-stage-chain-9m83m4b2/stage2 \
  --stage3 .selfhost-stage-chain-9m83m4b2/stage3 \
  --suite osprey --case fib --samples 1 \
  --output-dir bench-results/runtime-smoke
```

Build the Stage 0 helper from the current Rust compiler sources before running
the comparison:

```bash
cargo build --release --bin nlc --lib
mkdir -p target/compiler-runtime-benchmarks
rustc --edition=2021 bench/runtime-stage0-ir.rs \
  --extern next_lang=target/release/libnext_lang.rlib \
  -L dependency=target/release/deps \
  -o target/compiler-runtime-benchmarks/stage0-ir-helper
```

Pass that helper path with `--stage0-ir-helper`. Rebuild it whenever the Rust
compiler sources change so Stage 0 represents the same source revision as the
other compiler stages.

For the full suite, omit `--suite`, `--case`, and `--mode` (the default LangArena
mode is `run`). Use `--suite langarena --mode test` for a smaller LangArena
check. Repeat `--suite` or `--case` to select several suites or cases. A case
filter matches either a package directory name or its displayed benchmark name.
`--stage0-nlc` is optional and records the Rust-built compiler binary identity.

Each runtime process is pinned to one CPU (default 8) and measured by
`perf_counter_ns` plus GNU `/usr/bin/time` for user/system CPU and peak RSS.
The runner holds `/home/ben/linuxbench/bench.lock` for the run, validates one
warmup and every measured sample, rotates stage order between rounds, and writes
an atomic `report.json` checkpoint after each command. `summary.md` lists the
per-case whole-process medians; LangArena times include preparation and its
own warmup. No prep-time subtraction or cross-case geometric mean is used.

The output directory contains the report, full command stdout/stderr logs,
artifacts, and summary. The report records compiler/helper/runtime/tool hashes,
package source hashes, exact commands, IR and executable hashes/sizes, each
validated sample, stack/runtime metadata, and stage-to-stage IR/binary equality.
It also retains LangArena's headline, closest, not-comparable, pending, and
variant groups. Pending-float cases are listed without fabricated builds or
timings; absent official ports are listed in the inventory. The four
`main_reuse.rs` Rust variants are outside this comparison.

Final status is `failed` if an attempted build, output check, or run fails;
`completed_with_coverage_gaps` if a full selection has missing or pending cases
(or a selected case is pending); and `passed_selected_cases` when the selected,
present cases pass. The last status does not claim that every official port ran.
