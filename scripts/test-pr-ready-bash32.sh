#!/usr/bin/env bash

# Run the real PR-ready shell graph with compiler work replaced by a fake moon
# executable. This belongs on a macOS runner whose system /bin/bash is 3.2.

set -euo pipefail

if [ "${BASH_VERSINFO[0]}" -ne 3 ] || [ "${BASH_VERSINFO[1]}" -ne 2 ]; then
  echo "error: expected Bash 3.2, got ${BASH_VERSION}" >&2
  exit 1
fi

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
created_artifacts="$tmp_dir/created-artifacts"
evidence_path="$root_dir/_build/.canopy-pr-ready"
evidence_backup="$tmp_dir/pr-ready-evidence"
had_evidence=0
: >"$created_artifacts"

if [ -f "$evidence_path" ]; then
  cp -p "$evidence_path" "$evidence_backup"
  had_evidence=1
fi

cleanup() {
  local created_artifact

  while IFS= read -r created_artifact; do
    [ -n "$created_artifact" ] || continue
    rm -f "$created_artifact"
  done <"$created_artifacts"

  if [ "$had_evidence" -eq 1 ]; then
    mkdir -p "${evidence_path%/*}"
    cp -p "$evidence_backup" "$evidence_path"
  else
    rm -f "$evidence_path"
  fi

  rm -rf "$tmp_dir"
}
trap cleanup EXIT

fake_bin="$tmp_dir/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/moon" <<'FAKE_MOON'
#!/usr/bin/env bash
set -euo pipefail

# The compatibility smoke exercises the real shell orchestration, not MoonBit.
# Every moon invocation succeeds without changing tracked files.
exit 0
FAKE_MOON
chmod +x "$fake_bin/moon"

cd "$root_dir"

# build-js.sh verifies these outputs after invoking the fake compiler. Keep this
# literal list independent from its implementation so artifact-contract drift
# fails the public validator instead of being reproduced dynamically.
while IFS= read -r artifact; do
  artifact_path="$root_dir/$artifact"
  [ -n "$artifact" ] || continue
  if [ -e "$artifact_path" ] || [ -L "$artifact_path" ]; then
    continue
  fi
  printf '%s\n' "$artifact_path" >>"$created_artifacts"
  mkdir -p "${artifact_path%/*}"
  : >"$artifact_path"
done <<'ARTIFACTS'
_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.js
_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.d.ts
_build/js/release/build/dowdiness/canopy/ffi/lambda/moonbit.d.ts
_build/js/release/build/dowdiness/canopy/ffi/json/json.js
_build/js/release/build/dowdiness/canopy/ffi/json/json.d.ts
_build/js/release/build/dowdiness/canopy/ffi/json/moonbit.d.ts
_build/js/release/build/dowdiness/canopy/ffi/markdown/markdown.js
_build/js/release/build/dowdiness/canopy/ffi/markdown/markdown.d.ts
_build/js/release/build/dowdiness/canopy/ffi/markdown/moonbit.d.ts
_build/js/release/build/dowdiness/canopy/ffi/jsx/jsx.js
_build/js/release/build/dowdiness/canopy/ffi/jsx/jsx.d.ts
_build/js/release/build/dowdiness/canopy/ffi/jsx/moonbit.d.ts
_build/js/release/build/dowdiness/graphviz/browser/browser.js
_build/js/release/build/dowdiness/graphviz/browser/browser.d.ts
_build/js/release/build/dowdiness/canopy-canvas/main/main.js
_build/js/release/build/dowdiness/canopy-canvas/main/main.d.ts
_build/js/release/build/dowdiness/canopy-canvas/main/moonbit.d.ts
ARTIFACTS

PATH="$fake_bin:$PATH" \
  ./scripts/validate-pr-ready.sh \
    --base HEAD \
    --no-target "Bash 3.2 real shell graph compatibility"

PATH="$fake_bin:$PATH" ./scripts/validate-pr-ready.sh --verify-evidence

echo "ok: real PR-ready shell graph runs with Bash 3.2"
