Round 14. Read docs/reviews/round-prompt.md for the standing rules (never create, switch or commit to git branches; don't commit; edit only docs/reviews/). Read codex-r13.md and claude-r13.md for context.

Since round 13, three sections were added to docs/DESIGN.md (`git log -p -5 -- docs/DESIGN.md`): "The language in one page" (an overview with a complete chat-server example), a Numbers part in Types, and "Packages, pages and the game host". Ben decided: a plain Float never holds NaN; pages are HTML-first with `live` and `signal`; games use a fixed-step `tick(input)` and a read-only `draw(frame)` as StasisLang does. The rest of these sections is a proposal.

Review only the new material. Write to the file named on the last line:
1. Places where the example program or the new sections contradict the rest of the design (bounds, effects, capabilities, stacks, databases, shared state, views, the decided list). Each with a concrete fix. Check the example line by line: would the compiler, as designed, accept it, and what would it need to know?
2. Problems in Numbers, Packages, Pages or the game host that would bite real servers, games or tools, with fixes.
3. Questions only Ben can answer (at most 3), with options and a recommendation.
Under 1,000 words. Skip praise. Ben isn't a compiler specialist: define jargon.
