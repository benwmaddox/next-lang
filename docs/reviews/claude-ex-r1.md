# Code Review: EXAMPLES.md

**Reviewer:** Claude (independent review)  
**Date:** 2026-10-24

## 1. Rule Violations

None found. All examples follow DESIGN.md rules:
- Collections are bounded (Types, Collections)
- No closures; scoped blocks read locals directly (Functions as values)
- Numeric conversions explicit, no widening implicit; narrowing checked (Types, Numbers)
- Indexes are `long` (Types, Sizes indexes and time)
- `?.` and `??` on Option only; Result uses `match` or `?` (Types, ?. and ??)
- Parameter modes (`write Game`, `grow Text`) written (How the compiler assigns stacks)
- Views bounded to loop scope; no live views across suspending calls (Memory, Views)
- Ranges use plain/wrap/clamp (Types, Wrapping and clamping)
- Float operations don't produce NaN (Types, Floats)
- Game tick changes state, draw reads only (Rocks example, line 166: draw takes only Frame)
- Transactions on writer; `?` inside aborts (Example 3, line 366–386)

## 2. Bugs

**Example 1 (Rocks), line 120: point-scoring arithmetic.**
```
g.score = g.score + (long)points(r.size)
```
`points(r.size)` returns `int` for sizes 1–3: 400, 200, 133 respectively. Test at line 188 expects score 133 for one size-3 rock. That's correct: 400 / 3 = 133 integer division. No off-by-one.

**Example 3 (logsum), line 309: division by zero handled.**
```
if whole == 0L { return "0%" }
str_fixed((double)part * 100.0 / (double)whole, 1) + "%"
```
Guard at line 308 prevents division by zero. No bug.

**Example 4 (CRC-32), line 512: known-answer test.**
`crc32("123456789".bytes()) == 0xCBF43926u` is the standard CRC-32 test vector. Correct.

## 3. Realism

**Example 1, line 175: score_line bound mismatch.**
```
fn score_line(score: long, lives: int 0..3) -> Ascii max 40
```
Function claims `max 40` but accepts unbounded `long`. A 19-digit long (9223372036854775807) plus "Score ", "  Lives ", and "3" totals 34 chars—within 40 by luck, not proof. The function is correct for *this game* (scores never negative, max via game-over), but the signature misleads other callers. Better: either bound the parameter (`score: long 0..1_000_000`) or use `Ascii max 50`, or remove the bound and let the compiler verify per call site.

**Example 1, line 68: silent clamp on cooldown.**
```
ship.cooldown = ship.cooldown - 1  // clamp: never below 0, no check needed
```
The comment notes `int 0..15 clamp` pins the result to [0, 15]. Correct, but unconventional: instead of decrementing and checking, the type silently pins. Works, but a reader unfamiliar with clamp ranges may expect countdown to stop at 0 without knowing the range refinement.

**Example 2, line 237–245: large per-job state.**
Each spawned job holds `Counts` with a `map<Ascii max 200, long, 20_000>` (several MB). Then `join` copies each result. Bounded and correct, but the example itself notes this is "heavy" (line 337). A production tool would write each job's results into a shared frozen batch or database, not copy them. Example is honest about the tradeoff.

**Example 3, line 370: token bucket refill capped at 60.**
```
let tokens = b.tokens + (int)min(whole, 60L)
```
When `whole >= 60` seconds and `b.tokens = 60`, `tokens` becomes 120. Later, `tokens - 1 = 119` is stored in a `clamp` field, pinned to 60. This is correct (clamping enforces the cap), but the math suggests overflow: readers may not grasp that the clamp is intentional. Clearer with `min(b.tokens + refill, 60)` before the check.

## 4. Clarity

**Example 1 (Rocks): 3/5.** Reads naturally for a game coder. Loop over mutable state is clean; wrapping and clamp ranges are clear once the syntax is learned. Noise: explicit casts everywhere (`(float)size * 12.0f`, `(long)points(...)`). The comment "checked: r.size is 2 or 3 here" at line 142 explains the cast, but the cast itself is noise—the compiler could infer safety. Worst snippet:

