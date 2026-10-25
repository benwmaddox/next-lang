You are implementing next-lang, task T15 (append mode and loop growth), fix round 1. Repo: /mnt/d/code/next-lang. Read docs/tasks/T15-append-and-loop-growth.md and docs/tasks/T15-report.md. Same rules: do not commit, do not create, switch or stash branches, do not edit docs/DESIGN.md, docs/PLAN.md, docs/EXAMPLES.md, docs/reviews/ or docs/research/, use CARGO_TARGET_DIR=$HOME/.cache/next-lang/target, no external crates.

Reviewer finding: you extended `??` to `Result<Ascii, E>` because the task's correction example used `field(x) ?? return ok(())`. That example was the reviewer's error. DESIGN.md (the `??` rule) says `??` works on `Option` only; a `Result` is handled with `match` or passed up with `?`, so an error can't be silently replaced by a default. A special case for Result-Ascii only is also inconsistent. The task file's example (line 67) is now corrected to:

    match field(x) { ok(f) => buf.try_append(f), err(_) => ok(()) }

Fix: remove the `??`-on-Result extension entirely, so `??` on any `Result` is a build error saying to use `match` or `?` (check the existing message for this case and keep it consistent). Update the T15 fixtures to the `match` form, and make sure the `match` form still streams in append mode where the task requires it (or say precisely when it materialises first and why). Keep all other T15 behaviour.

Run cargo build, cargo test and cargo fmt -- --check (and the parse-dump update script if fixtures change). Append a "Fix round 1" section to docs/tasks/T15-report.md.
