Round 18. Read docs/reviews/round-prompt.md for the standing rules (never create, switch or commit to git branches; don't commit; edit only docs/reviews/). Read codex-r17.md and claude-r17.md for context.

Since round 17, Ben decided (`git log -p -4 -- docs/DESIGN.md`):
- x86-64 builds default to `x86-64-v2`; v3 is opt-in (replacing a v3 default).
- Functions are values (named, top-level functions only); no closures; context is passed explicitly. New part "Functions as values, no closures" in Types.
- Numbers use C#'s names and widths, lowercase: sbyte/short/int (32-bit)/long, byte/ushort/uint/ulong, float/double, bool; `double nan` for IEEE NaN; C# literal suffixes. Claude also proposed C#-style implicit widening and checked narrowing casts `(byte)x` with `unchecked(...)` for truncation (not yet confirmed by Ben).

Write to the file named on the last line:
1. Contradictions these introduced anywhere in docs/DESIGN.md (old names, the example program, `?.`/`??` uses, stack contracts of function values, effects, refinements like `int 0..1000`, the worked example, the Flow-era "no implicit conversions" rule), each with an exact fix.
2. Problems with the no-closures rule for real servers, games and tools (sorting, callbacks, event handlers, parallel loop bodies, page pieces), with the cleanest closure-free pattern for each.
3. Problems with 32-bit `int` as the default (overflow in sums, indexes over 2^31, timestamps, `len()` types), with fixes.
4. Questions only Ben can answer (at most 3), with options and a recommendation.
Under 900 words. Skip praise. Ben isn't a compiler specialist: define jargon.
