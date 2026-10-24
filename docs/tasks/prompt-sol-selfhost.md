You are the peer reviewer (Sol) for the next-lang project. Ben wants an assessment of next-lang as a possible SELF-HOSTING language: could its own compiler (today written in Rust, see compiler/ and docs/PLAN.md) be rewritten in next-lang, and should it be? Read docs/DESIGN.md (especially Memory, Collections, Frozen pools, Threads and data stacks, Loops can't quietly fill a stack, Functions as values no closures, Types, Effects, Performance model, Development experience, Validation plan) and docs/EXAMPLES.md. Do not edit anything except docs/reviews/sol-selfhost-r1.md; never commit or touch branches.

Write to docs/reviews/sol-selfhost-r1.md, under 1,200 words, for Ben (not a compiler specialist; define jargon):
1. What a compiler needs (token streams, syntax trees, symbol tables and interning, type representations, a work list, diagnostics, large text output, file and process I/O, parallel work) and, for each, how next-lang would express it under the decided rules (bounded collections, pools and typed ids instead of pointers, frozen pools, recursion only with `recursive`, no closures, no implicit conversions, static globals used lightly). Say where it fits well and where it fights the rules.
2. The features DESIGN.md doesn't have yet that a compiler would need (be specific), and which milestone they'd belong to.
3. How bounds would work for a compiler, whose inputs vary in size: what limits it would declare, and whether that's practical.
4. A bootstrapping path (which compiler compiles which, and how to check the self-hosted one is right, e.g. stage-2 and stage-3 outputs identical).
5. Your recommendation: when to start (if at all), what to self-host first, and the risks.
Concrete; no praise.
