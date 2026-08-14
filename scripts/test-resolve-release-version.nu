#!/usr/bin/env nu
# Regression tests for the release version event policy.

def run-case [resolver: string name: string event_name: string ref_type: string ref_name: string input_version: string expected_status: int expected_version: string] {
  let result = (^nu $resolver $event_name $ref_type $ref_name $input_version | complete)
  let actual_version = ($result.stdout | str trim)
  if $result.exit_code != $expected_status {
    print -e $"FAIL ($name): expected exit ($expected_status), got ($result.exit_code)"
    if ($result.stderr | is-not-empty) {
      print -e $result.stderr
    }
    exit 1
  }
  if $actual_version != $expected_version {
    print -e $"FAIL ($name): expected output '($expected_version)', got '($actual_version)'"
    exit 1
  }
  print $"PASS ($name)"
}

def main [] {
  let resolver = ($env.FILE_PWD | path expand | path join "resolve-release-version.nu")
  run-case $resolver "workflow dispatch uses input on main" "workflow_dispatch" "branch" "main" "v0.2.0" 0 "v0.2.0"
  run-case $resolver "workflow dispatch ignores feature ref" "workflow_dispatch" "branch" "feature/foo" "v0.2.0" 0 "v0.2.0"
  run-case $resolver "push tag uses tag ref" "push" "tag" "v0.2.0" "" 0 "v0.2.0"
  run-case $resolver "push branch fails" "push" "branch" "main" "" 1 ""
  run-case $resolver "unsupported event fails" "pull_request" "branch" "main" "v0.2.0" 1 ""
  run-case $resolver "empty manual version fails" "workflow_dispatch" "branch" "main" "" 1 ""
  run-case $resolver "invalid manual version fails" "workflow_dispatch" "branch" "main" "0.2.0" 1 ""
  run-case $resolver "leading-zero major fails" "workflow_dispatch" "branch" "main" "v01.2.3" 1 ""
  run-case $resolver "leading-zero minor fails" "workflow_dispatch" "branch" "main" "v1.02.3" 1 ""
  run-case $resolver "leading-zero patch fails" "workflow_dispatch" "branch" "main" "v1.2.03" 1 ""
  run-case $resolver "pre-release version fails under stable policy" "workflow_dispatch" "branch" "main" "v0.2.0-rc.1" 1 ""
  run-case $resolver "invalid push tag fails" "push" "tag" "v0.2.0-rc.1" "" 1 ""
}
