# E1c: the next-lang core library replaces the C runtime for the E1 subset

Depends on E1. The design is docs/design/core-library.md (revised for docs/reviews/sol-core-library-r1.md); DESIGN.md "The standard library needs no C library" is the rule. This task implements the parts the E1 subset needs, exactly as the note specifies; where the note and this file differ, the note wins.

## Build

- **Core library sources** in top-level `core/` (with the platform subdirectory the note defines), written in the note's closed core dialect, embedded into the self-hosted compiler as the generated, checked-in `selfhost/core_files.nl` with the staleness test and the IR header hash.
- **`sys` operations** for E1c's list (write, exit_group, mmap, mprotect, ioctl TCGETS, statx, rt_sigaction, openat, close), lowered by the self-hosted code generator through the note's inline-asm helpers, usable only from the embedded core (sealed as the note says: internal symbols, no user name resolution, no function values, privileged types rejected through aliases and inference).
- **Entry:** the compiler-emitted `_start` (module-level assembly calling `nl_core_start(sp)`), auxv and environment handled as the note says; the data stack mapped as the C runtime maps it; no own native stack yet.
- **Hooks:** the core library defines the functions the E1 IR already calls (`nl_print_*`, `nl_fail`, `nl_context_*`, test hooks), same names and signatures; behaviour exactly per the note's checklist (every flush point, failure messages and kinds, exit statuses 0/1/70, the test-child protocol with `NLC_TEST_INDEX` parsed as `strtol` does, `NLC_STACK_PREALLOC`).
- **Memory functions** `memcpy`, `memmove`, `memset`, `memcmp`, `bcmp` in core with the note's single policy (the whole helper closure marked, no memory intrinsics inside it, no `alwaysinline` across it), and the transitive post-link check for self-calls.
- **Link:** `nlc link-ir`/`test-ir` read the IR header's `nlc.runtime core` and link freestanding (`clang -O1|-O3 -nostdlib -static -Wl,-e,_start`); `nlc.runtime c` keeps today's path, so the harness can run a third leg.

## Acceptance

- `scripts/compare-selfhost.sh --build` passes with the core library (all 34 build and 39 diagnose packages identical to Rust nlc at -O1 and -O3, the 409 unsupported still rejected), and with the third leg (`--runtime=c`) to separate compiler bugs from core-library bugs.
- `nm -u` and `readelf` checks: no undefined symbols, no `INTERP`, no `NEEDED`; the memory functions never call themselves (transitive check).
- The note's tests: forced relocation during system-call argument evaluation, flush points (including a pipe and a terminal), partial-write fault injection for output, `/dev/full` for flush failure, test-mode exit codes.
- Measure: the E1 benchmark build and run both ways (C runtime against core library), binary sizes, startup time of a trivial program, and memcpy/memset speed against glibc through the note's shim (under the WSL bench lock).
- Run large builds under `ulimit -v 8000000` and `timeout`. Both full suites (NLC_FRONTEND=rust and selfhost) keep passing.
- Report: docs/tasks/E1c-report.md, including anything in the note that didn't work as designed (that goes back for review; no fallback to libc).
