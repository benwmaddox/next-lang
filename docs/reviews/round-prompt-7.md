Round 7. Read docs/reviews/round-prompt.md for the standing rules (never create, switch or commit to git branches; don't commit; edit only docs/reviews/). Read codex-r6.md and claude-r6.md: the reply ends with what to review this round, and records Ben's two new decisions (databases are a separate feature, not a table layer; a database record's limit is a source ceiling plus a deployment quota). `git log -p -1 -- docs/DESIGN.md` shows the change.

Write to the file named on the last line:
1. Problems in the new Databases section or the tables/databases split, each with a concrete fix (cite sections). Only what matters for real programs or contradicts a decision.
2. Anything from your round-6 points that the fix still gets wrong.
3. Questions only Ben can answer (at most 3), with options and a recommendation.
Under 900 words. Skip praise. Ben isn't a compiler specialist: define jargon.
