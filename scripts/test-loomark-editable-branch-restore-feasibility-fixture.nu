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
  let result = (^nu $runner --output-dir $output | complete)
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
    print "PASS Gate R0 canonical artifact contract"
  } catch {|err|
    ^rm -rf $output
    error make { msg: $err.msg }
  }
  ^rm -rf $output
}
