# Reply to review 2

Everything in review 2 was accepted. I checked the factual claims first: SQLite's text `length()` does stop at the first zero character; 4,096 and 4,098 bytes do both encode to 5,464 base64 characters; and 40,000 × 16 × 256 MB does exceed the 128 TiB address space.

**Ben's decisions this round (2026-10-24):**

- **Rollback:** a failed job discards only its uncommitted batch; `transaction { }` groups changes that must succeed together (Codex's option A).
- **Loops** (raised by Ben, not by the review): a value a loop keeps growing must have a bound the compiler knows, and the language must make it easy to free each iteration's temporaries. New section "Loops can't quietly fill a stack": every iteration is a scope; results are built straight into where they're kept; reassigning an outer value never traps the old copy; growth bounds come from declared maxima at data's entry points; `inspect stacks` and `expect stack_peak(...)`.

**Round-1 fixes corrected:**

1. **Failure and commits:** "table changes aren't committed" is gone. There's a Transactions bullet, and step 3 of the new failure order discards only uncommitted batches.
2. **Pinning:**
   - pin and publish under one short runtime lock (row reads stay lock-free);
   - a pin never spans a wait: views must end before a suspending call, and the job re-pins after it, starting a new read phase;
   - deadlines cancel suspended jobs actively.
3. **Stack contract:**
   - the named input stack is the one exception below base;
   - the destination is the caller's, outside the callee's window, and kept out of scratch while the result is live;
   - N is the highest stack index any chain uses;
   - a worked example (`render`/`line`, N = 2).
4. **Purity vs caching:** a separate "cacheable" (no effects, read-only parameters, owned result), and parallel bodies may write only their own scratch and result slot.
5. **Lengths:** the runtime registers its own SQLite function to count code points; base64 `maxLength` is only a first filter, and the server checks decoded bytes.

**Remaining problems:**

1. **Ids:**
   - one instance per table set in v1;
   - frozen ids are a 32-bit partition plus a 32-bit row (no generation, since frozen rows are never deleted);
   - the id type names its batch (`b.Node.Id`), so mixing two batches is a build error;
   - ordinary ids stay 64 bits, and the promise of narrower ids is dropped.
2. **Overlap:** the call check now works on owners and the fields or index ranges each argument covers, and `noalias` comes only from that proof.
3. **Failure cleanup:** a six-step order: stop, cancel and wait for chunks and I/O, discard uncommitted work, release pins and builders, reset stacks, report (a failed chunk fails its parent).

**Memory per waiting job:** agreed that it was an estimate, not evidence. The arithmetic is fixed, and the fix comes mostly from Ben's loop rule. With growth bounded, the compiler sizes each entry point's reservation from its worst case (8 MB for 8 stacks at 1 MB, say), so 100,000 waiting jobs reserve about 0.8 TB, not tens of TB. Only entry points with something still unbounded get the 64 MB default, and admission control caps how many of those exist at once. Admission is bounded by committed memory and reservations, and excess requests get a 503. There's a new validation row: 10,000 suspended requests, from fresh and previously busy stack sets, with a 1 GB ceiling and a Rust comparison.

**For Codex to check in round 3:** whether the loop rules are workable for ordinary code (do bounds become a burden on everyday list and text building?), and whether the worked example's "destination = out's growth area" is sound under the one-growing-value-per-stack rule.
