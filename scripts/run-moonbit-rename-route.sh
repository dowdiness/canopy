#!/bin/sh

set -eu

is_moonbit_route() {
  case "$1" in
    *.mbt|*.mbt.md|*.mbti|moon.mod|moon.mod.json|moon.pkg|moon.pkg.json|moon.work|moon.work.json|*/moon.mod|*/moon.mod.json|*/moon.pkg|*/moon.pkg.json|modules/*|apps/*|examples/*|adapters/*|deps/*|justfile|scripts/run-moon-module.sh|scripts/vendored-check-common.sh|scripts/run-moonbit-rename-route.sh)
      return 0
      ;;
  esac
  return 1
}

# Lefthook's normal staged-file glob sees the post-image path of a detected
# rename. If another post-image already routes through the normal MoonBit
# group, that group will exercise the operation once and this fallback must
# stay quiet.
POST_IMAGE=$(mktemp "${TMPDIR:-/tmp}/canopy-moonbit-post-image.XXXXXX")
trap 'rm -f "$POST_IMAGE"' EXIT HUP INT TERM

git diff --cached --name-only --diff-filter=ACMRD -- > "$POST_IMAGE"
while IFS= read -r path; do
  if is_moonbit_route "$path"; then
    exit 0
  fi
done < "$POST_IMAGE"

# Otherwise inspect the pre-image explicitly so moving MoonBit input out of
# the routed tree still exercises the operation it used to feed.
git diff --cached --name-status --find-renames --diff-filter=R -- | while IFS="$(printf '\t')" read -r status source destination; do
  case "$status" in
    R*)
      if is_moonbit_route "$source" && ! is_moonbit_route "$destination"; then
        just hook-moonbit-check
        just hook-moonbit-format-check
        exit 0
      fi
      ;;
  esac
done
