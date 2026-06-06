#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fake_bin="$tmp_dir/bin"
mkdir -p "$fake_bin"

cat > "$fake_bin/moon" <<'FAKE_MOON'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" != "update" ]; then
  echo "fake moon: expected update subcommand" >&2
  exit 2
fi

attempt=0
if [ -f "$FAKE_MOON_ATTEMPTS_FILE" ]; then
  attempt="$(cat "$FAKE_MOON_ATTEMPTS_FILE")"
fi
attempt=$((attempt + 1))
printf '%s\n' "$attempt" > "$FAKE_MOON_ATTEMPTS_FILE"

case "$FAKE_MOON_SCENARIO" in
  registry-clone-transient)
    if [ "$attempt" -eq 1 ]; then
      cat >&2 <<'LOG'
Error: update failed

Caused by:
    0: failed to clone registry index
    1: non-zero exit code: exit status: 128
LOG
      exit 255
    fi
    echo "fake moon: update succeeded"
    ;;
  deterministic-missing-package)
    cat >&2 <<'LOG'
Error: update failed

Caused by:
    0: package not found: moonbitlang/not-a-real-package
    1: client error (404 Not Found)
LOG
    exit 255
    ;;
  *)
    echo "fake moon: unknown scenario: $FAKE_MOON_SCENARIO" >&2
    exit 2
    ;;
esac
FAKE_MOON
chmod +x "$fake_bin/moon"

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [ "$actual" != "$expected" ]; then
    echo "error: $label: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

run_wrapper() {
  local scenario="$1"
  local attempts_file="$2"
  local output_file="$3"

  PATH="$fake_bin:$PATH" \
    FAKE_MOON_SCENARIO="$scenario" \
    FAKE_MOON_ATTEMPTS_FILE="$attempts_file" \
    MOON_UPDATE_MAX_ATTEMPTS=3 \
    MOON_UPDATE_RETRY_DELAY=0 \
    "$root_dir/scripts/moon-update.sh" >"$output_file" 2>&1
}

transient_attempts="$tmp_dir/transient-attempts"
transient_output="$tmp_dir/transient-output.log"
run_wrapper registry-clone-transient "$transient_attempts" "$transient_output"
assert_eq "$(cat "$transient_attempts")" "2" "transient registry clone should retry once before success"
grep -q "transient registry/CDN/network failure" "$transient_output" || {
  echo "error: transient retry message missing" >&2
  cat "$transient_output" >&2
  exit 1
}

missing_attempts="$tmp_dir/missing-attempts"
missing_output="$tmp_dir/missing-output.log"
if run_wrapper deterministic-missing-package "$missing_attempts" "$missing_output"; then
  echo "error: deterministic missing package unexpectedly succeeded" >&2
  exit 1
fi
assert_eq "$(cat "$missing_attempts")" "1" "deterministic missing package should not retry"
grep -q "not retrying" "$missing_output" || {
  echo "error: deterministic failure did not report non-retry" >&2
  cat "$missing_output" >&2
  exit 1
}

echo "ok: moon-update retry wrapper retries registry clone flakes only"
