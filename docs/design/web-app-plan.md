# Web app target (plan, 2026-10-30)

Goal (Ben): a web app where a request comes in, an optional cache is consulted, data is pulled from a database,
adjusted a little, formatted through a template, and returned as HTML or JSON. SQLite first; external libraries
are fine for the database and for HTTP.

## Pieces and where they come from

| Piece | Source |
| --- | --- |
| Worker threads, service jobs, mailboxes, reply slots | core (docs/design/mailboxes.md); `env.host()` is done |
| Sockets, accept/read/write, waiting without blocking a worker | `Net` capability: thin layer over `epoll` (Linux) and IOCP (Windows) in the C runtime |
| HTTP request parsing | picohttpparser (single file, MIT) behind the `Http` capability; response writing in next-lang |
| Database | SQLite amalgamation (public domain) as its own translation unit behind a `Db` capability; typed queries, one wait per `db.read { }` |
| Cache | an ordinary service job owning a bounded map; reached through its tagged mailbox with reply slots |
| Templates and JSON | next-lang library appending into a bounded output buffer |

## Order, each step ending in something that runs

1. Mailboxes and a worker pool: `mailbox<T, N>` with many senders, `spawn service`, single worker first, then several.
   Demo: a cache job answering several request jobs; checksum equal to a single-threaded run.
2. `Net` and a blocking echo server on one worker. Demo: `curl` receives bytes.
3. HTTP parse and respond on one worker, with routes such as `GET /thing/:id`. Demo: a JSON answer.
4. Suspend-on-I/O and the worker pool: many connections served by few threads.
5. SQLite: typed queries, a writer job and read jobs. Demo: a request returns rows.
6. The whole pipeline: request, optional cache, database, adjust, template, HTML or JSON.
7. Limits: reply-slot pool size as the busy limit (503), deadlines on waiting jobs, closed mailbox ends on failure.

Each of steps 4 and 6 gets a benchmark against a small Rust server doing the same work.

## Decisions taken

- SQLite is the first database; HTTP/1.1 only at first, with TLS left to a reverse proxy.
- JSON output is built by formatting into a bounded buffer first; a typed builder can follow.
- Native code is reached through capabilities, not a general `extern fn`.
