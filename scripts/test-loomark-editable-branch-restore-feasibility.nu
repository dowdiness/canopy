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

# The generated-interface preflight is intentionally scoped to tracked .mbti
# files, so runner output under the repository cannot change its baseline.
def interface-hashes [root: string] {
  let loomark = "apps/loomark/restore_feasibility_oracle/pkg.generated.mbti"
  let egw = "deps/event-graph-walker/internal/restore_feasibility_probe/pkg.generated.mbti"
  [
    { repo: "canopy" path: $loomark hash: (^sha256sum ($root | path join $loomark) | str trim | split row " " | first) }
    { repo: "event-graph-walker" path: $egw hash: (^sha256sum ($root | path join $egw) | str trim | split row " " | first) }
  ]
}

def submodule-preflight [root: string] {
  let path = ($root | path join "deps/event-graph-walker")
  let recorded = (^git -C $root ls-tree HEAD deps/event-graph-walker | str trim | split row "\t" | first | split row " " | get 2)
  let checked = (^git -C $path rev-parse HEAD | str trim)
  let origin = (^git -C $path remote get-url origin | str trim)
  let reachable = ((^git -C $path branch -r --contains $checked | str trim | is-not-empty))
  { recorded_commit: $recorded checked_out_commit: $checked origin: $origin origin_reachable: $reachable }
}

def summarize-samples [samples: list<any>] {
  let values = ($samples | where phase == "measured" | get elapsed_ns | sort)
  let count = ($values | length)
  { count: $count p50_ns: ($values | get (($count * 50 / 100 | math ceil) - 1)) p95_ns: ($values | get (($count * 95 / 100 | math ceil) - 1)) max_ns: ($values | last) }
}

# Each sample starts fresh producer/consumer processes.  The scenario order is
# rotated per independent run; raw nanoseconds remain in oracle-differential.
def measure-scenario [root: string run: int scenario: string] {
  mut samples = []
  for index in 0..<25 {
    let start = (date now | into int)
    let observation = if ($scenario | str starts-with "trace-") {
      let result = (^moon -C $root run deps/event-graph-walker/internal/restore_feasibility_probe --target native $scenario | complete)
      if $result.exit_code != 0 { error make { msg: "measurement_failure: trace mode failed" } }
      let row = ($result.stdout | lines | last | from json)
      let expected = ($scenario | str replace "trace-" "" | into int)
      if $row.payload.measurement_mode != $scenario or $row.payload.operation_count != $expected { error make { msg: "measurement_failure: trace mode evidence mismatch" } }
      $row
    } else {
      let mode = if $scenario == "restore" { "restore" } else if $scenario == "immediate-insert" { "insert" } else if $scenario == "visible-delete" { "delete" } else { "undelete" }
      let rows = (run-markdown-oracle $root $mode)
      let row = ($rows | where producer == "markdown_oracle" | first)
      if $row.payload.measurement_mode != $mode { error make { msg: "measurement_failure: markdown mode evidence mismatch" } }
      $row
    }
    let finish = (date now | into int)
    let phase = if $index < 5 { "warmup" } else { "measured" }
    $samples = ($samples | append { run: $run scenario: $scenario phase: $phase sample: $index elapsed_ns: ($finish - $start) observation: $observation.payload })
  }
  { schema_version: 1 kind: "measurement" run: $run scenario: $scenario samples: $samples summary: (summarize-samples $samples) }
}

def run-producer [root: string package: string] {
  let result = (^moon -C $root run $package --target native | complete)
  if $result.exit_code != 0 { fail $"producer ($package) failed: ($result.stderr)" }
  let rows = ($result.stdout | lines | where {|line| $line | str trim | is-not-empty } | each {|line| $line | from json })
  if ($rows | length) == 0 { fail $"producer ($package) emitted no JSONL" }
  $rows
}

