#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
PACKAGE=examples/spikes/minimal_no_shadow_lambda_projection/main
FILE=trace_replay_benchmark.mbt
CYCLES=3
CLEANUP=

if [[ ${1:-} == --record ]]; then
  [[ $# -eq 2 ]] || { echo 'usage: run-minimal-no-shadow-lambda-trace-replay.sh [--record DIR]' >&2; exit 2; }
  OUT=$2
  rm -rf "$OUT"
  mkdir -p "$OUT"
elif [[ $# -eq 0 ]]; then
  OUT=$(mktemp -d)
  CLEANUP=$OUT
else
  echo 'usage: run-minimal-no-shadow-lambda-trace-replay.sh [--record DIR]' >&2
  exit 2
fi
trap '[[ -z "$CLEANUP" ]] || rm -rf "$CLEANUP"' EXIT

printf '%s\n' '== P1.5 behavioral precondition =='
./scripts/run-minimal-no-shadow-lambda-projection.sh >/dev/null
printf '%s\n' 'P1.2 behavioral gate: PASS'

python3 - "$ROOT" "$PACKAGE" "$FILE" "$OUT" "$CYCLES" <<'PY'
import json
import os
import re
import statistics
import subprocess
import sys
from pathlib import Path

root, package, file_name, output, cycles = sys.argv[1:]
cycles = int(cycles)
out = Path(output)
out.mkdir(parents=True, exist_ok=True)
TIME = re.compile(r'^\s*([0-9.]+)\s+(ns|µs|ms)\s+±', re.MULTILINE)
TEST = re.compile(r'\("P1\.5 ([^"]+)"\) ok')
METRICS = re.compile(r'^P1\.5_METRICS (.+)$', re.MULTILINE)
UNITS = {"ns": 0.001, "µs": 1.0, "ms": 1000.0}
policies = {"A": "always_changed", "B": "eq_cutoff"}
test_suffixes = {"A": "always-changed", "B": "eq-cutoff"}
scenarios = {
    "whitespace-view": {"A": 0, "B": 1},
    "binding-view": {"A": 2, "B": 3},
    "tail-definition-operations": {"A": 4, "B": 5},
    "expression-source-map-operations": {"A": 6, "B": 7},
}
manifest = [
    {
        "scenario": "whitespace-view",
        "source_test": "modules/canopy/lang/lambda/companion/editor_view_decorations_test.mbt",
        "source_test_name": "analysis projection drops stale pattern decorations but keeps semantic decorations",
        "edit_provenance": "test-derived exact source transition",
        "demand_provenance": "annotation-root overlay for production view-patch demand",
        "operations": 1,
        "publications": 1,
        "demand_points": 2,
    },
    {
        "scenario": "binding-view",
        "source_test": "modules/canopy/lang/lambda/companion/editor_view_decorations_test.mbt",
        "source_test_name": "binding an unresolved reference clears its semantic warning",
        "edit_provenance": "test-derived exact source transition",
        "demand_provenance": "annotation-root overlay for production view-patch demand",
        "operations": 1,
        "publications": 1,
        "demand_points": 2,
    },
    {
        "scenario": "tail-definition-operations",
        "source_test": "modules/canopy/lang/lambda/companion/editor_incremental_patch_test.mbt",
        "source_test_name": "projection memo: registry node count stable after tail edit",
        "edit_provenance": "test-derived backspace-before-literal + insert sequence; final value is 90",
        "demand_provenance": "annotation-root overlay; no demand between operations",
        "operations": 2,
        "publications": 2,
        "demand_points": 2,
    },
    {
        "scenario": "expression-source-map-operations",
        "source_test": "modules/canopy/lang/lambda/companion/editor_incremental_patch_test.mbt",
        "source_test_name": "projection memo: expression-only document edit works",
        "edit_provenance": "test-derived two no-op backspaces at cursor zero + two inserts; final source is 9942",
        "demand_provenance": "exact SourceMap demand class; no demand between operations",
        "operations": 4,
        "publications": 2,
        "demand_points": 2,
    },
]
(out / "trace-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
records = []
behavior = {}

def parse_metrics(text):
    match = METRICS.search(text)
    if match is None:
        raise SystemExit("missing P1.5 metrics")
    result = {}
    for field in match.group(1).split():
        key, value = field.split("=", 1)
        result[key] = value if key in ("scenario", "policy") else int(value)
    return result

def invoke(target, index, raw):
    command = [
        "moon", "bench", "--release", "--target", target,
        "-p", package, "-f", file_name, "-i", str(index),
    ]
    completed = subprocess.run(
        command,
        cwd=root,
        env={**os.environ, "NEW_MOON_MOD": "0"},
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=True,
    )
    text = completed.stdout
    if "Total tests: 1, passed: 1, failed: 0." not in text:
        raise SystemExit(f"unexpected benchmark result: {target} index={index}")
    timing = TIME.search(text)
    test = TEST.search(text)
    if timing is None or test is None:
        raise SystemExit(f"could not parse: {target} index={index}")
    mean_us = float(timing.group(1)) * UNITS[timing.group(2)]
    metrics = parse_metrics(text)
    raw.write(f"\n===== index={index} name={test.group(1)} =====\n{text}")
    return mean_us, metrics, test.group(1)

for target in ("native", "js"):
    with (out / f"{target}.raw.log").open("w") as raw:
        print(f"\n== {target}: preliminary process per trace/policy ==")
        for scenario, arms in scenarios.items():
            for arm in ("A", "B"):
                value, metrics, test_name = invoke(target, arms[arm], raw)
                expected_name = f"{scenario}/{test_suffixes[arm]}"
                if test_name != expected_name or metrics["scenario"] != scenario or metrics["policy"] != policies[arm]:
                    raise SystemExit(f"index mapping drift: expected {expected_name}, got {test_name} / {metrics}")
                behavior[(target, scenario, arm)] = metrics
                print(f"preliminary {scenario:34} {policies[arm]:14} {value:9.2f} µs")
        for cycle in range(cycles):
            order = ("A", "B", "B", "A") if cycle % 2 == 0 else ("B", "A", "A", "B")
            print(f"\n{target} cycle {cycle + 1}: {''.join(order)}")
            for scenario, arms in scenarios.items():
                values = []
                for position, arm in enumerate(order):
                    value, metrics, test_name = invoke(target, arms[arm], raw)
                    expected_name = f"{scenario}/{test_suffixes[arm]}"
                    if test_name != expected_name:
                        raise SystemExit(f"index mapping drift: expected {expected_name}, got {test_name}")
                    expected = behavior[(target, scenario, arm)]
                    if metrics != expected:
                        raise SystemExit(f"behavior drift: {target} {scenario} {arm}")
                    records.append({
                        "target": target,
                        "scenario": scenario,
                        "cycle": cycle + 1,
                        "position": position + 1,
                        "arm": arm,
                        "policy": policies[arm],
                        "mean_us": value,
                    })
                    values.append(f"{arm}={value:.2f}")
                print(f"{scenario:34} " + " ".join(values))

behavior_rows = []
for target in ("native", "js"):
    for scenario in scenarios:
        for arm in ("A", "B"):
            behavior_rows.append({"target": target, **behavior[(target, scenario, arm)]})
(out / "behavior.json").write_text(json.dumps(behavior_rows, indent=2) + "\n")
(out / "abba-records.json").write_text(json.dumps(records, indent=2) + "\n")
with (out / "abba-records.tsv").open("w") as file:
    file.write("target\tscenario\tcycle\tposition\tarm\tpolicy\tmean_us\n")
    for record in records:
        file.write("\t".join(str(record[key]) for key in (
            "target", "scenario", "cycle", "position", "arm", "policy", "mean_us"
        )) + "\n")

summary = []
for target in ("native", "js"):
    for scenario in scenarios:
        subset = [r for r in records if r["target"] == target and r["scenario"] == scenario]
        deltas = []
        percentages = []
        for cycle in range(1, cycles + 1):
            ordered = sorted(
                (r for r in subset if r["cycle"] == cycle),
                key=lambda r: r["position"],
            )
            for offset in (0, 2):
                pair = ordered[offset:offset + 2]
                a = next(r["mean_us"] for r in pair if r["arm"] == "A")
                b = next(r["mean_us"] for r in pair if r["arm"] == "B")
                deltas.append(b - a)
                percentages.append((b - a) / a * 100.0)
        baseline = [r["mean_us"] for r in subset if r["arm"] == "A"]
        candidate = [r["mean_us"] for r in subset if r["arm"] == "B"]
        summary.append({
            "target": target,
            "scenario": scenario,
            "baseline_median_us": statistics.median(baseline),
            "candidate_median_us": statistics.median(candidate),
            "median_paired_delta_us": statistics.median(deltas),
            "median_pair_percentage": statistics.median(percentages),
            "paired_delta_min_us": min(deltas),
            "paired_delta_max_us": max(deltas),
            "candidate_wins": sum(delta < 0 for delta in deltas),
            "pairs": len(deltas),
        })
(out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")

lines = [
    "# P1.5 test-derived trace replay results",
    "",
    "Whole-session timing includes shell construction, initial root demand, every publication, final root demand, and close. Three ABBA/BAAB cycles produce six adjacent pairs per target/trace.",
    "",
    "| Target | Trace | Baseline median | Candidate median | Median paired delta | Median pair % | Range | Wins |",
    "|---|---|---:|---:|---:|---:|---:|---:|",
]
for row in summary:
    lines.append(
        f"| {row['target']} | {row['scenario']} | {row['baseline_median_us']:.2f} µs | "
        f"{row['candidate_median_us']:.2f} µs | {row['median_paired_delta_us']:+.2f} µs | "
        f"{row['median_pair_percentage']:+.2f}% | "
        f"{row['paired_delta_min_us']:+.2f}…{row['paired_delta_max_us']:+.2f} µs | "
        f"{row['candidate_wins']}/{row['pairs']} |"
    )
lines += [
    "",
    "Allocation, GC, mismatch visited-node count, fan-out, and real-user edit frequencies are not measured.",
]
(out / "SUMMARY.md").write_text("\n".join(lines) + "\n")
print("\n" + "\n".join(lines))
PY

printf '\nP1.5 artifacts: %s\n' "$OUT"
printf '%s\n' 'P1.5 RESULT: test-derived edit/demand traces replayed. This is not captured user-session evidence and selects no production policy.'
