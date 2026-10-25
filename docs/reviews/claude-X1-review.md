# Claude: X1 review (offset-addressed, relocatable data stack spike)

**Verdict:** the gate passed; offsets adopted (DESIGN.md "The job's data stack", PLAN.md offset milestone). The spike's code lives on the branch `spike/offset-stack` (commits 4ccd9df, 8ffbf2b, 9482e5f) and is being ported onto main by O1, not merged (main's emitter changed in T27 to T32). Its report and round specs are copied to main here.

- Round 1: the runtime (256 KB start, doubling with `mremap`, guard page) worked; the compiler side only failed closed, so nothing was measured.
- Round 2: a working slice (large lists and struct lists, read and `write` parameters, list results, Ascii builders), verified with poisoned old mappings; tight loops were about 2x slower because every access called `nl_context_base` out of line, which also stopped LLVM hoisting the list count.
- Round 3: the base cached like the top, plus alias scopes separating list counts from lanes: tight loops, struct-of-arrays loops, calls and builders within noise of pointer mode at -O1 and -O3. My 100x-longer confirmation run: about 675 ms both ways for both loops. A move costs a few microseconds.
