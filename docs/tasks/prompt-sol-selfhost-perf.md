You are Sol, the peer reviewer and investigator for the next-lang project, working in the worktree /mnt/d/code/next-lang-perf (branch perf-selfhost-lists, at main 86ff918). Claude is the manager. Another run (Luna, E3b) is working in the main checkout /mnt/d/code/next-lang: never touch it, and never touch /mnt/d/code/next-lang-go2nl.

**Question.** Benchmark checkpoint 1 (docs/bench/2026-10-27-checkpoint1.md) found that programs built by the self-hosted compiler are slower than the same programs built by stage 0 (the frozen Rust `nlc`) on the pairs E3a2 made buildable:

| Pair (bench/vs-rust/) | stage 0 | self-hosted |
| --- | ---: | ---: |
| increment_heavy | 0.73 s | 1.62 s (2.2x) |
| struct_update | 0.75 s | 1.74 s (2.3x) |
| tight_list | 0.49 s | 0.61 s (1.25x) |
| calls | 0.83 s | 0.65 s (faster) |

Find out why, with evidence, and say what to change. Both sides use the same LLVM at `NLC_OPT_LEVEL=3`; the self-hosted side links its core library (no libc) and uses the offset data stack (E3a1) and E3a2's location descriptors and `write` parameters.

**Method.** Read scripts/bench-vs-rust.sh to see how each side is built. For `increment_heavy` and `struct_update` (then `tight_list`), produce both compilers' IR, before and after LLVM optimisation (`opt -O3` / `llc`, or `-print-after-all` where useful), and compare the hot loop: loads and stores per iteration, calls left in the loop, data-stack base reloads, offset/descriptor arithmetic, bounds and overflow checks, `write` store-back, aliasing information (`noalias`, TBAA, `nonnull`/`dereferenceable`), vectorisation (`-Rpass=loop-vectorize -Rpass-missed=loop-vectorize`), and what blocks LICM/GVN. Confirm each suspected cause by a minimal hand edit to the self-hosted IR (or a small experimental change to selfhost/*.nl in this worktree), re-linking with `nlc link-ir` and timing it, so the report gives measured effect per cause, not guesses. Time with the same pinning as the benchmark script (`taskset -c 8`, best of 5) under `flock -x /home/ben/linuxbench/bench.lock`. Also check `calls`: what makes it faster than stage 0, so a fix keeps that.

**Constraints.** Stage 0 (compiler/src) is untouched. Experimental edits to selfhost/ or core/ in this worktree are fine, but list each in the report with its diff and measured effect, and leave the worktree as you found it at the end except for the report (save experimental patches under docs/reviews/sol-selfhost-perf/ as .patch files). Never edit or delete committed tests. Build state: CARGO_TARGET_DIR=$HOME/.cache/next-lang/target-perf; large builds under `ulimit -v 8000000` and `timeout`. No network, no external crates. Never run git commit, never create or switch branches, never stash or reset. Delete scratch files you create.

**Report.** Write docs/reviews/sol-selfhost-perf-r1.md: for each pair, the hot-loop IR difference (short excerpts), each cause with its measured share of the gap, recommended changes in order of payoff with where in selfhost/*.nl they belong and whether they fit E3b-E3g or should wait for P1, any correctness risk a change would carry (relocation safety of caching the data-stack base, aliasing of `write` arguments), and anything in the E3 spec (docs/tasks/E3-selfhost-collections-text.md) that forces the slow form.
