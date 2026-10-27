# Review of f413c13 (E3b), round 1: independent correctness read

Reviewer: Claude Opus (independent; did not read the manager's review).
Method: built the commit's selfhost compiler from `git archive f413c13`
(`/mnt/d/tmp/opus-e3b/shc`) and, for comparison, its parent `f413c13^`. Ran
small packages through stage 0 (`nlc --frontend=rust run`) and the selfhost
compiler (`shc build … --runtime=core`, `link-ir` at O1, run under `env -i`,
and again with `NLC_TEST_STACK_FORCE_MOVE=1` where relevant). File:line refer
to the files at f413c13.

Summary: 2 critical, 3 high, 2 medium, 2 low, plus 1 stage-0 note. All
findings except L2 are CONFIRMED with a program. Several are pre-existing
(the parent commit behaves the same), but they sit inside E3b's scope or
E3b makes them much more common; each says so.

A key fact behind the severity ranking: **a push the checker marks as proven
skips the runtime capacity check**. So any count fact that is wrong makes a
silent out-of-bounds write. It is not only a difference in which programs
are accepted. In the tests below, selfhost writes 2 elements into a
`list<int, 1>`, writes 5 into a `list<int, 4>`, and segfaults after printing
garbage.

---

## CRITICAL

### C1. Count facts are not joined at `if`/`match`. A `clear()` on one branch leaves the count at 0 after the branch. CONFIRMED

`check_one_body` changes `compiler.bindings[b].collection_count` in place as
it walks (selfhost/compiler.nl:5762-5774; `clear` sets 0 at 5768). There is
no snapshot at the start of an `if` or `match` and no join at the end. So
the walk's final state is whatever the last branch it walked left behind.
Stage 0 snapshots `collection_counts` at the start of an `if`. After the
`if` it joins with `max` and drops any key that is missing from either
branch that falls through (compiler/src/checker.rs, around line 12322).

```nl
fn main() {
    var xs: list<int, 1> = [5]
    let c: bool = false
    if c { xs.clear() }
    xs.push(7)
    print(xs)
}
```
- stage 0: `main.nl:5:5: error: this collection operation returns a Result with error type Full; handle it …` (exit 2)
- selfhost: builds, prints `[5, 7]` (exit 0). That is two elements in a capacity-1 list: the proven push wrote past the end.

Second form, `p_ifclear2`: `xs.push(1); if c { xs.clear() } else { xs.push(2) }; xs.push(3)` on a
`list<int, 2>`. Stage 0 rejects it. Selfhost accepts it, but it then hits H1
at link time.

Fix: in `check_one_body`, record the list-count facts when an `If` or
`Match` frame starts. Restore them before walking each branch and arm. At
the end, join the branches that fall through: keep the larger count, and
use -1 if any branch has -1. This mirrors stage 0's `(true,true)` /
`(true,false)` / … cases.

### C2. `finish_loop_push_proofs` overwrites counts that the loop body invalidated. CONFIRMED (four forms)

selfhost/collections.nl:284-302 sets
`binding.collection_count = proof.final_count` for every proof made for the
loop. It does this even when the body ended the fact (insert, pop, remove,
assignment, or passing the list as `write`), and it ignores other additions
to the list. Stage 0's `finish_loop_push_proofs` removes the key when
`after_body` lacks it (checker.rs, around line 13545).

The same gap exists inside the loop. `loop_push_is_proven` (collections.nl:252)
returns true at depth > 0 if any proof exists for the binding. It never
checks whether the body has already invalidated the fact. So an `insert`
before or after the push does not end the proof. The per-iteration count
also counts only `push`, not `insert` or pushes made through `write`
helpers.

| Package | Program (core) | stage 0 | selfhost |
| --- | --- | --- | --- |
| `p_loopinsert` | `var xs: list<int, 4> = list {}`; `for i in 0..2 { xs.push(i); discard xs.insert(0L, i) }`; `xs.push(9)`; `print(xs)` | rejects line 7 (unused Full result) | `[1, 0, 0, 1, 9]`: **5 elements in a capacity-4 list** |
| `p_loopwrite` | `fn fill_up(values: write list<int,4>) { discard values.push(1); discard values.push(1) }`; `for i in 0..2 { xs.push(i); fill_up(xs) }`; `xs.push(9)` | rejects line 11 | `[0, 1, 1, 1, 9]`: 5 elements in capacity 4 |
| `p_loopassign` | `let full: list<int,2> = [8, 8]`; `for i in 0..1 { xs.push(i); xs = full }`; `xs.push(9)`; `print(xs)` | rejects line 8 | prints kilobytes of garbage, then **segfault (exit 139)** |
| `p_looppop` | `for i in 0..2 { xs.push(i); let _ = xs.pop() }`; `xs.push(9)` on `list<int,4>` | rejects line 7 | `[9]`. Safe at run time, but accepts a program stage 0 rejects |

Fix:
- collections.nl:284 `finish_loop_push_proofs`: apply `final_count` only
  when the binding's count is still ≥ 0 at the end of the body. Otherwise
  leave it at -1.
- For keys the loop did not push to, use `max(before, after)` as stage 0
  does. That also covers a `clear()` inside a loop that may run zero times.
- In `loop_push_is_proven` at depth > 0, also require
  `bindings[b].collection_count >= 0`.
- `count_loop_pushes_for_binding` (collections.nl:126) should make the
  proof invalid when the body contains `insert`, `pop`, `remove`, an
  assignment to the binding, or a write-call on it. Stage 0 gets the same
  effect from `after_body` lacking the key.

---

## HIGH

### H1. A proven push as the tail of an `if` block emits invalid IR (undefined `%agg.N`). CONFIRMED (valid program)

The checker makes a block whose tail is a proven push unit-typed
(`tail_proven_success`, compiler.nl:5924-5925). The emitter's block-tail
path in `emit_expr_linear` (the `FLAG_HAS_TAIL` branch at compiler.nl:9336
and phase 11) still emits an aggregate copy of the tail's
`Result<(), Full>` into the block's result slot. That slot was never
allocated.

```nl
fn main() {
    var xs: list<int, 3> = list {}
    let c: bool = true
    if c { xs.push(1) }
    print(xs)
}
```
- stage 0: `[1]`
- selfhost: `shc` exits 0, then `link-ir` fails: `out.ll:51: error: use of undefined value '%agg.13'` in `call void @nl.copy.8(ptr %nl.ctx, ptr %agg.13, ptr %agg.11)`.

The same failure happens with `if c { xs.push(1) } else { xs.push(2) }`
(`p_tail1`) and in `p_ifelse_push` (`xs.push(1); if c { xs.clear() } else { xs.push(2) }; xs.push(3)`,
which stage 0 runs and prints `[1, 2, 3]`). A proven push as a
*function-body* tail (`fn g() { …; xs.push(1) }`) works. `for` bodies work,
because the fixtures cover them.

Fix: in `emit_expr_linear`, Block phase 11 (compiler.nl, around 9336-9360),
treat a tail with `FACT_PROVEN_SUCCESS` as a discarded statement. Evaluate
it and do not copy a value into the block slot. The same applies to any
`If` or `Match` result slot the parent uses.

### H2. Statement kinds other than Let/Assign/ExpressionStatement/Expect/Return/Break/Continue are silently dropped inside blocks lowered by `emit_expr_linear`. This hits `discard`, `for`, `for each`, `while` and nested `{}` inside any `if` or `match` arm. CONFIRMED (valid programs, wrong output)

In `emit_expr_linear`, the block-statement dispatch (compiler.nl, around
9261-9335) ends with `} else { compiler.expr_work[frame_index] = frame }`.
Any other statement kind is skipped and emits no code. Statement `if`
bodies and match-arm blocks go through this path.

```nl
fn main() {
    var xs: list<int, 3> = list {}
    let c: bool = true
    if c { discard xs.push(1) }
    print(xs)
}
```
- stage 0: `[1]`
- selfhost: `[]`

```nl
fn main() {
    let c: bool = true
    var j: int = 0
    if c {
        for k in 0..3 { j += 1 }
    }
    print(j)
}
```
- stage 0: `3`
- selfhost: `0`

The `while` forms are also wrong against DESIGN. `if c { while j < 3 { j += 1 } }`,
a `while` in a match arm, and a `while` inside an `if`-expression block all
print `0` where the answer is `3` (`w_stmtif`, `w_match`, `w_expr`). Stage 0
rejects `while`, so DESIGN is the reference for those.

The bigger package `q_discard` (`discard` in an `if`, a nested `{}` block
in an `if`, a `for` in an `if`, a `for` in a match arm) gives stage 0
`[1, 2, 3]` and selfhost `[]`.

Pre-existing: the parent commit's compiler gives the same wrong results for
the `for` and `discard` forms. E3b's scope makes it urgent, for three
reasons. `discard` "in full" is an E3b item. The new no-`else` statement
`if` makes this path the normal one. And every `while` inside a branch is
lost. No fixture covers any of these forms, so the comparison suite passes.

Fix: in the `emit_expr_linear` block dispatch, lower `Discard`, `For`,
`ForEach`, `While` and nested `Block` statements. The simplest way is to
reuse `emit_function_body`'s statement lowering. Until then, set
`compiler.ir_overflow = true` (fail loudly) instead of dropping the
statement. Add fixtures for each kind inside an `if` and a match arm.

### H3. An array literal starts a count fact, so selfhost accepts unused pushes that stage 0 rejects. CONFIRMED

compiler.nl, Let handling (around 5468-5474) sets
`collection_count = count_children(...)` when a list is initialised from an
`ArrayLiteral`. The spec (E3 "Proven pushes") says a fact starts at 0 only
from `list {}` or a default. Stage 0 has no fact there.

```nl
fn main() {
    var xs: list<int, 3> = [1]
    xs.push(2)
    print(xs)
}
```
- stage 0: rejects, `main.nl:3:5: error: this collection operation returns a Result with error type Full; …`
- selfhost: `[1, 2]`

The push is safe at run time here, because the count is exact. But this is
a program stage 0 rejects and selfhost accepts. It also makes C1 and C2
reachable from literal-initialised lists: `p_ifclear` uses `[5]`. Ranked
high because it breaks the stage-0 acceptance contract for a very common
initialiser.

Fix: delete the `ArrayLiteral` branch, so the count is -1, unless stage 0
is changed deliberately and the change is pinned.

---

## MEDIUM

### M1. With an unsuffixed literal on both sides of a bitwise operator or shift, the operator ignores the expected type. `let c: long = 1 << 40` is rejected. CONFIRMED (valid program)

`body_child_expected` (compiler.nl:4523-4528), branch `op >= 16 && op <= 20`:
when the other operand is an unsuffixed literal, its natural type (`int`)
wins over `frame.expected`.

```nl
fn main() {
    let c: long = 1 << 40
    print(c)
}
```
- stage 0: `1099511627776`
- selfhost: `main.nl:2:19: error: expected long, found int; cast explicitly with (long)value`

Mixed cases work and match stage 0: `1 << n`, `n << 2`, `n & 3` and `6 | n`
with `n: long` print `32`, `20`, `1` and `7`.

Fix: when both operands are unsuffixed integers, use `frame.expected`
(int or long) first, then the other side's natural type.

### M2. An unsuffixed literal in a comparison against a `long` is rejected. CONFIRMED (valid program; pre-existing)

```nl
fn main() {
    var l: long = 3000000000
    print(l == 3000000000)
    print(3000000000 == l)
    print(l > 2)
}
```
- stage 0: `true`, `true`, `true`
- selfhost: `main.nl:3:11: error: expected int, found long; cast explicitly with (int)value`

The parent commit fails the same way. This falls under E3b's "unsuffixed
literals take their type from context" item, so it is listed here.

Fix: in the comparison branch of `body_child_expected` (around 4510-4520),
give an unsuffixed literal the other operand's natural type, as the
arithmetic branch already does.

---

## LOW

### L1. The while step budget is one counter per function frame, shared by all its loops and never reset. CONFIRMED behaviour; whether it is wrong is a spec question

`emit_function_definition` and `emit_test_definition` (compiler.nl:9974,
10063) allocate one `%while.steps` per function. Every `while` in that
function adds to it, and nothing resets it.

- `w_two`: two separate `while i < 6000000 { i += 1 }` loops in `main`. The first prints `6000000`, then the second fails with `main.nl:6:5: loop step budget exhausted`.
- `w_nested`: `for k in 0..100 { var j = 0; while j < 200000 { j += 1 } }` fails, even though each `while` runs 200,000 steps.
- Moving the same `while` into a helper function gives it a fresh 10M budget on every call.

So the budget is neither per loop, as the report's "a while loop gets a
10,000,000 step counter" says, nor per job, as DESIGN's job-context step
budget suggests (DESIGN, around line 502). The manager should decide which
is meant. Then either reset the counter at each `while` entry (per loop),
or move it into the context (per job).

### L2. PLAUSIBLE: `?.` receivers named by a place are read after the arguments run

`emit_optional_call_invoke` (compiler.nl, around 8250) reads the receiver
payload from the receiver's place *after* the arguments are evaluated. The
tag is checked before them, in `emit_optional_call_start`. If an argument
could change the receiver, the tag and payload would disagree. I tried
`o?.scale(clear_it(o))` with `clear_it(o: write Option<int>)` setting
`o = none`. Stage 0 and selfhost agree (`some(8)`, then `none`), so I could
not trigger this. It is risky code: it relies on the argument lowering
never writing through the receiver's place before the call. Copying the
receiver payload into a temporary right after the tag test would close it.

---

## Stage-0 note (not a selfhost finding)

Stage 0 itself has an unsound proven push in two shapes. Selfhost matches
it, as the contract requires.
- `p_loopclear`: `var xs: list<int,1> = [5]; for i in 0..0 { xs.clear() }; xs.push(7); print(xs)` prints `[5, 7]`.
- `p_matchclear`: `match o { some(v) => xs.clear(), none => () }; xs.push(7)` with `o = none` prints `[5, 7]`.

In both, a capacity-1 list gets two elements. This is worth a stage-0
reference fix (join the counts at `match`, and use `max(before, after)` for
a loop that may run zero times), with a fixture.

## Checked and found matching (no finding)

- `push`/`insert` at capacity return `err(Full)` and leave the list unchanged. `pop` with `??` and with `match`. `pop()` called twice in one argument list together with `count()` (`pair(xs.pop(), xs.pop(), xs.count())` gives `some(3)`, `some(2)`, `1` in both compilers, so the order is left to right).
- `?` store-back for `write` parameters: a struct with a list field, `?` on `Option` in a function returning `Option`, and `?` inside a `for` inside a `write` function. All match stage 0, including under forced relocation.
- Sums over 4 KB: `enum Big { Data(Wide), Pair(int, Wide) }` with `Wide = long[513]`, held as locals, reassigned, put in `Result<Big, Full>`, and passed through `?.` chains (`o?.bump(7L)?.bump(1L)`). Also `list<Option<Huge>, 2>` with a 520-field struct: push past capacity, `pop ?? none`, field reads. All match stage 0, including with `NLC_TEST_STACK_FORCE_MOVE=1`.
- Shifts: `3 << 31`, `-8 >> 1`, `1L << 63` and `a << 32` (fails with `bad shift`) match stage 0 exactly.
- `if`/`else if` without a final `else` used as a value is rejected with real text.
- Unsuffixed `long` context in `let`, call arguments, struct fields, list literals, returns and `+=` works. `let x: int = 3000000000` is rejected.

## Scratch

All scratch work was under `/mnt/d/tmp/opus-e3b/` and has been deleted.
