# Round 15: `docs/DESIGN.md`

## 1. Round-14 fixes needing correction

1. **The read comment overclaims consistency** (`DESIGN.md:58-59, 73-76, 641`). The `db.read` block contains only `Room.get`; `Messages` runs a separate read. The live-update section says separate pieces can see different versions. Replace “both queries see one version” with “this transaction reads only the room; `Messages` may read a newer version.” If the page needs one version, read both together and pass owned results down.

2. **`Full` is not only the disk quota** (`:51, 87; Databases :300, 305`). The database section also defines running out of integer row keys as `Full`. Update the enum comment and action comment to include both documented causes.

3. **The effect summary is incomplete and misattributes reads** (`:115; Effects :573, 578`). An effect is a tracked external operation; a capability is a value granting permission to perform one. `room` reads `Chat` and `online`; `Messages` reads `Chat`, not `online`. Also, `post` sends a live signal, but the closed effect list omits `signal`, and the capability section does not explain or grant authority to send it. State the per-function effects and add a signal capability/effect, or define which existing capability includes it; show its grant in the manifest and entry point.

4. **The general failure list still includes float division by zero** (`:487, 501, 503`). The float rule says `1.0 / 0.0` yields infinity, while the general list says a divisor of zero fails. Qualify that item as integer division by zero.

5. **The tick recovery sentence confuses handled values with job failures** (`:198, 652; Failures :487, 496`). Overflow and stack exhaustion fail the job; they are not a `Result` (success or error value) a caller can handle afterward. Ignoring a collection's `Full` is a build error. For recoverable conditions, handle collection results or use `checked_add`, which returns `Option` (a value or absence). Rewrite the sentence around those checked forms; an actual failed tick stops the game and cannot resume its partly changed state.

## 2. First steps and recorded decisions

No first-steps 1–2 blocker found, and no contradiction to any recorded decision.

## 3. Later

- The live-refresh rule (`:641`) should later say what an open-page subscription retains for a new job: bounded copies of piece arguments such as `room_key`, independent of the original request's memory, and how server-owned capabilities such as `Db` are supplied again. This does not block the first steps.

## 4. Questions

None.
