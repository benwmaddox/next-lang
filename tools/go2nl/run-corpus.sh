#!/usr/bin/env bash
# Build go2nl and run the Go-vs-next-lang oracle corpus against stage 0 nlc.
# NLC defaults to a stage 0 built from this checkout (see README.md).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
NLC="${NLC:-$HOME/.cache/next-lang/target-go2nl/release/nlc}"
OUT="${OUT:-$HOME/go2nl-out/corpus}"
mkdir -p "$HOME/.cache/go2nl"
(cd "$here" && go build -o "$HOME/.cache/go2nl/go2nl" .)
ulimit -v 8000000
cd "$here/../.."   # nlc reads runtime/ from the checkout
exec "$HOME/.cache/go2nl/go2nl" corpus -dir "$here/corpus" -nlc "$NLC" -out "$OUT" "$@"
