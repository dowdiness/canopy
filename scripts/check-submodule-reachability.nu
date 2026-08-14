#!/usr/bin/env nu

# Check the parent checkout's submodule state and configured-origin reachability.
# This command is intentionally read-only: it does not commit, push, change
# branches, or update the superproject's gitlinks.

def fail [message: string] {
  print -e $"error: ($message)"
  exit 1
}

def print-command-error [output: record] {
  if ($output.stderr | is-not-empty) {
    print -e ($output.stderr | str trim)
  }
}

def check-reachable [path: string, sha: string] {
  let fetched = (^git -C $path fetch --quiet --prune origin | complete)
  if $fetched.exit_code != 0 {
    print-command-error $fetched
    fail $"could not fetch submodule origin: ($path)"
  }

  let refs = (^git -C $path for-each-ref '--format=%(refname)' --contains $sha refs/remotes/origin | complete)
  if $refs.exit_code != 0 {
    print-command-error $refs
    fail $"could not inspect submodule origin refs: ($path)"
  }

  if (($refs.stdout | str trim) | is-empty) {
    let exact = (^git -C $path fetch --quiet --no-tags --refetch origin $sha | complete)
    if $exact.exit_code != 0 {
      print-command-error $exact
      print -e $"error: submodule commit is not fetchable from origin: ($path)"
      print -e "push the commit to the configured origin before the parent PR"
      exit 1
    }
  }
}

def parse-status-path [line: string] {
  let path_with_state = ($line | str substring 42.. | str trim)
  $path_with_state | str replace --regex ' \([^)]*\)$' ''
}

def check-current-checkout [] {
  let status = (^git submodule status --recursive | complete)
  if $status.exit_code != 0 {
    print-command-error $status
    exit $status.exit_code
  }

  for line in ($status.stdout | lines) {
    if ($line | is-empty) {
      continue
    }
    let marker = ($line | str substring 0..0)
    match $marker {
      "-" => (fail $"submodule is not initialized: ($line)")
      "+" => (fail $"submodule does not match its recorded gitlink: ($line)")
      "U" => (fail $"submodule has a merge conflict: ($line)")
      _ => {}
    }
  }

  for line in ($status.stdout | lines) {
    if ($line | is-empty) {
      continue
    }
    let path = (parse-status-path $line)
    if ($path | is-empty) {
      fail $"Git returned a submodule status line without a path: ($line)"
    }
    let sha_result = (^git -C $path rev-parse HEAD | complete)
    if $sha_result.exit_code != 0 {
      print-command-error $sha_result
      fail $"could not resolve submodule HEAD: ($path)"
    }
    check-reachable $path ($sha_result.stdout | str trim)
  }
}

def check-commit [commit: string] {
  let tree = (^git ls-tree -r -z --full-tree $commit | complete)
  if $tree.exit_code != 0 {
    print-command-error $tree
    exit $tree.exit_code
  }

  for entry in ($tree.stdout | split row (char nul) | where {|item| $item | is-not-empty }) {
    let fields = ($entry | split row (char tab))
    if ($fields | length) != 2 {
      continue
    }
    let metadata = ($fields.0 | split row " ")
    if ($metadata | length) < 3 or $metadata.0 != "160000" {
      continue
    }

    let sha = $metadata.2
    let path = $fields.1
    let git_dir = (^git -C $path rev-parse --git-dir | complete)
    if $git_dir.exit_code != 0 {
      print-command-error $git_dir
      fail $"submodule is not initialized for pushed commit: ($path)"
    }
    check-reachable $path $sha
  }
}

def main [--commit: string = ""] {
  # FILE_PWD is the directory containing this script, so an absolute invocation
  # from another Git worktree cannot accidentally inspect the caller's repo.
  let root = ([$env.FILE_PWD, ".."] | path join | path expand)
  cd $root

  if ($commit | is-empty) {
    check-current-checkout
    return
  }

  let verified = (^git rev-parse --verify ($commit + "^{commit}") | complete)
  if $verified.exit_code != 0 {
    print-command-error $verified
    fail $"pushed commit is not available locally: ($commit)"
  }
  check-commit ($verified.stdout | str trim)
}
