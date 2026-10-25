#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
target_dir="${CARGO_TARGET_DIR:-$HOME/.cache/next-lang/target}"
nlc="${NLC:-$target_dir/debug/nlc}"
max_seconds="${SELFHOST_PARSE_MAX_SECONDS:-2.0}"

if [[ ! -x "$nlc" ]]; then
    echo "nlc not found at $nlc; run cargo build first or set NLC" >&2
    exit 2
fi
if [[ ! -x /usr/bin/time ]]; then
    echo "/usr/bin/time is required for the selfhost benchmark" >&2
    exit 2
fi

work="$(mktemp -d "$repo_root/.selfhost-bench.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
work_relative="${work#"$repo_root"/}"
selfhost="$work/selfhost"
timings="$work/timings"
cd "$repo_root"

"$repo_root/scripts/gen-bench-corpus.sh" "$work_relative/benchmark" --parse
"$nlc" build selfhost -o "$selfhost"

for run in 1 2 3 4 5; do
    /usr/bin/time -f '%e %M' -o "$work/current-time" \
        "$selfhost" parse "$work_relative/benchmark" --tokens --tree >/dev/null
    read -r elapsed rss < "$work/current-time"
    printf '%s %s\n' "$elapsed" "$rss" >>"$timings"
    printf 'run %s: %s s, %s KiB RSS\n' "$run" "$elapsed" "$rss"
done

read -r best best_rss < <(
    awk 'NR == 1 || $1 < best { best = $1; rss = $2 } END { print best, rss }' "$timings"
)
printf 'best of 5: %s s, %s KiB RSS (limit %s s)\n' "$best" "$best_rss" "$max_seconds"
awk -v best="$best" -v limit="$max_seconds" 'BEGIN { exit !(best <= limit) }' || {
    echo "selfhost parse benchmark exceeded its time limit" >&2
    exit 1
}
