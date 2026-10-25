# T28: capped data-stack reservations (Linux)

**On hold (2026-10-25):** waiting for X1 (docs/tasks/X1-offset-stack-spike.md), which measures a relocatable, offset-addressed data stack; if X1 is adopted, this cap is replaced.

Same rules (docs/PLAN.md). Depends on T27. Implements the first part of DESIGN.md "The job's data stack" as decided 2026-10-25 ("Reserve generously, commit only what's used", Reservation and Past the reservation bullets), following docs/reviews/sol-stack-policy-r1.md point 10. Pooling, demand histories, trimming, `clear_stacks_between_jobs`, admission and suspension wait for the job scheduler; Windows commit and `strict_stack` are separate later tasks.

- **Cap:** each entry point reserves the smaller of its computed worst case (T17, after T27's fixes) and its cap: 64 GiB by default, set per entry point in `package.toml` (`[stack_reserve]` with `main = "8 GiB"` and test names, with binary units). An unknown or overflowing bound reserves the cap (and arithmetic overflow in the analysis is diagnosed, not wrapped). Keep the helper margin, page rounding and the inaccessible guard page.
- **Warnings:** a build warning when an entry point's computed worst case passes its cap (naming it, the cap, the bound and the critical path from T27), and a separate one for each single region larger than the cap (it can never be placed). `inspect stacks` shows the uncapped bound, the cap and the reservation; `stack_peak` keeps using uncapped bounds.
- **Exhaustion:** passing the reservation fails the job with `data stack range exhausted` through `nl_fail` (exit 1; 70 in a test child), replacing today's wording; never a crash.
- **Unsupported options:** `strict_stack`, `clear_stacks_between_jobs` and trimming settings in a manifest are build errors saying they aren't implemented yet (not silently accepted).
- **Strict overcommit:** under `vm.overcommit_memory = 2`, cap the reservation at what the commit limit allows or refuse to start with a clear message (DESIGN's Commit bullet); test by reading a fake policy through the existing test hooks if a real mode switch isn't possible in WSL.
- Tests: cap at N and N+1 pages (a program whose real use fits the cap passes; one whose use passes it fails with the new message); a region larger than the cap (build warning, and the runtime failure if reached); an unknown-bound entry point reserving the cap; `ulimit -v` below the cap refused at startup; the self-hosted parser running under the default cap and under a cap just above its measured peak.
- Report: docs/tasks/T28-report.md.
