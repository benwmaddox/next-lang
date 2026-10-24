Round 20. Read docs/reviews/round-prompt.md for the standing rules (never create, switch or commit to git branches; don't commit; edit only docs/reviews/).

New: docs/EXAMPLES.md, four realistic programs written to docs/DESIGN.md's rules for Ben to review (a game, a command-line tool, a JSON API with a rate limit, CRC-32). Each lists the open points writing it raised. Review them as a careful reader who knows DESIGN.md:
1. Lines that break a decided rule in DESIGN.md (bounds, no closures, no implicit conversions, `long` indexes, `?.`/`??` on Option only, views and removal, effects, parallel bodies with no effects, transactions, failed ticks), each with the corrected line.
2. Bugs in the programs themselves (logic, off-by-one, a wrong expected value in a test; for example check the score in the Rocks test and the CRC check value).
3. For each example's "open points", which are real design gaps and which have an answer already in DESIGN.md (cite it), and anything missing from those lists.
4. Questions only Ben can answer (at most 3), with options and a recommendation.
Under 1,100 words. Skip praise. Ben isn't a compiler specialist: define jargon. Write to the file named on the last line.
