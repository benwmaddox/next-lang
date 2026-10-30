# Frozen runtime for stage 0

This is a copy of `runtime/nl_runtime.c` and `nl_unicode_upper.h` taken when the Rust compiler (stage 0) was
frozen. Everything the frozen compiler emits, and everything the self-hosted compiler emits for the core
runtime (which shares the core library's context layout, see `core/context.nl`), links this copy.

`runtime/nl_runtime.c` is the live runtime for programs the self-hosted compiler builds with `--runtime=c`,
and is free to shrink: do not edit this copy to match it.
