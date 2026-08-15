#!/usr/bin/env nu
# Regression tests for deterministic, reachable release changelog generation.

def fail [message: string] {
  error make { msg: $message }
}

def git [repo: string args: list<string>] {
  let result = (^git -C $repo ...$args | complete)
  if $result.exit_code != 0 {
    fail $"git failed in ($repo): git ($args | str join ' ')\n($result.stderr)"
  }
  $result.stdout | str trim
}

def make-repo [root: string name: string] {
  let repo = ($root | path join $name)
  mkdir $repo
  git $repo ["init", "--quiet", "--initial-branch=main"] | ignore
  git $repo ["config", "user.email", "release-changelog-test@example.invalid"] | ignore
  git $repo ["config", "user.name", "release-changelog-test"] | ignore
  $repo
}

def commit [repo: string message: string] {
  let file = ($repo | path join "history.txt")
  $message | save -f $file
  git $repo ["add", "history.txt"] | ignore
  git $repo ["commit", "--quiet", "-m", $message] | ignore
  git $repo ["rev-parse", "HEAD"]
}

def run-generator [generator: string repo: string version: string source_sha: string] {
  let output = ($repo | path join "CHANGELOG.txt")
  let result = (do {
    cd $repo
    ^nu $generator $version $source_sha "dowdiness/canopy" $output
  } | complete)
  { result: $result, output: $output }
}

def assert-status [name: string result: record expected: int] {
  if $result.result.exit_code != $expected {
    fail $"FAIL ($name): expected exit ($expected), got ($result.result.exit_code)\n($result.result.stdout)\n($result.result.stderr)"
  }
  print $"PASS ($name)"
}

def commit-line [repo: string sha: string] {
  let subject = (git $repo ["show", "-s", "--format=%s", $sha])
  let abbreviated = (git $repo ["show", "-s", "--format=%h", $sha])
  "- " + $subject + " (" + $abbreviated + ")"
}

def assert-output [name: string output: string expected: string] {
  let actual = (open $output --raw)
  if $actual != $expected {
    fail $"FAIL ($name): changelog snapshot mismatch\nexpected:\n($expected)\nactual:\n($actual)"
  }
  print $"PASS ($name)"
}

def test-shallow-fails [root: string generator: string] {
  let source = (make-repo $root "shallow")
  let sha = (commit $source "shallow source")
  let shallow = ($root | path join "shallow-clone")
  ^git clone --quiet --depth 1 --no-local $source $shallow
  let result = (run-generator $generator $shallow "v9.0.0" (git $shallow ["rev-parse", "HEAD"]))
  assert-status "shallow repository fails" $result 1
}

def test-first-release [root: string generator: string] {
  let repo = (make-repo $root "first-release")
  mut shas = []
  for index in 1..12 {
    $shas = ($shas | append (commit $repo $"commit ($index)"))
  }
  let source = ($shas | last)
  let result = (run-generator $generator $repo "v1.0.0" $source)
  assert-status "first release succeeds" $result 0
  let lines = ($shas | skip 2 | reverse | each {|sha| commit-line $repo $sha } | str join "\n")
  let expected = $"## What's Changed\n\n($lines)\n\n**Full Changelog**: https://github.com/dowdiness/canopy/commits/v1.0.0\n"
  assert-output "first release uses latest 10 and commits link" $result.output $expected
}

def test-reachable-tag-selection [root: string generator: string] {
  let repo = (make-repo $root "reachable-tags")
  let first = (commit $repo "older release commit")
  git $repo ["tag", "-a", "v0.1.0", $first, "-m", "annotated previous"] | ignore
  let second = (commit $repo "selected range commit")
  git $repo ["tag", "btree-v0.2.0", $second] | ignore
  git $repo ["tag", "v0.2.0-rc.1", $second] | ignore
  let source = (commit $repo "release source")
  git $repo ["tag", "v0.2.0", $source] | ignore

  git $repo ["switch", "--quiet", "-c", "side"] | ignore
  let side = (commit $repo "side branch only")
  git $repo ["tag", "v0.1.5", $side] | ignore
  git $repo ["switch", "--quiet", "main"] | ignore

  let result = (run-generator $generator $repo "v0.2.0" $source)
  assert-status "reachable stable tag selection succeeds" $result 0
  let commits = ([(commit-line $repo $source), (commit-line $repo $second)] | str join "\n")
  let expected = $"## What's Changed\n\n($commits)\n\n**Full Changelog**: https://github.com/dowdiness/canopy/compare/v0.1.0...v0.2.0\n"
  assert-output "annotated previous tag is peeled and range is rendered" $result.output $expected
}

def main [] {
  let generator = ($env.FILE_PWD | path expand | path join "generate-release-changelog.nu")
  let root = (^mktemp -d | str trim)
  try {
    test-shallow-fails $root $generator
    test-first-release $root $generator
    test-reachable-tag-selection $root $generator
  } catch {|err|
    ^rm -rf $root
    print -e $err.msg
    exit 1
  }
  ^rm -rf $root
}
