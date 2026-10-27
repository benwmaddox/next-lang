# E3a1 early-merge report

## Merge result and conflict resolutions

The combined worktree keeps E3a1's `// E3a1 begin/end` sections and main's
E2b/E2c/fix-round changes.

- `core/context.nl`: kept E3a1's single `DataStackContext` layout and context
  ownership. E2c's fallible wrappers operate through that context; the core
  state remains context-owned rather than becoming a second mutable global.
- `selfhost/compiler.nl`: combined E3a1's relocatable locations, region
  planner, context injection and startup with E2b's enum/match paths and
  E2c's `Option`, `Result`, `?`, and `??` paths. Shared emitters now use the
  same offset descriptors and context ABI. Match arms have their own region
  scopes, with a nested block scope for pattern bindings. A return from a
  never-valued arm skips the normal region restore so no instructions are
  emitted after its terminator.
- `selfhost/main.nl`: kept E3a1's core-only startup and test region-threshold
  option alongside main's frontend and shadow-rule behavior. The E3a1 startup
  parameter `count` is `file_count` to satisfy the merged no-shadow rule.
- `tests/e1/classification.tsv`: retained main's E2b/E2c/fix rows and the
  complete `# E3a begin/end` block. Core source embedding was regenerated with
  `scripts/embed-core.sh` (10 files, 53,168 bytes; SHA-256
  `786fce11325ce300511933fbdd7956a554d99f377a98c7242ab0ba062f5a2aed`);
  `selfhost/core_files.nl` was not hand-merged.

The task's requested Git merge could not be recorded in the real repository
metadata: `git merge --no-commit --no-ff e3a` failed while creating
`.git/ORIG_HEAD.lock` because `.git` is mounted read-only. The working tree
contains the resolved merge result, but the real checkout has no `MERGE_HEAD`
or merge index state. No commit, branch change, stash or reset was made.

## Hooks and fallible wrappers

The E2b, E2c and E2b-fix1 reports record no new C-runtime hooks after branch
point `bcb58d8`, so there were no additional hook contracts to capture before
the merge. E3a1's existing C-runtime context-prefix and legacy-hook fixtures
remain in `compiler/tests/selfhost_context_offsets.rs` and
`compiler/tests/selfhost_context_offsets.c`.

`core/stack.nl` now uses E2c's `Result<_, Errno>` wrappers for mapping,
remapping, unmapping and clock reads. Its `stack_write` takes a stack offset
and returns the wrapped `write` result; `stack_load8` and `stack_store8` also
take offsets, so no stale stack pointer crosses a call that may grow the
mapping. `core/result.nl` adds the `remap`, `unmap` and `clock_gettime`
wrappers. The wrapper audit now covers those raw operations while preserving
the injected `nl_core_sys_write` and startup-writer exceptions.

The build-comparison harness uses only the core runtime. The output probe in
`scripts/test-core-output.py` also uses only core, and was updated to retain
the context-initializing entry path and pass `%nl.ctx` to injected probe calls.
Its short-write and EINTR probes pass, along with pipe, `/dev/full`, buffering
and terminal-order checks.

## Reclassifications

Five existing packages moved from `unsupported` to `build`:

- `tests/e2/size_doubling_chain`
- `tests/e2/size_over`
- `tests/e2/size_padding`
- `tests/e2/enum_size_over`
- `tests/e2/enum_size_padding`

The first three now build with E3a1's large-struct regions. The last two are
the cross-slice cases: each needs enum payload support and large-value region
storage, and each exceeded the large-value gate on its isolated compiler
side. The merged table also marks the five existing E3a1 probes and the two
new merge fixtures as build packages. No committed package under `tests/` was
edited or deleted; the new source and expected-output files are under
`tests/e3/merge_regions` and `tests/e3/merge_native_budget`.

The merged classification counts are 90 build, 115 diagnose, 45 rejects and
374 unsupported packages.

## Merged fixtures and budget correction

`tests/e3/merge_regions` uses a 4,160-byte struct, an enum carrying that
struct, `Option<Large>` through `?` and `??`, and a large `NestedSums` record
that contains both `Option<Large>` and the payload enum. It copies, compares
and prints the combined values, and matches the large enum payload with a
binding. Its `?` and `?? return` cases leave blocks with live large values.
The relocation checker compiles it with
`--test-region-threshold=0`; every directed merge fixture must show positive
stack movement, including the large match-arm binding.

`tests/e3/merge_native_budget` pins the native-path budget correction: 30
non-recursive calls each pass and return a 4,800-byte struct, then print `42`.
`add_frame_slot_bytes` counts only aggregates at or below the configured
region threshold. Larger values are region-resident and no longer inflate the
1 MiB native-frame path budget.

The first relocation run also caught a merged match-arm bug: a return emitted
the block's normal region restore after `ret`. The block emitter now emits
that restore only on fallthrough paths; `enum_match_never` and the relocation
matrix pass with the fix.

## Acceptance

- `NLC_FRONTEND=rust cargo test --offline`: passed.
- `NLC_FRONTEND=selfhost cargo test --offline`: passed.
- After expanding `merge_regions` with `NestedSums`, the `language` test target
  passed in both frontend modes.
- `selfhost_interfaces` and `core_wrapper_audit`: passed together.
- `scripts/test-core-output.py`: injected short-write and EINTR probes passed.
- Default comparison: 90 build, 115 diagnose, 45 rejects, 374 unsupported;
  zero mismatches and zero seeded mismatches.
- `NLC_LONG_TESTS=1 scripts/compare-selfhost.sh --build`: the same counts and
  zero mismatches at O1 and O3; eight seeded builds and eight seeded
  diagnostics matched at both levels.
- `scripts/check-selfhost-relocation.py`: 90 build packages; 137 runs and 13
  relocated packages at each of O1 and O3; zero mismatches. Directed A1 and
  merge fixtures all showed positive relocation evidence.
- `cargo fmt --all -- --check`, `scripts/check-core-test-index.py`, and
  `git diff --check`: passed.
