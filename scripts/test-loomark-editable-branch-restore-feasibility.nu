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

def normalize-operations [operations: list<any> writer_id: string] {
  $operations | each {|raw|
    let operation = ($raw | to json -r | str replace --all $writer_id '$fresh-writer' | from json)
    { identity: $operation.id parents: $operation.parents payload: { kind: $operation.kind content: ($operation | get -o content) origin_left: ($operation | get -o origin_left) origin_right: ($operation | get -o origin_right) } }
  }
}

def run-markdown-oracle [root: string mode: string = "undelete"] {
  let produced = (^moon -C $root run apps/loomark/restore_feasibility_oracle --target native producer | complete)
  if $produced.exit_code != 0 { fail $"Markdown archive producer failed: ($produced.stderr)" }
  let producer_raw = ($produced.stdout | str trim | from json)
  let oracle_history = ($producer_raw.payload.oracle_post_edit_history | from json)
  let oracle_next_operations = (normalize-operations $oracle_history.operations $producer_raw.payload.oracle_writer_id)
  if ($oracle_next_operations | is-empty) { fail "Markdown oracle emitted no next operations" }
  let oracle_frontier = ($producer_raw.payload.oracle_post_edit_frontier | str replace --all $producer_raw.payload.oracle_writer_id '$fresh-writer' | from json)
  let producer = ($producer_raw | upsert payload.oracle_next_operation ($oracle_next_operations | first) | upsert payload.oracle_next_operations $oracle_next_operations | upsert payload.oracle_post_edit_frontier $oracle_frontier)
  let archive_bytes = $producer.payload.archive_json
  let consumer = (with-env { GATE_R0_ARCHIVE_JSON: $archive_bytes } { ^moon -C $root run apps/loomark/restore_feasibility_oracle --target native consumer $mode } | complete)
  if $consumer.exit_code != 0 { fail $"Markdown fresh consumer failed: ($consumer.stderr)" }
  let consumer_raw = ($consumer.stdout | str trim | from json)
  let consumer_history = ($consumer_raw.payload.post_insert_history | from json)
  let consumer_next_operations = (normalize-operations $consumer_history.operations $consumer_raw.payload.fresh_writer_id)
  if $mode != "restore" and ($consumer_next_operations | is-empty) { fail "Markdown consumer emitted no next operations" }
  let consumer_frontier = ($consumer_raw.payload.frontier_after_insert | str replace --all $consumer_raw.payload.fresh_writer_id '$fresh-writer' | from json)
  let consumer_row = if $mode == "restore" {
    $consumer_raw | upsert payload.next_operation null | upsert payload.next_operations []
  } else {
    $consumer_raw | upsert payload.next_operation ($consumer_next_operations | first) | upsert payload.next_operations $consumer_next_operations
  } | upsert payload.frontier_after_insert $consumer_frontier
  [$producer $consumer_row]
}

def prepare-browser-standalone [root: string output: string] {
  let build = (^moon -C $root build --quiet --release --target js apps/loomark/main apps/loomark/worker apps/loomark/projection_worker | complete)
  if $build.exit_code != 0 { fail $"browser standalone build failed: ($build.stderr)" }
  let dist = ($output | path join ".browser-dist" | path expand)
  rm -rf $dist
  mkdir $dist
  ^cp ($root | path join "apps/loomark/public/styles.css") ($dist | path join "styles.css")
  ^cp ($root | path join "apps/loomark/public/favicon.svg") ($dist | path join "favicon.svg")
  ^cp ($root | path join "_build/js/release/build/dowdiness/loomark/main/main.js") ($dist | path join "index.js")
  ^cp ($root | path join "_build/js/release/build/dowdiness/loomark/worker/worker.js") ($dist | path join "capability-worker.js")
  ^cp ($root | path join "_build/js/release/build/dowdiness/loomark/projection_worker/projection_worker.js") ($dist | path join "projection-worker.js")
  let html = (open --raw ($root | path join "apps/loomark/public/index.html") | str replace "</body>" "    <script type=\"module\" src=\"./index.js\"></script>\n  </body>")
  $html | save -f ($dist | path join "index.html")
  $dist
}