```
for b, id in g.bullets { 
    if !spent.contains(bid) && distance(...) < radius(...) {
        hit.push(rid); spent.add(bid); break
    }
}
```

This is idiomatic, but reads backwards: we check `!spent.contains(bid)` *before* `distance`, so a bullet only triggers once. The intent (a bullet hits the first rock it touches) is buried. Clearer:

```
for b, id in g.bullets {
    if distance(r.pos, b.pos) < radius(r.size) && !spent.contains(bid) {
        hit.push(rid); spent.add(bid); break
    }
}
```

Order now matches intent: *is it close?* then *is this bullet fresh?*

**Example 2 (logsum): 2/5.** Hardest example to follow. Noise from three sources:
1. **Checked conversions**: `status.try_as<int 100..599>() ?? return none` and `ascii_path.limit(200) ?? return none` each add a check that's correct but verbose.
2. **Error handling**: `map_io()?` and six `.is_err()` calls in `merge` (lines 291–294) muddy the logic flow.
3. **Spawning jobs**: `spawn count_file(...)` is clean, but readers unfamiliar with admission and job semantics may wonder whether 500 jobs can really run in parallel, and whether counted Counts structs per job is excessive.

Clearest improvement: define a conversion helper:
```
fn valid_status(s: long) -> Option<int 100..599> {
    s.try_as<int 100..599>()
}
```
Then `let code = valid_status(status) ?? return none` reads as a single thought.

**Example 3 (messages API): 4/5.** Transaction syntax is explicit and readable. Rate-limiter semantics are sound but subtle (token arithmetic, clock reset). The token bucket logic (line 368–373) is correct but requires re-reading: when does `since` reset, and why? Scenarios are clean. Only noise: match at line 382–385 handles a Result when `transaction { }` could return the Result directly, though the current style is safer (shows all paths).

**Example 4 (CRC-32): 5/5.** Cleanest example. Loop is direct, table is precomputed (a win from work-at-build-time philosophy), and the bitwise logic is terse but idiomatic. Explicit casts (`(uint)b`, `(long)((crc ^ ...) & 0xFFu)`) are noise in a bit-heavy function, but the design's "no implicit conversions" rule requires them. A shorter form like `b.u32` (widen, can't fail) might reduce noise without loss of clarity—this is noted in the example's open points.

**Rating summary:** Rocks 3/5, logsum 2/5, messages 4/5, CRC-32 5/5.

## 5. Open Design Questions

**Question 1 (for Ben): Bounded function contracts under implicit calls.**
Line 175's `score_line(score: long) -> Ascii max 40` is provably correct *for this game* but doesn't enforce the bound at the type level. In production, could a function that reads its own score from shared state (not passed as a parameter) declare `-> Ascii max 40` if it can prove the bound—or must all bounds be on parameters? If shared state can be bound in the caller's type system (e.g., `shared global game.score: long 0..1_000_000`), can a function rely on that?

Recommendation: Either let callers bind shared state fields, or require score-displaying functions to take a bounded `long` parameter.

**Question 2 (for Ben): Token bucket initialization and long idle times.**
When a rate-limit bucket sees 60+ seconds of idle time, `min(whole, 60L)` at line 370 prevents refill overflow, but the clamping on storage hides the logic. Should the example clamp tokens explicitly before the `tokens >= 60` check, or is the current design (cap-on-refill, then clamp-on-store) the intended pattern?

Recommendation: Document whether clamping at the point of use (before tests) or point of storage is the idiomatic pattern.

---

**Summary of findings:**
- Code is correct per design rules; no violations or bugs.
- Clarity varies: Rocks and CRC-32 are accessible; logsum's checked conversions obscure intent; token-bucket math is subtle but not wrong.
- Main pattern friction: required explicit casts, verbose error handling, and bounded-type checking that relies on code comments rather than signatures.

