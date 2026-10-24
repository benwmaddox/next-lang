# Second-pass review of examples (2026-10-24)

Independent review of four examples against DESIGN.md, looking for rule violations, bugs, and clarity issues.

## Rule violations

None found. All four examples correctly apply the decided rules: compound assignment with clamping/wrapping applied automatically, context-typed literals, `?? continue`, `discard`, named refinements with safe casts, widening methods (`.to_long()`, `.to_double()`, `.to_uint()`), bounded collections, no closures, long indexes where enforced. The `?.` and `??` operators are used only on `Option` types. Capabilities are explicit (clock, fs, db). Transaction `?` aborts the batch.

## Bugs

**logsum, line 302, percent function scope:** The bound comment says "At most 25 characters", but the return type is `Ascii max 32`. A long is 19 digits (2^63−1 ≈ 9.2×10^18); formatted with one decimal place as a percentage: "922337203685477580700.0%" ≈ 24 chars. The bound is correct and conservative—no bug, just overstated in the comment. Consider changing the comment to "up to 32 chars for the most extreme longs" if accuracy matters.

**CRC example, loop counter inference:** Line 497 (`for i in 0..256`) uses `i` directly as an array index on line 502 without casting. DESIGN.md states "With no implicit conversions, indexing with an `int` is written `a[(long)i]`, or `i` is declared `long` in the first place." The example assumes the compiler infers that i should be `long` from its use as an index. This is flagged as an open design point (EXAMPLES.md line 537–538: "assumes a loop's counter type comes from how it's used, which DESIGN.md doesn't say yet"). Not a bug if type inference is intended; if the loop counter defaults to `int`, this violates the rule and needs `for i: long in 0..256` or casting on line 502.

All test values recomputed:
- Rocks "a bullet splits a big rock in two": 400 ÷ 3 = 133 ✓
- Rocks "fragments use the slots of every rock hit in the same tick": 62 untouched + 2 from size-3 split = 64 ✓
- logsum "a full path map counts what it drops": 20,001 attempts, 20,000 succeed, 1 skipped ✓
- logsum "a path's count is exact across files": 1 + 1,000 = 1,001 ✓
- API rate limiter "refill tops up one token a second": 2500 ms ÷ 1000 = 2 whole seconds ✓
- API scenario: 60 tokens used, refill adds 3 after 3 seconds = 3 more allowed ✓
- Rocks draw commands: 1 clear + 64 circles + 32 dots + 1 triangle + 1 text = 99 ≤ 100 ✓

## Clarity

**1. Rocks (game): 3/5**
Well-structured and readable. Good use of named refinements (Size, Lives) and explicit bounds (wrapping angle, clamping timers). Strengths: the removal-before-split pattern (lines 104–127) is clear, thanks to its explanation ("Find every hit first..."). Weakness: the "two meanings of `..`" (DESIGN.md line 816) is genuinely confusing—lines 148 (`for k in 0..2`), 154 (`for k in 0..n`), and 199 (`for i in 0..62`) all use the same syntax to mean "stops before", while line 16 (`Size = int 1..3`) means "includes the end". A reader new to the language will stumble on this. The design should clarify or use two spellings (`..` vs. `..=` as Rust does).

**2. logsum (CLI tool): 2/5**
Dense and shows off language features, but clarity suffers from variable shadowing and chained operators without clear type flow. 
- Line 268: `let line = io(line)?` shadows the loop variable `line` (yielded from `file.lines()`) with a new one (unwrapped Bytes). A new name (`let lineResult` or `let bytes`) would be clearer.
- Line 289: `let ascii = raw_path.to_ascii().ok() ?? return none` chains `.ok()` (Result→Option) and `??` (Option→return). The `.ok()` conversion is hidden in the middle. Clearer as:
  ```
  let ascii_opt = raw_path.to_ascii().ok() ?? return none
  ```
  or rename to show the type transformation.
- Line 290: `let path = ascii.fit<UrlPath>() ?? return none` uses `fit`, a method not defined in the examples, without explanation of what "fit" means (presumably a checked cast). A comment or a shown signature would help.
- Overall readability hurt by no-longer-seeing-Result-vs-Option, and the `fit` method is opaque.

**3. API with rate limiter: 4/5**
Clear and well-commented. The pure `refill` function (lines 376–380) is separated from the stateful `take_token` for easy testing. The transaction logic with `?` aborting is explicit. One weakness: line 388 (`var b = refill(limits.by_address.get(address) ?? Bucket { since: now }, now)`) creates a Bucket inline if the address is new—good, but the default initialization `Bucket { since: now }` silently sets `tokens` to its struct default (60 from line 365). A reader may miss that refill then steps it down. A brief comment explaining the default would help.

**4. CRC-32: 5/5**
Elegant and clear. The compile-time constant table is a great motivator for compile-time computation. Widening methods (`.to_uint()`, `.to_long()`) read naturally. The check block (line 527) is a powerful idea and well-motivated. No clarity issues.

**Suggested rewrite of logsum parse** (lines 286–294) for clarity:
```
fn parse(line: Bytes max 4096) -> Option<Entry> {
    let request = line.between('"', '"') ?? return none
    let raw_path = request.word(1) ?? return none          // "GET /r/12 HTTP/1.1" -> "/r/12"
    
    let ascii = match raw_path.to_ascii() {
        ok(a) => a
        err(_) => return none                              // not ASCII: skipped
    }
    let path = ascii.fit<UrlPath>() ?? return none          // over 200 bytes: skipped
    let status_str = line.after_last('"')?.word(0)? ?? return none
    let status = status_str.parse_int() ?? return none
    let code = status.fit<int 100..599>() ?? return none    // fit: the Option form of a checked cast
    some(Entry { path, status: code })
}
```
This separates the `.to_ascii()` error handling from the chaining, makes the types clearer, and removes one level of `??` chaining. Trade-off: one more line and explicit match. The choice depends on how often chained `??` is used elsewhere (if often, the original style is consistent; if rare, the expanded style is clearer).

## Questions for Ben

1. **Loop counter type inference:** Does the compiler infer `for i in 0..256` to `long` from i's use as an index, or should the examples write `for i: long in 0..256`? (DESIGN.md section "Loop counter types" is marked open.) The CRC example assumes inference works; logsum and API examples don't index loop counters, so they're silent. If inference is intended, update DESIGN.md; if explicit, fix the CRC example.

2. **Range syntax:** The "two meanings of `..`" is a genuine pain point. Would Rust-style `..` (exclusive) and `..=` (inclusive) be better than one symbol with context-dependent behavior? Or clarify in DESIGN.md that refinements use `..=` (`int 1..3` means 1 to 3 inclusive) and loops use `..` (`for i in 0..5` means 0 to 4)?

---

**Top findings:**
1. Logsum's chained operators and variable shadowing reduce clarity for newcomers; CRC-32 is the clarity model for the set.
2. Loop counter type inference is unresolved in DESIGN.md but assumed in CRC; explicit guidance needed.
3. The "two meanings of `..`" is a genuine usability issue for readers new to the language and should be resolved via design or documentation before v1.
