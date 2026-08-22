export const BROWSER_MEASUREMENT_INTERVALS = [
  "storage_read_ms",
  "archive_open_ms",
  "restore_to_text_observed_ms",
  "first_edit_ms",
  "first_edit_storage_write_ms",
  "restore_plus_first_edit_ms",
]

function measurementFailure(message) {
  throw new Error(`measurement_failure: ${message}`)
}

function requireMilliseconds(value, label) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    measurementFailure(`${label} must be a finite non-negative number`)
  }
  return value
}

export function nearestRankSummary(values) {
  if (!Array.isArray(values) || values.length === 0) {
    measurementFailure("nearest-rank summary requires samples")
  }
  const raw = values.map((value, index) => requireMilliseconds(value, `sample ${index}`))
  const sorted = [...raw].sort((left, right) => left - right)
  const selected = percentage => {
    const rank = Math.ceil((percentage / 100) * sorted.length)
    return { rank, value_ms: sorted[rank - 1] }
  }
  return {
    n: raw.length,
    raw_values_ms: raw,
    p50: selected(50),
    p95: selected(95),
    max_ms: sorted.at(-1),
  }
}

export function buildBrowserMeasurement({ fixtureId, browserVersion, samples }) {
  if (typeof fixtureId !== "string" || fixtureId.length === 0) {
    measurementFailure("fixture id is missing")
  }
  if (typeof browserVersion !== "string" || browserVersion.length === 0) {
    measurementFailure("browser revision is missing")
  }
  if (!Array.isArray(samples) || samples.length !== 20) {
    measurementFailure("expected exactly 20 measured reloads")
  }
  for (const [index, sample] of samples.entries()) {
    if (sample?.sample !== index) {
      measurementFailure(`sample order mismatch at ${index}`)
    }
    for (const interval of BROWSER_MEASUREMENT_INTERVALS) {
      if (!Object.hasOwn(sample, interval)) {
        measurementFailure(`missing ${interval} for sample ${index}`)
      }
      requireMilliseconds(sample[interval], `${interval} for sample ${index}`)
    }
    if (sample.storage_read_ms + sample.archive_open_ms > sample.restore_to_text_observed_ms) {
      measurementFailure(`restore interval ordering is invalid for sample ${index}`)
    }
    if (sample.first_edit_storage_write_ms > sample.first_edit_ms) {
      measurementFailure(`first-edit interval ordering is invalid for sample ${index}`)
    }
    if (
      sample.restore_to_text_observed_ms + sample.first_edit_ms >
      sample.restore_plus_first_edit_ms
    ) {
      measurementFailure(`restore-plus-first-edit interval ordering is invalid for sample ${index}`)
    }
  }
  return {
    fixture_id: fixtureId,
    browser_version: browserVersion,
    consumer: "full_history_v1",
    output: "release_warren_static",
    warmup_navigations: 1,
    measured_reloads: samples.length,
    samples,
    intervals: Object.fromEntries(BROWSER_MEASUREMENT_INTERVALS.map(interval => [
      interval,
      nearestRankSummary(samples.map(sample => sample[interval])),
    ])),
    fallback_error: {
      applicability: "not_applicable",
      reason: "valid_fixture_no_recovery",
    },
  }
}

export function buildBrowserTimingNotApplicable(fixtureId, candidate) {
  return {
    schema_version: 1,
    run_id: "gate-r0-v1",
    case_id: fixtureId,
    producer: "runner",
    status: "pass",
    payload: {
      record: "candidate_result",
      candidate,
      path: "browser_product_restore",
      outcome: "not_applicable",
      reason: "product_restore_seam_absent",
    },
  }
}
