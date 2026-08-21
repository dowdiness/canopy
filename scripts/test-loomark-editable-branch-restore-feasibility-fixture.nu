#!/usr/bin/env nu

# Contract fixture for Gate R0's evidence shell.  The production runner owns
# effects; this fixture observes only its process contract and emitted bytes.

def fail [message: string] { error make { msg: $message } }

def assert-equal [actual: any expected: any label: string] {
  if $actual != $expected { fail $"($label): expected ($expected), got ($actual)" }
}

def main [] {
  let runner = ($env.FILE_PWD | path join "test-loomark-editable-branch-restore-feasibility.nu")
  let output = (^mktemp -d | str trim)
  let result = (^nu $runner --allow-dirty --output-dir $output | complete)
  try {
    assert-equal $result.exit_code 0 "canonical gate exits successfully"
    let expected = [
      manifest.json result.json capability-ledger.json candidate-captures.jsonl
      candidate-results.json operation-matrix.jsonl oracle-differential.jsonl
      cold-history.jsonl negative-results.json validation.log
    ]
    let actual = (ls $output | get name | path basename | sort)
    assert-equal $actual ($expected | sort) "fixed artifact set"
    let gate_result = (open ($output | path join "result.json"))
    assert-equal $gate_result.schema_version 1 "result schema"
    assert-equal $gate_result.status "pass" "result status"
    let captures = (open ($output | path join "candidate-captures.jsonl") | lines | each {|line| $line | from json })
    assert-equal (($captures | where producer == "markdown_archive_producer" | length) > 0) true "archive producer evidence"
    assert-equal (($captures | where producer == "markdown_oracle" | length) > 0) true "fresh markdown consumer evidence"
    let matrix = (open ($output | path join "operation-matrix.jsonl") | lines | each {|line| $line | from json })
    let egw_cases = (open ($output | path join "cold-history.jsonl") | lines | each {|line| $line | from json } | get case_id)
    for row in $matrix {
      assert-equal ($egw_cases | any {|case_id| $case_id == $row.trace }) true $"EGW observation for ($row.trace)"
    }
    print "PASS Gate R0 canonical artifact contract"
  } catch {|err|
    ^rm -rf $output
    error make { msg: $err.msg }
  }
  ^rm -rf $output
}
