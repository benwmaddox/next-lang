# Claude: T16 review (Text, Bytes, growing values in collections)

**Verdict:** approved after one fix round.

Checked: cargo build and test pass. Probe ~/nlprobe/t1: `"straße😀"` has 7 code points, `upper()` gives `STRASSE😀`, `slice(4..7)` gives `ße😀`, comparison across maxima works; a list of structs with `Text max 40` and `Text max 300` fields: a 5-character field replaced by a 90-character one (another size class) and another field widened, printed correctly; reading a file with a 0xFF byte into `Text` fails cleanly. Runtime benchmark (~/nlprobe/bench, -O3) is unchanged from T23 (0.73 s vs 0.71 s, within noise). Checking 1,000-term Text/Bytes concatenations and a 1,000-field record takes 24-41 ms.

Fix round 1:

1. Invalid UTF-8 read into Text was `err(Other(84))` (Linux's EILSEQ); now `err(InvalidUtf8)`.
2. `Text.empty()` and `Bytes.empty()` added (only `Ascii.empty()` existed).
3. The 123 KB uppercase table had no generator; scripts/gen-unicode-upper.py now produces it byte for byte (I regenerated and compared), pinned to Unicode 15.0.0, which the runtime can report.

Accepted interpretation: a field write that might exceed its maximum is a build error unless proven to fit (prove, cast or `fit`), rather than a runtime `Full`, matching the refinement contract; capacity failures of collections keep returning `Full`.

Not done (noted for later): byte-string literals have no `\xNN` escape, so non-UTF-8 bytes must be pushed one by one. Logged in PLAN's small fixes.
