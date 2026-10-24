# Round 22: examples, pass 2

References use current EXAMPLES line numbers. `Option` means value-or-absence; `Result` means success-or-error. These are paper examples, so calculations and rules can be checked, but compilation cannot.

## 1. Rule mismatches and bugs

**291: the optional-call chain needs an unwritten rule.** [DESIGN 511](../DESIGN.md#L511) defines `x?.f()` as `some(f(x))` when present. But `word(0)` itself returns an `Option`, as line 288 demonstrates. Under that definition, `after_last('"')?.word(0)` produces an option containing another option; the following `?.parse_int()` receives that inner option, not bytes. This is a specification/example mismatch, rather than a violation of a decided syntax rule. Until the design explicitly says optional calls combine those two layers, replace line 291 with:

```
let response = line.after_last('"') ?? return none
let status_word = response.word(0) ?? return none
let status = status_word.parse_int() ?? return none
```

**283, 292: name the repeated status refinement.** A refinement is a type with an extra restriction. [DESIGN 564](../DESIGN.md#L564) says one used more than once gets a name. Corrected declarations/use:

```
type HttpStatus = int 100..599
struct Entry { path: UrlPath, status: HttpStatus }
let code = status.fit<HttpStatus>() ?? return none
```

**378: long idle time loses the promised fractional second.** Lines 373–375 promise to keep it, but `since: now` discards it whenever 60 whole seconds have elapsed. Start empty at 0 ms and refill at 60,500 ms: the code gives 60 tokens with `since = 60,500`. Drain them immediately; at 61,000 ms it gives zero. Preserving the fraction gives one. Correct line 378:

```
if secs >= 60 { return Bucket { tokens: 60, since: b.since + Duration.seconds(secs) } }
```

This is a mismatch with the example's stated refill policy, not a DESIGN violation. Add that boundary test; the existing 90-second test cannot detect it.

**336–342: the cross-file regression test misses the original failure.** It calls `count` directly, so it cannot catch a return to separate per-file maps. Also, file B contributes only 19,999 other paths, leaving room for `/shared` even in a separate map. Use two actual in-memory files through `count_file`, with A containing `/shared` once and B containing **20,000** other paths followed by `/shared` 1,000 times. Correct the loop bound and expectations:

```
for i in 0..20_000 { /* write B's distinct paths */ }
expect c.paths.get("/shared") == some(1_001)
expect c.skipped == 1
```

The current implementation gives these results; the old separate-map implementation does not.

**Recomputed expectations:** all currently written numeric assertions agree with the code. Integer `400 / 3` is **133**; the split test gives **62 + 2 = 64** rocks; 40 firing attempts retain **32** bullets. Maximum drawing is **99** commands. The longest score label is **35** characters, including a negative long's sign; the extreme fixed-decimal percentage needs **25**. Path-map tests currently give **20,000/1** (stored/skipped) and **1,001/0** (shared count/skipped). Paging yields **100, 100, then 50** rows. The frozen-clock limit is **60 successes, rejection; three seconds; three successes, rejection**. CRC-32 is **0xCBF43926** for `123456789`, **0** for empty input.

## 2. Clarity

Scale: **1** requires substantial explanation; **5** is readily readable by a working programmer new to the language.

- **Rocks — 3/5.** `step`, `steer`, `fire` and the tests communicate the game directly. Collision handling requires tracking three temporary collections, two kinds of ids and three phases. That burden comes partly from the design: a view is temporary access to existing storage, and the rule against removal while a view exists forces deferred removal. `safe` sounds like a boolean; `invulnerable_ticks` says what the number measures. `hit` and `spent` would read better as `hit_rock_ids` and `spent_bullet_ids`. Repeated `f` suffixes still add noise where context already supplies `float`. `cooldown -= 1` looks familiar but its stopping at zero depends on a declaration far away; that is a readability cost of type-directed clamping.
- **logsum — 3/5.** Sequential file processing and one accumulator make the overall algorithm easy to follow. The parser is still punctuation-heavy: `?`, `?.`, `??`, `.ok()` and `fit` each mean something different. `io` sounds like doing I/O, although it only changes an error's type; `tool_result` would better describe it. `c`, `e`, `p`, `i` save little space in reporting/counting. `skipped` combines malformed input with valid responses whose paths are untracked, so it invites a wrong interpretation of the totals. The repeated status restriction needs language knowledge that a name would remove.
- **Messages API — 3/5.** Paging and response mapping read conventionally. Understanding the limiter requires knowing where the transaction runs, what `?` aborts, why time is read inside it, and that constructing a `Bucket` silently caps arithmetic. `since` does not say which event it dates; `refilled_through` is more accurate. `.ok() ?? false` hides the reason for denial. The example also relies on `Chat`, `Name` and `Body` from the overview; link that dependency beside the code. These are substantial prerequisites for a short endpoint.
- **CRC-32 — 4/5.** The table loop, byte loop and comparison against a slow implementation are easy to locate. The polynomial and bit operations require checksum knowledge, but little language-specific knowledge. `t` and `c` are unnecessarily opaque: `table` and `remainder` help. The explicit number conversions remain visual clutter imposed by the design, though their method spelling is easier to scan than casts.

Two clearer rewrites, retaining the same rules:

**Parser, 287–293:** separate extraction, conversion and validation; no optional-call chaining knowledge required.

```
let request = line.between('"', '"') ?? return none
let raw_path = request.word(1) ?? return none
let ascii_path = raw_path.to_ascii().ok() ?? return none
let path = ascii_path.fit<UrlPath>() ?? return none

let response = line.after_last('"') ?? return none
let status_word = response.word(0) ?? return none
let status_number = status_word.parse_int() ?? return none
let status = status_number.fit<HttpStatus>() ?? return none
some(Entry { path, status })
```

**Refill, 376–379:** make the cap visible at the calculation, and preserve whole-second advancement uniformly.

```
fn refill(bucket: Bucket, now: Instant) -> Bucket {
    let elapsed_seconds = (now - bucket.since).whole_seconds()
    let added_tokens = (int)min(elapsed_seconds, 60)
    Bucket {
        tokens: min(60, bucket.tokens + added_tokens),
        since: bucket.since + Duration.seconds(elapsed_seconds),
    }
}
```

## 3. Questions only Ben can answer

None.
