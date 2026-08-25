#!/usr/bin/env bash
set -euo pipefail

suite_dir="$(cd "$(dirname "$0")" && pwd -P)"
repo_root="$(cd "$suite_dir/../../../.." && pwd -P)"
cd "$repo_root"

expected_quint=0.32.0
choreo_commit=000cf4eed315187dc6f216a148781cff7dde6521
if [[ -n "${QUINT_BIN:-}" ]]; then
  quint_bin="$QUINT_BIN"
else
  quint_bin="$suite_dir/node_modules/.bin/quint"
  if [[ ! -x "$quint_bin" ]] || [[ "$($quint_bin --version 2>/dev/null)" != "$expected_quint" ]]; then
    npm ci --prefix "$suite_dir" --ignore-scripts --no-audit --no-fund
  fi
fi
if [[ ! -x "$quint_bin" ]] || [[ "$($quint_bin --version)" != "$expected_quint" ]]; then
  echo "STOPPED: expected Quint $expected_quint; run npm ci in $suite_dir or set QUINT_BIN" >&2
  exit 2
fi

choreo_dir="${CHOREO_DIR:-$repo_root/deps/choreo}"
if [[ ! -d "$choreo_dir/.git" && ! -f "$choreo_dir/.git" ]] || \
   [[ "$(git -C "$choreo_dir" rev-parse HEAD 2>/dev/null)" != "$choreo_commit" ]]; then
  echo "STOPPED: initialize deps/choreo at $choreo_commit" >&2
  echo "Run: git submodule update --init --recursive deps/choreo" >&2
  exit 2
fi

java_major() {
  java -version 2>&1 | awk -F'[".]' '/version/ { if ($2 == "1") print $3; else print $2; exit }'
}

