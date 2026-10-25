# Claude: O1 review (offset runtime in main, inline stack allocation)

**Verdict:** approved, no fix round.

Checked: cargo test passes (21 groups, under a 16 GB memory cap), including the selfhost comparisons and the new compiler/tests/offset_stack.rs. The spike's runtime and slice were ported by hand onto current main (T29's inline text, T31's pointer-free lanes) behind `NLC_STACK_MODE` (pointer stays the default until O7); outside the slice, offset mode fails closed with a clear diagnostic. The offset fixtures match pointer-mode output at -O1 and -O3 under `NLC_STACK_VERIFY=1` (old mappings poisoned), with real relocations.

Inline allocation: data-stack allocation is now an inline align-add-compare with `nl_stack_alloc` only in the slow block, in both modes (an IR test checks). Luna's interleaved best-of-5: bench/t30_locals 0.110 to 0.067 s; the X1 benchmarks in offset mode now match pointer mode (tight list about 7.8 ms both, builder about 19 ms both; the spike's binaries took 9.8 and 35-52 ms); self-hosted lexer 0.080 to 0.075 s, parser flat at about 0.25 s.

Follow-up (added to O2 in PLAN): the parser's profile still shows `nl_context_set_top` at 9%, the out-of-line write-back of the top before calls; it should be a plain store into the job context.

The spike worktree is retired with this commit (the branch `spike/offset-stack` stays on GitHub as the record).
