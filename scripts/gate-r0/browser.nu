# Browser-owned full-history oracle adapter for Gate R0. This module owns the
# release-static build, fixed fixture validation, fresh Chromium invocation,
# and normalization of browser observations. The canonical runner sees only
# the returned observation rows.

def fail [message: string] { error make { msg: $message } }

def prepare-browser-standalone [root: string output: string] {
  let _runner_output = $output
  let build = (with-env { NEW_MOON_MOD: "0" } {
    ^moon -C $root build --target js --release | complete
  })
  if $build.exit_code != 0 { fail $"browser release JS build failed: ($build.stderr)" }
  let install = (^bash ($root | path join "scripts/install-local-warren.sh") | complete)
  if $install.exit_code != 0 { fail $"pinned Warren install failed: ($install.stderr)" }
  let warren = ($root | path join "_build/tools/bin/warren")
  let loomark = ($root | path join "apps/loomark")
  let assembled = (do {
    cd $loomark
    ^$warren build | complete
  })
  if $assembled.exit_code != 0 { fail $"release Warren build failed: ($assembled.stderr)" }
  let dist = ($root | path join "apps/loomark/dist" | path expand)
  ^cp ($root | path join "_build/js/release/build/dowdiness/loomark/worker/worker.js") ($dist | path join "capability-worker.js")
  ^cp ($root | path join "_build/js/release/build/dowdiness/loomark/projection_worker/projection_worker.js") ($dist | path join "projection-worker.js")
  for required in [index.html index.js styles.css favicon.svg capability-worker.js projection-worker.js] {
    if not (($dist | path join $required) | path exists) {
      fail $"release Warren output missing: ($required)"
    }
  }
  $dist
}

export def browser-result-rows [observations: list<any>] {
  $observations | each {|row|
    let measurement = $row.payload.browser_measurement
    let oracle = {
      schema_version: 1
      run_id: "gate-r0-v1"
      case_id: $row.case_id
      producer: "loomark_fresh_browser_oracle"
      status: "pass"
      payload: {
        record: "candidate_result"
        candidate: "full_history_oracle"
        path: "browser_full_history_v1"
        outcome: "pass"
        measurement: $measurement
      }
    }
    [$oracle] | append $row.payload.candidate_browser_timing
  } | flatten
}

export def run-browser-catalog [root: string output: string] {
  let fixture_root = ($root | path join "apps/loomark/examples/vanilla/fixtures/r0-browser-v1")
  let catalog_path = ($fixture_root | path join "browser-fixture-catalog-v1.json")
  if not ($catalog_path | path exists) { fail "browser fixture catalog is missing" }
  let integrity = (^node ($root | path join "apps/loomark/examples/vanilla/test-r0-browser-fixtures.mjs") | complete)
  if $integrity.exit_code != 0 { fail $"browser fixture integrity failed: ($integrity.stderr)" }
  let measurement_contract = (^node --test ($root | path join "apps/loomark/examples/vanilla/test-r0-browser-measurement.mjs") | complete)
  if $measurement_contract.exit_code != 0 { fail $"browser measurement contract failed: ($measurement_contract.stderr)" }
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
      fail $"evidence_missing: browser fixture source catalog mismatch: ($fixture.fixture_id)"
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
    if $result.exit_code != 0 {
      let classification = if ($result.stderr | str contains "measurement_failure") { "measurement_failure" } else { "oracle_mismatch" }
      fail $"($classification): fresh Chromium fixture failed for ($fixture.fixture_id): ($result.stderr)"
    }
    let row = ($result.stdout | lines | where {|line| $line | str trim | is-not-empty } | last | from json)
    if $row.payload.browser_version != "149.0.7827.55" {
      fail $"browser revision mismatch: ($fixture.fixture_id)"
    }
    if $row.schema_version != 1 or $row.run_id != "gate-r0-v1" or $row.case_id != $fixture.fixture_id or $row.status != "pass" or $row.payload.record != "browser_oracle_result" or $row.payload.operation_count != 1000 or $row.payload.post_edit_operation_count != 1001 or $row.payload.archive_sha256 != $fixture.archive_sha256 or $row.payload.restored_text_sha256 != $fixture.expected_text_sha256 or $row.payload.restored_history_sha256 != $fixture.history_sha256 or $row.payload.selected_consumer != "full_history_v1" or $row.payload.candidate_consumer_starts != 0 or $row.payload.full_history_consumer_starts != 1 or $row.payload.first_edit.scalar != "U+005A" or $row.payload.first_edit.canonical_utf16_position != $fixture.expected_text_utf16_units or not $row.payload.first_edit.browser_control_position_valid or not $row.payload.first_edit.adapter_mapping_proved or not $row.payload.first_edit.result_equal or not $row.payload.edit_persisted_after_fresh_page {
      fail $"oracle_mismatch: browser fixture result mismatch: ($fixture.fixture_id)"
    }
    let accounting = $row.payload.read_accounting
    if $accounting.archive_transport_bytes != $fixture.archive_bytes or $accounting.archive_decode_read_operations != 1 or $accounting.oracle_full_history_event_reads != 1000 or $accounting.candidate_event_reads != 0 or $accounting.first_edit_local_operations != 1 {
      fail $"oracle_mismatch: browser fixture read accounting mismatch: ($fixture.fixture_id)"
    }
    let measurement = $row.payload.browser_measurement
    let intervals = [storage_read_ms archive_open_ms restore_to_text_observed_ms first_edit_ms first_edit_storage_write_ms restore_plus_first_edit_ms]
    if $measurement.fixture_id != $fixture.fixture_id or $measurement.browser_version != "149.0.7827.55" or $measurement.consumer != "full_history_v1" or $measurement.output != "release_warren_static" or $measurement.warmup_navigations != 1 or $measurement.measured_reloads != 20 or ($measurement.samples | length) != 20 or ($measurement.intervals | columns) != $intervals or $measurement.fallback_error.applicability != "not_applicable" or $measurement.fallback_error.reason != "valid_fixture_no_recovery" {
      fail $"measurement_failure: browser measurement envelope mismatch: ($fixture.fixture_id)"
    }
    for interval in $intervals {
      let summary = ($measurement.intervals | get $interval)
      if $summary.n != 20 or ($summary.raw_values_ms | length) != 20 or $summary.p50.rank != 10 or $summary.p95.rank != 19 or ($summary.raw_values_ms | any {|value| $value < 0 }) {
        fail $"measurement_failure: browser interval mismatch: ($fixture.fixture_id):($interval)"
      }
    }
    let candidate_timing = $row.payload.candidate_browser_timing
    if ($candidate_timing | length) != 2 or ($candidate_timing | get payload.candidate) != [A C] or ($candidate_timing | any {|candidate| $candidate.case_id != $fixture.fixture_id or $candidate.status != "pass" or $candidate.payload.record != "candidate_result" or $candidate.payload.path != "browser_product_restore" or $candidate.payload.outcome != "not_applicable" or $candidate.payload.reason != "product_restore_seam_absent" }) {
      fail $"measurement_failure: candidate browser timing mismatch: ($fixture.fixture_id)"
    }
    $observations = ($observations | append $row)
  }
  if not ($observations | any {|row| not $row.payload.first_edit.coordinate_positions_equal }) {
    fail "oracle_mismatch: browser corpus did not exercise CRLF coordinate mapping"
  }
  let browser_revisions = ($observations | get payload.browser_version | uniq)
  if ($browser_revisions | length) != 1 {
    fail "oracle_mismatch: browser revision differs across fixtures"
  }
  $observations
}
