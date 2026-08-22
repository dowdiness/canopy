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

if [ "${1:-}" = "version" ] && [ "${2:-}" = "--all" ]; then
  echo "moonc ${FAKE_MOON_VERSION:-v0.10.8+8606a5800} /tmp/fake-moonc"
  exit 0
fi

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
  registry-clone-always-transient)
    cat >&2 <<'LOG'
Error: update failed

Caused by:
    0: failed to clone registry index
    1: non-zero exit code: exit status: 128
LOG
    exit 255
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

cat > "$fake_bin/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail

if [ -n "${FAKE_CURL_CALLS_FILE:-}" ]; then
  curl_calls=0
  if [ -f "$FAKE_CURL_CALLS_FILE" ]; then
    curl_calls="$(cat "$FAKE_CURL_CALLS_FILE")"
  fi
  printf '%s\n' "$((curl_calls + 1))" > "$FAKE_CURL_CALLS_FILE"
fi

if [ "${FAKE_CURL_SCENARIO:-success}" = "fail" ]; then
  exit 42
fi

cat <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$HOME/.moon/bin"
cat > "$HOME/.moon/bin/moon" <<'FAKE_INSTALLED_MOON'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "version" ] && [ "${2:-}" = "--all" ]; then
  echo "moonc ${FAKE_INSTALLED_MOON_VERSION:-v0.10.8+8606a5800} /tmp/installed-moonc"
  exit 0
fi

exec "$FAKE_MOON_BIN" "$@"
FAKE_INSTALLED_MOON
chmod +x "$HOME/.moon/bin/moon"
INSTALLER
FAKE_CURL
chmod +x "$fake_bin/curl"

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
  local moon_version="${4:-v0.10.8+8606a5800}"
  local curl_scenario="${5:-success}"
  local installed_version="${6:-v0.10.8+8606a5800}"
  local home_dir="$output_file.home"
  mkdir -p "$home_dir"

  PATH="$fake_bin:$PATH" \
    HOME="$home_dir" \
    FAKE_MOON_BIN="$fake_bin/moon" \
    FAKE_MOON_VERSION="$moon_version" \
    FAKE_INSTALLED_MOON_VERSION="$installed_version" \
    FAKE_CURL_CALLS_FILE="$output_file.curl-calls" \
    FAKE_CURL_SCENARIO="$curl_scenario" \
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
if [ -e "$transient_output.curl-calls" ]; then
  echo "error: matching MoonBit unexpectedly invoked the installer" >&2
  cat "$transient_output.curl-calls" >&2
  exit 1
fi

repaired_attempts="$tmp_dir/repaired-attempts"
repaired_output="$tmp_dir/repaired-output.log"
run_wrapper registry-clone-transient "$repaired_attempts" "$repaired_output" v0.10.8+ade96c819
assert_eq "$(cat "$repaired_attempts")" "2" "mismatched MoonBit should install the pinned compiler before retrying"
assert_eq "$(cat "$repaired_output.curl-calls")" "1" "mismatched MoonBit should invoke the installer once"
grep -q "installing MoonBit 0.10.8+8606a5800" "$repaired_output" || {
  echo "error: mismatched MoonBit did not trigger the pinned installation" >&2
  cat "$repaired_output" >&2
  exit 1
}

if run_wrapper registry-clone-transient "$tmp_dir/failed-install-attempts" "$tmp_dir/failed-install.log" v0.10.8+ade96c819 fail; then
  echo "error: failed MoonBit installation unexpectedly succeeded" >&2
  exit 1
fi
grep -q "failed to install MoonBit" "$tmp_dir/failed-install.log" || {
  echo "error: failed MoonBit installation was not reported" >&2
  cat "$tmp_dir/failed-install.log" >&2
  exit 1
}
assert_eq "$(cat "$tmp_dir/failed-install.log.curl-calls")" "1" "failed MoonBit installation should invoke the installer once"

if run_wrapper registry-clone-transient "$tmp_dir/bad-install-attempts" "$tmp_dir/bad-install.log" v0.10.8+ade96c819 success v0.10.8+ade96c819; then
  echo "error: mismatched post-install MoonBit unexpectedly succeeded" >&2
  exit 1
fi
grep -q "does not provide moonc v0.10.8+8606a5800" "$tmp_dir/bad-install.log" || {
  echo "error: mismatched post-install MoonBit was not rejected" >&2
  cat "$tmp_dir/bad-install.log" >&2
  exit 1
}
assert_eq "$(cat "$tmp_dir/bad-install.log.curl-calls")" "1" "bad post-install MoonBit should invoke the installer once"

exhausted_attempts="$tmp_dir/exhausted-attempts"
exhausted_output="$tmp_dir/exhausted-output.log"
if run_wrapper registry-clone-always-transient "$exhausted_attempts" "$exhausted_output"; then
  echo "error: exhausted transient registry clone unexpectedly succeeded" >&2
  exit 1
fi
assert_eq "$(cat "$exhausted_attempts")" "3" "transient registry clone should stop at max attempts"
grep -q "setup/network failure persisted" "$exhausted_output" || {
  echo "error: exhausted transient failure did not report setup/network failure" >&2
  cat "$exhausted_output" >&2
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

echo "ok: moon-update pins MoonBit and retries registry clone flakes only"
