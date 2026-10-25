# Claude: T31 review (pointer-free collection text lanes)

**Verdict:** approved after one fix round (run in two sessions: WSL restarted mid-round, most likely because clang ran out of memory on the stress IR; the second session ran every large build under a memory cap).

Checked: cargo test passes (19 groups, under a 16 GB virtual-memory cap). Collection text lanes hold length (and code points) plus inline bytes up to 64 bytes, or a `{class, byte offset}` handle plus length above; no address is stored in a lane (an IR test checks), and slots are allocated, reused and freed by index. Small lanes save 8 bytes per element (`list<Row, 500>.name` 76 to 68 bytes). My probe: an 8,388,600-byte Ascii value pushed into `list<Page, 1>` (Page holding `Ascii max 8_388_608`), read back and copied, prints the right lengths.

Fix round 1:

1. The self-hosted parser and lexer had slowed (paired 0.23 to 0.28 s and 0.07 to 0.09 s): each large-field read decoded a class and slot and multiplied by the class size. Handles now store the byte offset from the collection base; both are back within noise.
2. The "clang crash" was clang exhausting memory on a packed collection type that held every size class inline as a first-class array (up to `[8388608 x i8]`). Class data is now one flat byte region addressed with `i8` offsets, and large values are never loaded or stored as whole aggregates: clang builds the 8 MB, 17-class stress case in 0.02 s and 80 MB. An IR test keeps the collection type a small metadata prefix.

Lesson for future tasks: run large stress builds under `ulimit -v` and `timeout`, so a runaway clang can't take WSL down.
