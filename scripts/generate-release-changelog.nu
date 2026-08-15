#!/usr/bin/env nu
# Generate deterministic release notes for a reachable stable Canopy release range.

const SCRIPT_DIR = (path self | path dirname)
source ($SCRIPT_DIR | path join "release-version-policy.nu")

def fail [message: string] {
  print -e $"error: ($message)"
  exit 1
}

def git-output [args: list<string>] {
  let result = (^git ...$args | complete)
  if $result.exit_code != 0 {
    let detail = if ($result.stderr | is-empty) { "" } else { $"\n($result.stderr)" }
    let message = "git command failed: git " + ($args | str join " ") + $detail
    fail $message
  }
  $result.stdout | str trim
}

def git-status [args: list<string>] {
  let result = (^git ...$args | complete)
  $result.exit_code
}

def resolve-source [source_sha: string] {
  let result = (^git rev-parse --verify ($source_sha + "^{commit}") | complete)
  if $result.exit_code != 0 {
    fail $"source commit '($source_sha)' was not found"
  }
  $result.stdout | str trim
}

def tag-candidate [tag: string source: string version: string] {
  if $tag == $version or not (is-stable-version $tag) {
    return null
  }
  let commit_result = (^git rev-parse --verify ("refs/tags/" + $tag + "^{commit}") | complete)
  if $commit_result.exit_code != 0 {
    return null
  }
  let commit = ($commit_result.stdout | str trim)
  if (git-status ["merge-base", "--is-ancestor", $commit, $source]) != 0 {
    return null
  }
  let distance = (git-output ["rev-list", "--count", ($commit + ".." + $source)] | into int)
  { tag: $tag, commit: $commit, distance: $distance }
}

def reachable-stable-tags [source: string version: string] {
  let tags = (git-output ["for-each-ref", "--format=%(refname:strip=2)", "refs/tags"] | lines)
  $tags | each {|tag| tag-candidate $tag $source $version } | compact
}

def previous-tag [source: string version: string] {
  let candidates = (reachable-stable-tags $source $version)
  if ($candidates | is-empty) {
    null
  } else {
    $candidates | sort-by distance tag | first
  }
}

def commit-lines [source: string previous: any] {
  if ($previous | is-empty) {
    git-output ["log", $source, "-10", "--pretty=format:- %s (%h)"]
  } else {
    git-output ["log", ($previous.commit + ".." + $source), "--pretty=format:- %s (%h)"]
  }
}

def main [version: string source_sha: string repository: string output_path: string] {
  if not (is-stable-version $version) {
    fail $"invalid release version '($version)'; expected vMAJOR.MINOR.PATCH"
  }

  let shallow = (git-output ["rev-parse", "--is-shallow-repository"])
  if $shallow == "true" {
    fail "cannot generate release changelog from a shallow repository"
  }

  let source = (resolve-source $source_sha)
  let previous = (previous-tag $source $version)
  let lines = (commit-lines $source $previous)
  let link = if ($previous | is-empty) {
    $"https://github.com/($repository)/commits/($version)"
  } else {
    $"https://github.com/($repository)/compare/($previous.tag)...($version)"
  }
  let changelog = $"## What's Changed\n\n($lines)\n\n**Full Changelog**: ($link)\n"
  $changelog | save --raw -f $output_path
}
