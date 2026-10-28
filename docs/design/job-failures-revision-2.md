# Job failures and future memory-cap policy, revision 2

**Status:** discussion draft. Failure rules below are a confirmed future policy
if a configurable arena cap is implemented. Cap enforcement and typed handler
dispatch are deferred, not B1 prerequisites. The current core-managed data
stack starts at 256 KiB and grows/moves with overflow and OS-failure guards; it
has no configurable hard cap or job-level exception runtime. Collection caps
and test limits are not a whole-run arena cap. API names, payload fields,
handler storage, and runtime mechanism remain proposals or open questions.

## Confirmed future execution rules

- If a hard arena cap is added, its rare exhaustion ends the current run with a
  typed `MemoryLimit` exception. Memory reservation does not return a `Result`
  per allocation; logical collection-capacity results stay separate.
- Catching happens only at the job boundary. Every handler names the exact
  exception type. There is no bare catch and no function-level `try/catch`.
- Writes to persistent job state that completed before failure remain. There
  are no snapshots, undo, or automatic rollback. The failed run's arena is
  released in bulk; no partially produced function return value is delivered.
  Existing record-field invariants and validation rules are unchanged.
- The failed run is not retried or resumed. One instance processes one run at
  a time; parallel work uses more instances.
- Exception capture and reporting must not require a general heap, garbage
  collector, borrow checker, or loan/move/inferred-ownership/lifetime analysis.
  Scope planning, arena reset, and explicit bounded storage remain ordinary
  compiler work. The backend mechanism for capture and reporting is not selected.
- Mailbox `FULL` remains an explicit send status. Logical collection `Full` is
  separate; its policy is unresolved and is not promoted to an exception here.

## Illustrative shape

The worker uses ordinary local storage backed by the run arena. There is no
per-allocation `Result` or `unwrap` path:

```text
struct WorkerState { completed: long; }
struct Request { value: byte; }

function worker_job(state: WorkerState, request: Request): void {
    var scratch: byte[4096]; // ordinary run-local storage
    scratch[0] = request.value;
    state.completed = state.completed + 1L;
}
```

`main` registers a handler for a selected set of workers. The exception type is
an explicit job-configuration value, not a general catch-language construct.
The handler receives a typed payload with scalar fields:

```text
struct MemoryLimit {
    job_id: int;
    requested_bytes: long;
    cap_bytes: long;
}

function report_memory_limit(event: MemoryLimit): void {
    report_limit(event.job_id, event.requested_bytes, event.cap_bytes);
}

function main(startup: StartupInfo): int {
    let worker_count = min(configured_workers, startup.grant_cores);
    let workers = create_job_instances(worker_job, worker_count, configured_cap);
    set_exception_handler(workers, MemoryLimit, report_memory_limit);
    return 0;
}
```

All type fields and API names are illustrative. The example does not select how
the handler obtains memory or I/O resources, how the runtime stores its payload,
or how the operating system implements capture. It shows typed job-level
configuration without a general `catch` DSL.

## Deferred questions for a future handler implementation

1. What bounded memory and output budget is available to the handler after the
   failed run has reached its cap? May it use a separate reserved region?
2. What happens if the handler itself fails, reaches a limit, or cannot finish
   reporting? Keep the behavior explicit without adding GC or a borrow checker.
3. After handling `MemoryLimit`, what may `main` do with that instance? Reuse,
   retire, and replace behavior remains open; no instance-lifecycle policy is
   selected here.
4. Which future failures, if any, become typed job exceptions? In particular,
   whether OS `ENOMEM` maps to `MemoryLimit` remains open; OS errors such as
   `EINTR` retain their ordinary error information. Mailbox and collection
   `Full` policies remain separate questions.

Handler allocation, instance replacement, and OS error mapping are not selected
here. There is no automatic retry of the failed run.
