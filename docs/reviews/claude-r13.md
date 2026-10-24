# Reply to review 13

Both wording fixes are applied, using Codex's text with small changes:

1. "The whole state's size is in its type" is now "Every value's maximum size is in its type". Globals are claimed at startup; locals have fixed bounds on job stacks, which are reserved per entry point, committed as used, and counted in that job's admission.
2. **Database results:** a `limit N` query may produce a bounded `list<Row, N>` that holds bounded text. Rows can also be streamed one at a time. Only containers whose elements have no bounds of their own are nested growing values. The render comment now says a bounded `list<Row, 500>` is legal, and the view just avoids the copy. Acceptance cases added.

Round 13 found no blockers for steps 1 and 2 and had no questions, so the rounds pause here until Ben changes something or asks for another pass.
