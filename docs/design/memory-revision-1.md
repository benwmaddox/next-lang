# Memory model, revision 1

**Status:** discussion draft; not adopted. Confirmed directions are per-instance
static-state lifetime, a movable per-run data arena with a cap, startup resource
grants, one run at a time per instance, and explicit `FULL` mailbox-send status.
Syntax, APIs, and the other rules below remain proposals; the examples are not
supported by the current next-lang compiler.

The proposal follows Stasis's function/view/result style (`docs/spec.md`
sections 7.1 and 7.5; language quick reference, Storage).

## Proposed baseline

- A job instance may own an optional, fixed-layout static region. Its values
  persist across runs of that same instance. The layout is chosen when the
  instance is created and does not grow during its lifetime.
- Each run gets a temporary bump arena. Ordinary locals and short-lived
  workspaces may use it without a source-level allocation call. Scope exit
  restores the arena mark; run completion resets the whole arena.
- The data arena may move while growing, up to a configured cap. Its offsets
  are runtime details: source code continues to access fields and array
  elements by name and index. This says nothing about moving the native call
  stack, which remains unchanged. Arena addresses are not exposed as a way to
  retain run-local data.
- Static fields contain fixed-layout values, never views into the run arena.
  To keep run-produced data, copy it into caller-provided static output.
- Fixed-size arrays keep an explicit length/count and check every index. There
  is no implicit append or unbounded-growth contract in this baseline.
- There is no per-object `free`, move or ownership/lifetime system, generic
  allocation API, or new allocation keyword. Bounded containers remain
  available; pools, free lists, and shared snapshots can be considered when a
  concrete need appears. Recursion remains deferred.

## Passing, results, and failure

Proposed observable rules:

- Scalars copy when assigned, passed, or returned.
- A named struct or array parameter is a caller-backed view. Field or element
  writes are visible to the caller, and the parameter binding cannot be
  redirected to another object.
- Functions return scalars or `void`. A named-struct result uses a caller-owned
  output parameter; named structs and arrays of named structs are not returned
  by value.
- A run-arena view cannot be saved in static state. A routine that needs a
  persistent result copies its contents into fixed static storage explicitly.
- Invalid indices remain errors. Bounded operations check capacity before
  writing; the examples below leave outputs unchanged when they return `false`.

The overflow policy for arena exhaustion is unresolved: should it return a
checked `bool` from an ordinary operation, or fail the job with a diagnostic?
This draft adds no propagation operator or hidden error channel.

## Sketches

These use the Stasis-style `function name(args): ReturnType` notation as a
proposal, not a selected next-lang syntax. Job-storage binding syntax is
intentionally omitted and remains open.

### Parse into caller-owned output

```text
struct ParsedNumber { value: int; }

function try_parse_decimal(input: u8[], out: ParsedNumber): bool {
    if input.length == 0 { return false; }
    var value: int = 0;
    for i in 0..input.length {
        let digit = input[i] - '0';
        if digit < 0 || digit > 9 { return false; }
        if value > (INT_MAX - digit) / 10 { return false; }
        value = value * 10 + digit;
    }
    out.value = value;
    return true;
}
```

The locals are temporary run data. Validation finishes before `out` changes;
the caller can bind `out` to fixed job storage or another owned result.

### Bounded text output

```text
struct TextBuffer { length: int; bytes: u8[64]; }

function try_copy_text(input: u8[], out: TextBuffer): bool {
    if input.length > 64 { return false; }
    for i in 0..input.length { out.bytes[i] = input[i]; }
    out.length = input.length;
    return true;
}
```

The caller owns the fixed-capacity destination. The capacity check precedes
all writes; this routine's source and destination are distinct caller objects.

### Update persistent job state

```text
struct ScoreState { score: int; }

function try_add_score(state: ScoreState, delta: int): bool {
    if delta < 0 { return false; }
    if state.score > INT_MAX - delta { return false; }
    state.score = state.score + delta;
    return true;
}
```

Bind `state` to the instance's fixed static region. The update validates first,
then writes once, so a `false` result leaves this field unchanged. This is an
ordinary function contract, not an implicit transaction over the whole job.

## Startup and job coordination

The proposed program entry receives CPU information and a resource grant. The
grant describes what this program may use, may be a subset of the host, and
must not be mistaken for host totals. CPU details are exposed only as allowed
by the grant. `main` declares named jobs, chooses instance counts within that
grant, and connects triggers and bounded mailboxes. This is explicit setup,
not an automatic general-purpose scheduler.

```text
struct StartupInfo {
    cpu_info: CpuInfo; // opaque information filtered to the grant
    grant_cores: int;
    grant_ram_bytes: long;
}
struct Message { length: int; bytes: u8[256]; }

function worker_job(message: Message): void { /* handle one delivery */ }

function main(startup: StartupInfo): int {
    if startup.grant_cores == 0 { return 1; }
    let count = min(4, startup.grant_cores);
    let per_worker_cap = configured_worker_cap;
    if configured_runtime_reserve + count * per_worker_cap > startup.grant_ram_bytes {
        return 1;
    }
    let workers = create_job_instances(worker_job, count, per_worker_cap);
    let inbox = make_mailbox(Message, 8);
    connect_http_trigger("/event", inbox);
    connect_mailbox(inbox, workers);
    return 0;
}
```

All API names, types (including `CpuInfo` and `Mailbox`), configuration names,
and signatures are placeholders. The example uses configured caps and an
explicit runtime reserve; admission and headroom policy remain open. Each
worker instance keeps its static state across deliveries, and each delivery
gets a fresh run arena. Mailboxes copy bounded payloads into their own storage.

Each reusable instance runs one delivery at a time; parallelism comes from
creating more instances. A bounded send either copies the message and returns
`SENT`, or returns `FULL`. It never waits, drops, or retries implicitly; the
caller handles `FULL` explicitly. Capacity admission and payload publication
are one runtime operation, with internal synchronization for concurrent
senders. A `FULL` result leaves the message unsent and the inbox unchanged.

```text
function route(message: Message, inbox: Mailbox): void {
    let status = try_send(inbox, message); // one runtime operation
    if status == FULL { /* caller chooses an explicit policy */ }
}
```

`SendStatus`, `SENT`, `FULL`, and `try_send` are illustrative names, not
selected syntax. What happens to static state after a failed delivery remains
open; follow-up policy for `FULL` belongs to the caller.

## Decisions for revision 2

1. If a run fails after earlier writes to static state, are those writes kept,
   or is static state restored to its run-start value?
2. What should arena-cap exhaustion do: return a checked result, or fail the
   job with a diagnostic? How should callers handle that outcome?