verify_quint() {
  if command -v java >/dev/null 2>&1 && [[ "$(java_major)" -ge 17 ]]; then
    "$quint_bin" verify "$@"
  elif command -v nix >/dev/null 2>&1; then
    nix shell nixpkgs#jdk17_headless -c "$quint_bin" verify "$@"
  else
    echo "STOPPED: quint verify requires Java 17 or Nix" >&2
    exit 2
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Local deterministic conformance and symbolic verification.
"$quint_bin" typecheck "$suite_dir/Recovery.qnt"
"$quint_bin" run "$suite_dir/Recovery.qnt" --main Recovery --mbt \
  --out-itf "$tmp/recovery-{seq}.itf.json" --seed 0x032 --step step \
  --max-steps 11 --verbosity 0
local_trace="$tmp/recovery-0.itf.json"
jq -e '[.states[]."mbt::actionTaken"] == ["init", "open", "startRecovery", "watchdogCurrent", "watchdogStale", "watchdogCurrent", "watchdogCurrent", "watchdogExhaust", "noteSyncApplied", "startRecoveryAgain", "peerLeftTarget", "done"]' "$local_trace" >/dev/null
"$quint_bin" run "$suite_dir/Recovery.qnt" --main Recovery --invariant safety \
  --seed 0x032 --step step --max-steps 11 --verbosity 0
NEW_MOON_MOD=0 moon run --target native ./modules/canopy/sync_session/verification -- \
  "$local_trace"

set +e
local_negative="$(NEW_MOON_MOD=0 moon run --target native ./modules/canopy/sync_session/verification -- \
  "$local_trace" --broken 2>&1)"
local_negative_status=$?
set -e
if [[ "$local_negative_status" -eq 0 || "$local_negative" != *"StateDiverged"* ]]; then
  printf '%s\n' "$local_negative" >&2
  echo "local driver mutation did not produce StateDiverged" >&2
  exit 1
fi

verify_dir="$tmp/verify-spec"
mkdir -p "$verify_dir"
cp "$suite_dir/Recovery.qnt" "$verify_dir/"
cp "$suite_dir/RecoveryCore.qnt" "$verify_dir/"
cp "$suite_dir/RecoveryDistributed.qnt" "$verify_dir/"
(
  cd "$verify_dir"
  verify_quint Recovery.qnt --main Recovery --invariant safety \
    --max-steps 20 --verbosity 1
  verify_quint RecoveryDistributed.qnt --main RecoveryDistributed \
    --invariant safety --max-steps 6 --verbosity 1
)

# Verify-friendly raw distributed exploration and mutation control.
"$quint_bin" typecheck "$suite_dir/RecoveryDistributed.qnt"
"$quint_bin" run "$suite_dir/RecoveryDistributed.qnt" \
  --main RecoveryDistributed --mbt \
  --out-itf "$tmp/distributed-{seq}.itf.json" --invariant safety --seed 0x99 \
  --step step --max-steps 20 --max-samples 500 --n-traces 500 --verbosity 0
jq -es '([.[].states[].s.local.attempt."#bigint"] | unique | sort) == ["0","1","2","3","4"] and ([.[].states[].s.local.status] | index("Error(Exhausted)")) != null and ([.[].states[].s.local.status] | index("Error(TargetLeft)")) != null and any(.[].states[].s.local; .target == "bob") and any(.[].states[].s.local; .target == "carol") and any(.[].states[].s.local; .recoveries."#bigint" == "2") and any(.[].states[].s.local; .status == "Idle" and .applied."#bigint" == "6") and any(.[].states[].s; ([.messages."#set"[].id."#bigint" | tonumber] | min? // 0) < (.local.requestId."#bigint" | tonumber))' "$tmp"/distributed-*.itf.json >/dev/null

set +e
distributed_mutation="$("$quint_bin" run "$suite_dir/RecoveryDistributed.qnt" \
  --main RecoveryDistributed --invariant safety --seed 0x032 \
  --step modelMutationStep --max-steps 3 --max-samples 1 --verbosity 1 2>&1)"
distributed_mutation_status=$?
set -e
if [[ "$distributed_mutation_status" -eq 0 || "$distributed_mutation" != *"Invariant violated"* ]]; then
  printf '%s\n' "$distributed_mutation" >&2
  echo "distributed model mutation was not rejected by safety" >&2
  exit 1
fi

# Choreo simulation and multi-trace implementation conformance.
choreo_spec="$tmp/choreo-spec"
mkdir -p "$choreo_spec"
cp "$suite_dir/RecoveryCore.qnt" "$choreo_spec/"
cp "$suite_dir/RecoveryChoreo.qnt" "$choreo_spec/"
cp "$choreo_dir/choreo.qnt" "$choreo_spec/"
cp -R "$choreo_dir/spells" "$choreo_spec/"
"$quint_bin" typecheck "$choreo_spec/RecoveryCore.qnt"
"$quint_bin" typecheck "$choreo_spec/RecoveryChoreo.qnt"
"$quint_bin" run "$choreo_spec/RecoveryChoreo.qnt" --main RecoveryChoreo --mbt \
  --out-itf "$tmp/choreo-named-{seq}.itf.json" --seed 0x032 \
  --step replayStep --max-steps 9 --verbosity 0
choreo_named="$tmp/choreo-named-0.itf.json"
jq -e '[.states[]."mbt::actionTaken"] == ["init", "openAlice", "openBob", "openCarol", "aliceStartsRecovery", "bobRepliesEmpty", "aliceReceivesEmpty", "aliceFiresStaleTimeout1", "bobRepliesHelpful", "aliceReceivesHelpful"]' "$choreo_named" >/dev/null
"$quint_bin" run "$choreo_spec/RecoveryChoreo.qnt" --main RecoveryChoreo --mbt \
  --out-itf "$tmp/choreo-random-{seq}.itf.json" --invariant safety --seed 0x032 \
  --step step --max-steps 20 --max-samples 200 --n-traces 200 --verbosity 0
jq -es '([.[].states[]."RecoveryChoreo::choreo::display".status] | index("Error(Exhausted)")) != null and ([.[].states[]."RecoveryChoreo::choreo::display".attempt."#bigint"] | unique | sort) == ["0","1","2","3","4"] and any(.[].states[]."RecoveryChoreo::choreo::display"; .target == "bob") and any(.[].states[]."RecoveryChoreo::choreo::display"; .target == "carol") and any(.[].states[]."RecoveryChoreo::choreo::s".system."#map"[]; .[0] == "alice" and .[1].core.recoveries."#bigint" == "2") and any(.[].states[]."RecoveryChoreo::choreo::display"; .status == "Idle" and .applied."#bigint" == "6")' "$tmp"/choreo-random-*.itf.json >/dev/null

NEW_MOON_MOD=0 moon run --target native ./modules/canopy/sync_session/verification -- \
  "$choreo_named" --choreo
NEW_MOON_MOD=0 moon run --target native ./modules/canopy/sync_session/verification -- \
  "$tmp"/choreo-random-*.itf.json --choreo

set +e
choreo_negative="$(NEW_MOON_MOD=0 moon run --target native ./modules/canopy/sync_session/verification -- \
  "$choreo_named" --choreo --broken 2>&1)"
choreo_negative_status=$?
choreo_mutation="$("$quint_bin" run "$choreo_spec/RecoveryChoreo.qnt" \
  --main RecoveryChoreo --invariant safety --seed 0x032 \
  --step modelMutationStep --max-steps 5 --max-samples 1 2>&1)"
choreo_mutation_status=$?
set -e
if [[ "$choreo_negative_status" -eq 0 || "$choreo_negative" != *"StateDiverged"* ]]; then
  printf '%s\n' "$choreo_negative" >&2
  echo "Choreo driver mutation did not produce StateDiverged" >&2
  exit 1
fi
if [[ "$choreo_mutation_status" -eq 0 || "$choreo_mutation" != *"Invariant violated"* ]]; then
  printf '%s\n' "$choreo_mutation" >&2
  echo "Choreo model mutation was not rejected by safety" >&2
  exit 1
fi

echo "PASS: flat and distributed symbolic verification"
echo "PASS: 500 raw distributed traces cover two recovery cycles, retries, stale soup, both targets, exhaustion, target leave, and helpful recovery"
echo "PASS: 200 randomized Choreo traces conform to public SyncSession behavior across repeated recovery"
echo "PASS: model and driver mutation controls detected"
