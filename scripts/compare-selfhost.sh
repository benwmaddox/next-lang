#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
reference=""
selfhost=""
tokens_mode=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tokens)
            tokens_mode=1
            shift
            ;;
        --reference)
            [[ $# -ge 2 ]] || { echo "missing value for --reference" >&2; exit 2; }
            reference="$2"
            shift 2
            ;;
        --selfhost)
            [[ $# -ge 2 ]] || { echo "missing value for --selfhost" >&2; exit 2; }
            selfhost="$2"
            shift 2
            ;;
        *)
            echo "unknown harness option: $1" >&2
            exit 2
            ;;
    esac
done
if [[ $tokens_mode != 1 || -z "$reference" || -z "$selfhost" ]]; then
    echo "usage: scripts/compare-selfhost.sh --tokens --reference <nlc> --selfhost <lexer>" >&2
    exit 2
fi
if [[ ! -x "$reference" || ! -x "$selfhost" ]]; then
    echo "reference and self-hosted executables must both be executable" >&2
    exit 2
fi

work="$(mktemp -d "$repo_root/.selfhost-compare.XXXXXX")"
keep_work=0
cleanup() {
    if [[ $keep_work == 1 ]]; then
        echo "comparison artifacts retained at ${work#$repo_root/}" >&2
    else
        python3 - "$work" <<'PY'
from pathlib import Path
import shutil
shutil.rmtree(Path(__import__("sys").argv[1]))
PY
    fi
}
trap cleanup EXIT

mkdir -p "$work/generated"
python3 "$repo_root/scripts/selfhost-adversarial-cases.py" "$repo_root" "$work/generated"
bench_relative="${work#$repo_root/}/benchmark"
"$repo_root/scripts/gen-bench-corpus.sh" "$bench_relative"

reference_stdout="$work/reference.stdout"
reference_stderr="$work/reference.stderr"
selfhost_stdout="$work/selfhost.stdout"
selfhost_stderr="$work/selfhost.stderr"
corpus_count=0
directed_count=0
fuzz_count=0
benchmark_count=0
current_case=""

first_difference() {
    local label="$1"
    local left="$2"
    local right="$3"
    python3 - "$label" "$left" "$right" <<'PY'
import sys

label, left_path, right_path = sys.argv[1:]
offset = 0
with open(left_path, "rb") as left, open(right_path, "rb") as right:
    while True:
        a = left.read(65536)
        b = right.read(65536)
        common = min(len(a), len(b))
        for index in range(common):
            if a[index] != b[index]:
                print(f"first {label} difference at byte {offset + index}: reference=0x{a[index]:02x}, selfhost=0x{b[index]:02x}")
                raise SystemExit
        if len(a) != len(b):
            left_byte = a[common] if common < len(a) else None
            right_byte = b[common] if common < len(b) else None
            print(f"first {label} difference at byte {offset + common}: reference={left_byte!r}, selfhost={right_byte!r} (lengths differ)")
            raise SystemExit
        if not a:
            print(f"{label} differs, but the first differing byte was not found")
            raise SystemExit
        offset += common
PY
}

fail_case() {
    local reason="$1"
    keep_work=1
    echo "selfhost comparison failed for $current_case: $reason" >&2
    if [[ "$current_case" == *"/fuzz/"* ]]; then
        echo "mutation seed: $(cat "$work/generated/fuzz-seed.txt")" >&2
        echo "failing input: $current_case/main.nl" >&2
    fi
    if [[ -f "$reference_stdout" && -f "$selfhost_stdout" ]] && ! cmp -s "$reference_stdout" "$selfhost_stdout"; then
        first_difference stdout "$reference_stdout" "$selfhost_stdout" >&2
    fi
    if [[ -f "$reference_stderr" && -f "$selfhost_stderr" ]] && ! cmp -s "$reference_stderr" "$selfhost_stderr"; then
        first_difference stderr "$reference_stderr" "$selfhost_stderr" >&2
        echo "reference stderr:" >&2
        head -c 1000 "$reference_stderr" >&2
        echo >&2
        echo "selfhost stderr:" >&2
        head -c 1000 "$selfhost_stderr" >&2
        echo >&2
    fi
    exit 1
}

compare_package() {
    local package="$1"
    local category="$2"
    current_case="$package"
    local reference_status=0
    local selfhost_status=0
    set +e
    "$reference" lex "$package" >"$reference_stdout" 2>"$reference_stderr"
    reference_status=$?
    "$selfhost" lex "$package" >"$selfhost_stdout" 2>"$selfhost_stderr"
    selfhost_status=$?
    set -e

    if [[ $reference_status != $selfhost_status ]]; then
        fail_case "exit status differs: reference=$reference_status selfhost=$selfhost_status"
    fi
    if ! cmp -s "$reference_stdout" "$selfhost_stdout"; then
        fail_case "stdout differs"
    fi
    if ! cmp -s "$reference_stderr" "$selfhost_stderr"; then
        if [[ $reference_status == 3 ]] \
            && grep -a -q '^nlc: tool failure: ' "$reference_stderr" \
            && grep -a -q '^nlc: tool failure: ' "$selfhost_stderr"; then
            : # Rooted filesystem and operating-system error text can differ.
        else
            fail_case "stderr differs"
        fi
    fi
    case "$category" in
        corpus) corpus_count=$((corpus_count + 1)) ;;
        fuzz) fuzz_count=$((fuzz_count + 1)) ;;
        benchmark) benchmark_count=$((benchmark_count + 1)) ;;
        *) directed_count=$((directed_count + 1)) ;;
    esac
}

