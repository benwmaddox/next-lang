# Round 21 review

References name EXAMPLES lines. Proposed syntax is not itself a rule violation. `Result` means success-or-error; `Option` means value-or-absence.

## 1. Decided-rule violations

- **237: wrong job result type.** `count_file` returns `Result<Counts, ToolError>`. A job carries its function's complete return type ([DESIGN 321](../DESIGN.md#L321)), so correct the declaration:

  ```
  var jobs: list<Job<Result<Counts, ToolError>>, 500> = list {}
  ```

  Then `j.join()?` has the intended meaning.

- **370: arithmetic does not inherit the field's clamping behavior.** Clamping applies when storing into a clamping type; intermediate arithmetic uses ordinary numbers ([DESIGN 517](../DESIGN.md#L517), [560–567](../DESIGN.md#L560)). With 59 tokens and 60 elapsed seconds, `tokens` becomes 119; storing 118 clamps to 60, allowing **61** requests at that instant. Correct the line:

  ```
  let tokens = min(60, b.tokens + (int)min(whole, 60L))
  ```

- **365–367, 390–392: clock access lacks a capability**, the value granting permission to read time. Time must come through a capability passed down from an entry point ([DESIGN 622–624](../DESIGN.md#L622)). Using provisional clock-method spelling, correct these lines:

  ```
  fn take_token(address: Ascii max 45, clock: Clock) -> bool {
  let now = clock.monotonic_now()       // still read inside the writer transaction
  task every 60s prune_limits(clock: Clock) {
  let now = clock.monotonic_now()
  ```

  Add `clock: Clock` to `get_messages`, pass it to `take_token`, and have the host/scenarios supply it.

- **166: missing draw-list capacity.** [DESIGN 727](../DESIGN.md#L727) requires a declared command capacity. Using proposed bound syntax: `fn draw(frame: Frame max 100) {`. Maximum commands: **1 clear + 64 rocks + 32 bullets + 1 ship + 1 text = 99**.

- **158: “exact everywhere” overstates the replay promise.** [DESIGN 730](../DESIGN.md#L730) guarantees the same build and platform; others are best effort. Corrected line:

  ```
  fn direction(angle: float) -> Vector2 { Vector2(cos(angle), sin(angle)) } // repeatable on the same build/platform
  ```

## 2. Program bugs and test expectations

- **223, 251–294: per-file truncation corrupts the promised path totals.** File A contains `/shared` once. File B contains 20,000 other distinct paths, then `/shared` 1,000 times. B discards those 1,000 occurrences before merging. The final map retains `/shared` but reports **1 instead of 1,001**. With only those records, `skipped` becomes **1,001 instead of 1**. Merging maps also does not preserve line encounter order. Fix by streaming files into one accumulator (below), or choose the first 20,000 keys in an ordered first pass and count those keys across all files in a second pass. Add this two-file test.

- **115–123: removing each parent immediately before splitting still loses usable space.** Start with 64 rocks; hit a size-3 rock followed by a size-1 rock. The first gets only one fragment; removing the second later leaves **63** rocks. Both fragments would fit, yielding **64**. Copy victims into `list<Rock, 64>` and remove **all** hit parents first; only then score and split the copies.

- **130–133: the final death leaves one life displayed.** A valid `lives == 0` state also enters the subtraction branch and attempts −1. Correct the branch to `if g.ship.lives <= 1 { g.ship.lives = 0; g.over = true } else { ... }`.

- **446–451: `general` is undefined.** The earlier scenario's `room` is local to that scenario. Give this scenario its own database and room:

  ```
  let db = Db.memory(Chat)
  let general = db.transaction { Room.add(Room { name: "General" }) }.unwrap()
  ```

  Reset `limits` per scenario too. With isolated state and a frozen clock, **60 successes, one rejection; advance 3 seconds; three successes, one rejection** is the correct expectation.

Recomputed: `400 / 3 = 133` with integer division; CRC-32 of `123456789` is `0xCBF43926`, and empty input gives zero. `score_line` needs at most **35** characters; the extreme signed-long percentage needs **25**, within 32.

## 3. More workable code

- **235–245, 337: give logsum a practical exact default.** Hundreds of multi-megabyte maps and their copies are expensive. Streaming into one map also fixes the counting bug:

  ```
  var total = Counts {}
  for path in files { count_file(env.fs, path, total)? }
  ```

  Change the helper to `fn count_file(fs: Fs, path: Path, c: write Counts) -> Result<(), ToolError>`, remove its local `c`, and end with `ok(())`. Parallel counting can use the two-pass approach above when measurements justify it.

- **127–135: respawning at the centre can consume successive lives on consecutive ticks against the same rock.** Add `invulnerable: int 0..120 clamp = 0`; decrement once per step, skip ship collisions while positive, and set it to 120 after respawning. This gives two seconds to escape at 60 ticks/second.

## 4. Questions only Ben can answer

None.
