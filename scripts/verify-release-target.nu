#!/usr/bin/env nu
# Verify that a release tag is absent or resolves to the release source commit.
# The decision is independent of GitHub environment variables; the remote is an
# explicit argument so local callers and regression tests can use a bare repo.

def resolve-tag-commit [remote_output: string tag_ref: string] {
  let rows = ($remote_output
    | lines
    | each {|line| $line | parse -r '^(?P<sha>[0-9a-fA-F]+)[[:space:]]+(?P<ref>.+)$' }
    | flatten)
  let peeled_ref = $tag_ref + "^{}"
  let peeled = ($rows | where ref == $peeled_ref)
  if ($peeled | is-not-empty) {
    $peeled | first | get sha
  } else {
    let direct = ($rows | where ref == $tag_ref)
    if ($direct | is-not-empty) {
      $direct | first | get sha
    } else {
      ""
    }
  }
}

def tag-state [source_sha: string resolved_commit: string] {
  if ($resolved_commit | is-empty) {
    "absent"
  } else if $resolved_commit == $source_sha {
    "same"
  } else {
    "different"
  }
}

def allowed-state [state: string] {
  $state == "absent" or $state == "same"
}

def main [version: string source_sha: string remote: string] {
  if ($source_sha | is-empty) {
    print -e "error: release source SHA must not be empty"
    exit 2
  }

  let tag_ref = "refs/tags/" + $version
  let peeled_ref = $tag_ref + "^{}"
  let result = (^git ls-remote --exit-code $remote $tag_ref $peeled_ref | complete)
  if $result.exit_code != 0 and $result.exit_code != 2 {
    print -e $"error: failed to inspect release tag ($version) on remote ($remote)"
    if ($result.stderr | is-not-empty) {
      print -e $result.stderr
    }
    exit $result.exit_code
  }

  let resolved_commit = if $result.exit_code == 2 {
    ""
  } else {
    resolve-tag-commit $result.stdout $tag_ref
  }
  let state = tag-state $source_sha $resolved_commit

  if not (allowed-state $state) {
    print -e $"error: release tag ($version) resolves to ($resolved_commit), but source is ($source_sha)"
    exit 1
  }

  print $"release target verified: ($version) ($state)"
}
