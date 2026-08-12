#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
PACKAGE=examples/spikes/minimal_no_shadow_lambda_projection/main
FILE=cutoff_benchmark.mbt
CYCLES=2
CLEANUP=

if [[ ${1:-} == --record ]]; then
  [[ $# -eq 2 ]] || { echo 'usage: run-minimal-no-shadow-lambda-cutoff-benchmark.sh [--record DIR]' >&2; exit 2; }
  OUT=$2
  rm -rf "$OUT"
  mkdir -p "$OUT"
elif [[ $# -eq 0 ]]; then
  OUT=$(mktemp -d)
  CLEANUP=$OUT
else
  echo 'usage: run-minimal-no-shadow-lambda-cutoff-benchmark.sh [--record DIR]' >&2
  exit 2
fi
trap '[[ -z "$CLEANUP" ]] || rm -rf "$CLEANUP"' EXIT

printf '%s\n' '== P1.3 behavioral precondition =='
./scripts/run-minimal-no-shadow-lambda-projection.sh >/dev/null
printf '%s\n' 'P1.2 behavioral gate: PASS'

python3 - "$ROOT" "$PACKAGE" "$FILE" "$OUT" "$CYCLES" <<'PY'
import json
import re
import statistics
import subprocess
import sys
from pathlib import Path

root, package, filename, output, cycles = sys.argv[1:]
cycles = int(cycles)
out = Path(output)
out.mkdir(parents=True, exist_ok=True)
TIME = re.compile(r'^\s*([0-9.]+)\s+(ns|µs|ms)\s+±', re.MULTILINE)
TEST = re.compile(r'\("P1\.3 ([^"]+)"\) ok')
UNITS = {"ns": 0.001, "µs": 1.0, "ms": 1000.0}
indices = {
    "small": {"A": 0, "B": 1},
    "medium": {"A": 3, "B": 2},
    "large": {"A": 4, "B": 5},
}
policies = {"A": "always_changed", "B": "eq_cutoff"}
records = []

def invoke(target, index, raw):
    command = [
        "moon", "bench", "--release", "--target", target,
        "-p", package, "-f", filename, "-i", str(index),
    ]
    completed = subprocess.run(
        command,
        cwd=root,
        env={**__import__("os").environ, "NEW_MOON_MOD": "0"},
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=True,
    )
    text = completed.stdout
    if "Total tests: 1, passed: 1, failed: 0." not in text:
        raise SystemExit(f"unexpected benchmark result for {target} index {index}")
    match = TIME.search(text)
    test = TEST.search(text)
    if match is None or test is None:
        raise SystemExit(f"could not parse {target} index {index}")
    mean_us = float(match.group(1)) * UNITS[match.group(2)]
    raw.write(f"\n===== index={index} name={test.group(1)} =====\n{text}")
    return mean_us

for target in ("native", "js"):
    raw_path = out / f"{target}.raw.log"
    with raw_path.open("w") as raw:
        print(f"\n== {target}: preliminary invocation per policy/size ==")
        for size in ("small", "medium", "large"):
            for arm in ("A", "B"):
                value = invoke(target, indices[size][arm], raw)
                print(f"preliminary {size:6} {policies[arm]:14} {value:9.2f} µs")
        for cycle in range(cycles):
            order = ("A", "B", "B", "A") if cycle % 2 == 0 else ("B", "A", "A", "B")
            print(f"\n{target} cycle {cycle + 1}: {''.join(order)}")
            for size in ("small", "medium", "large"):
                pair_values = []
                for position, arm in enumerate(order):
                    value = invoke(target, indices[size][arm], raw)
                    records.append({
                        "target": target,
                        "size": size,
                        "cycle": cycle + 1,
                        "position": position + 1,
                        "arm": arm,
                        "policy": policies[arm],
                        "mean_us": value,
                    })
                    pair_values.append(f"{arm}={value:.2f}")
                print(f"{size:6} " + " ".join(pair_values))

(out / "abba-records.json").write_text(json.dumps(records, indent=2) + "\n")
with (out / "abba-records.tsv").open("w") as file:
    file.write("target\tsize\tcycle\tposition\tarm\tpolicy\tmean_us\n")
    for record in records:
        file.write("\t".join(str(record[key]) for key in (
            "target", "size", "cycle", "position", "arm", "policy", "mean_us"
        )) + "\n")

summary = []
for target in ("native", "js"):
    for size in ("small", "medium", "large"):
        subset = [r for r in records if r["target"] == target and r["size"] == size]
        deltas = []
        for cycle in range(1, cycles + 1):
            ordered = [r for r in subset if r["cycle"] == cycle]
            ordered.sort(key=lambda r: r["position"])
            for offset in (0, 2):
                pair = ordered[offset:offset + 2]
                a = next(r["mean_us"] for r in pair if r["arm"] == "A")
                b = next(r["mean_us"] for r in pair if r["arm"] == "B")
                deltas.append(b - a)
        baseline = [r["mean_us"] for r in subset if r["arm"] == "A"]
        candidate = [r["mean_us"] for r in subset if r["arm"] == "B"]
        base_median = statistics.median(baseline)
        candidate_median = statistics.median(candidate)
        summary.append({
            "target": target,
            "size": size,
            "baseline_median_us": base_median,
            "candidate_median_us": candidate_median,
            "median_paired_delta_us": statistics.median(deltas),
            "paired_delta_percent_of_baseline_median": statistics.median(deltas) / base_median * 100.0,
            "paired_delta_min_us": min(deltas),
            "paired_delta_max_us": max(deltas),
            "candidate_wins": sum(delta < 0 for delta in deltas),
            "pairs": len(deltas),
        })

(out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
lines = [
    "# P1.3 process-level AB/BA results",
    "",
    f"Cycles: {cycles}; order alternates ABBA then BAAB; each size/policy gets a separate preliminary invocation. Every recorded moon bench process performs its own intra-process batches.",
    "",
    "| Target | Size | Baseline median | Candidate median | Median paired delta | Paired range | Wins |",
    "|---|---|---:|---:|---:|---:|---:|",
]
for row in summary:
    lines.append(
        f"| {row['target']} | {row['size']} | {row['baseline_median_us']:.2f} µs | "
        f"{row['candidate_median_us']:.2f} µs | {row['median_paired_delta_us']:+.2f} µs "
        f"({row['paired_delta_percent_of_baseline_median']:+.2f}%) | "
        f"{row['paired_delta_min_us']:+.2f}…{row['paired_delta_max_us']:+.2f} µs | "
        f"{row['candidate_wins']}/{row['pairs']} |"
    )
(out / "SUMMARY.md").write_text("\n".join(lines) + "\n")
print("\n" + "\n".join(lines))
PY

printf '\n%s\n' '== component scale check (varying operands; not additive) =='
for target in native js; do
  LOG="$OUT/$target.components.log"
  NEW_MOON_MOD=0 moon bench --release --target "$target" \
    -p "$PACKAGE" -f "$FILE" -i 6-18 | tee "$LOG"
  grep -Fq 'Total tests: 12, passed: 12, failed: 0.' "$LOG"
done

printf '\nP1.3 artifacts: %s\n' "$OUT"
printf '%s\n' 'P1.3 RESULT: counterbalanced measurements recorded. Interpret SUMMARY.md before changing the verdict; component costs are qualitative and non-additive.'
