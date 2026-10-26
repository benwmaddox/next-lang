# next-lang vs Rust Benchmarks

A set of paired benchmark programs comparing next-lang's stage-0 compiler against idiomatic Rust on equivalent tasks.

## Overview

Each benchmark pair consists of:
- `main.nl`: equivalent program in next-lang
- `main.rs`: equivalent program in Rust (compiled with `rustc -O`)

The programs use deterministic input (linear congruential generator seeded with 1) and produce checksums, allowing output verification.

## Benchmark Pairs

### tight_list
**Measures:** Sum and scan operations over a large list (100,000 elements) with conditional branching.

- Tests tight loop performance with data access and if/else branches
- Uses modulo operations to create realistic branch behavior
- Runtime: ~0.3–0.5 seconds

**Selfhost readiness:** E3a2 (arrays and lists ready; no Text, Option, or function values needed)

### struct_update
**Measures:** Update of struct fields across many iterations.

- Tests array-of-structs layout and field update performance
- 4,096 particles updated over 1,000 iterations
- Each particle has 4 long fields (x, y, vx, vy)
- Runtime: ~0.5–1.0 seconds

**Selfhost readiness:** E3a2 (structs and list elements ready)

### calls
**Measures:** Function call overhead with `write` parameters and small function bodies.

- Tests parameter-passing cost vs. direct field access
- Calls `bump_field` (takes a `write long`) and `process_value` frequently
- 1,024 items × 100 rounds with 4 calls per item
- Runtime: ~0.3–0.5 seconds

**Selfhost readiness:** E3a2 (write parameters are part of E3a2)

**Fairness note:** next-lang uses `write` parameters (a pointer to a field) while Rust uses `&mut`; both are compile-time verified as non-aliasing. The cost should be similar after optimization.

### increment_heavy
**Measures:** Nested struct field increments and cache locality.

- Tests performance of deeply nested field access in a hot loop
- 512 items, each with 3 levels of nesting (Outer → Middle → Inner)
- 10,000 iterations of triple increment and checksum
- Runtime: ~0.4–0.7 seconds

**Selfhost readiness:** E3a2 (nested structs are inline per element; no unbounded nesting)

### search_heavy
**Measures:** Sorting and binary search operations.

- Generates a list of 10,000 random numbers, sorts them, and performs 1,000 binary searches
- Benchmarks the built-in `sort_by` and `binary_search` functions
- Runtime: ~0.5–1.0 seconds

**Selfhost readiness:** E4 (function values needed for custom comparators; not ready in E3a2)

**Note:** Currently works with stage 0; will be re-evaluated when selfhost supports function values.

## Fairness and Notes

- **LCG:** Both versions use the same linear congruential generator with parameters chosen to keep intermediate values within a signed 64-bit range and avoid overflow: `seed = (seed * 1103515245 + 12345) % 2147483648`
- **Arithmetic:** next-lang checks all arithmetic operations for overflow (part of the safety model); Rust does not in release builds. The LCG choice avoids triggering this difference.
- **Compilation:** 
  - next-lang: `NLC_OPT_LEVEL=3 nlc build <dir> -o <out>` (release level; the default, 1, is the checked development level)
  - Rust: `rustc --edition 2021 -C opt-level=3 -C codegen-units=1 -C lto=fat -C panic=abort -C strip=symbols` (stripped, so binary sizes compare like for like)
  - Both at their highest optimisation, on the same CPU target (baseline x86-64; neither uses `target-cpu=native`, since stage 0 has no way to target a newer level). When the self-hosted compiler can target x86-64-v3, add a second run with both at v3.
- **Output:** Each program prints three values to stdout. Outputs are byte-for-byte compared before timing.

## Running the Benchmarks

Build and verify all pairs compile and produce matching output:
```bash
bash scripts/bench-vs-rust.sh
```

Run with timing (requires Linux, WSL, and the bench lock at `/home/ben/linuxbench/bench.lock`):
```bash
bash scripts/bench-vs-rust.sh --time --out results.md
```

Run a specific pair:
```bash
bash scripts/bench-vs-rust.sh --time tight_list
```

## Implementation Notes

- **No file I/O:** Input is generated inside the program to avoid I/O variance.
- **Deterministic:** All programs use the same seed and have no randomness beyond the seeded LCG.
- **Checksumming:** Results are accumulated into a checksum to prevent dead-code elimination while keeping the output small.
- **Selfhost compilation:** The `--compiler selfhost` flag is reserved for future use when the self-hosted compiler is available (not yet implemented in stage 0).

## Expected Results

**After E3a2** (when the self-hosted compiler matches stage 0 for arrays, lists, and structs):
- tight_list: next-lang within ~10% of Rust
- struct_update: next-lang within ~15% of Rust  
- calls: next-lang within ~10% of Rust (write params have similar cost to &mut)
- increment_heavy: next-lang within ~10% of Rust
- search_heavy: not expected to be ready until function values (E4) are implemented in selfhost

**Stage 0 baseline:** All pairs should compile and produce identical output using the release nlc.