def validate-envelopes [rows: list<any> required_cases: list<string>] {
  for row in $rows {
    let schema = ($row | get -o schema_version)
    let run_id = ($row | get -o run_id | default "")
    let case_id = ($row | get -o case_id | default "")
    let status = ($row | get -o status | default "")
    if $schema != 1 or $run_id != "gate-r0-v1" or ($case_id | is-empty) {
      return "evidence_missing"
    }
    if $status == "fail" {
      let classification = ($row | get -o payload.failure_class | default "harness_failure")
      return $classification
    }
    if $status != "pass" { return "evidence_missing" }
  }
  for case_id in $required_cases {
    if ($rows | where case_id == $case_id | length) != 1 {
      return "evidence_missing"
    }
  }
  ""
}

def run-markdown-oracle [root: string mode: string = "undelete"] {
  let produced = (^moon -C $root run apps/loomark/restore_feasibility_oracle --target native producer | complete)
  if $produced.exit_code != 0 { fail $"Markdown archive producer failed: ($produced.stderr)" }
  let producer_raw = ($produced.stdout | str trim | from json)
  let archive = ($producer_raw.payload.archive_json | from json)
  let base_history = ($archive.history | from json)
  let base_operation_count = ($base_history.operations | length)
  let oracle_history = ($producer_raw.payload.oracle_post_edit_history | from json)
  let oracle_op = ($oracle_history.operations | get $base_operation_count)
  let oracle_next = { identity: $oracle_op.id parents: $oracle_op.parents payload: { kind: $oracle_op.kind content: ($oracle_op | get -o content) origin_left: ($oracle_op | get -o origin_left) origin_right: ($oracle_op | get -o origin_right) } }
  let producer = ($producer_raw | upsert payload.oracle_next_operation $oracle_next)
  let archive_bytes = $producer.payload.archive_json
  let archive_file = (^mktemp | str trim)
  $archive_bytes | save -f $archive_file
  let consumer = (with-env { GATE_R0_ARCHIVE_PATH: $archive_file } { ^moon -C $root run apps/loomark/restore_feasibility_oracle --target native consumer $mode } | complete)
  ^rm -f $archive_file
  if $consumer.exit_code != 0 { fail $"Markdown fresh consumer failed: ($consumer.stderr)" }
  let consumer_raw = ($consumer.stdout | str trim | from json)
  let consumer_history = ($consumer_raw.payload.post_insert_history | from json)
  let consumer_op = ($consumer_history.operations | get $base_operation_count)
  let consumer_next = { identity: $consumer_op.id parents: $consumer_op.parents payload: { kind: $consumer_op.kind content: ($consumer_op | get -o content) origin_left: ($consumer_op | get -o origin_left) origin_right: ($consumer_op | get -o origin_right) } }
  let consumer_row = ($consumer_raw | upsert payload.next_operation $consumer_next)
  [$producer $consumer_row]
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
  if not (($output | path join "candidate-captures.jsonl") | path exists) { write-jsonl ($output | path join "candidate-captures.jsonl") [] }
  write-json ($output | path join "candidate-results.json") { schema_version: 1 candidates: [] }
  write-jsonl ($output | path join "operation-matrix.jsonl") []
  write-jsonl ($output | path join "oracle-differential.jsonl") []
  if not (($output | path join "cold-history.jsonl") | path exists) { write-jsonl ($output | path join "cold-history.jsonl") [] }
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
  let mbti_before_info = (^git -C $root diff --name-only -- 'apps/loomark/restore_feasibility_oracle/*.mbti' | str trim)
  let egw_before_info = (^git -C ($root | path join "deps/event-graph-walker") diff --name-only -- 'internal/restore_feasibility_probe/*.mbti' | str trim)
  let info = (^moon -C $root info apps/loomark/restore_feasibility_oracle | complete)
  let egw_info = (^moon -C ($root | path join "deps/event-graph-walker") info internal/restore_feasibility_probe | complete)
  let mbti_after_info = (^git -C $root diff --name-only -- 'apps/loomark/restore_feasibility_oracle/*.mbti' | str trim)
  let egw_after_info = (^git -C ($root | path join "deps/event-graph-walker") diff --name-only -- 'internal/restore_feasibility_probe/*.mbti' | str trim)
  if $info.exit_code != 0 or $egw_info.exit_code != 0 or $mbti_before_info != $mbti_after_info or $egw_before_info != $egw_after_info {
    write-failure-artifacts $output_dir "preflight_invalid"
    exit 10
  }
  let preflight_interfaces = (interface-hashes $root)
  let submodule = (submodule-preflight $root)
  let toolchain = (^moon --version | complete)
  if $toolchain.exit_code != 0 { write-failure-artifacts $output_dir "toolchain_failure"; exit 20 }
  if $submodule.recorded_commit != $submodule.checked_out_commit or not $submodule.origin_reachable {
    write-failure-artifacts $output_dir "submodule_failure"
    exit 21
  }
  try {
    let egw = (run-producer $root "deps/event-graph-walker/internal/restore_feasibility_probe")
    write-jsonl ($output_dir | path join "cold-history.jsonl") $egw
    let required_egw = (["known-positive-provider-read" "strict-forward" "closed-concurrent"] | append (operation-matrix | get trace))
    let egw_failure = (validate-envelopes $egw $required_egw)
    if ($egw_failure | is-not-empty) { write-failure-artifacts $output_dir $egw_failure; exit (exit-code $egw_failure) }
    let positive = ($egw | where case_id == "known-positive-provider-read" | first)
    if $positive.payload.provider_calls != 1 or $positive.payload.provider_operations <= 0 or $positive.payload.provider_bytes <= 0 {
      write-failure-artifacts $output_dir "evidence_missing"; exit 34
    }
    let fast = ($egw | where {|row| $row.case_id == "strict-forward" or $row.case_id == "closed-concurrent" })
    if ($fast | any {|row| $row.payload.provider_calls != 0 or $row.payload.provider_operations != 0 or $row.payload.provider_bytes != 0 }) {
      write-failure-artifacts $output_dir "unexpected_cold_read"; exit 33
    }
    let markdown = (run-markdown-oracle $root)
    write-jsonl ($output_dir | path join "candidate-captures.jsonl") ($egw | append $markdown)
    let markdown_failure = (validate-envelopes $markdown [])
    if ($markdown_failure | is-not-empty) { write-failure-artifacts $output_dir $markdown_failure; exit (exit-code $markdown_failure) }
    if ($markdown | where case_id == "full-history-oracle" | length) != 2 {
      error make { msg: "evidence_missing: Markdown producer/consumer correlation missing" }
    }
    let orders = [["restore" "immediate-insert" "visible-delete" "undelete" "trace-1" "trace-10" "trace-100"] ["trace-100" "trace-10" "trace-1" "undelete" "visible-delete" "immediate-insert" "restore"]]
    mut measurements = []
    for run in 0..<2 {
      let build = (^moon -C $root build apps/loomark/restore_feasibility_oracle --target native | complete)
      if $build.exit_code != 0 { error make { msg: "measurement_failure: fresh build failed" } }
      for scenario in ($orders | get $run) {
        $measurements = ($measurements | append (measure-scenario $root $run $scenario))
      }
    }
    let archive_producer = ($markdown | where producer == "markdown_archive_producer" | first)
    let archive_consumer = ($markdown | where producer == "markdown_oracle" | first)
    if $archive_consumer.payload.next_operation != $archive_producer.payload.oracle_next_operation or $archive_consumer.payload.frontier_after_insert != $archive_producer.payload.oracle_post_edit_frontier {
      error make { msg: "causal_semantics_mismatch: normalized next operation or post-edit frontier differs" }
    }
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
    let postflight_interfaces = (interface-hashes $root)
    if $preflight_interfaces != $postflight_interfaces {
      write-failure-artifacts $output_dir "interface_drift"
      exit 35
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
      preflight: {
        interface_hashes: $preflight_interfaces
        interface_baseline_agrees_after_run: true
        submodule: $submodule
        toolchain: { available: true version: ($toolchain.stdout | str trim) }
        probe_publish_excluded: true
        probe_packaging_evidence: "internal/restore_feasibility_probe is pkgtype executable beneath EGW internal/, absent from public package exports"
      }
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
    write-jsonl ($output_dir | path join "oracle-differential.jsonl") ([{ schema_version: 1 run_id: "gate-r0-v1" oracle: "full-history" status: "pass" serialized_archive_bytes: $archive_producer.payload.archive_bytes observations: $markdown memory: { availability: "not_applicable" calibration: "R0 process oracle does not claim resident-memory measurement" } } ] | append $measurements)
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
