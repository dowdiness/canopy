#!/usr/bin/env nu

# Gate R0 canonical evidence runner.  Exit codes: 0 pass; 10 preflight; 20
# toolchain; 21 submodule; 30 harness; 31 oracle; 32 causal; 33 cold read; 34
# evidence; 35 interface; 40 measurement; 50 runner failure.  Candidate
# negatives/not-applicable outcomes are evidence, never runner failures.

def fail [message: string] { error make { msg: $message } }

def exit-code [failure: string] {
  match $failure {
    "preflight_invalid" => 10
    "toolchain_failure" => 20
    "submodule_failure" => 21
    "harness_failure" => 30
    "oracle_mismatch" => 31
    "causal_semantics_mismatch" => 32
    "unexpected_cold_read" => 33
    "evidence_missing" => 34
    "interface_drift" => 35
    "measurement_failure" => 40
    _ => 50
  }
}

def write-json [path: string value: any] { $value | to json -r | save -f $path }

def write-jsonl [path: string rows: list<any>] {
  ($rows | each {|row| $row | to json -r } | str join "\n") + "\n" | save -f $path
}

def run-producer [root: string package: string] {
  let result = (^moon -C $root run $package --target native | complete)
  if $result.exit_code != 0 { fail $"producer ($package) failed: ($result.stderr)" }
  let rows = ($result.stdout | lines | where {|line| $line | str trim | is-not-empty } | each {|line| $line | from json })
  if ($rows | length) == 0 { fail $"producer ($package) emitted no JSONL" }
  $rows
}

def run-markdown-oracle [root: string] {
  let produced = (^moon -C $root run apps/loomark/restore_feasibility_oracle --target native producer | complete)
  if $produced.exit_code != 0 { fail $"Markdown archive producer failed: ($produced.stderr)" }
  let producer = ($produced.stdout | str trim | from json)
  let archive_bytes = $producer.payload.archive_json
  let consumer = (with-env { GATE_R0_ARCHIVE_JSON: $archive_bytes } { ^moon -C $root run apps/loomark/restore_feasibility_oracle --target native consumer } | complete)
  if $consumer.exit_code != 0 { fail $"Markdown fresh consumer failed: ($consumer.stderr)" }
  [$producer ($consumer.stdout | str trim | from json)]
}

def operation-matrix [] {
  [
    {trace: "initial-materialization" authority: "exact_frontier" projection: "plain_text" expected: "oracle"}
    {trace: "local-insert-start" authority: "writer_policy" projection: "editable_branch" expected: "strict_forward"}
    {trace: "local-insert-middle" authority: "writer_policy" projection: "editable_branch" expected: "strict_forward"}
    {trace: "local-insert-end" authority: "writer_policy" projection: "editable_branch" expected: "strict_forward"}
    {trace: "sequential-insert" authority: "writer_policy" projection: "editable_branch" expected: "strict_forward"}
    {trace: "non-bmp-utf16" authority: "position_identity_index" projection: "editable_branch" expected: "strict_forward"}
    {trace: "visible-delete" authority: "payload_target_lookup" projection: "editable_branch" expected: "strict_forward"}
    {trace: "stale-delete" authority: "payload_target_lookup" projection: "editable_branch" expected: "recovery"}
    {trace: "undelete" authority: "payload_target_lookup" projection: "editable_branch" expected: "strict_forward"}
    {trace: "duplicate" authority: "identity_membership" projection: "plain_text" expected: "duplicate"}
    {trace: "conflict" authority: "identity_membership" projection: "plain_text" expected: "conflict"}
    {trace: "partial-prefix" authority: "ancestry_pending" projection: "plain_text" expected: "partial_admission"}
    {trace: "source-equal-advance" authority: "exact_frontier" projection: "plain_text" expected: "strict_forward"}
    {trace: "zero-commit-recovery" authority: "ancestry_pending" projection: "plain_text" expected: "recovery"}
    {trace: "missing-parent" authority: "ancestry_pending" projection: "plain_text" expected: "fallback"}
    {trace: "pending-drain" authority: "ancestry_pending" projection: "editable_branch" expected: "pending_drain"}
    {trace: "tail-contained-parallel" authority: "ancestry_pending" projection: "editable_branch" expected: "closed_concurrent"}
    {trace: "missing-origin" authority: "payload_target_lookup" projection: "editable_branch" expected: "fallback"}
    {trace: "missing-target" authority: "payload_target_lookup" projection: "editable_branch" expected: "fallback"}
    {trace: "ancestor-before-base" authority: "ancestry_pending" projection: "editable_branch" expected: "fallback"}
    {trace: "trace-1" authority: "writer_policy" projection: "editable_branch" expected: "strict_forward"}
    {trace: "trace-10" authority: "writer_policy" projection: "editable_branch" expected: "strict_forward"}
    {trace: "trace-100" authority: "writer_policy" projection: "editable_branch" expected: "strict_forward"}
  ]
}

