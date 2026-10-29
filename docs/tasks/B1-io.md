# B1: compiler-used I/O with the existing C runtime

The own-source probe after builders and ordinary recursion stops at
`collections.nl:488:10: type Env`. Ben chose the existing C runtime for the
first self-hosted compiler (2026-10-28). Implement the checker/emitter support
needed to reuse it; defer the core I/O port. Rust Stage0 stays unchanged.

## Scope

Recognize the existing Env/Fs/Out/Args/Arg values, Path, DirEntry, FileKind,
and IoError. Add only the compiler-used operations: argument count/get and byte
access; Env fs/out/err/exit; extension-filtered listing; join; bounded Bytes
read; one complete file write; and Out.write. Reuse `runtime/nl_runtime.c`.
Do not add new language features, general effect machinery, or runtime services.

Add explicit `--runtime=c`, C startup/link metadata, and the declarations and
small adapters required by the current emitter's internal calling convention.
Language functions keep their current context/top parameters. C calls use the
frozen C signatures. Existing core output remains available for previous tests.
After the seed, clang links the generated compiler without the Rust driver.

## Boundary details

Preserve general native value layouts. Convert only at the C I/O boundary:

- Raw input modes are 0 list<byte>, 1 Arg, 2 a data-pointer/length descriptor
  for Ascii/Text/Bytes. There is no mode 3.
- List bytes occupy i32 lanes; packed Bytes uses one byte. Path is
  list<byte,4096>, size 16392.
- C's Result<Path,IoError> has payload at 4; the current compiler's aligned
  layout uses 8. Adapt success and error payloads, rather than change all sums.
  Result<(),IoError> already agrees: outer tag 0, IoError tag 4, errno 8.
- C directory names occupy 16392-byte slots. The native list<DirEntry,N>
  groups name lengths at B+8+i*8 and bytes at B+8+N*8+(i*4096+j)*4.
  The kind lane agrees at B+8+N*16392+i*4. Save live lengths and move live
  payloads in descending order, then publish the native length lane. This
  needs only a small length scratch, not a second capacity-sized entry list.
- Raw C set-top rejects a top beyond its reservation. The current core slow
  path publishes the top before growth; C mode must reserve through its
  existing public allocator before publishing the new top.

The attempted core I/O port is preserved outside the active checkout diff;
it is not a prerequisite and is not part of this implementation.

## Validation

Three focused argument/output, file-workflow, and record-field fixtures have
frozen C oracles, including a manual two-argument run and forwarded writable
list/buffer parameters. Build a fresh seed, validate C output at
O1/O3, then probe the compiler's source again. Run the full staged checks before
push. The stage-chain harness links stages 2 and 3 directly with clang and the
C runtime and compares IR/binary identity. Its claim is separate from compiler
corpus correctness and benchmarking.
