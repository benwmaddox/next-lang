Round 16. Read docs/reviews/round-prompt.md for the standing rules (never create, switch or commit to git branches; don't commit; edit only docs/reviews/). Read codex-r15.md and claude-r15.md for context.

New since round 15: "Targets and CPU features" in the Performance model of docs/DESIGN.md (`git log -p -1 -- docs/DESIGN.md`), added after Ben asked whether ahead-of-time LLVM builds are as efficient as they can get, given that some optimizations depend on the architecture. Review it:
1. Factual errors about LLVM, x86-64 levels, ARM, multiversioning, PGO or BOLT, with corrections (cite sources where useful).
2. Gaps that would matter for servers, games or tools on Windows, Linux, macOS and 64-bit Android (for example Apple's arm64 baseline, Android's ABI, what `native` means for dev builds shared between machines), with fixes.
3. Whether the float claim holds: exact code identical across multiversioned levels, given LLVM's defaults (FP contraction, vectorized reductions, libm calls like sin and exp).
4. Questions only Ben can answer (at most 2), or "None".
Under 800 words. Skip praise. Ben isn't a compiler specialist: define jargon. Write to the file named on the last line.
