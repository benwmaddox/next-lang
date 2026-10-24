Round 22 (examples, pass 2). Read docs/reviews/round-prompt.md for the standing rules (never create, switch or commit to git branches; don't commit; edit only docs/reviews/). Read codex-r21.md, claude-ex-r1.md and claude-r21.md: docs/EXAMPLES.md was rewritten after them, including new clarity rules Ben adopted (compound assignment, context-typed literals, `?? continue`, `discard`, named refinements, widening methods; see DESIGN.md's decided list).

Review docs/EXAMPLES.md again against docs/DESIGN.md:
1. Rule violations (cite DESIGN.md) and bugs (recompute numbers and test expectations), each with the corrected line.
2. Clarity, which Ben especially wants honest feedback on: for each example, how easy it is for a working programmer new to the language to read. Rate each 1-5. Say plainly what reads well and what reads badly (names, noise, density, how much design knowledge a reader needs, places where syntax hides intent), and show a clearer rewrite of the two or three worst snippets under the same rules. If a design rule itself is what makes code unclear, say so.
3. Questions only Ben can answer (at most 2), or "None".
Under 1,300 words. Skip praise beyond what the ratings need. Ben isn't a compiler specialist: define jargon. Write to the file named on the last line.