def run-browser-catalog [root: string output: string] {
  let fixture_root = ($root | path join "apps/loomark/examples/vanilla/fixtures/r0-browser-v1")
  let catalog_path = ($fixture_root | path join "browser-fixture-catalog-v1.json")
  if not ($catalog_path | path exists) { fail "browser fixture catalog is missing" }
  let integrity = (^node ($root | path join "apps/loomark/examples/vanilla/test-r0-browser-fixtures.mjs") | complete)
  if $integrity.exit_code != 0 { fail $"browser fixture integrity failed: ($integrity.stderr)" }
  let catalog = (open $catalog_path)
  let canonical_catalog = (open ($root | path join "deps/event-graph-walker/internal/restore_feasibility_probe/fixtures/fixture-catalog-v1.json"))
  let expected_ids = [
    S-linear-1000
    S-distributed-1000
    S-tombstone-1000
    S-replacement-1000
    S-unicode-1000
  ]
  if $catalog.schema_version != 1 or $catalog.fixture_seed != "none" or ($catalog.fixtures | get fixture_id) != $expected_ids {
    fail "browser fixture catalog schema mismatch"
  }
  let dist = (prepare-browser-standalone $root $output)
  let oracle = ($root | path join "apps/loomark/examples/vanilla/browser-restore-oracle.mjs")
  mut observations = []
  for fixture in $catalog.fixtures {
    let canonical_fixture = ($canonical_catalog.fixtures | where fixture_id == $fixture.fixture_id | first)
    if $canonical_fixture.canonical_sha256 != $fixture.canonical_fixture_sha256 {
      fail $"browser fixture source catalog mismatch: ($fixture.fixture_id)"
    }
    let archive_path = ($fixture_root | path join $fixture.archive_path)
    if not ($archive_path | path exists) { fail $"browser fixture missing: ($fixture.archive_path)" }
    let archive_hash = (^sha256sum $archive_path | str trim | split row " " | first)
    let archive_bytes = (^stat -c "%s" $archive_path | str trim | into int)
    let archive = (open $archive_path)
    let history = ($archive.history | from json)
    if $fixture.event_count != 1000 or $archive_hash != $fixture.archive_sha256 or $archive_bytes != $fixture.archive_bytes or $archive.document_id != $"loomark-r0-fixture-($fixture.fixture_id)" or ($history.operations | length) != $fixture.event_count {
      fail $"browser fixture catalog mismatch: ($fixture.fixture_id)"
    }
    let result = (^node $oracle $archive_path $fixture.fixture_id ($fixture.event_count | into string) $dist | complete)
    if $result.exit_code != 0 { fail $"fresh Chromium fixture failed for ($fixture.fixture_id): ($result.stderr)" }
    let row = ($result.stdout | lines | where {|line| $line | str trim | is-not-empty } | last | from json)
    if ($row.payload.browser_version | is-empty) {
      fail $"browser revision missing: ($fixture.fixture_id)"
    }
    if $row.schema_version != 1 or $row.run_id != "gate-r0-v1" or $row.case_id != $fixture.fixture_id or $row.status != "pass" or $row.payload.record != "browser_oracle_result" or $row.payload.operation_count != 1000 or $row.payload.post_edit_operation_count != 1001 or $row.payload.archive_sha256 != $fixture.archive_sha256 or $row.payload.restored_text_sha256 != $fixture.expected_text_sha256 or $row.payload.restored_history_sha256 != $fixture.history_sha256 or $row.payload.selected_consumer != "full_history_v1" or $row.payload.candidate_consumer_starts != 0 or $row.payload.full_history_consumer_starts != 1 or $row.payload.first_edit.scalar != "U+005A" or $row.payload.first_edit.canonical_utf16_position != $fixture.expected_text_utf16_units or not $row.payload.first_edit.browser_control_position_valid or not $row.payload.first_edit.adapter_mapping_proved or not $row.payload.first_edit.result_equal or not $row.payload.edit_persisted_after_fresh_page {
      fail $"browser fixture result mismatch: ($fixture.fixture_id)"
    }
    let accounting = $row.payload.read_accounting
    if $accounting.archive_transport_bytes != $fixture.archive_bytes or $accounting.archive_decode_read_operations != 1 or $accounting.oracle_full_history_event_reads != 1000 or $accounting.candidate_event_reads != 0 or $accounting.first_edit_local_operations != 1 {
      fail $"browser fixture read accounting mismatch: ($fixture.fixture_id)"
    }
    $observations = ($observations | append $row)
  }
  if not ($observations | any {|row| not $row.payload.first_edit.coordinate_positions_equal }) {
    fail "browser corpus did not exercise CRLF coordinate mapping"
  }
  let browser_revisions = ($observations | get payload.browser_version | uniq)
  if ($browser_revisions | length) != 1 {
    fail "browser revision differs across fixtures"
  }
  rm -rf $dist
  $observations
}

