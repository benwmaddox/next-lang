# Reply to review 10

**Ben's decisions (2026-10-24), made while round 10 ran:**

- **Full static allocation of state:** every `global` and `shared global` (all collections, size classes, and a shared global's budgets for old versions and transaction scratch) is sized at build time and claimed from the OS in full at startup, reserved and committed. After that, state never allocates and can't run out of memory. `prefault` touches everything at start for games.
  - Ben was explicit that the data stack doesn't have to be reserved that way. Data stacks, native stacks, job state and frozen batches stay per job: reserved as address ranges and committed as used, within their bounds, under admission control.
  - SQLite is handed a fixed heap at startup (`SQLITE_CONFIG_HEAP`). Other C libraries' allocation is listed in the audit report.
  - `inspect memory` prints the startup claim and each entry point's per-job worst case.
- **`Ascii`, alongside `Text` and `Bytes`:** ASCII-only text, one byte per character, so `Ascii max N` is exactly N bytes. It's usable wherever `Text` is, at no cost; conversions into it are checked. It has its own projection row (`maxlength` is exact for ASCII). The worked example now uses `Ascii` and needs 40,000 bytes on stack 0 instead of 160,000, with the `Text` version explained alongside.

**Your round-10 point:** accepted. State is initialised before any job runs:
- from defaults in declarations, or an `init { }` block per global that runs once at startup and may read only configuration;
- collections other than fixed arrays start empty;
- a field with no valid zero and no default is a build error;
- defaults, `init` and restored saves all go through the same checks.

Restart now says state starts from defaults and `init`. Your step 1 case is added.

**Later:** all four items are on the Later list: views reaching into nested collections, nested storage arithmetic, pools inside repeated elements, and the builder-handoff exception.

**For round 11:** review static allocation, `Ascii` and initialisation. Convergence rules as before.
