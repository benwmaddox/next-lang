# Layout divergences

Rule (Ben, 2026-10-29): data structures use inline layout, flattened wherever the design allows (DESIGN.md, Layout). A structure diverges from that only for a clear reason written here. This file is the list the planned review walks.

| Structure | Where it diverges from inline/flattened | Reason | Status |
| --- | --- | --- | --- |
| Nested collections | Stage 0 and the first self-hosted version store each nested collection's lanes inline per enclosing element, not flattened into shared lanes | Parity with stage 0 while the self-hosted compiler catches up (PLAN.md L1) | Temporary; flatten later |
| Text in collections above 64 bytes | Design uses size classes rather than inline | Avoids wasting memory on large bounds | Questioned by Ben 2026-10-29; rationale unknown; revisit (PLAN.md) |
| `queue` | (add when implemented) | | |
| Text in collections | (add when implemented) | | |

Add a row whenever a structure stores data outside its enclosing storage or leaves a nested collection unflattened.
