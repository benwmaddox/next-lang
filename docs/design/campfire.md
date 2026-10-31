# Campfire in next-lang: plan and friction log (2026-10-31)

Goal (Ben): an idiomatic Campfire in next-lang, to see whether it can mimic all of Campfire's behaviour and still be fast, and to
collect the awkward code and the things that have to be fixed again and again. Status: plan only; nothing is built.

## What "Campfire" is here

ONCE Campfire (37signals, MIT), Rails commit 90b3300. References already in `D:\code`:

| What | Where | Size |
| --- | --- | --- |
| crudspec's version, the whole app as one spec | `crudspec/apps/campfire/campfire.crud` | 1,778 lines; 10 entities (User, Session, Room, Membership, Message, Boost, Ban, Search, PushSubscription, Webhook), about 45 actions, 15 screens, many components, workflows, a bot API, presence and typing channels |
| Route-by-route map of Rails to the spec | `crudspec/apps/campfire/docs/COVERAGE.md` | every route, channel and job |
| The behaviour oracle | `crudspec/apps/campfire/oracle/` | 42 scenarios (JSON) and the Rails golden files |
| Burin's version | `burin/apps/campfire` | precomputed pages, one writer |
| Rust port, Rails app | recorded in `crudspec/bench` | the performance reference |

crudspec's server side is 1,828 lines against Rails' 6,964 and the Rust port's 49,143. Its speed is 79x Rails with no cache, 156x with
a full-page cache (WSL2, 4 cores, the Campfire room page).

## Why we are doing it (Ben, 2026-10-31)

The process is to test whether the language is **useful** and has a **good developer experience**. Campfire is the test
subject, not the product. So alongside "does it match Rails and is it fast" each slice reports developer-experience measures,
and a snag is a finding even when the code ends up working:

- **Edit-build-run loop:** seconds from saving a change to seeing it run (the compiler, the generators, linking), and the
  time of the test run.
- **Error quality:** for each mistake made while writing (and a few made on purpose), whether the message names the place,
  says what is wrong and what to do; a bad message is logged like any other snag.
- **Size and shape:** lines of next-lang per slice against crudspec's and Rails' for the same behaviour, how many generated or
  non-next-lang files are needed (Python generators, shell, SQL), how many places a change touches.
- **Repeated fixes:** the same mistake or workaround appearing again is counted; three hits means a language or library fix.
- **Confidence:** what the compiler caught before the program ran (build-time query check, template bounds, service checks)
  against what was found by running it.
- **Findings feed back:** the friction log is read at the end of each slice and the top items are fixed in the language before the
  next slice starts, as was done for the first six.

## How to judge it

- **Behaviour:** the 42 oracle scenarios. They are data (setup rows, actors, actions) with Rails' answers as goldens, and crudspec's
  replay driver (`test/replay-runtime.ts`) judges any server that speaks its two test endpoints (`/_test/load` to load the setup
  rows, `/_test/dump` to read state back). The next-lang app can implement those two endpoints in a `--test` mode and be judged by
  the same driver. To verify before relying on it: the exact row format the endpoints use.
- **Speed:** crudspec's `bench/` for the Campfire room page, same data, same four cores, same method (Rails, Rust port, crudspec,
  next-lang), requests per second and memory under load.
- **Awkwardness:** `docs/campfire-friction.md` (below), one entry per snag, with a count when the same one is hit again.

## What next-lang has and lacks for it

| Campfire needs | next-lang now |
| --- | --- |
| Request headers, cookies, query string, POST bodies (forms, JSON), file uploads | only method and target |
| Response status, headers (Set-Cookie, Location, caching), redirects | status, content kind, body |
| Sessions (random tokens), password hashing, CSRF, rate limits | none; crypto only from libraries (no own crypto) |
| SQLite reads | typed single-row `db_row`, checked against `schema.sql`; no multi-row results, no joins into structs, no writes, no transactions, no migrations |
| Templates with loops, components, layouts, forms, flash | HTML/JSON templates with holes and `if`; no loops, components or layouts |
| Rooms, membership, roles, involvement, unread, bans | application logic; the services model fits (a service per room?) |
| Live updates (new messages, unread dots, presence, typing) | no server push (SSE or WebSocket), but mailboxes and services give the fan-out |
| Search | SQLite FTS5 is available in the vendored amalgamation (needs the flag) |
| Link previews, webhooks, web push | no outbound HTTP client |
| Attachments, avatars, logos | no file storage |
| Rich text: @mentions, autolink, sanitising | libraries to write (bounded text functions) |
| Time, scheduling | `now_ms`, timers, `tick` |

## Slices, each ending in scenarios that pass and a measurement

1. **Reads.** `schema.sql` from the spec's entities; multi-row typed queries (`list<Row, N>`); template loops; `GET /` and
   `GET /rooms/:id` for a signed-in user whose identity is given by a test header. Measure the room page against the references.
2. **Identity.** Request headers and cookies, `Set-Cookie`, sessions table, sign-in and sign-out, password check through a
   library, first run, ban by IP. Oracle sets `a01`-`a03`.
3. **Writes.** POST bodies, redirects, `db` writes with transactions; post, edit and delete messages; join, rooms (open, closed,
   direct), membership, roles. Sets `d`, `g`, `m`, `p`, `r`.
4. **Live.** Server push (SSE first), a service per room for fan-out, unread and involvement, presence, typing. Sets `u`, `m`.
5. **Admin and bots.** Account, users, bot API with keys, webhooks (needs an outbound client), push.
6. **Extras.** Search (FTS5), boosts, link previews, attachments, avatars.

Slices 1-4 are "core chat" and cover the 25 `slice-v1` scenarios; 5-6 cover the 13 `v2-areas` scenarios. I would stop to measure and
review friction after slice 3 and again after slice 4.

## Rules for the implementation

- Idiomatic means: services for the things that own state (rooms, the cache, presence), tasks for connections, typed queries,
  templates, build-time checks; no escape hatches written in C for application logic.
- The compile-time and allocate-at-startup principles apply (`web-usability.md`): sizes declared, pools made at startup,
  exhaustion visible.
- A capability added for Campfire must be generic (a request model, a response model, a transaction) and tested on its own.

## Friction log

`docs/campfire-friction.md`. Seeded with what the web work so far already hit (below); every entry says where it was hit, how
often, and what would remove it (a language change, a library, a tool, or nothing).
