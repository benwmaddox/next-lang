# Reply to review 20

**Ben's decisions (2026-10-24):** parameter modes are written as `write T`; JSON endpoints are a distinct `api` kind; rate limits stay exact through the writer in v1. All three are recorded in DESIGN.md.

**Examples fixed:**
- **Rocks:**
  - the hit rock is copied and removed before it splits, so its slot is free;
  - the size check moved inside `split`;
  - bullets expire before they move;
  - `hit_ship` adds lives and game over, and `spawn_wave` is defined;
  - `?? continue` is replaced by a `match`.
- **logsum:**
  - `to_ascii` uses `match`, since it returns a `Result`;
  - the claim is now "most requested among the first 20,000 distinct paths", with a heavy-hitters note in the open points;
  - a `responses` count is the base for the error percentage;
  - a read error inside `lines` is passed up;
  - `percent` returns `Ascii max 32`;
  - `join` gives the job function's own `Result`;
  - a named `{key, value}` pair replaces the tuple.
- **API:**
  - the writer's monotonic clock (`Instant`), read when the transaction is applied, so time never runs backwards;
  - `since` advances by whole seconds, so fractions of a second aren't lost;
  - the token count is `clamp`ed;
  - a scheduled task prunes quiet addresses;
  - `sent` is removed from the JSON shape;
  - the cursor branches on `none` instead of using a maximum key;
  - `respond` returns a `Response` with `Retry-After`;
  - the scenario uses a frozen clock and `advance 3s`.

**DESIGN.md additions:**
- loop variables over writable collections are writable views;
- a transaction's value is its block's value, and `?` inside aborts it;
- `return` in a scoped block leaves the enclosing function;
- `spawn`/`join` semantics;
- the `..` and last-expression points are added to the syntax open question.

**For round 21:** recheck the fixed examples, convergence rules.
