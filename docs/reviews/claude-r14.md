# Reply to review 14

**Ben's decisions (2026-10-24):**
- **Replay:** exact on the same build and platform. A recording stores the build id, the initial state and assets, the random seed and generator version, and the inputs. Anything else is best effort.
- **A failed tick stops the game,** with the error and the recorded inputs. There's no staging, against my recommendation; it's Ben's call, and it costs nothing per tick.

**Example (point 1):** rewritten.
- **Missing values:** `?? return not_found()` answers a missing room with a 404, and presence defaults to 0.
- **Reads:** the room page reads in one transaction; the message list is a `piece Messages` with its own bounded read, ordered `.key desc` with `limit(50)`.
- **Types:** `type Body` and `type Name` are declared once; `Viewer` comes from the session; `PostError { Empty, Full }`, with the error mapped and `ok(())` returned.
- **Locals:** `room_key` replaces the local `room`.
- **Test and `main`:** the test uses `Db.memory(Chat)` and `unwrap`. `main` returns `Result`, handles startup failures, and binds the route parameters and the session viewer.
- **Effects:** the claims under the example are corrected (database, snapshot, signal).

**One declaration (point 3):** `Body` is one declaration. There's no browser `maxlength` for `Text`. `Url` values for `href`/`src` allow only safe schemes.

**Live updates (point 4):**
- A live piece re-runs as a new job and loads current data itself, so nothing from the original request survives.
- Pieces read in their own transactions; a page that needs consistency reads once and passes the result down.
- Notices are numbered and combined, and pages reload on reconnect, so a lost notice means a stale view until the next one.
- Queues are bounded, overflowing into "reload everything".
- Rendered size includes markup and escaping, and request byte limits are checked before decoding.

**Game host (point 5):**
- `tick` and `draw` run one at a time on the home worker.
- `tick` can't suspend, and `draw` has its own stack reservation.
- The draw list has a declared capacity; extra draws are dropped and counted.
- `draw` gets a separate random source, and the simulation's random state is in saves.
- Assets live for the whole run.

**Numbers:**
- **`fast` blocks:** results are `FloatNaN`; only the `reassoc`/`contract`/`arcp` permissions are used; their results can't go into tick state.
- **Division:** float division by zero gives infinity, and only a NaN result fails.
- **Width:** logical width is separate from storage width; shifts need `0 <= n < width`; MIN / −1 fails.
- **`Fixed`:** multiplying gives an exact `Fixed<4>` computed in 128 bits, and rounding back is explicit.

**Packages:** a module is a file. Its cache key includes the interfaces of the private sibling declarations it uses.

**For round 15:** recheck the rewritten example line by line and the amended sections. Convergence rules as before.
