#!/usr/bin/env bash
# bench-vs-rust.sh [--time] [--selfhost] [pair...]
#
# For each bench/vs-rust pair: build the next-lang program with stage-0 nlc and,
# with --selfhost, with the self-hosted compiler (built from the committed
# selfhost/ at HEAD, so uncommitted work in the checkout doesn't leak in); build
# the Rust program and, when present, its buffer-reusing variant main_reuse.rs.
# Everything is at its highest optimisation on the same CPU target. All outputs
# must be identical. With --time, report best-of-5 wall time and peak RSS
# (pinned to one core, under the WSL bench lock) and binary sizes. A pair the
# self-hosted compiler can't build yet shows "-" in its columns.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
nlc="${NLC:-${CARGO_TARGET_DIR:-$HOME/.cache/next-lang/target}/release/nlc}"
cpu="${BENCH_CPU:-8}"
time_runs=0
use_selfhost=0
pairs=()
for arg in "$@"; do
    case "$arg" in
        --time) time_runs=1 ;;
        --selfhost) use_selfhost=1 ;;
        *) pairs+=("$arg") ;;
    esac
done
if [[ ${#pairs[@]} -eq 0 ]]; then
    for dir in "$repo_root"/bench/vs-rust/*/; do pairs+=("$(basename "$dir")"); done
fi
[[ -x "$nlc" ]] || { echo "nlc not found at $nlc; build it or set NLC" >&2; exit 1; }
work="$(mktemp -d /tmp/bench-vs-rust.XXXXXX)"
trap 'rm -rf -- "$work"' EXIT
rust_flags=(--edition 2021 -C opt-level=3 -C codegen-units=1 -C lto=fat -C panic=abort -C strip=symbols)

selfhost_compiler=""
if (( use_selfhost )); then
    mkdir -p "$work/src"
    git -C "$repo_root" archive HEAD selfhost | tar -x -C "$work/src"
    echo "building the self-hosted compiler from HEAD ($(git -C "$repo_root" rev-parse --short HEAD)) ..." >&2
    (cd "$work/src" && NLC_OPT_LEVEL=3 "$nlc" --frontend=rust build selfhost -o "$work/selfhost-nlc") >"$work/selfhost-build.log" 2>&1 \
        || { cat "$work/selfhost-build.log" >&2; exit 1; }
    selfhost_compiler="$work/selfhost-nlc"
fi

best_of_5() {
    local best=999999 peak=0 line seconds kib
    for _ in 1 2 3 4 5; do
        line=$( { /usr/bin/time -f "%e %M" taskset -c "$cpu" "$1" >/dev/null; } 2>&1 | tail -1)
        seconds=${line% *}; kib=${line#* }
        best=$(awk -v a="$best" -v b="$seconds" 'BEGIN { print (b < a) ? b : a }')
        (( kib > peak )) && peak=$kib
    done
    echo "$best $peak"
}

ratio() { awk -v a="$1" -v b="$2" 'BEGIN { if (a == "-" || b <= 0) print "-"; else printf "%.2f", a / b }'; }
size_of() { [[ -f "$1" ]] && stat -c %s "$1" || echo "-"; }

run() {
    local status=0
    if (( time_runs )); then
        printf "%-16s | %7s %7s %7s %7s | %6s %6s %6s | %7s %7s %7s %7s | %8s %8s %8s\n" \
            pair stage0 self rust reuse s0/rs sh/rs s0/re \
            s0_KiB sh_KiB rs_KiB re_KiB s0_B sh_B rs_B
    fi
    for pair in "${pairs[@]}"; do
        local dir="$repo_root/bench/vs-rust/$pair"
        NLC_OPT_LEVEL=3 "$nlc" build "$dir" -o "$work/$pair.s0" >"$work/$pair.s0.log" 2>&1 \
            || { echo "$pair: stage-0 build failed"; cat "$work/$pair.s0.log"; status=1; continue; }
        rustc "${rust_flags[@]}" "$dir/main.rs" -o "$work/$pair.rs" || { echo "$pair: Rust build failed"; status=1; continue; }
        "$work/$pair.s0" >"$work/$pair.s0.out"
        "$work/$pair.rs" >"$work/$pair.rs.out"
        cmp -s "$work/$pair.s0.out" "$work/$pair.rs.out" || { echo "$pair: OUTPUT DIFFERS (stage 0 vs Rust)"; status=1; continue; }
        if [[ -f "$dir/main_reuse.rs" ]]; then
            rustc "${rust_flags[@]}" "$dir/main_reuse.rs" -o "$work/$pair.re" || { echo "$pair: Rust reuse build failed"; status=1; continue; }
            "$work/$pair.re" >"$work/$pair.re.out"
            cmp -s "$work/$pair.s0.out" "$work/$pair.re.out" || { echo "$pair: OUTPUT DIFFERS (reuse)"; status=1; continue; }
        fi
        if [[ -n "$selfhost_compiler" ]]; then
            # The self-hosted compiler writes its IR only to a path relative to the package.
            if (cd "$dir" && "$selfhost_compiler" build . -o .bench-vs-rust.ll --runtime=core \
                    && mv .bench-vs-rust.ll "$work/$pair.ll") >"$work/$pair.sh.log" 2>&1 \
                && NLC_OPT_LEVEL=3 "$nlc" link-ir "$work/$pair.ll" -o "$work/$pair.sh" >>"$work/$pair.sh.log" 2>&1; then
                "$work/$pair.sh" >"$work/$pair.sh.out"
                cmp -s "$work/$pair.s0.out" "$work/$pair.sh.out" || { echo "$pair: OUTPUT DIFFERS (self-hosted)"; status=1; continue; }
            else
                rm -f "$work/$pair.sh" "$dir/.bench-vs-rust.ll"
                (( time_runs )) || echo "$pair: self-hosted compiler can't build it yet: $(head -1 "$work/$pair.sh.log")"
            fi
        fi
        if (( time_runs )); then
            local s0_s s0_k sh_s="-" sh_k="-" rs_s rs_k re_s="-" re_k="-"
            read -r s0_s s0_k < <(best_of_5 "$work/$pair.s0")
            read -r rs_s rs_k < <(best_of_5 "$work/$pair.rs")
            [[ -f "$work/$pair.sh" ]] && read -r sh_s sh_k < <(best_of_5 "$work/$pair.sh")
            [[ -f "$work/$pair.re" ]] && read -r re_s re_k < <(best_of_5 "$work/$pair.re")
            printf "%-16s | %7s %7s %7s %7s | %6s %6s %6s | %7s %7s %7s %7s | %8s %8s %8s\n" \
                "$pair" "$s0_s" "$sh_s" "$rs_s" "$re_s" \
                "$(ratio "$s0_s" "$rs_s")" "$(ratio "$sh_s" "$rs_s")" "$(ratio "$s0_s" "$re_s")" \
                "$s0_k" "$sh_k" "$rs_k" "$re_k" \
                "$(size_of "$work/$pair.s0")" "$(size_of "$work/$pair.sh")" "$(size_of "$work/$pair.rs")"
        else
            echo "$pair: builds, outputs match"
        fi
    done
    return $status
}

if (( time_runs )); then
    flock -x /home/ben/linuxbench/bench.lock bash -c \
        "$(declare -f best_of_5 ratio size_of run); $(declare -p pairs work nlc cpu time_runs selfhost_compiler rust_flags repo_root); run"
else
    run
fi