assert_selfhost_cli() {
    local expected_status="$1"
    local expected_stderr="$2"
    shift 2
    current_case="selfhost CLI $*"
    local status=0
    set +e
    "$selfhost" "$@" >"$selfhost_stdout" 2>"$selfhost_stderr"
    status=$?
    set -e
    if [[ $status != "$expected_status" ]]; then
        fail_case "expected CLI status $expected_status; got $status"
    fi
    if [[ -s "$selfhost_stdout" ]]; then
        fail_case "CLI rejection wrote stdout"
    fi
    printf '%s\n' "$expected_stderr" >"$reference_stderr"
    if ! cmp -s "$reference_stderr" "$selfhost_stderr"; then
        fail_case "CLI stderr did not match its specified response"
    fi
}

cd "$repo_root"
mapfile -t corpus_packages < <(
    find tests/run tests/test tests/parse/cases -type f -name '*.nl' -printf '%h\n' | sort -u
)
for package in "${corpus_packages[@]}"; do
    compare_package "$package" corpus
done

mapfile -t generated_packages < <(
    find "${work#$repo_root/}/generated" -path "${work#$repo_root/}/generated/fuzz" -prune -o -type f -name '*.nl' -printf '%h\n' | sort -u
)
for package in "${generated_packages[@]}"; do
    compare_package "$package" directed
    if [[ "$package" == *"later_file_failure_has_no_stdout"* ]]; then
        if [[ -s "$reference_stdout" || -s "$selfhost_stdout" ]]; then
            fail_case "a later-file lexer failure produced partial stdout"
        fi
    fi
done

mapfile -t fuzz_packages < <(
    find "${work#$repo_root/}/generated/fuzz" -type f -name '*.nl' -printf '%h\n' | sort -u
)
for package in "${fuzz_packages[@]}"; do
    compare_package "$package" fuzz
done

assert_selfhost_cli 3 "nlc: tool failure: not implemented yet" lex tests/run/arithmetic --tree
assert_selfhost_cli 3 "nlc: tool failure: not implemented yet" lex tests/run/arithmetic --tokens --tree
assert_selfhost_cli 3 "usage: nlc run selfhost -- lex <package> [--tokens] [--tree]" lex tests/run/arithmetic --tokens --tokens
assert_selfhost_cli 3 "usage: nlc run selfhost -- lex <package> [--tokens] [--tree]" lex tests/run/arithmetic --unknown

compare_package "$bench_relative" benchmark
benchmark_rows=$(($(wc -l < "$reference_stdout") - 13))
benchmark_bytes=$(du -b "$work/benchmark"/*.nl | awk '{total += $1} END {print total + 0}')
benchmark_source_bytes=$(du -b "$work/benchmark"/bench-00.nl | awk '{print $1 + 0}')
benchmark_max_file_bytes=$(stat -c %s "$work/benchmark/bench-00.nl")
token_live_bytes=$((benchmark_rows * 20))
file_live_bytes=$((13 * 8159))
directory_live_bytes=$((13 * 16396))
data_live_estimate=$((benchmark_source_bytes * 14 + token_live_bytes + file_live_bytes + directory_live_bytes + 1048576))

reference_time="$work/reference.time"
selfhost_time="$work/selfhost.time"
/usr/bin/time -f 'elapsed_seconds=%e max_rss_kib=%M' -o "$reference_time" "$reference" lex "$bench_relative" >/dev/null
/usr/bin/time -f 'elapsed_seconds=%e max_rss_kib=%M' -o "$selfhost_time" "$selfhost" lex "$bench_relative" >/dev/null

echo "selfhost lexer comparison passed"
echo "corpus packages: $corpus_count"
echo "directed and limit cases: $directed_count"
echo "byte mutations: $fuzz_count (seed $(cat "$work/generated/fuzz-seed.txt"))"
echo "benchmark: 13 files, 54,145 lines, $benchmark_bytes bytes, $benchmark_rows tokens"
echo "benchmark logical live-data high water estimate: $data_live_estimate bytes (source $benchmark_source_bytes package bytes plus $benchmark_max_file_bytes file staging, $token_live_bytes token bytes, file and directory entries, 1 MiB output buffer)"
echo "benchmark process measurements: reference $(cat "$reference_time"); selfhost $(cat "$selfhost_time")"
echo "selfhost stack reservation: run 'nlc inspect stacks selfhost' (reservation includes unused table capacity)"