def operation-matrix [] {
  [
    {trace: "initial-materialization" authority: "exact_frontier" projection: "plain_text" expected: "oracle"}
    {trace: "local-insert-start" authority: "writer_policy" projection: "editable_branch" expected: "strict-forward"}
    {trace: "local-insert-middle" authority: "writer_policy" projection: "editable_branch" expected: "strict-forward"}
    {trace: "local-insert-end" authority: "writer_policy" projection: "editable_branch" expected: "strict-forward"}
    {trace: "sequential-insert" authority: "writer_policy" projection: "editable_branch" expected: "strict-forward"}
    {trace: "non-bmp-utf16" authority: "position_identity_index" projection: "editable_branch" expected: "strict-forward"}
    {trace: "visible-delete" authority: "payload_target_lookup" projection: "editable_branch" expected: "strict-forward"}
    {trace: "stale-delete" authority: "payload_target_lookup" projection: "editable_branch" expected: "recovery"}
    {trace: "undelete" authority: "payload_target_lookup" projection: "editable_branch" expected: "strict-forward"}
    {trace: "duplicate" authority: "identity_membership" projection: "plain_text" expected: "duplicate"}
    {trace: "conflict" authority: "identity_membership" projection: "plain_text" expected: "conflict"}
    {trace: "partial-prefix" authority: "ancestry_pending" projection: "plain_text" expected: "partial-admission"}
    {trace: "source-equal-advance" authority: "exact_frontier" projection: "plain_text" expected: "strict-forward"}
    {trace: "zero-commit-recovery" authority: "ancestry_pending" projection: "plain_text" expected: "recovery"}
    {trace: "missing-parent" authority: "ancestry_pending" projection: "plain_text" expected: "fallback"}
    {trace: "pending-drain" authority: "ancestry_pending" projection: "editable_branch" expected: "pending-drain"}
    {trace: "tail-contained-parallel" authority: "ancestry_pending" projection: "editable_branch" expected: "closed-concurrent"}
    {trace: "missing-origin" authority: "payload_target_lookup" projection: "editable_branch" expected: "fallback"}
    {trace: "missing-target" authority: "payload_target_lookup" projection: "editable_branch" expected: "fallback"}
    {trace: "ancestor-before-base" authority: "ancestry_pending" projection: "editable_branch" expected: "fallback"}
    {trace: "trace-1" authority: "writer_policy" projection: "editable_branch" expected: "strict-forward"}
    {trace: "trace-10" authority: "writer_policy" projection: "editable_branch" expected: "strict-forward"}
    {trace: "trace-100" authority: "writer_policy" projection: "editable_branch" expected: "strict-forward"}
  ]
}

def candidate-outcomes [] {
  [
    { candidate: "A" issue: "#1291" outcome: "not_applicable" reason: "separate retained-state evaluation ticket" }
    { candidate: "B" issue: "#1290" outcome: "not_applicable" reason: "separate retained-state evaluation ticket" }
    { candidate: "C" issue: "#1292" outcome: "not_applicable" reason: "separate retained-state evaluation ticket" }
  ]
}

