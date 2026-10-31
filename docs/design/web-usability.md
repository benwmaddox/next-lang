# What next-lang can take from crudspec and Burin for web apps (2026-10-31)

Sources read: crudspec's README, `lang/LANGUAGE.md` (views, screens, the checks list), its notes on column pruning and
the facts layer; Burin's `docs/DESIGN.md` (principles 1 and 5, "Loading only what a page uses", "Lessons kept").
The compilers themselves were not read. Our reference workload is `bench/web` (jobs, mailboxes, SQLite, JSON and HTML).

## What the workload does by hand today

- It loads a row with three SQL calls (`db_query` for the value, another for the price, `db_text` for the name). The
  SQL is a string, so a wrong column name or type is found at run time.
- It builds JSON and HTML with hand-written `push_*` functions, including escaping. Forgetting an escape is a bug the
  compiler cannot see; the body buffer's size (512) is a number someone picked.
- It parses `/item/<id>` and chooses the route by looking at bytes (`item_id`, `route_of`).
- Its shared cache never expires an entry; a write to the database would not reach it.
- Its request path is a cycle of bounded mailboxes (request, cache, database, cache, reply); nothing checks that it
  cannot deadlock.

## What to take, in order

1. **Typed queries with column projection** (crudspec: typed rows, pruning; Burin principle 5).
   A query is a declaration whose result is a struct; the struct is the projection. The compiler makes the select
   list from the struct's fields, so a smaller struct reads fewer columns, and a row decodes straight into the struct
   with no boxing: one round trip per row instead of one per column. Later: the SQL is checked against the schema when
   the program is built (SQLite prepares it against a database made from the schema), which also finds a missing column
   or a type that does not match.
   Measured value to expect: crudspec saw +45% on a page reading few columns and nothing where nearly all are read.
   Here the gain is mostly the round trips.
2. **Templates that compile to bounded straight-line code** (crudspec's HTML-in-source with `{expr}`, `{for}`, `{if}`,
   `{match}`; Burin's constant parts as static bytes). Escaping follows the context a value is in (element text,
   attribute, URL, JSON string), so it cannot be forgotten; tags and attributes are checked; script is refused. The
   output's maximum size is the sum of the pieces' maximums (the design already types `$"{id}:{name}"` that way), so a
   template that could overflow its buffer fails the build. Components with typed parameters and layouts with slots
   come after the basics.
3. **A typed route table with link checks** (crudspec's `LINK_ARGS`, `ROUTE_PARAM`, `ROUTE_SHADOWED`,
   `SCREEN_UNREACHABLE`): `GET /item/:id` with `id: long` parsed by the compiler, links built from route names, a
   route that an earlier one always takes is an error.
4. **Query cost checks** (crudspec's `QUERY_UNINDEXED`, `QUERY_SORTED`, `INDEX_UNUSED`): at build time ask SQLite for
   `EXPLAIN QUERY PLAN` of every declared query on the app's own schema. Cheap once queries are declarations.
5. **A message-topology check** (next-lang's own whole-app analysis; spawns happen from `main`, so the graph is
   static): who sends to whom, a cycle of blocking waits between bounded mailboxes, a `send` whose Full result is not
   handled, a mailbox end that is never closed.
6. **Invalidation from read sets** (Burin "Keeping precomputed pages right"): the compiler records which tables and
   columns each cached value reads; a write that touches them rebuilds or drops it; a write with no precise rule falls
   back to dropping everything (slower, never wrong); a background scrub compares cached values with fresh ones.
   Burin's rule that a cached piece never depends on the viewer already holds for `bench/web`'s cached bodies.

## What not to take

crudspec's entities, permissions, actions and screens as language kernel: next-lang is a general language, so these
stay a library and conventions. Invariant proofs (Z3), data migration and agent APIs are out of scope for now. The
facts table (crudspec `lang/facts.ts`) is worth copying only as far as a check needs it; the owner's verdict there was
not to grow it into a general DSL kernel.

## Step 1 plan: typed queries

1. `env.db_row(from_clause, key, row)`: the compiler passes a description of the struct `row` (each field's name, kind
   and offset, and a Bytes field's capacity); the runtime prepares `select <field names> <from_clause>` once per
   thread, binds `?1` to the key, and decodes the first row into the struct. Fields: `long`, `int`, `bool`, `Bytes`.
   Returns whether a row was found. Missing or NULL columns leave the field as it was.
2. Use it in `bench/web` (one query instead of three) and measure a cache miss and the whole workload.
3. Then: a query declaration syntax that names the query and its result type once, and the build-time schema check.

## Principle: as much as possible at compile time (Ben, 2026-10-31)

Everything above is a way to move work from run time to build time, and each new feature should be judged by what it
can fix before the program runs:

- **Queries are literals.** `Env.db_row` takes a string literal; the compiler writes the select list from the struct's
  fields, so the full statement is known when the program is built and each call site prepares it once (a constant
  identifies it; no text is built or compared per call). Next: the build prepares every query against the schema, so a
  missing column, a wrong type or a table scan is a build error (`EXPLAIN QUERY PLAN`, crudspec's `QUERY_UNINDEXED`).
- **Templates are straight-line code**: the constant text is static bytes, the output's maximum size is a sum known at
  build time, and a value is escaped by the context it sits in, chosen by the compiler.
- **Routes are a table**: patterns, parameter types and links are parsed and checked at build time; the program only
  matches and converts.
- **Topology is static**: the mailbox graph is known from `main`, so deadlock-prone cycles, unhandled Full results and
  unclosed ends are build errors.
- **Sizes carry through**: a field's declared maximum is the SQLite column check, the buffer size and the template's
  bound.
- **Read sets for caches** are computed from the declared queries, so invalidation needs no hand-written rules.

## Step 2 as built: templates (prototype, 2026-10-31)

`tools/tmpl.py` compiles `*.tpl` files in a package to `templates.gen.nl` (ignored by git) when `scripts/nlc` builds it.
Syntax: a header `html template page(row: Row, taxed: long) max 512` or `json template ...`, then the body; `{path}` and
`{path|money}` holes, `{#if bool}...{#else}...{#end}`, `{{` and `}}` for braces. Checked when built: parameter and field
names and types (structs are read from the package's `.nl` files), the largest possible output against the buffer size,
the escaping context of every hole (HTML text, quoted attribute, URL attribute, JSON string or value), and the
places a hole is refused (script, style, event attributes, unquoted values, comments, the start of a URL).
Not yet: loops over lists, components and layouts, nested templates, text that is not ASCII, inference of the right
escaping for a `Text` that is already HTML. The generator is Python so it could be tried on the real workload quickly;
the language rules above are the part to keep, and the generator should move into the compiler so templates need
neither Python nor a generated file.
