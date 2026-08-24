#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
QUINT_BIN="${QUINT_BIN:-/tmp/quint032/node_modules/.bin/quint}"
if [[ ! -x "$QUINT_BIN" ]]; then echo "STOPPED: Quint 0.32.0 not found; set QUINT_BIN" >&2; exit 2; fi
[[ "$($QUINT_BIN --version)" == "0.32.0" ]] || { echo "STOPPED: expected Quint 0.32.0" >&2; exit 2; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
"$QUINT_BIN" typecheck examples/quint-sync-recovery-prototype/Recovery.qnt
"$QUINT_BIN" run examples/quint-sync-recovery-prototype/Recovery.qnt --main Recovery --mbt \
  --out-itf "$tmp/recovery-{seq}.itf.json" --seed 0x032 --step step --max-steps 11
trace="$tmp/recovery-0.itf.json"
jq -e '[.states[]."mbt::actionTaken"] == ["init", "open", "startRecovery", "watchdogCurrent", "watchdogStale", "watchdogCurrent", "watchdogCurrent", "watchdogExhaust", "noteSyncApplied", "startRecoveryAgain", "peerLeftTarget", "done"]' "$trace" >/dev/null
"$QUINT_BIN" run examples/quint-sync-recovery-prototype/Recovery.qnt --main Recovery --invariant=safety --seed 0x032 --step step --max-steps 11 >/dev/null

echo "named actions: $(jq -c '[.states[]."mbt::actionTaken"]' "$trace")"
NEW_MOON_MOD=0 moon run --target native ./examples/quint-sync-recovery-prototype -- "$trace"

set +e
negative_output=$(NEW_MOON_MOD=0 moon run --target native ./examples/quint-sync-recovery-prototype -- "$trace" --broken 2>&1)
negative_status=$?
set -e
printf '%s\n' "$negative_output"
if [[ "$negative_status" -eq 0 ]]; then
  echo "negative control unexpectedly passed" >&2
  exit 1
fi
if [[ "$negative_output" != *"DIVERGENCE:"* || "$negative_output" != *"StateDiverged"* ]]; then
  echo "negative control failed for a reason other than StateDiverged" >&2
  exit 1
fi
echo "negative control: expected StateDiverged detected"