def write-failure-artifacts [output: string failure: string] {
  write-json ($output | path join "manifest.json") { schema_version: 1 run_id: "gate-r0-v1" status: "fail" }
  write-json ($output | path join "capability-ledger.json") { schema_version: 1 rows: [] }
  write-jsonl ($output | path join "candidate-captures.jsonl") []
  write-json ($output | path join "candidate-results.json") { schema_version: 1 candidates: [] }
  write-jsonl ($output | path join "operation-matrix.jsonl") []
  write-jsonl ($output | path join "oracle-differential.jsonl") []
  write-jsonl ($output | path join "cold-history.jsonl") []
  write-json ($output | path join "negative-results.json") { schema_version: 1 negatives: [] }
  $"Gate R0 failure: ($failure)\n" | save -f ($output | path join "validation.log")
  write-json ($output | path join "result.json") { schema_version: 1 status: "fail" failure_class: $failure }
}

def main [--output-dir: string --allow-dirty --inject-failure: string] {
  let root = ([$env.FILE_PWD, ".."] | path join | path expand)
  mkdir $output_dir
  if ($inject_failure | is-not-empty) {
    write-failure-artifacts $output_dir $inject_failure
    exit (exit-code $inject_failure)
  }
  let status = (^git -C $root status --porcelain | complete)
  if $status.exit_code != 0 { exit 10 }
  if (not $allow_dirty) and ($status.stdout | str trim | is-not-empty) {
    write-failure-artifacts $output_dir "preflight_invalid"
    exit 10
  }
  try {
    let egw = (run-producer $root "deps/event-graph-walker/internal/restore_feasibility_probe")
    let markdown = (run-markdown-oracle $root)
    let archive_producer = ($markdown | where producer == "markdown_archive_producer" | first)
    let archive_consumer = ($markdown | where producer == "markdown_oracle" | first)
    if $archive_consumer.payload.text != $archive_producer.payload.expected_after_text {
      error make { msg: "oracle_mismatch: restored edit text differs from producer expectation" }
    }
    let causal_bad = (($archive_consumer.payload.visible_delete_text != $archive_producer.payload.expected_before_text) or ($archive_consumer.payload.undelete_text != $archive_producer.payload.expected_after_text) or ($archive_consumer.payload.target_visibility != "hidden"))
    if $causal_bad {
      error make { msg: "causal_semantics_mismatch: delete/undelete evidence is inconsistent" }
    }
    let identity_bad = (($archive_consumer.payload.fresh_writer_id == $archive_producer.payload.source_writer_id) or ($archive_consumer.payload.frontier_before != $archive_producer.payload.source_frontier))
    if $identity_bad {
      error make { msg: "causal_semantics_mismatch: fresh writer or restored frontier differs" }
    }
    let captures = ($egw | append $markdown)
    let positive = ($egw | where case_id == "known-positive-provider-read" | first)
    if $positive.payload.provider_calls != 1 or $positive.payload.provider_operations <= 0 or $positive.payload.provider_bytes <= 0 {
      fail "known-positive provider control did not fire exactly once with bytes and operations"
    }
    let fast = ($egw | where {|row| $row.case_id == "strict-forward" or $row.case_id == "closed-concurrent" })
    if ($fast | any {|row| $row.payload.provider_calls != 0 or $row.payload.provider_operations != 0 or $row.payload.provider_bytes != 0 }) {
      fail "zero-read fast path observed a canonical provider read"
    }
    let manifest = {
      schema_version: 1
      run_id: "gate-r0-v1"
      shared_effect_boundary: "absent"
      shared_effect_boundary_issue: "#1281"
      source_revision: (^git -C $root rev-parse HEAD | str trim)
      egw_revision: (^git -C ($root | path join "deps/event-graph-walker") rev-parse HEAD | str trim)
      bytes_only_boundary: "separate native producer processes; JSONL stdout is the only joined value"
      archive_format_changed: false
      wire_format_changed: false
      public_markdown_interface_changed: false
    }
    let candidates = [
      { candidate: "A" issue: "#1291" outcome: "not_applicable" reason: "separate retained-state evaluation ticket" }
      { candidate: "B" issue: "#1290" outcome: "not_applicable" reason: "separate retained-state evaluation ticket" }
      { candidate: "C" issue: "#1292" outcome: "not_applicable" reason: "separate retained-state evaluation ticket" }
    ]
    let ledger = {
      schema_version: 1
      authority_levels: ["exact_frontier" "identity_membership" "payload_target_lookup" "writer_policy" "sequence_provenance" "duplicate_evidence" "ancestry_pending" "resident_operation_log"]
      projection_levels: ["plain_text" "position_identity_index" "disposable_legacy_materializer" "editable_branch"]
      rows: (operation-matrix)
    }
    write-json ($output_dir | path join "manifest.json") $manifest
    write-json ($output_dir | path join "capability-ledger.json") $ledger
    write-jsonl ($output_dir | path join "candidate-captures.jsonl") $captures
    write-json ($output_dir | path join "candidate-results.json") { schema_version: 1 candidates: $candidates }
    write-jsonl ($output_dir | path join "operation-matrix.jsonl") (operation-matrix)
    write-jsonl ($output_dir | path join "oracle-differential.jsonl") [{ schema_version: 1 run_id: "gate-r0-v1" oracle: "full-history" status: "pass" observations: $markdown }]
    write-jsonl ($output_dir | path join "cold-history.jsonl") $egw
    write-json ($output_dir | path join "negative-results.json") { schema_version: 1 negatives: [] }
    "Gate R0 pass\npositive provider control: 1 call\nstrict/closed provider calls: 0\n" | save -f ($output_dir | path join "validation.log")
    write-json ($output_dir | path join "result.json") {
      schema_version: 1
      status: "pass"
      failure_class: null
      candidate_outcomes: $candidates
      artifact_paths: ["manifest.json" "result.json" "capability-ledger.json" "candidate-captures.jsonl" "candidate-results.json" "operation-matrix.jsonl" "oracle-differential.jsonl" "cold-history.jsonl" "negative-results.json" "validation.log"]
    }
  } catch {|err|
    let detail = ($err | to json -r)
    let failure = if ($detail | str contains "oracle_mismatch") {
      "oracle_mismatch"
    } else if ($detail | str contains "causal_semantics_mismatch") {
      "causal_semantics_mismatch"
    } else if ($detail | str contains "unexpected_cold_read") {
      "unexpected_cold_read"
    } else if ($detail | str contains "evidence_missing") {
      "evidence_missing"
    } else if ($detail | str contains "measurement_failure") {
      "measurement_failure"
    } else {
      "harness_failure"
    }
    write-failure-artifacts $output_dir $failure
    exit (exit-code $failure)
  }
}
