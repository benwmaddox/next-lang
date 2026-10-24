Round 17. Read docs/reviews/round-prompt.md for the standing rules (never create, switch or commit to git branches; don't commit; edit only docs/reviews/). Read codex-r16.md and claude-r16.md.

Ben decided: x86-64 builds assume `x86-64-v3` by default, with a build flag or manifest setting for older levels; `native` is opt-in for local runs. See "Targets and CPU features" in docs/DESIGN.md (`git log -p -3 -- docs/DESIGN.md`).

Check only this change. Write to the file named on the last line:
1. Factual errors in the "what v3 buys" text or the hardware-support claims, with corrections.
2. Contradictions with the rest of the targets section, Numbers, replay, or multiversioning, with exact fixes.
3. Anything a v3 default breaks in practice (CI machines, emulators such as the Android x86-64 emulator, virtual machines, Windows on ARM running x86-64 programs, older developer laptops), and how the refusal message and flag should handle it.
4. Questions only Ben can answer (at most 2), or "None".
Under 600 words. Skip praise. Ben isn't a compiler specialist: define jargon.
