#!/usr/bin/env node
// PROTOTYPE — combine counterbalanced sustained-input runs without dropping raw samples.
import { readFile, writeFile } from "node:fs/promises"
import { basename } from "node:path"

const [outputPath, ...inputPaths] = process.argv.slice(2)
if (outputPath === undefined || inputPaths.length < 2) {
  throw new Error("usage: aggregate-loomark-localtext-sustained-input.mjs OUTPUT INPUT...")
}

const runs = await Promise.all(inputPaths.map(async path => {
  const parsed = JSON.parse(await readFile(path, "utf8"))
  const firstLane = parsed.results?.find(result => result.measurement_order === 1)?.lane
  const inferredOrder = firstLane === "local_text" ? "local-first" : "full-first"
  return {
    label: basename(path),
    evidence: { ...parsed, lane_order: parsed.lane_order ?? inferredOrder },
  }
}))
const first = runs[0].evidence
for (const { label, evidence } of runs) {
  if (evidence.schema_version !== 1 || evidence.prototype !== true) {
    throw new Error(`unsupported sustained-input evidence: ${label}`)
  }
  if (evidence.burst !== first.burst ||
      evidence.intended_input_interval_ms !== first.intended_input_interval_ms ||
      evidence.browser_version !== first.browser_version) {
    throw new Error(`measurement protocol mismatch: ${label}`)
  }
}

const expectedSamples = new Map([[2000, 10], [10000, 3]])
const expectedOrders = new Set(["full-first", "local-first"])
const expectedLanes = new Set(["full_history_v1", "local_text"])
if (runs.length !== expectedSamples.size * expectedOrders.size) {
  throw new Error("counterbalanced evidence requires exactly four independent runs")
}
for (const [lineCount, sampleCount] of expectedSamples) {
  const matching = runs.filter(run => (
    run.evidence.results.length > 0 &&
    run.evidence.results.every(result => result.line_count === lineCount)
  ))
  if (matching.length !== expectedOrders.size ||
      new Set(matching.map(run => run.evidence.lane_order)).size !== expectedOrders.size ||
      matching.some(run => !expectedOrders.has(run.evidence.lane_order))) {
    throw new Error(`missing counterbalanced lane orders for ${lineCount} lines`)
  }
  const sourceSizes = new Set()
  const seedSizes = new Map()
  for (const { label, evidence } of matching) {
    const laneSet = new Set(evidence.results.map(result => result.lane))
    const orderSet = new Set(evidence.results.map(result => result.measurement_order))
    const expectedFirstLane = evidence.lane_order === "local-first"
      ? "local_text"
      : "full_history_v1"
    const firstResult = evidence.results.find(result => result.measurement_order === 1)
    if (evidence.sample_count !== sampleCount ||
        evidence.results.length !== expectedLanes.size ||
        evidence.results.some(result => result.samples.length !== sampleCount) ||
        laneSet.size !== expectedLanes.size ||
        evidence.results.some(result => !expectedLanes.has(result.lane)) ||
        orderSet.size !== expectedLanes.size ||
        !orderSet.has(1) || !orderSet.has(2) ||
        firstResult?.lane !== expectedFirstLane) {
      throw new Error(`invalid lane/sample/order contract: ${label}`)
    }
    for (const result of evidence.results) {
      sourceSizes.add(result.source_bytes)
      const knownSeedSize = seedSizes.get(result.lane)
      if (knownSeedSize !== undefined && knownSeedSize !== result.seed_bytes) {
        throw new Error(`seed size mismatch for ${lineCount} ${result.lane}`)
      }
      seedSizes.set(result.lane, result.seed_bytes)
    }
  }
  if (sourceSizes.size !== 1 || seedSizes.size !== expectedLanes.size) {
    throw new Error(`source/lane mismatch for ${lineCount} lines`)
  }
}

function percentile(values, percent) {
  const sorted = [...values].sort((left, right) => left - right)
  return sorted[Math.max(0, Math.ceil(percent / 100 * sorted.length) - 1)]
}

function rounded(value) {
  return Number(value.toFixed(3))
}

function summarize(values) {
  return {
    p50: rounded(percentile(values, 50)),
    p95: rounded(percentile(values, 95)),
    max: rounded(Math.max(...values)),
    raw: values.map(rounded),
  }
}

