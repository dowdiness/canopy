#!/usr/bin/env bash

# Run `moon update` with bounded retries for the transient mooncakes CloudFront
# CDN flake (issue #467): the CDN intermittently returns HTTP 403 for
# symbols.zip during registry/symbol resolution. Identical re-runs always clear
# it, so a small in-job retry auto-recovers without a manual "re-run failed
# jobs".
#
# Discipline: only the known-transient CDN/network signature is retried. Any
# other failure (a real toolchain or dependency error) exits immediately with
# the original status, so a genuine break is never masked by retries.
#
# Runs `moon update` in the current working directory; callers cd into the
# target module first (the registry it updates is global). Extra args are
# forwarded to `moon update`.
#
# Tunables (env):
#   MOON_UPDATE_MAX_ATTEMPTS  total attempts, including the first (default 3)
#   MOON_UPDATE_RETRY_DELAY   base backoff seconds; delay = base * attempt (default 5)

set -uo pipefail

MAX_ATTEMPTS="${MOON_UPDATE_MAX_ATTEMPTS:-3}"
BASE_DELAY="${MOON_UPDATE_RETRY_DELAY:-5}"

# Fail fast on a misconfigured tunable rather than letting a nonnumeric value
# make the bounded-attempt comparison error out and loop until the CI job times
# out.
case "$MAX_ATTEMPTS" in '' | *[!0-9]*) MAX_ATTEMPTS=bad ;; esac
case "$BASE_DELAY" in *[!0-9]*) BASE_DELAY=bad ;; esac
if [ "$MAX_ATTEMPTS" = bad ] || [ "$MAX_ATTEMPTS" -lt 1 ] || [ "$BASE_DELAY" = bad ]; then
  echo "moon-update: MOON_UPDATE_MAX_ATTEMPTS (>=1) and MOON_UPDATE_RETRY_DELAY must be non-negative integers." >&2
  exit 2
fi

# Signatures that are unambiguously transient infrastructure noise, never a code
# or dependency-spec error. Keyed on transient HTTP status semantics (the issue
# #467 403, plus 429 / 5xx) and network-layer failures — deliberately NOT the
# generic "client error" (which also covers a deterministic 404 missing package
# or 401) nor a bare "symbols.zip". Matched case-insensitively against combined
# stdout+stderr.
TRANSIENT_RE='403 forbidden|429 too many requests|server error|connection (reset|refused|timed out)|could not resolve host|temporary failure in name resolution|network is unreachable|error sending request|operation timed out'

attempt=1
while :; do
  log="$(mktemp)"
  moon update "$@" 2>&1 | tee "$log"
  status="${PIPESTATUS[0]}"

  if [ "$status" -eq 0 ]; then
    rm -f "$log"
    exit 0
  fi

  if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
    echo "moon-update: failed after ${attempt} attempt(s) (exit ${status}); giving up." >&2
    rm -f "$log"
    exit "$status"
  fi

  if ! grep -qiE "$TRANSIENT_RE" "$log"; then
    echo "moon-update: failure (exit ${status}) is not the transient CDN/network signature; not retrying." >&2
    rm -f "$log"
    exit "$status"
  fi

  rm -f "$log"
  delay=$(( BASE_DELAY * attempt ))
  echo "moon-update: transient CDN/network failure (exit ${status}); attempt ${attempt}/${MAX_ATTEMPTS}, retrying in ${delay}s..." >&2
  sleep "$delay"
  attempt=$(( attempt + 1 ))
done
