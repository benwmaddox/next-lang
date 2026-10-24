# T08: globals and static allocation (milestone M2, part 3)

Depends on T07. Same rules. Read DESIGN.md "Where data lives", "Who owns state", "Static allocation", "Initialised before use". Reviewed: docs/reviews/sol-T08-T09-r1.md (its decisions are folded in below). Map and set are T09; queue, ring and grid are T10.

## Globals

- `global app: App = App { ... }` at the top level. One worker thread in this task, so a global's home worker is the program; `shared global` is later.
- A struct global may hold collections from T06/T07, including a pool field whose owner is `app.nodes` (`app.nodes.Id`). It's initialised in place; T07's rules hold: no copying, returning or replacing a value that contains a pool, including replacing `app` or an enclosing struct.
- **Hidden access is part of a function's contract:** the checker infers, for every function, which globals (and which field paths of them) it reads and writes, transitively through calls. Those paths join T04's overlap check and T06's view rules: passing `app.items` as `write` to a helper that also reads `app.items` by name is a build error; calling, under a live view of `app.items`, a helper that removes from `app.items` is a build error; touching a disjoint field (`app.score`) is fine. A function that reads a global isn't cacheable (T05) even without `print`.

## Static allocation (DESIGN.md "Static allocation")

- The compiler sizes all globals, counting metadata and alignment. The runtime claims that memory in one piece at startup, before `main`, and refuses to start, with a message naming the reason, when it can't guarantee the memory. On Linux: read `vm.overcommit_memory`; read the effective cgroup v2 memory limit (`memory.max` of the process's group and its ancestors, the smallest that applies) and `memory.swap.max`; require the startup claim plus the configured job headroom (manifest key `job_headroom`, default 256 MB) to fit; then touch every page of the claim (charging it to the group). Outside strict overcommit, that touch-and-check is what makes the guarantee; if anything doesn't fit, refuse.
- `--allow-overcommit` (a runtime flag) waives the guarantee for development: startup prints one line saying the guarantee is off, and `inspect memory` shows it.
- `prefault` keeps its meaning (touch everything at startup, which this policy does anyway on Linux); `locked` (mlock) is optional: unsupported means a build error, not a silent no-op.
- Tests inject the platform readings (overcommit mode, cgroup limits) through an environment variable the runtime reads only in test builds, and check each branch, including refusal before `main`.

## Initialisation

- A global's initialiser is evaluated at compile time when it depends only on constants (T05's evaluator; the starting state is data in the binary). Otherwise it runs once at startup, before `main`: it may read globals that are already complete, in dependency order (the checker orders globals by what their initialisers read, transitively through helpers); a cycle, or an initialiser reading its own global, is a build error naming the cycle. Startup initialisers may not write other globals, read files, or call effectful functions; reading configuration is later.
- Every refinement in an initial value is checked as in T04. **Whole-value invariants (`invariant start <= end`) are not in this task**: they're a separate later task covering locals, globals, defaults, completed values and every later write together.

## `nlc inspect memory`

- `nlc inspect memory <package>` prints each global's byte size (with metadata and alignment), the total startup claim, the job headroom, and whether the guarantee is waived. A warning when globals pass a budget (manifest key `globals_budget`, default 64 MB). Local storage isn't part of the startup claim; per-entry-point stack reporting is M3.

## Acceptance cases

- A compile-time-initialised global (no startup code for it in the IR); a startup-initialised one depending on another (forward reference, ordered correctly, each evaluated once); an indirect initialisation cycle (build error); an initialiser calling `print` (build error).
- Hidden access: the `write app.items` plus by-name read case (build error); removing under a live view through a helper (build error); a disjoint-field access (allowed); a function reading a global used in a `const` (build error: not cacheable).
- Pools in globals: a global pool field with `app.nodes.Id`; resetting it by replacing `app` (build error); a local pool's id stored into a global (build error); a global pool's id held in a local list (allowed).
- Static allocation: each injected policy branch (strict mode fits; default mode with a fitting cgroup; a cgroup too small: refusal before `main`; swap limit; `--allow-overcommit` with its notice); `inspect memory` output including the budget warning.

## Report

docs/tasks/T08-report.md.
