#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VERIFIER="$ROOT/scripts/verify-release-target.nu"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

REMOTE="$TEMP_DIR/remote.git"
WORK="$TEMP_DIR/work"
git init --bare "$REMOTE" >/dev/null
git init "$WORK" >/dev/null
git -C "$WORK" config user.email release-target-test@example.invalid
git -C "$WORK" config user.name release-target-test
printf 'source\n' > "$WORK/source.txt"
git -C "$WORK" add source.txt
git -C "$WORK" commit -m source >/dev/null
SOURCE_SHA=$(git -C "$WORK" rev-parse HEAD)

run_case() {
  local name=$1 expected_status=$2 version=$3 source_sha=$4
  local output status
  set +e
  output=$(nu "$VERIFIER" "$version" "$source_sha" "$REMOTE" 2>&1)
  status=$?
  set -e
  if [[ "$status" -ne "$expected_status" ]]; then
    printf 'FAIL %s: expected exit %s, got %s\n%s\n' \
      "$name" "$expected_status" "$status" "$output" >&2
    exit 1
  fi
  printf 'PASS %s\n' "$name"
}

run_case "absent tag allowed" 0 v0.2.0 "$SOURCE_SHA"

git -C "$WORK" tag v0.2.0 "$SOURCE_SHA"
git -C "$WORK" push "$REMOTE" refs/tags/v0.2.0 >/dev/null
run_case "pushed tag source commit accepted" 0 v0.2.0 "$SOURCE_SHA"
run_case "existing tag same commit allowed" 0 v0.2.0 "$SOURCE_SHA"

git -C "$WORK" tag -a v0.2.1 "$SOURCE_SHA" -m annotated
git -C "$WORK" push "$REMOTE" refs/tags/v0.2.1 >/dev/null
run_case "annotated tag dereferences to commit" 0 v0.2.1 "$SOURCE_SHA"

printf 'different\n' >> "$WORK/source.txt"
git -C "$WORK" add source.txt
git -C "$WORK" commit -m different >/dev/null
OTHER_SHA=$(git -C "$WORK" rev-parse HEAD)
git -C "$WORK" tag v0.2.2 "$OTHER_SHA"
git -C "$WORK" push "$REMOTE" refs/tags/v0.2.2 >/dev/null
run_case "existing tag different commit rejected" 1 v0.2.2 "$SOURCE_SHA"
