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

commits_for_push() {
  local_sha=$1
  remote_sha=$2
  if [ "$remote_sha" = "$all_zeroes" ]; then
    git rev-list --reverse "$local_sha" --not --remotes=origin
  else
    git rev-list --reverse "$local_sha" --not "$remote_sha" --remotes=origin
  fi
}

inspect_push_history() {
  local_sha=$1
  remote_sha=$2
  commits=$(commits_for_push "$local_sha" "$remote_sha") || {
    echo "error: could not enumerate commits introduced by the pushed ref" >&2
    exit 1
  }

  while IFS= read -r commit; do
    [ -n "$commit" ] || continue
    paths=$(git diff-tree --root --no-commit-id --name-only -r -m "$commit") || {
      echo "error: could not inspect pushed commit: $commit" >&2
      exit 1
    }
    if printf '%s\n' "$paths" | has_submodule_path; then
      add_commit "$commit"
    fi
  done <<EOF
$commits
EOF
}

saw_update=0
while IFS=' ' read -r _local_ref local_sha _remote_ref remote_sha; do
  [ -n "${local_sha:-}" ] || continue
  saw_update=1
  remote_sha=${remote_sha:-$all_zeroes}

  # A deleted local ref contributes no new tree to the push.
  [ "$local_sha" != "$all_zeroes" ] || continue
  inspect_push_history "$local_sha" "$remote_sha"
done

# Direct `lefthook run pre-push` probes and unusual Git clients may provide no
# ref-update stream. Inspect the checked-out ref against its configured push
# base, or conservatively inspect all origin-unreachable history.
if [ "$saw_update" -eq 0 ]; then
  local_sha=$(git rev-parse HEAD)
  remote_sha=$(git rev-parse '@{push}' 2>/dev/null || printf '%s' "$all_zeroes")
  inspect_push_history "$local_sha" "$remote_sha"
fi

while IFS= read -r commit; do
  [ -n "$commit" ] || continue
  just hook-submodule-reachability "$commit"
done <"$commits_file"
