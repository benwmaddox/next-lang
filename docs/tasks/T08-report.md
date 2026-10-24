# T08 implementation report

Implemented program globals, startup initialization, hidden global-access checks, Linux memory backing checks, and memory inspection across parsing, checking, constant evaluation, LLVM emission, the CLI, and the runtime.

## Delivered

- Added `global name: Type = value` declarations, including the `prefault` modifier used by the examples. Compile-time-only initializers are emitted as binary data; initializers that read globals run once before `main`, in dependency order. Cycles, self-reads, startup writes, and direct or transitive printing are build errors.
- Added global reads and writes to function access summaries. Transitive hidden accesses are checked against `write` arguments and live collection views. Disjoint global fields remain usable; resetting a global pool aggregate and storing local pool IDs into globals are rejected. Global pool IDs can be held in local collections.
- Laid globals into one aligned state block and accounted for their size in `inspect memory`. Added `job_headroom` and `globals_budget` manifest settings, defaulting to 256 MiB and 64 MiB. Bare integer values mean MiB; `B`, `MB`, `MiB`, `GB`, and `GiB` suffixes are also accepted.
- Added Linux startup policy checks for strict overcommit commit limits, effective cgroup v2 memory and swap limits across ancestors, host availability, page touching, and post-touch headroom. `--allow-overcommit` skips the guarantee check and prints a notice. Test builds can inject policy readings through `NLC_TEST_MEMORY_POLICY`.
- Added `nlc inspect memory <package> [--allow-overcommit]`, with per-global aligned sizes, total claim, headroom, waiver status, local-storage exclusion, and budget warnings.

## Decisions and boundaries

- All globals are touched at startup on Linux, so `prefault` is accepted but needs no separate runtime action. `locked` is unsupported in T08 and produces a build error rather than being ignored.
- The Linux runtime refuses startup if it cannot read the policy needed for the selected guarantee. Other operating systems need their own backing policies and remain outside T08.
- Local storage and per-entry-point stack reporting remain outside the global startup claim; stack reporting is deferred to M3.

## Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `cargo test` — passed: 6 unit tests, 1 collection IR test, 3 globals tests, 3 language integration tests (including all run and test fixtures), 1 pool IR test, and doc tests.
- No external crates were added. No commits or branch changes were made.