def artifact-paths [] {
  [
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
}

def cleanup-runner-internals [output: string] {
  for entry in (ls -a $output) {
    let name = ($entry.name | path basename)
    if ($name | str starts-with ".") or $name in ["fixture-catalog.json" "browser-fixture-catalog.json" "browser-results.json"] {
      rm -rf $entry.name
    }
  }
}

def assert-artifact-set [output: string] {
  let expected = (artifact-paths | sort)
  let actual = (ls -a $output | get name | each {|path| $path | path basename } | sort)
  if $actual != $expected {
    fail $"artifact set differs: expected=($expected | to json -r) actual=($actual | to json -r)"
  }
}

def write-failure-artifacts [output: string failure: string] {
  cleanup-runner-internals $output
  write-json ($output | path join "manifest.json") { schema_version: 1 run_id: "gate-r0-v1" status: "fail" }
  write-json ($output | path join "capability-ledger.json") { schema_version: 1 rows: [] }
  write-jsonl ($output | path join "candidate-captures.jsonl") []
  write-json ($output | path join "candidate-results.json") { schema_version: 1 candidates: [] }
  write-jsonl ($output | path join "operation-matrix.jsonl") []
  write-jsonl ($output | path join "oracle-differential.jsonl") []
  write-jsonl ($output | path join "cold-history.jsonl") []
  write-json ($output | path join "negative-results.json") { schema_version: 1 negatives: [] }
  $"Gate R0 failure: ($failure)\n" | save -f ($output | path join "validation.log")
  write-json ($output | path join "result.json") { schema_version: 1 status: "fail" failure_class: $failure candidate_outcomes: (candidate-outcomes) artifact_paths: (artifact-paths) }
  assert-artifact-set $output
}

def candidate-cases [suite: string] {
  match $suite {
    "ordinary" => ["S-linear-1000" "S-tombstone-1000" "S-replacement-1000" "S-unicode-1000" "U-mixed-1000"]
    "concurrency" => ["C-short-10000" "C-multiroot-1000" "A-long-10000-r010"]
    "legacy" => ["S-linear-1000"]
    "all" => ["S-linear-1000" "S-tombstone-1000" "S-replacement-1000" "S-unicode-1000" "U-mixed-1000" "C-short-10000" "C-multiroot-1000" "A-long-10000-r010"]
    _ => { fail $"unknown Gate R0 suite: ($suite)" }
  }
}

def run-candidate-suite [root: string output: string suite: string candidate_case: string = ""] {
  let egw_root = ($root | path join "deps/event-graph-walker")
  let package = "internal/restore_feasibility_probe"
  let cases = if ($candidate_case | is-empty) { candidate-cases $suite } else { [$candidate_case] }
  let pinned_catalog_path = ($egw_root | path join "internal/restore_feasibility_probe/fixtures/fixture-catalog-v1.json")
  if not ($pinned_catalog_path | path exists) { fail "pinned fixture catalog is missing" }
  let pinned_source = (open --raw $pinned_catalog_path)
  let catalog_sha256 = (^sha256sum $pinned_catalog_path | str trim | split row " " | first)
  let regenerated_path = ($output | path join ".regenerated-fixture-catalog.json")
  let regenerated = (with-env { NEW_MOON_MOD: "0" } {
    ^moon -C $egw_root run --quiet --release --target native $package -- generate-catalog --output $regenerated_path | complete
  })
  if $regenerated.exit_code != 0 { fail $"fixture catalog regeneration failed: ($regenerated.stderr)" }
  let regenerated_source = (open --raw $regenerated_path)
  rm -f $regenerated_path
  if $regenerated_source != $pinned_source { fail "pinned fixture catalog differs from deterministic regeneration" }
  let catalog = ($pinned_source | from json)
  if $catalog.schema_version != 1 or $catalog.fixture_seed != "none" or ($catalog.fixtures | is-empty) {
    fail "fixture catalog schema mismatch"
  }
  mut captures = []
  mut results = []
  for case_id in $cases {
    let produced = (with-env { NEW_MOON_MOD: "0" } {
      ^moon -C $egw_root run --quiet --release --target native $package -- produce --catalog $pinned_catalog_path --case-id $case_id | complete
    })
    if $produced.exit_code != 0 { fail $"native candidate producer failed for ($case_id): ($produced.stderr)" }
    let capture = ($produced.stdout | lines | where {|line| $line | str trim | is-not-empty } | last | from json)
    if $capture.payload.record != "candidate_capture" or $capture.case_id != $case_id or $capture.producer != "egw_authority_native" or $capture.status != "pass" {
      fail $"candidate capture schema mismatch for ($case_id)"
    }
    let persisted_capture = ($capture | reject payload.expected_replay_order payload.expected_final_text payload.adapter_observation_sha256)
    let capture_path = ($output | path join $".candidate-($case_id).jsonl")
    write-jsonl $capture_path [$persisted_capture]
    let consumed = (with-env { NEW_MOON_MOD: "0" } {
      ^moon -C $egw_root run --quiet --release --target js $package -- consume --capture-jsonl $capture_path --catalog $pinned_catalog_path --case-id $case_id | complete
    })
    rm -f $capture_path
    if $consumed.exit_code != 0 { fail $"fresh JS candidate consumer failed for ($case_id): ($consumed.stderr)" }
    let result = ($consumed.stdout | lines | where {|line| $line | str trim | is-not-empty } | last | from json)
    if $result.payload.record != "candidate_result" or $result.case_id != $case_id or $result.status != "pass" or $result.payload.outcome != "not_applicable" or $result.payload.provider_fixture_bytes_sha256 != $persisted_capture.payload.provider_fixture_bytes_sha256 {
      fail $"candidate result mismatch for ($case_id)"
    }
    $captures = ($captures | append $persisted_capture)
    $results = ($results | append $result)
  }
  let outcomes = (candidate-outcomes)
  write-json ($output | path join "manifest.json") {
    schema_version: 1
    run_id: "gate-r0-v1"
    suite: $suite
    source_revision: (^git -C $root rev-parse HEAD | str trim)
    egw_revision: (^git -C $egw_root rev-parse HEAD | str trim)
    bytes_only_boundary: "native producer capture file consumed by a separately compiled fresh JS process"
    archive_format_changed: false
    wire_format_changed: false
    public_markdown_interface_changed: false
    fixture_catalog: {
      status: "available"
      path: "deps/event-graph-walker/internal/restore_feasibility_probe/fixtures/fixture-catalog-v1.json"
      sha256: $catalog_sha256
      fixture_seed: $catalog.fixture_seed
      fixture_hashes: ($catalog.fixtures | each {|fixture| {
        fixture_id: $fixture.fixture_id
        canonical_sha256: $fixture.canonical_sha256
      } })
    }
  }
  write-json ($output | path join "capability-ledger.json") { schema_version: 1 rows: (operation-matrix) }
  write-jsonl ($output | path join "candidate-captures.jsonl") $captures
  write-json ($output | path join "candidate-results.json") { schema_version: 1 candidates: $outcomes observations: $results }
  write-jsonl ($output | path join "operation-matrix.jsonl") (operation-matrix)
  write-jsonl ($output | path join "oracle-differential.jsonl") []
  write-jsonl ($output | path join "cold-history.jsonl") []
  write-json ($output | path join "negative-results.json") { schema_version: 1 negatives: $outcomes }
  $"Gate R0 candidate suite pass: ($suite)\nfresh JS observations: ($results | length)\n" | save -f ($output | path join "validation.log")
  write-json ($output | path join "result.json") {
    schema_version: 1
    status: "pass"
    failure_class: null
    suite: $suite
    candidate_outcomes: $outcomes
    artifact_paths: (artifact-paths)
  }
  assert-artifact-set $output
  {
    catalog: $catalog
    catalog_sha256: $catalog_sha256
    captures: $captures
    observations: $results
  }
}

def runner-self-test [root: string] {
  let temp = (^mktemp -d | str trim)
  try {
    for failure in ["preflight_invalid" "toolchain_failure" "submodule_failure" "harness_failure" "oracle_mismatch" "causal_semantics_mismatch" "unexpected_cold_read" "evidence_missing" "interface_drift" "measurement_failure"] {
      let output = ($temp | path join $failure)
      mkdir $output
      write-failure-artifacts $output $failure
      assert-artifact-set $output
      let result = (open ($output | path join "result.json"))
      if $result.status != "fail" or $result.failure_class != $failure or (exit-code $failure) == 0 {
        fail $"failure injection self-test failed: ($failure)"
      }
    }
    let candidate_output = ($temp | path join "candidate")
    mkdir $candidate_output
    let _candidate_bundle = (run-candidate-suite $root $candidate_output "concurrency" "C-multiroot-4")
    assert-artifact-set $candidate_output
    let candidate_result = (open ($candidate_output | path join "result.json"))
    if $candidate_result.status != "pass" { fail "candidate process-seam self-test failed" }
    let authority = (run-producer $root "deps/event-graph-walker/internal/restore_feasibility_probe")
    let positive = ($authority | where case_id == "known-positive-provider-read" | first)
    let fast = ($authority | where {|row| $row.case_id == "strict-forward" or $row.case_id == "closed-concurrent" })
    if $positive.payload.provider_calls != 1 or ($fast | any {|row| $row.payload.provider_calls != 0 }) {
      fail "provider-read positive-control self-test failed"
    }
    print "Gate R0 runner self-test pass"
  } catch {|err|
    rm -rf $temp
    error make { msg: ($err | to json -r) }
  }
  rm -rf $temp
}

def main [
  --output-dir: string = "target/gate-r0"
  --suite: string = "all"
  --candidate-case: string = ""
  --allow-dirty
  --inject-failure: string = ""
  --self-test
  --ide-check
] {
  let root = ([$env.FILE_PWD, ".."] | path join | path expand)
  if $ide_check { print "Gate R0 runner syntax valid"; return }
  if $self_test { runner-self-test $root; return }
  mkdir $output_dir
  cleanup-runner-internals $output_dir
  if not ($suite in ["all" "self-test" "oracle" "ordinary" "concurrency" "legacy"]) {
    write-failure-artifacts $output_dir "preflight_invalid"
    exit 10
  }
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
  if $suite == "self-test" {
    runner-self-test $root
    let _candidate_bundle = (run-candidate-suite $root $output_dir "concurrency" "C-multiroot-4")
    return
  }
  if $suite in ["ordinary" "concurrency" "legacy"] {
    try {
      let _candidate_bundle = (run-candidate-suite $root $output_dir $suite $candidate_case)
    } catch {|err|
      write-failure-artifacts $output_dir "harness_failure"
      $"($err | to json -r)\n" | save --append ($output_dir | path join "validation.log")
      exit 30
    }
    return
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
    let candidate_bundle = if $suite == "all" {
      let candidate_output = ($output_dir | path join ".candidate-suite")
      mkdir $candidate_output
      let bundle = (run-candidate-suite $root $candidate_output "all" $candidate_case)
      rm -rf $candidate_output
      $bundle
    } else {
      { catalog: { schema_version: 1 fixture_seed: "none" fixtures: [] } catalog_sha256: null captures: [] observations: [] }
    }
    let browser_observations = if $suite in ["all" "oracle"] {
      run-browser-catalog $root $output_dir
    } else {
      []
    }
    let egw = (run-producer $root "deps/event-graph-walker/internal/restore_feasibility_probe")
    write-jsonl ($output_dir | path join "cold-history.jsonl") $egw
    let required_egw = (["known-positive-provider-read" "strict-forward" "closed-concurrent" "immediate-insert-zero-read" "immediate-delete-zero-read" "immediate-undelete-zero-read"] | append (operation-matrix | get trace))
    let egw_failure = (validate-envelopes $egw $required_egw)
    if ($egw_failure | is-not-empty) { write-failure-artifacts $output_dir $egw_failure; exit (exit-code $egw_failure) }
    for matrix_row in (operation-matrix) {
      let observation = ($egw | where case_id == $matrix_row.trace | first)
      if $observation.payload.classification != $matrix_row.expected { write-failure-artifacts $output_dir "causal_semantics_mismatch"; exit 32 }
    }
    let semantic_checks = [
      { case_id: "duplicate" field: "duplicate" expected: "observed" }
      { case_id: "conflict" field: "conflict" expected: "rejected" }
      { case_id: "partial-prefix" field: "pending" expected: "unresolved" }
      { case_id: "missing-parent" field: "pending" expected: "unresolved" }
      { case_id: "ancestor-before-base" field: "pending" expected: "unresolved" }
      { case_id: "pending-drain" field: "pending" expected: "drained" }
    ]
    for check in $semantic_checks {
      let observation = ($egw | where case_id == $check.case_id | first)
      if ($observation.payload | get $check.field) != $check.expected { write-failure-artifacts $output_dir "causal_semantics_mismatch"; exit 32 }
    }
    let positive = ($egw | where case_id == "known-positive-provider-read" | first)
    if $positive.payload.provider_calls != 1 or $positive.payload.provider_operations <= 0 or $positive.payload.provider_bytes <= 0 {
      write-failure-artifacts $output_dir "evidence_missing"; exit 34
    }
    let fast = ($egw | where {|row| $row.case_id == "strict-forward" or $row.case_id == "closed-concurrent" or ($row.case_id | str starts-with "immediate-") })
    if ($fast | any {|row| $row.payload.provider_calls != 0 or $row.payload.provider_operations != 0 or $row.payload.provider_bytes != 0 }) {
      write-failure-artifacts $output_dir "unexpected_cold_read"; exit 33
    }
    for expected in [
      { case_id: "immediate-insert-zero-read" mode: "insert" operations: 1 }
      { case_id: "immediate-delete-zero-read" mode: "delete" operations: 2 }
      { case_id: "immediate-undelete-zero-read" mode: "undelete" operations: 3 }
    ] {
      let observation = ($egw | where case_id == $expected.case_id | first)
      if $observation.payload.product_mode != $expected.mode or $observation.payload.operation_count != $expected.operations {
        write-failure-artifacts $output_dir "causal_semantics_mismatch"; exit 32
      }
    }
    let markdown_raw = (run-markdown-oracle $root)
    let markdown = if ($env | get -o GATE_R0_TEST_DUPLICATE_MARKDOWN_PARTICIPANT | default "") == "1" {
      $markdown_raw | append ($markdown_raw | where producer == "markdown_oracle" | first)
    } else {
      $markdown_raw
    }
    # Candidate captures are produced only by the native candidate process seam.
    let markdown_failure = (validate-envelopes $markdown [])
    if ($markdown_failure | is-not-empty) { write-failure-artifacts $output_dir $markdown_failure; exit (exit-code $markdown_failure) }
    let archive_participants = ($markdown | where producer == "markdown_archive_producer")
    let oracle_participants = ($markdown | where producer == "markdown_oracle")
    if ($archive_participants | length) != 1 or ($oracle_participants | length) != 1 {
      write-failure-artifacts $output_dir "evidence_missing"
      exit 34
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
    if $archive_consumer.payload.product_recovery_classification != $archive_producer.payload.product_recovery_classification or $archive_consumer.payload.recovery_observability != "loomark-local-archive-load" or $archive_producer.payload.recovery_observability != "loomark-local-archive-load" {
      error make { msg: "causal_semantics_mismatch: product recovery observation differs" }
    }
    if $archive_consumer.payload.fresh_writer_id == $archive_producer.payload.oracle_writer_id {
      error make { msg: "causal_semantics_mismatch: independent restores reused a writer identity" }
    }
    if $archive_consumer.payload.next_operation != $archive_producer.payload.oracle_next_operation or $archive_consumer.payload.next_operations != $archive_producer.payload.oracle_next_operations or $archive_consumer.payload.frontier_after_insert != $archive_producer.payload.oracle_post_edit_frontier {
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
    let captures = $candidate_bundle.captures
    let postflight_interfaces = (interface-hashes $root)
    if $preflight_interfaces != $postflight_interfaces {
      write-failure-artifacts $output_dir "interface_drift"
      exit 35
    }
    let browser_catalog_path = ($root | path join "apps/loomark/examples/vanilla/fixtures/r0-browser-v1/browser-fixture-catalog-v1.json")
    let browser_catalog = (open $browser_catalog_path)
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
      fixture_catalog: {
        status: (if $suite == "all" { "available" } else { "not_run" })
        path: "deps/event-graph-walker/internal/restore_feasibility_probe/fixtures/fixture-catalog-v1.json"
        sha256: $candidate_bundle.catalog_sha256
        fixture_seed: $candidate_bundle.catalog.fixture_seed
        fixture_hashes: ($candidate_bundle.catalog.fixtures | each {|fixture| {
          fixture_id: $fixture.fixture_id
          canonical_sha256: $fixture.canonical_sha256
        } })
      }
      browser_fixture_catalog: {
        status: "available"
        path: "apps/loomark/examples/vanilla/fixtures/r0-browser-v1/browser-fixture-catalog-v1.json"
        sha256: (^sha256sum $browser_catalog_path | str trim | split row " " | first)
        fixture_seed: $browser_catalog.fixture_seed
        archives: ($browser_catalog.fixtures | each {|fixture| {
          fixture_id: $fixture.fixture_id
          path: $fixture.archive_path
          sha256: $fixture.archive_sha256
          bytes: $fixture.archive_bytes
          canonical_fixture_sha256: $fixture.canonical_fixture_sha256
        } })
      }
      browser_oracle_correctness: "pass"
      browser_revision: (($browser_observations | first).payload.browser_version)
      browser_measurement: "not_run"
      preflight: {
        interface_hashes: $preflight_interfaces
        interface_baseline_agrees_after_run: true
        submodule: $submodule
        toolchain: { available: true version: ($toolchain.stdout | str trim) }
        probe_publish_excluded: true
        probe_packaging_evidence: "internal/restore_feasibility_probe is pkgtype executable beneath EGW internal/, absent from public package exports"
      }
    }
    let candidates = (candidate-outcomes)
    let ledger = {
      schema_version: 1
      authority_levels: ["exact_frontier" "identity_membership" "payload_target_lookup" "writer_policy" "sequence_provenance" "duplicate_evidence" "ancestry_pending" "resident_operation_log"]
      projection_levels: ["plain_text" "position_identity_index" "disposable_legacy_materializer" "editable_branch"]
      rows: (operation-matrix)
    }
    let operation_rows = ((operation-matrix) | append ($browser_observations | each {|row| {
      schema_version: 1
      run_id: "gate-r0-v1"
      trace: "browser-full-history-v1"
      case_id: $row.case_id
      authority: "full_history_oracle"
      projection: "loomark_product"
      expected: "oracle"
      actual: "oracle"
      outcome: "pass"
      observation: $row.payload
    } }))
    write-json ($output_dir | path join "manifest.json") $manifest
    write-json ($output_dir | path join "capability-ledger.json") $ledger
    write-jsonl ($output_dir | path join "candidate-captures.jsonl") $captures
    write-json ($output_dir | path join "candidate-results.json") { schema_version: 1 candidates: $candidates observations: $candidate_bundle.observations }
    write-jsonl ($output_dir | path join "operation-matrix.jsonl") $operation_rows
    write-jsonl ($output_dir | path join "oracle-differential.jsonl") ([{ schema_version: 1 run_id: "gate-r0-v1" oracle: "full-history" status: "pass" serialized_archive_bytes: $archive_producer.payload.archive_bytes observations: $markdown memory: { availability: "not_applicable" calibration: "R0 process oracle does not claim resident-memory measurement" } } ] | append $measurements)
    write-jsonl ($output_dir | path join "cold-history.jsonl") $egw
    write-json ($output_dir | path join "negative-results.json") { schema_version: 1 negatives: $candidates }
    $"Gate R0 pass\npositive provider control: 1 call\nstrict/closed provider calls: 0\nfresh Chromium fixture correctness: ($browser_observations | length)\nbrowser measurement: not run\n" | save -f ($output_dir | path join "validation.log")
    write-json ($output_dir | path join "result.json") {
      schema_version: 1
      status: "pass"
      failure_class: null
      implementation_complete: false
      blocked_obligations: [browser_measurement]
      candidate_outcomes: $candidates
      artifact_paths: (artifact-paths)
    }
    assert-artifact-set $output_dir
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