const resultGroups = new Map()
for (const { label, evidence } of runs) {
  for (const result of evidence.results) {
    const key = `${result.line_count}:${result.lane}`
    const group = resultGroups.get(key) ?? {
      line_count: result.line_count,
      lane: result.lane,
      source_bytes: result.source_bytes,
      seed_bytes: result.seed_bytes,
      run_sources: [],
      samples: [],
    }
    group.run_sources.push({
      label,
      lane_order: evidence.lane_order ?? "auto",
      measurement_order: result.measurement_order,
      sample_count: result.samples.length,
    })
    group.samples.push(...result.samples)
    resultGroups.set(key, group)
  }
}

const scalarFields = [
  "content_visible_ms",
  "second_delivery_lag_ms",
  "later_delivery_lag_max_ms",
  "later_scheduled_input_visible_max_ms",
  "later_input_visible_max_ms",
  "later_causal_ready_max_ms",
  "burst_durable_ms",
  "causal_commit_count",
  "write_count",
  "max_long_task_ms",
  "max_frame_gap_ms",
  "persisted_bytes",
]
const aggregateResults = [...resultGroups.values()]
  .sort((left, right) => left.line_count - right.line_count || left.lane.localeCompare(right.lane))
  .map(group => ({
    ...group,
    sample_count: group.samples.length,
    summary: Object.fromEntries(scalarFields.map(field => [
      field,
      summarize(group.samples.map(sample => sample[field])),
    ])),
    per_ordinal_summary: [...first.burst].map((character, ordinal) => ({
      ordinal,
      character,
      delivery_lag_ms: summarize(group.samples.map(sample => sample.per_input[ordinal].delivery_lag_ms)),
      input_visible_ms: summarize(group.samples.map(sample => sample.per_input[ordinal].input_visible_ms)),
      scheduled_input_visible_ms: summarize(
        group.samples.map(sample => sample.per_input[ordinal].scheduled_input_visible_ms),
      ),
      causal_ready_ms: summarize(group.samples.map(sample => sample.per_input[ordinal].causal_ready_ms)),
      scheduled_causal_ready_ms: summarize(
        group.samples.map(sample => sample.per_input[ordinal].scheduled_causal_ready_ms),
      ),
    })),
  }))

const comparisons = [...new Set(aggregateResults.map(result => result.line_count))].map(lineCount => {
  const full = aggregateResults.find(result => result.line_count === lineCount && result.lane === "full_history_v1")
  const local = aggregateResults.find(result => result.line_count === lineCount && result.lane === "local_text")
  if (full === undefined || local === undefined) throw new Error(`missing lane for ${lineCount} lines`)
  return {
    line_count: lineCount,
    local_over_full: Object.fromEntries(scalarFields.map(field => [field, {
      p50: full.summary[field].p50 === 0 ? null : rounded(local.summary[field].p50 / full.summary[field].p50),
      p95: full.summary[field].p95 === 0 ? null : rounded(local.summary[field].p95 / full.summary[field].p95),
    }])),
  }
})

const causalReceiptFieldsRetained = aggregateResults.every(result => (
  result.samples.every(sample => sample.per_input.every(input => (
    Number.isSafeInteger(input.causal_sequence) &&
    Number.isSafeInteger(input.expected_committed_length) &&
    Number.isSafeInteger(input.causal_committed_length)
  )))
))

const output = {
  schema_version: 1,
  prototype: true,
  question: first.question,
  burst: first.burst,
  intended_input_interval_ms: first.intended_input_interval_ms,
  browser_versions: [...new Set(runs.map(run => run.evidence.browser_version))],
  aggregation: "raw samples from independent full-first and local-first browser runs",
  evidence_capabilities: {
    causal_receipt_fields_retained: causalReceiptFieldsRetained,
  },
  limitations: causalReceiptFieldsRetained ? [] : [
    "Selected causal receipt sequence and committed length were validated during measurement but are not retained in these source runs; causal timings are diagnostic rather than independently auditable.",
  ],
  aggregate_results: aggregateResults,
  comparisons,
  runs,
}
await writeFile(outputPath, `${JSON.stringify(output, null, 2)}\n`)
process.stdout.write(`${outputPath}\n`)
