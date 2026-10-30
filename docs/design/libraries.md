# Core and libraries (direction, 2026-10-30)

Ben's goal: next-lang is a small core, and different libraries serve different uses (web apps, games, CLIs).
Prefer libraries that complement the stack and arena memory model.

## Layers

1. **Core:** the language, the compiler, the stack/arena memory model, bounded collections (list, map, pool,
   mailbox), text and numbers, and the two C runtimes (Linux, Windows). Nothing domain-specific.
2. **Capabilities:** the values a program is *handed*: `Fs`, `Out`, `Host`, and next `Net`, `Db`, `Clock`. A library
   can do I/O only through a capability its caller passes in. The runtime implements them; C libraries such as
   SQLite sit behind them.
3. **Libraries in next-lang:** packages with a manifest (DESIGN.md, "Using another package"), written in the
   language using arenas and bounded types.
   - Web: HTTP parsing and responses, routing, templates, JSON.
   - Games: input, a per-frame arena, math, asset loading, audio mixing.
   - CLIs: argument parsing, terminal output, file walking.
4. **Native wrappers:** small separately compiled C pieces for things not worth rewriting (SQLite, an HTTP
   request parser, TLS, image decoders, a windowing/graphics layer). Each is exposed through a capability or a typed
   API, never as a general foreign-call hole. They are linked only when a program uses them.

## What "complements stack and arena memory" means

A library should be accepted, or written, only if it passes these checks:

- **Bounded by declaration:** every buffer, result and queue has its maximum in its type. A library that needs an
  unbounded general heap is out, or wrapped so growth stays inside a declared cap.
- **Scope-shaped lifetimes:** work belongs to a request, frame or command and is freed by one reset.
- **Copy across boundaries:** data crossing a job, mailbox or native call is a flat copy, not a shared pointer.
- **No hidden allocation or global state:** a library takes its working memory as a parameter (`write`/`grow` buffers
  or an arena), as `Fs.read` fills a caller's buffer.
- **Checkable cost:** the compiler can bound stack use, so libraries avoid unbounded recursion and loops, or declare a
  step budget.

## Fit by domain

| Domain | Memory shape | Notes |
| --- | --- | --- |
| Web | request arena, reply slots, fixed pools | parsing into fixed buffers, SQLite rows read one at a time into the request arena, templates appending to a bounded output buffer |
| Games | per-frame arena reset every frame, fixed entity pools | plain-record layouts suit tight loops (audio, physics); rendering needs a native wrapper (for example SDL3) |
| CLIs | one arena for the whole run | the simplest case: args, files and text |

## Open decisions, in order

1. **Native code in a package:** a manifest section naming C sources and the capability they expose, compiled only
   when used. To be written with the SQLite capability, the first real case.
2. **Distribution:** start with libraries referenced by path or git tag; a registry comes later.
3. **Capability granting:** a library's manifest lists the capabilities it may be passed; `main` grants them.
4. **Versioning:** a minimal compatible-version rule once there is more than one library.
