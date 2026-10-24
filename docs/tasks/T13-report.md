# T13 report: data stack and destination emission

## Implemented

- Added one 64 MiB data-stack reservation per program run and per test child. The Linux runtime reserves writable, demand-paged space with an inaccessible guard page and reports reservation failures at startup. `NLC_TEST_DATA_STACK_BYTES` changes the reservation only in `NLC_TEST_BUILD` binaries.
- Added hidden context and current-top arguments to generated functions, direct and indirect calls, optional calls, test wrappers, and global initializers. Generated entry points create and destroy their stack context.
- Values larger than 4,096 bytes use aligned data-stack regions. Large locals allocate at their declaration scope; large fixed scratch is allocated in the function preamble. Large parameters pass by pointer, and large results are built in caller-owned destinations.
- Added destination-directed emission for large copies, empty collections and pools, constructors, direct, indirect, and optional calls, branches, matches, `try`, coalescing, and filled arrays. Scope exits, loop iteration exits, `break`, `continue`, `return`, propagated errors, and failed expectations restore the saved top.
- Function types retain the maximum data-stack requirement of compatible function values. The contract analyzer follows direct and resolved indirect calls, accounts for large local and fixed scratch storage, and `nlc inspect contracts <package>` reports function byte requirements, parameter modes and placement, and result placement.
- LLVM `noalias` is emitted for a `write` parameter only when the checker proves its explicit arguments do not overlap and the function has no hidden large-result destination. Read pointers and unproven aliases remain unannotated.
- Updated the old oversized-value fixtures to expect success now that values above the former 64 KiB checker limit are legal.

## Verification

Ran from WSL with the target directory outside the repository:

```text
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt --all -- --check
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test
```

All commands passed. The full suite includes the 1 MiB local, nested large return/copy, sorting of 100,000 elements, loop-scope cleanup, IR ABI/noalias checks, indirect function-type contract, and bounded exhaustion tests at normal and reduced reservation sizes.

## `inspect contracts` sample

Ran `nlc inspect contracts tests/run/t13_stack_contracts`:

```text
function make_nested
  byte requirement: 14424
  parameters: none
  result placement: caller destination (9616 bytes)
function identity
  byte requirement: 0
  parameter: values: read pointer (65544 bytes)
  result placement: caller destination (65544 bytes)
function write_nested
  byte requirement: 0
  parameter: value: write pointer (4808 bytes)
  result placement: none
function possibly_alias
  byte requirement: 0
  parameter: left: read pointer (9616 bytes)
  parameter: right: read pointer (9616 bytes)
  result placement: value
function sort_large
  byte requirement: 1600016
  parameters: none
  result placement: none
function consume
  byte requirement: 0
  parameter: value: read value (8 bytes)
  result placement: none
function indirect_large_target
  byte requirement: 8192
  parameters: none
  result placement: value
function call_indirect
  byte requirement: 8192
  parameter: callback: read value (8 bytes; function targets need up to 8192 data-stack bytes)
  result placement: value
function copy_large
  byte requirement: 0
  parameter: value: read pointer (8192 bytes)
  result placement: caller destination (8192 bytes)
function maybe_copy
  byte requirement: 8196
  parameter: value: read pointer (8196 bytes)
  result placement: caller destination (8196 bytes)
function maybe_try_copy
  byte requirement: 8196
  parameter: value: read pointer (8196 bytes)
  result placement: caller destination (8196 bytes)
function no_stack_loop
  byte requirement: 0
  parameters: none
  result placement: none
function outer_survives_loop
  byte requirement: 16392
  parameters: none
  result placement: none
function main
  byte requirement: 3011968
  parameters: none
  result placement: none
```

## Scope note

T13 now carries data-stack maxima through function types and indirect-call analysis. These byte estimates are conservative: local and scratch regions in mutually exclusive branches can be summed. Native-stack bounds are not calculated here: DESIGN assigns those bounds to optimized target frame sizes and the later T17 sizing work. Treating an unoptimized estimate as a bound would not be reliable. Growing values, builders, append mode, `Text`, and size classes remain out of scope for T13.

## Fix round 1

- Fixed pointer arguments for whole structure-of-arrays elements. The emitter now gathers each struct field from its collection lane into a temporary, passes that address, and scatters fields back after a `write` call. Large call temporaries use data-stack regions and are released after copyback; the caller's stack top is passed after argument preparation. Copyback runs after the callee returns even when it returned early through `?`.
- The gather/scatter path handles array, list, pool, map, queue, ring, and grid storage, including loop element views. Map struct values are stored in one array-of-structs field, so map lane lookup now selects that field before selecting a struct member.
- Other address consumers gather into storage when they need one address for a SoA element. Destination emission copies element fields directly into its destination, covering large returns and copies into struct fields or collections. Large match scrutinees, equality, printing, and optional calls were exercised; no remaining emitter path contains the former panic.
- Large grid `fill` emission now treats grids as fixed collections, allowing large struct elements to be initialized through the destination path.
- Added `tests/run/t13_soa_gather` for the reported list, write, loop, `pick`, and array cases; pool and map loop values; a write loop view and a callee failure through `?`; 4,096-byte and 4,104-byte struct elements; returning and storing an element; equality and printing; optional calls and matching; queue, ring, and grid views; and a nested large collection element. The fixture prints the expected values. A stack-contract regression assertion checks that the 8,004-byte gather is counted in its caller.

Ran the requested checks with `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target`:

```text
cargo fmt -- --check
cargo build
cargo test
```

All passed. `nlc inspect contracts tests/run/t13_soa_gather` reports a 603,402-byte requirement for `main`, including conservative room for its gathered large struct arguments.
