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
    let manifest = (open ($output | path join "manifest.json"))
    assert-equal ($manifest.preflight.interface_hashes | is-empty) false "interface baseline hashes"
    assert-equal ($manifest.preflight.interface_hashes | length) 2 "two scoped interface hashes"
    assert-equal $manifest.preflight.probe_publish_excluded true "probe publication exclusion"
    assert-equal $manifest.preflight.submodule.recorded_commit $manifest.preflight.submodule.checked_out_commit "submodule recorded checkout"
    assert-equal $manifest.preflight.toolchain.available true "toolchain preflight"
    let captures = (open ($output | path join "candidate-captures.jsonl") | lines | each {|line| $line | from json })
    assert-equal (($captures | where producer == "markdown_archive_producer" | length) > 0) true "archive producer evidence"
    assert-equal (($captures | where producer == "markdown_oracle" | length) > 0) true "fresh markdown consumer evidence"
    let archive_capture = ($captures | where producer == "markdown_archive_producer" | first)
    let consumer_capture = ($captures | where producer == "markdown_oracle" | first)
    assert-equal ($consumer_capture.payload.fresh_writer_id != $archive_capture.payload.oracle_writer_id) true "independent fresh writer identities"
    assert-equal $consumer_capture.payload.next_operation $archive_capture.payload.oracle_next_operation "normalized next operation"
    assert-equal $consumer_capture.payload.next_operations $archive_capture.payload.oracle_next_operations "normalized next operation increment"
    assert-equal $consumer_capture.payload.frontier_after_insert $archive_capture.payload.oracle_post_edit_frontier "post-edit frontier"
    let matrix = (open ($output | path join "operation-matrix.jsonl") | lines | each {|line| $line | from json })
    let egw_cases = (open ($output | path join "cold-history.jsonl") | lines | each {|line| $line | from json } | get case_id)
    for row in $matrix {
      assert-equal ($egw_cases | any {|case_id| $case_id == $row.trace }) true $"EGW observation for ($row.trace)"
    }
    for expected in [
      { failure: "preflight_invalid" code: 10 }
      { failure: "toolchain_failure" code: 20 }
      { failure: "submodule_failure" code: 21 }
      { failure: "harness_failure" code: 30 }
      { failure: "oracle_mismatch" code: 31 }
      { failure: "causal_semantics_mismatch" code: 32 }
      { failure: "unexpected_cold_read" code: 33 }
      { failure: "evidence_missing" code: 34 }
      { failure: "interface_drift" code: 35 }
      { failure: "measurement_failure" code: 40 }
      { failure: "runner_failure" code: 50 }
    ] {
      let injected = (^mktemp -d | str trim)
      let injected_result = (^nu $runner --allow-dirty --output-dir $injected --inject-failure $expected.failure | complete)
      assert-equal $injected_result.exit_code $expected.code $"exit code for ($expected.failure)"
      let failed = (open ($injected | path join "result.json"))
      assert-equal $failed.failure_class $expected.failure $"result failure for ($expected.failure)"
      assert-equal ($failed.candidate_outcomes | length) 3 $"failure candidates for ($expected.failure)"
      assert-equal ($failed.artifact_paths | length) 10 $"failure artifacts for ($expected.failure)"
      ^rm -rf $injected
    }
    let cold_output = (^mktemp -d | str trim)
    let cold_result = (with-env { GATE_R0_TEST_FORCE_COLD_READ: "strict-forward" } {
      ^nu $runner --allow-dirty --output-dir $cold_output
    } | complete)
    assert-equal $cold_result.exit_code 33 "live unexpected cold-read exit"
    assert-equal (open ($cold_output | path join "result.json") | get failure_class) "unexpected_cold_read" "live unexpected cold-read classification"
    assert-equal (open ($cold_output | path join "result.json") | get artifact_paths | length) 10 "live cold-read artifact paths"
    ^rm -rf $cold_output
    let missing_output = (^mktemp -d | str trim)
    let missing_result = (with-env { GATE_R0_TEST_OMIT_CASE: "pending-drain" } {
      ^nu $runner --allow-dirty --output-dir $missing_output
    } | complete)
    assert-equal $missing_result.exit_code 34 "live missing-evidence exit"
    assert-equal (open ($missing_output | path join "result.json") | get failure_class) "evidence_missing" "live missing-evidence classification"
    assert-equal (open ($missing_output | path join "result.json") | get candidate_outcomes | length) 3 "live missing-evidence candidates"
    ^rm -rf $missing_output
    let participant_output = (^mktemp -d | str trim)
    let participant_result = (with-env { GATE_R0_TEST_DUPLICATE_MARKDOWN_PARTICIPANT: "1" } {
      ^nu $runner --allow-dirty --output-dir $participant_output
    } | complete)
    assert-equal $participant_result.exit_code 34 "duplicate Markdown participant exit"
    assert-equal (open ($participant_output | path join "result.json") | get failure_class) "evidence_missing" "duplicate Markdown participant classification"
    ^rm -rf $participant_output
    let egw_observations = (open ($output | path join "cold-history.jsonl") | lines | each {|line| $line | from json })
    for row in $matrix {
      let observation = ($egw_observations | where case_id == $row.trace | first)
      assert-equal (($observation.payload.transition | str length) > 0) true $"transition witness for ($row.trace)"
      assert-equal $observation.payload.classification $row.expected $"classification for ($row.trace)"
    }
    print "PASS Gate R0 canonical artifact contract"
  } catch {|err|
    ^rm -rf $output
    error make { msg: $err.msg }
  }
  ^rm -rf $output
}
