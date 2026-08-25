#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
QUINT_BIN="${QUINT_BIN:-/tmp/quint032/node_modules/.bin/quint}"
CHOREO_COMMIT=000cf4eed315187dc6f216a148781cff7dde6521
if [[ ! -x "$QUINT_BIN" ]]; then echo "STOPPED: Quint 0.32.0 not found; set QUINT_BIN" >&2; exit 2; fi
[[ "$($QUINT_BIN --version)" == "0.32.0" ]] || { echo "STOPPED: expected Quint 0.32.0" >&2; exit 2; }

if [[ -n "${CHOREO_DIR:-}" ]]; then
  choreo_dir="$CHOREO_DIR"
else
  choreo_dir="/tmp/canopy-choreo-$CHOREO_COMMIT"
  if [[ ! -d "$choreo_dir/.git" ]]; then
    GIT_TERMINAL_PROMPT=0 git clone --filter=blob:none --no-checkout \
      https://github.com/informalsystems/choreo.git "$choreo_dir" >/dev/null
    git -C "$choreo_dir" fetch --depth 1 origin "$CHOREO_COMMIT" >/dev/null
    git -C "$choreo_dir" checkout --detach "$CHOREO_COMMIT" >/dev/null
  fi
fi
[[ "$(git -C "$choreo_dir" rev-parse HEAD)" == "$CHOREO_COMMIT" ]] || {
  echo "STOPPED: expected Choreo commit $CHOREO_COMMIT in $choreo_dir" >&2
  exit 2
}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
"$QUINT_BIN" typecheck examples/quint-sync-recovery-prototype/Recovery.qnt
"$QUINT_BIN" run examples/quint-sync-recovery-prototype/Recovery.qnt --main Recovery --mbt \
  --out-itf "$tmp/recovery-{seq}.itf.json" --seed 0x032 --step step --max-steps 11 >/dev/null
trace="$tmp/recovery-0.itf.json"
jq -e '[.states[]."mbt::actionTaken"] == ["init", "open", "startRecovery", "watchdogCurrent", "watchdogStale", "watchdogCurrent", "watchdogCurrent", "watchdogExhaust", "noteSyncApplied", "startRecoveryAgain", "peerLeftTarget", "done"]' "$trace" >/dev/null
"$QUINT_BIN" run examples/quint-sync-recovery-prototype/Recovery.qnt --main Recovery --invariant=safety --seed 0x032 --step step --max-steps 11 >/dev/null

echo "local actions: $(jq -c '[.states[]."mbt::actionTaken"]' "$trace")"
NEW_MOON_MOD=0 moon run --target native ./examples/quint-sync-recovery-prototype -- "$trace"

set +e
negative_output=$(NEW_MOON_MOD=0 moon run --target native ./examples/quint-sync-recovery-prototype -- "$trace" --broken 2>&1)
negative_status=$?
set -e
if [[ "$negative_status" -eq 0 || "$negative_output" != *"DIVERGENCE:"* || "$negative_output" != *"StateDiverged"* ]]; then
  printf '%s\n' "$negative_output" >&2
  echo "local negative control did not produce StateDiverged" >&2
  exit 1
fi
echo "local negative control: expected StateDiverged detected"

spec_dir="$tmp/choreo-spec"
mkdir -p "$spec_dir"
cp examples/quint-sync-recovery-prototype/RecoveryCore.qnt "$spec_dir/"
cp examples/quint-sync-recovery-prototype/RecoveryChoreo.qnt "$spec_dir/"
cp "$choreo_dir/choreo.qnt" "$spec_dir/"
cp -R "$choreo_dir/spells" "$spec_dir/"
"$QUINT_BIN" typecheck "$spec_dir/RecoveryCore.qnt"
"$QUINT_BIN" typecheck "$spec_dir/RecoveryChoreo.qnt"
"$QUINT_BIN" run "$spec_dir/RecoveryChoreo.qnt" --main RecoveryChoreo --mbt \
  --out-itf "$tmp/choreo-{seq}.itf.json" --seed 0x032 --step replayStep --max-steps 9 >/dev/null
choreo_trace="$tmp/choreo-0.itf.json"
jq -e '[.states[]."mbt::actionTaken"] == ["init", "openAlice", "openBob", "openCarol", "aliceStartsRecovery", "bobRepliesEmpty", "aliceReceivesEmpty", "aliceFiresStaleTimeout1", "bobRepliesHelpful", "aliceReceivesHelpful"]' "$choreo_trace" >/dev/null
"$QUINT_BIN" run "$spec_dir/RecoveryChoreo.qnt" --main RecoveryChoreo --mbt \
  --out-itf "$tmp/choreo-random-{seq}.itf.json" --invariant safety --seed 0x032 \
  --step step --max-steps 12 --max-samples 100 --n-traces 100 --verbosity 0
jq -es '([.[].states[]."RecoveryChoreo::choreo::display".status] | index("Error(Exhausted)")) != null and ([.[].states[]."RecoveryChoreo::choreo::display".attempt."#bigint"] | unique | sort) == ["0","1","2","3","4"] and any(.[].states[]."RecoveryChoreo::choreo::display"; .target == "bob") and any(.[].states[]."RecoveryChoreo::choreo::display"; .target == "carol") and any(.[].states[]."RecoveryChoreo::choreo::display"; .status == "Idle" and .applied."#bigint" == "3")' "$tmp"/choreo-random-*.itf.json >/dev/null

echo "Choreo randomized coverage: attempts 0..4, exhaustion, both targets, and helpful recovery"
echo "Choreo actions: $(jq -c '[.states[]."mbt::actionTaken"]' "$choreo_trace")"
NEW_MOON_MOD=0 moon run --target native ./examples/quint-sync-recovery-prototype -- \
  "$choreo_trace" --choreo

set +e
choreo_negative=$(NEW_MOON_MOD=0 moon run --target native ./examples/quint-sync-recovery-prototype -- \
  "$choreo_trace" --choreo --broken 2>&1)
choreo_negative_status=$?
mutation_output=$("$QUINT_BIN" run "$spec_dir/RecoveryChoreo.qnt" --main RecoveryChoreo \
  --invariant safety --seed 0x032 --step modelMutationStep --max-steps 5 --max-samples 1 2>&1)
mutation_status=$?
set -e
if [[ "$choreo_negative_status" -eq 0 || "$choreo_negative" != *"DIVERGENCE:"* || "$choreo_negative" != *"StateDiverged"* ]]; then
  printf '%s\n' "$choreo_negative" >&2
  echo "Choreo driver negative control did not produce StateDiverged" >&2
  exit 1
fi
if [[ "$mutation_status" -eq 0 || "$mutation_output" != *"Invariant violated"* ]]; then
  echo "Choreo model mutation was not rejected by safety" >&2
  exit 1
fi
echo "Choreo driver negative control: expected StateDiverged detected"
echo "Choreo model mutation: expected safety violation detected"
