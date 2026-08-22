#!/usr/bin/env nu

use ./artifacts.nu [
  artifact-paths
  assert-artifact-set
  reset-artifact-output
  write-failure-bundle
]

def fail [message: string] { error make { msg: $message } }

def expect [condition: bool message: string] {
  if not $condition { fail $message }
}

def expect-error [message: string action: closure] {
  let failed = try {
    do $action
    false
  } catch {
    true
  }
  if not $failed { fail $message }
}

def main [] {
  let expected = [
    "manifest.json"
    "result.json"
    "capability-ledger.json"
    "candidate-captures.jsonl"
    "candidate-results.json"
    "operation-matrix.jsonl"
    "oracle-differential.jsonl"
    "cold-history.jsonl"
    "negative-results.json"
    "validation.log"
  ]
  expect ((artifact-paths) == $expected) "canonical artifact paths differ"

  let temp = (^mktemp -d | str trim)
  let output = ($temp | path join "output")
  let outcomes = [
    { candidate: "A" outcome: "not_applicable" }
    { candidate: "B" outcome: "not_applicable" }
    { candidate: "C" outcome: "not_applicable" }
  ]
  try {
    mkdir $output
    "stale" | save ($output | path join "stale.txt")
    mkdir ($output | path join "stale-directory")
    "nested" | save ($output | path join "stale-directory/nested.txt")
    mkdir ($output | path join ".candidate-suite")
    ^ln -s "stale.txt" ($output | path join "stale-link")

    reset-artifact-output $output
    expect ((ls -a $output | is-empty)) "reset retained stale output entries"

    let external = ($temp | path join "external")
    let linked_output = ($temp | path join "linked-output")
    mkdir $external
    "retain" | save ($external | path join "sentinel.txt")
    ^ln -s $external $linked_output
    expect-error "symlink output root was accepted" {|| reset-artifact-output $linked_output }
    expect (($external | path join "sentinel.txt" | path exists)) "symlink output root deleted external contents"

    let file_output = ($temp | path join "file-output")
    "retain" | save $file_output
    expect-error "regular-file output root was accepted" {|| reset-artifact-output $file_output }
    expect ((open --raw $file_output) == "retain") "regular-file output root was overwritten"

    mkdir ($output | path join "result.json")
    ^ln -s "result.json" ($output | path join "manifest.json")
    write-failure-bundle $output "oracle_mismatch" $outcomes
    assert-artifact-set $output

    let actual = (ls -a $output | get name | each {|path| $path | path basename } | sort)
    expect ($actual == ($expected | sort)) "failure bundle does not contain exactly ten artifacts"
    expect (($output | path join "result.json" | path type) == "file") "result artifact is not a file"
    expect (($output | path join "manifest.json" | path type) == "file") "manifest artifact is not a file"

    let result = (open ($output | path join "result.json"))
    expect ($result.status == "fail") "failure bundle status differs"
    expect ($result.failure_class == "oracle_mismatch") "failure class differs"
    expect ($result.candidate_outcomes == $outcomes) "candidate outcomes differ"
    expect ($result.artifact_paths == $expected) "result artifact inventory differs"

    rm ($output | path join "validation.log")
    expect-error "missing artifact was accepted" {|| assert-artifact-set $output }
    "extra" | save ($output | path join "validation.log")
    "extra" | save ($output | path join "extra.txt")
    expect-error "extra artifact was accepted" {|| assert-artifact-set $output }
  } catch {|error|
    rm -rf $temp
    error make { msg: ($error | get -o msg | default ($error | to json -r)) }
  }
  rm -rf $temp
  print "PASS Gate R0 artifact bundle contract"
}
