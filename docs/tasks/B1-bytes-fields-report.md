# B1 Bytes-field collection prerequisite

Status: implementation and validation in progress. Luna/max subagents own
source and test implementation; Sol coordinates debugging and review.

## Goal and scope

At `928d394`, the compiler's own-source probe stops at
`collections.nl:18:12: text in collections`. The parameter is
`files: list<SourceFile, MAX_SOURCE_FILES>`; `SourceFile.name` is
`Bytes max 4096` alongside seven long fields. The bounded task is direct Bytes
fields in non-nested struct collection elements, preserving existing lane
geometry and relocation/publication rules.

Direct text elements, Ascii/Text fields, nested collections, and text sum
payloads remain deferred. Builders, I/O, recursion, and the B1 stage chain are
separate remaining dependencies. Stage0 and existing fixture contents/oracles
remain unchanged.

## Implementation

`deferred_text.nl` admits direct Bytes fields at the collection/struct boundary
without admitting other text paths. `collections.nl` routes Bytes leaves through
live-length copy/equality helpers for storage, gathering, movement, literals,
fill, printing, and copies. Bytes-bearing values bypass whole-buffer memcpy
shortcuts. `compiler.nl` applies the per-element Bytes slot stride in local,
field-path, view, and parameter-descriptor addressing. The existing Bytes helper
in `text.nl` skips exact-pointer self-copy; the change is Bytes-only.

Existing layout constants, context ABI, and field-lane geometry are unchanged.
Odd capacities 3 and 17 exercise unaligned slots and distinguish field stride
from padded whole-record size. SourceFile's name lane still reserves 1,050,624
bytes; that is a static layout calculation, not measured resident memory.

## Focused validation

All seven new packages pass at O1/O3 against the explicit release reference:
one matching build, one real diagnostic, and five unsupported-shape gates.
The records fixture checks empty/short/4096-byte names, odd-capacity fields,
nonzero indexes, readonly list/array parameters, a write-list parameter,
foreach views, whole-record gather/printing, independent copies, equality,
insert/remove/pop, empty pop, clear/refill, and zero-capacity count/copy.
The unsupported cases retain direct Bytes elements, Ascii/Text fields, nested
collections, and sum-payload collection elements behind their gates.

An O1/O3 audit of 28 related unsupported packages also passes unchanged.
The complete matrix found one additional promotion: `tests/run/t16_view_shift`
now reaches its real live-view insertion diagnostic, matching the frozen
compiler's rejection. Its classification moves from unsupported to diagnose;
its source and oracles remain intact. The earlier staged attempt stopped on
that stale row after 506 seconds and is not passing acceptance evidence.
Formatting, Python syntax, and diff checks pass. Independent Sol review covered
all four indexed-address paths, helper propagation, bypass exclusions, live
slots, and self-copy. No further concrete source defect was found.

The invalid field assignment is rejected at the correct source position. Its
aggregate expected type is displayed as `never` by the pre-existing scalar-only
type-name fallback; this wording limitation is not pinned as an exact oracle.
The actual Bytes type check remains enforced. Frozen Stage0 also cannot print
the zero-capacity record list, so its reference-backed test covers count/copy
rather than that pre-existing printer failure.

## Relocation evidence

The final relocation selector passes at both O1/O3 and requires a positive move
for this exact records package. Selfhost IR shows main reserves 329,941 bytes,
which grows the forced 4,096-byte reservation to 524,288 bytes. After four rows
are populated, including the maximum name, `check_after_move` reserves another
362,592 bytes. Its requested end is about 692,533 bytes, so it forces another
growth while the caller's populated list is live. Its 300,008-byte scratch list
accounts for most of that frame. Other pre-call growth requests fit in 524,288.

The forced run reports `initial=4096 reserved=1048576 peak_used=696712 growths=2
relocations=2`. Stack verification passes and output matches the 1,652-byte
reference output. Subsequent field reads, equality, and copies resolve through
the moved context base. These are correctness statistics, not compiler benchmarks.

## Own-source probe and next task

The fresh source-keyed compiler
`cd3895637cf8aa613b3fe51bffaf39740f55d54d804606552e035c39702e4e94`
now exits 2 without IR at:

```text
collections.nl:107:1: error: not supported by the self-hosted compiler yet: generic or recursive functions
```

The declaration is recursive, so source-used recursion is the next demonstrated
prerequisite. Current source census: 212 constants, 76 recursive declarations,
and 201 grow-Bytes annotations. Builders and I/O remain later dependencies.
The required full staged-suite result will be recorded before landing.
