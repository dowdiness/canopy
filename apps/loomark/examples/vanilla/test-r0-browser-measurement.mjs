import assert from "node:assert/strict"
import test from "node:test"

import {
  BROWSER_MEASUREMENT_INTERVALS,
  buildBrowserMeasurement,
  buildBrowserTimingNotApplicable,
  nearestRankSummary,
} from "./r0-browser-measurement.mjs"

test("nearest-rank summary retains raw values and selects ranks 10 and 19 for n=20", () => {
  const raw = [
    20, 1, 19, 2, 18, 3, 17, 4, 16, 5,
    15, 6, 14, 7, 13, 8, 12, 9, 11, 10,
  ]
  assert.deepEqual(nearestRankSummary(raw), {
    n: 20,
    raw_values_ms: raw,
    p50: { rank: 10, value_ms: 10 },
    p95: { rank: 19, value_ms: 19 },
    max_ms: 20,
  })
})

test("browser measurement requires every applicable interval on all 20 reloads", () => {
  const complete = {
    storage_read_ms: 1,
    archive_open_ms: 2,
    restore_to_text_observed_ms: 10,
    first_edit_ms: 5,
    first_edit_storage_write_ms: 2,
    restore_plus_first_edit_ms: 20,
  }
  const samples = Array.from({ length: 20 }, (_, sample) => ({ sample, ...complete }))
  const result = buildBrowserMeasurement({
    fixtureId: "S-linear-1000",
    browserVersion: "149.0.7827.55",
    samples,
  })
  assert.equal(result.warmup_navigations, 1)
  assert.equal(result.measured_reloads, 20)
  assert.deepEqual(Object.keys(result.intervals), BROWSER_MEASUREMENT_INTERVALS)
  assert.equal(result.intervals.storage_read_ms.n, 20)
  assert.equal(result.intervals.storage_read_ms.p95.rank, 19)
  assert.deepEqual(result.fallback_error, {
    applicability: "not_applicable",
    reason: "valid_fixture_no_recovery",
  })

  assert.throws(
    () => buildBrowserMeasurement({
      fixtureId: "S-linear-1000",
      browserVersion: "149.0.7827.55",
      samples: samples.map((row, index) => index === 7
        ? Object.fromEntries(Object.entries(row).filter(([key]) => key !== "first_edit_ms"))
        : row),
    }),
    /measurement_failure: missing first_edit_ms for sample 7/,
  )
  assert.throws(
    () => buildBrowserMeasurement({
      fixtureId: "S-linear-1000",
      browserVersion: "149.0.7827.55",
      samples: samples.map((row, index) => index === 3
        ? { ...row, restore_plus_first_edit_ms: 12 }
        : row),
    }),
    /measurement_failure: restore-plus-first-edit interval ordering is invalid for sample 3/,
  )
})

test("candidate browser timing is explicitly unavailable without the product seam", () => {
  assert.deepEqual(buildBrowserTimingNotApplicable("S-linear-1000", "A"), {
    schema_version: 1,
    run_id: "gate-r0-v1",
    case_id: "S-linear-1000",
    producer: "runner",
    status: "pass",
    payload: {
      record: "candidate_result",
      candidate: "A",
      path: "browser_product_restore",
      outcome: "not_applicable",
      reason: "product_restore_seam_absent",
    },
  })
})
