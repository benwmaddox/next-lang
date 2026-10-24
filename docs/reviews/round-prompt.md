You are reviewing docs/DESIGN.md, a design for a new general-purpose programming language (working name next-lang). Another agent (Claude) wrote it, and you two will go back and forth refining it with the owner, Ben. Ben is not a compiler specialist: define jargon in plain words.

Context: it draws on six languages Ben built in the past four weeks (Burin at D:\code\burin, a Rust web language with an LLVM helper compiler; crudspec; AgentLang; Stasis; Hobthrush; and the Goose memory model from github.com/aardappel/goose). You may read D:\code\burin for evidence, but do not edit anything outside docs/reviews/.

Decisions Ben has already made (don't re-argue them; you may point out their costs):
- one compiler target, LLVM; no JIT, no interpreter, no live swap; restart after an edit; 3 s edit-to-running is fine
- no garbage collector; data in tables with typed ids; temporaries on compiler-assigned data stacks, one growing value per stack (Goose-style)
- efficiency of threads and stacks matters a lot
- it is a separate project from Burin and must not depend on it
- design doc only for now, no prototype code

Write your review as markdown to the file named in the last line of this prompt. Structure:
1. The 5-10 most important problems: contradictions, things that won't work as written, missing pieces that block implementation, claims without evidence. For each: where (section), why it matters, and a concrete proposed fix (wording or design).
2. Smaller issues (one line each).
3. Questions only Ben can answer (decisions of taste or priority), each with options and your recommendation.
Be specific and concrete; skip praise. Keep it under 1,500 words.

Also answer this question from Ben in its own section ("Shared immutable data across threads"): many compilers share large immutable data between threads, e.g. the TypeScript compiler's Go rewrite (TypeScript 7, "Corsa"), which parses files in parallel and lets several type-checker threads read the same immutable syntax trees. Can this design do that reasonably, given per-thread stacks freed per scope, tables with one writer, and snapshots? If not as written, what is the smallest addition that would make it work efficiently, and what would still be off the table? Be concrete about lifetimes, memory layout and costs.
Decisions added on 2026-10-24: recursion opt-in via `recursive`; Text (UTF-8) and Bytes are separate; generics copied per type; servers, games and tools weigh equally.
