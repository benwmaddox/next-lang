# Round 19 convergence review

## 1. Round-18 fixes and decisions

None found that contradict a recorded decision or block steps 1–2.

- **The language in one page:** `?.count()` produces an optional `long`; the unsuffixed default `0` takes that type from context, so `?? 0` needs no implicit numeric conversion. The transaction now handles a `Result` with `match`, rather than the Option-only `??`. `post(room_key)` has the defined declarative-binding meaning: a function identifier plus bounded arguments, with the server supplying the remaining arguments.
- **Functions as values, no closures:** the indirect-call contract (the information needed to call through a function value) now includes parameter modes, result/append support, effects, suspension, state dependencies and stack bounds. Call analysis follows indirect calls. Scoped blocks use generated named helpers and bounded context; they do not introduce user-storable functions that capture locals. Saves use symbolic function identifiers rather than process addresses.
- **Sizes, indexes and time:** lengths, counts, capacities, offsets and indexes use refined `long`s—a 64-bit integer with a checked range. Numeric conversions remain explicit. The stated sums, 499,999,500 and 9,999,990,000, are correct. `Time` and `Duration` have distinct meanings and declared units.
- **Stack example:** its ASCII bounds remain consistent: at most 68 bytes per line, within the declared 80, and 500 × 80 = 40,000 bytes. The two-stack claim explicitly requires `str` to write directly into the output without another growing temporary while `name` occupies stack 1.

## 2. Problems blocking first steps 1–2

None found. The round-18 changes do not require implementing routes, databases, callbacks or time facilities before state/typed ids and stack assignment.

## 3. Later — new items only

- **Route lifetime:** distinguish evaluating the route declaration from dispatching its generated helpers on later requests. State whether `serve` owns copied context or borrows it until shutdown; borrowed context must survive every request using it. This would clarify “runs where it's written” without changing the scoped-block decision.
- **Synchronous C callbacks:** specify how a callback that must return a result immediately reaches its owner's worker. Permit direct calls on that worker; otherwise require an explicit supported handoff or reject the binding, rather than silently queueing a callback whose caller needs its answer now.
- **Time operations:** define `Time - Time -> Duration`, `Time + Duration -> Time`, and overflow behavior. Distinguish calendar timestamps from the monotonic clock used for elapsed-time limits—a clock that does not jump when the system clock is corrected.

## 4. Questions only Ben can answer

None.
