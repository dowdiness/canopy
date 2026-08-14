#!/bin/sh

set -eu

all_zeroes=0000000000000000000000000000000000000000
commits_file=$(mktemp "${TMPDIR:-/tmp}/canopy-submodule-push.XXXXXX")
trap 'rm -f "$commits_file"' EXIT HUP INT TERM

has_submodule_path() {
  while IFS= read -r path; do
    case "$path" in
      .gitmodules|deps/*)
        return 0
        ;;
    esac
  done
  return 1
}

add_commit() {
  commit=$1
  if ! grep -Fqx "$commit" "$commits_file"; then
    printf '%s\n' "$commit" >>"$commits_file"
  fi
}

saw_update=0
while IFS=' ' read -r _local_ref local_sha _remote_ref remote_sha; do
  [ -n "${local_sha:-}" ] || continue
  saw_update=1
  remote_sha=${remote_sha:-$all_zeroes}

  # A deleted local ref contributes no new tree to the push.
  [ "$local_sha" != "$all_zeroes" ] || continue

  if [ "$remote_sha" = "$all_zeroes" ]; then
    paths=$(git ls-tree -r --name-only "$local_sha")
  else
    # Do not compare against a guessed base when the advertised remote object
    # is unavailable locally. Validate the pushed commit conservatively instead.
    if ! paths=$(git diff --name-only "$remote_sha" "$local_sha" -- 2>/dev/null); then
      add_commit "$local_sha"
      continue
    fi
  fi

  if printf '%s\n' "$paths" | has_submodule_path; then
    add_commit "$local_sha"
  fi
done

# Direct `lefthook run pre-push` probes and unusual Git clients may provide no
# ref-update stream. Keep the adapter conservative in that case.
if [ "$saw_update" -eq 0 ]; then
  if paths=$(git diff --name-only HEAD '@{push}' -- 2>/dev/null); then
    if printf '%s\n' "$paths" | has_submodule_path; then
      add_commit "$(git rev-parse HEAD)"
    fi
  else
    add_commit "$(git rev-parse HEAD)"
  fi
fi

while IFS= read -r commit; do
  [ -n "$commit" ] || continue
  just hook-submodule-reachability "$commit"
done <"$commits_file"
