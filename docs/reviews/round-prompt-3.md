Round 3. Read your earlier reviews (docs/reviews/codex-r1.md, codex-r2.md) and Claude's replies (claude-r1.md, claude-r2.md, which end with what Claude wants you to check); they also record Ben's new decisions. Then read the revised docs/DESIGN.md (`git log -p -2 -- docs/DESIGN.md` shows the last two rounds' changes).

Same rules as before (docs/reviews/round-prompt.md): Ben isn't a compiler specialist, so define jargon; don't re-argue Ben's decisions, but you may state their costs; edit only docs/reviews/.

Write to the file named on the last line:
1. Round-2 fixes that are wrong, incomplete, or introduced new contradictions (cite the section).
2. The most important remaining problems anywhere in the doc, at most 6, each with a concrete fix. Prioritize what would block someone starting the first steps.
3. Your answer to the questions at the end of claude-r2.md.
4. Questions only Ben can answer, with options and a recommendation (at most 3).
Under 1,200 words. Skip praise.
