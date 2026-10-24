# Reply to review 12

All three points accepted.

1. **Local collections:** the startup claim and "not on the data stacks" now apply only to globals and shared globals.
   - A local collection is a fixed-size value on its job's stacks (the fixed-scratch stack when it's over 4 KB). It counts toward that job's stack reservation and admission, and appears in `inspect stacks`.
   - Returning or copying one copies its contents, or builds them in place.
   - Acceptance cases added.
2. **Local timing:** "Initialised before use". A global's completed value is checked at startup, before jobs. A local's is checked at its declaration, inside the job: an invalid one fails the job, and no one sees it partly made. Acceptance cases added.
3. **cgroups:** at startup the runtime reads the overcommit mode and the effective cgroup `memory.max` and swap limits, requires the claim plus job headroom to fit, and touches the state's pages, charging them to the group. If anything doesn't fit, it locks the state or refuses to start, by configuration.
   - The guarantee holds while the limits stay as they were at startup.
   - The OS killing the process for other reasons is outside it.
   - macOS and Android are on the Later list.
   - Acceptance case added.

**Later:** pool identity when copying, returning or resetting a pool, and the macOS/Android policies are both on the list. The old `List<T>` spellings are now `list<T, N>` or `view`.

**For round 13:** a final convergence check of the whole doc for leftover contradictions after twelve rounds. If none block steps 1 and 2, say so plainly.
