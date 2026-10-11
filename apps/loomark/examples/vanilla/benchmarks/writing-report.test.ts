import assert from "node:assert/strict"
import { test } from "node:test"
import { compareRuns, distribution, type Run, type Sample } from "./writing-report.ts"

const sample = (operation: string, totalMs: number, warmup = false): Sample => ({
  operation, warmup, timings: { totalMs }, trusted: true,
})
const run = (variant: Run["variant"], repetition: number, samples: Sample[], error?: string): Run => ({
  variant, scenario: "giant-paragraph-end", repetition, environment: {}, samples, ...(error ? { error } : {}),
})

test("comparison excludes warmups, separates operations and reports target misses without rejecting measurements", () => {
  const rows = compareRuns([
    run("baseline", 0, [sample("insert", 900, true), sample("insert", 5), sample("insert", 7), sample("undo", 1)]),
    run("candidate", 0, [sample("insert", 800, true), sample("insert", 9), sample("insert", 11), sample("undo", 100)]),
  ])
  const insert = rows.find(row => row.operation === "insert")!
  assert.deepEqual(insert.baseline.totalMs, { count: 2, median: 6, p95: 7, max: 7 })
  assert.deepEqual(insert.candidate.totalMs, { count: 2, median: 10, p95: 11, max: 11 })
  assert.equal(insert.change.totalMs.medianDelta, 4)
  assert.equal(insert.target.baselineOverTarget, 0)
  assert.equal(insert.target.candidateOverTarget, 1)
  assert.equal(rows.find(row => row.operation === "undo")!.candidate.totalMs.median, 100)
})

test("an interrupted or failed repetition cannot bias an otherwise complete pair", () => {
  const rows = compareRuns([
    run("baseline", 0, [sample("insert", 2)]),
    run("candidate", 0, [sample("insert", 4)]),
    run("baseline", 1, [sample("insert", 1000)]),
    run("candidate", 2, [sample("insert", 2000)]),
    run("baseline", 3, [sample("insert", 3000)]),
    run("candidate", 3, [sample("insert", 4000)], "Incorrect text after undo"),
  ])
  assert.deepEqual(rows[0].baseline.totalMs, { count: 1, median: 2, p95: 2, max: 2 })
  assert.deepEqual(rows[0].candidate.totalMs, { count: 1, median: 4, p95: 4, max: 4 })
})

test("zero-duration baseline does not fabricate a percentage change", () => {
  const rows = compareRuns([run("baseline", 0, [sample("insert", 0)]), run("candidate", 0, [sample("insert", 1)])])
  assert.equal(rows[0].change.totalMs.medianPercent, null)
  assert.equal(rows[0].change.totalMs.medianDelta, 1)
})

test("invalid timing observations are not accepted as a successful distribution", () => {
  for (const values of [[], [NaN], [Infinity], [-1]]) assert.throws(() => distribution(values))
})
