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

**Selfhost readiness:** E3a2 (arrays and lists ready; no Text, Option, or function values needed)

### struct_update
**Measures:** Update of struct fields across many iterations.

- Tests array-of-structs layout and field update performance
- 4,096 particles updated over 1,000 iterations
- Each particle has 4 long fields (x, y, vx, vy)

**Selfhost readiness:** E3a2 (structs and list elements ready)

### calls
**Measures:** Function call overhead with `write` parameters and small function bodies.

- Tests parameter-passing cost vs. direct field access
- Calls `bump_field` (takes a `write long`) and `process_value` frequently
- 1,024 items × 100 rounds with 4 calls per item

**Selfhost readiness:** E3a2 (write parameters are part of E3a2)

**Fairness note:** next-lang uses `write` parameters (a pointer to a field) while Rust uses `&mut`; both are compile-time verified as non-aliasing. The cost should be similar after optimization.

### increment_heavy
**Measures:** Nested struct field increments and cache locality.

- Tests performance of deeply nested field access in a hot loop
- 512 items, each with 3 levels of nesting (Outer → Middle → Inner)
- 10,000 iterations of triple increment and checksum

**Selfhost readiness:** E3a2 (nested structs are inline per element; no unbounded nesting)

### search_heavy
**Measures:** Sorting and binary search operations.

- Generates a list of 10,000 random numbers, sorts them, and performs 1,000 binary searches
- Benchmarks the built-in `sort_by` and `binary_search` functions

**Selfhost readiness:** E4 (function values needed for custom comparators; not ready in E3a2)

**Note:** Currently works with stage 0; will be re-evaluated when selfhost supports function values.

### request_scratch
**Measures:** Short-lived scratch lists and text responses simulating request handling.

- Simulates 100,000 requests
- Each request builds a variable-size list (1-256 items via LCG), computes a checksum, formats a small text response, and discards everything
- Key allocation pattern: many fresh lists and strings per iteration; next-lang resets at scope exit, Rust allocates and frees each

**Selfhost readiness:** E3a2 (lists, text concatenation, functions returning Ascii)

### text_format
**Measures:** Formatting many records into text lines and accumulating them.

- Formats 100,000 records (id, value, name) into formatted lines (e.g., "12345:999=42")
- Appends each line to an output buffer; next-lang uses `+=` on Ascii, Rust uses `push_str`
- Key pattern: repeated small-string appends into a growing buffer

**Selfhost readiness:** E3c/E3d1 (text builders, `+=` on Ascii, functions returning text)

### nested_lists
**Measures:** Nested collection structures (list of structs with list fields).

- 10,000 iterations, each building 1-200 groups, each with 1-100 items
- Iterates nested structure and checksums values
- Key pattern: Rust's `Vec<Vec<T>>` (separate allocations per group) vs next-lang's bounded lists (inline in struct)

**Selfhost readiness:** E3a2 (struct fields with list type, nested list iteration)

### tokenize
**Measures:** Creating and storing many short texts from a word table via LCG selection.

- 1,000 batches, each with 2,048 tokens picked from a 10-word table using LCG
- Stores tokens in a list and iterates to checksum their lengths
- Key pattern: many short string allocations and storage in a collection

**Selfhost readiness:** E3a2 (list of structs with Ascii fields, word-table selection via match)

## Reuse Variants (`main_reuse.rs`)

For each pair with a `main_reuse.rs` file, a hand-tuned Rust version reuses its buffers (Vec/String instances cleared between iterations with `clear()` and `with_capacity`). This shows how much of any next-lang/Rust gap is due to allocator overhead vs. language design:

- **request_scratch:** reuses request list and response buffer per request
- **text_format:** reuses output buffer and line buffer across records
- **nested_lists:** reuses group list and item list per iteration
- **tokenize:** reuses token list and word buffer per batch

The reuse variants use only standard Rust (`std::fmt::Write` for efficient formatting); no unsafe code or external crates.

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
bash scripts/bench-vs-rust.sh --time              # stage 0 and Rust (and Rust reuse where present)
bash scripts/bench-vs-rust.sh --selfhost --time   # adds the self-hosted compiler, built from HEAD; '-' where it can't build a pair yet
bash scripts/bench-vs-rust.sh --selfhost calls    # build and check outputs only, for named pairs
```

Run a specific pair:
```bash
bash scripts/bench-vs-rust.sh --time tight_list
```

## Implementation Notes

- **No file I/O:** Input is generated inside the program to avoid I/O variance.
- **Deterministic:** All programs use the same seed and have no randomness beyond the seeded LCG.
- **Checksumming:** Results are accumulated into a checksum to prevent dead-code elimination while keeping the output small.
- **Selfhost compilation:** not wired in yet; add a self-hosted build path when checkpoint pairs are ready. Workloads are sized for roughly 0.5-1.5 s on the next-lang side at stage 0.

## Expected Results

**Stage 0 baseline:** All pairs (existing and allocation-focused) compile and produce identical output using the release nlc.

**After E3a2** (when the self-hosted compiler matches stage 0 for arrays, lists, and structs):
- tight_list, struct_update, calls, increment_heavy: ready; next-lang within ~10-15% of Rust (write params have similar cost to &mut)
- request_scratch, text_format, tokenize: ready; expect next-lang to be faster on Rust idiomatic (Vec/String alloc per iteration), and closer to reuse Rust when allocator pressure is high
- nested_lists: ready for E3a2 but layout still uses inline lists per element (not flattened); expect similar or slightly slower than Vec<Vec<T>>
- search_heavy: not ready until function values (E4) are implemented in selfhost

**After E3c/E3d1** (text builders):
- text_format reuse variant: next-lang's `+=` on Ascii should match reuse Rust's `push_str` efficiency

**After E3e** (if nested list layout is flattened):
- nested_lists: expect next-lang faster than Rust once the nested arrays are flattened into a single array per field (better locality)

## Pairs the self-hosted compiler builds today

- **collatz**: scalar loops and calls (longest Collatz chain below 3,000,000).
- **struct_math**: small structs passed to and returned from functions in a 30M-step loop.

These measure the self-hosted compiler's code against stage 0's and Rust's before collections arrive.
