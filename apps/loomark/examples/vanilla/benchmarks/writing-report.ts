export const INPUT_TARGET_MS = 10

export type Sample = {
  operation: string
  warmup: boolean
  timings: Record<string, number>
  trusted: boolean | null
  inputType?: string
}

export type Run = {
  variant: "baseline" | "candidate"
  scenario: string
  repetition: number
  environment: object
  samples: Sample[]
  error?: string
}

export function distribution(values: number[]) {
  if (values.length === 0 || values.some(value => !Number.isFinite(value) || value < 0)) {
    throw new Error("Timing distributions require finite, nonnegative samples")
  }
  const sorted = [...values].sort((left, right) => left - right)
  const middle = Math.floor(sorted.length / 2)
  return {
    count: sorted.length,
    median: sorted.length % 2 === 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle],
    p95: sorted[Math.ceil(sorted.length * 0.95) - 1],
    max: sorted[sorted.length - 1],
  }
}

export function compareRuns(runs: Run[]) {
  const successful = runs.filter(run => run.error === undefined)
  return [...new Set(successful.map(run => run.scenario))].flatMap(scenario => {
    const matching = successful.filter(run => run.scenario === scenario && successful.some(other =>
      other.scenario === scenario && other.repetition === run.repetition && other.variant !== run.variant))
    const operations = [...new Set(matching.flatMap(run => run.samples.map(sample => sample.operation)))]
    return operations.flatMap(operation => {
      const samplesFor = (variant: Run["variant"]) => matching
        .filter(run => run.variant === variant)
        .flatMap(run => run.samples.filter(sample => !sample.warmup && sample.operation === operation))
      const baseline = samplesFor("baseline")
      const candidate = samplesFor("candidate")
      // Incomplete pairs are kept in raw runs, never presented as a comparison.
      if (baseline.length === 0 || candidate.length === 0) return []
      const summarize = (samples: Sample[]) => Object.fromEntries(
        Object.keys(samples[0].timings).map(metric => [metric, distribution(samples.map(sample => sample.timings[metric]))]),
      )
      const before = summarize(baseline)
      const after = summarize(candidate)
      return [{
        scenario,
        operation,
        baseline: before,
        candidate: after,
        change: Object.fromEntries(Object.keys(before).map(metric => [metric, {
          medianDelta: after[metric].median - before[metric].median,
          p95Delta: after[metric].p95 - before[metric].p95,
          medianPercent: before[metric].median === 0 ? null : (after[metric].median / before[metric].median - 1) * 100,
        }])),
        target: {
          milliseconds: INPUT_TARGET_MS,
          baselineOverTarget: baseline.filter(sample => sample.timings.totalMs > INPUT_TARGET_MS).length,
          candidateOverTarget: candidate.filter(sample => sample.timings.totalMs > INPUT_TARGET_MS).length,
        },
      }]
    })
  })
}

export function markdownReport(runs: Run[], complete: boolean) {
  const rows = compareRuns(runs)
  const number = (value: number) => value.toFixed(2)
  return [
    "# Loomark writing benchmark",
    "",
    complete ? "Measurement completed. Timing differences are informational, not a calibrated regression gate."
      : "INCOMPLETE: a build, measurement or editing-correctness failure prevented a complete comparison.",
    "",
    "The 10 ms target is reported separately; a successful benchmark process does not mean the target was met.",
    "Native total: beforeinput capture through input bubbling. Synthetic total includes selection and setRangeText.",
    "Frame intervals are scheduling observations, not paint-completion timestamps. Focus bounds include measured DOM reads, not all Focus CPU/rendering work.",
    "",
    "| Scenario | Operation | Base median ms | Candidate median ms | Base p95 ms | Candidate p95 ms | Median delta ms | Base max ms | Candidate max ms | Base >10 ms | Candidate >10 ms |",
    "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ...rows.map(row => `| ${row.scenario} | ${row.operation} | ${number(row.baseline.totalMs.median)} | ${number(row.candidate.totalMs.median)} | ${number(row.baseline.totalMs.p95)} | ${number(row.candidate.totalMs.p95)} | ${number(row.change.totalMs.medianDelta)} | ${number(row.baseline.totalMs.max)} | ${number(row.candidate.totalMs.max)} | ${row.target.baselineOverTarget}/${row.baseline.totalMs.count} | ${row.target.candidateOverTarget}/${row.candidate.totalMs.count} |`),
    "",
    "Raw samples, warmups, per-run results, timing breakdowns and release/environment identity are in measurements.json.",
    ...runs.filter(run => run.error).map(run => `\nFailure (${run.variant}, ${run.scenario}): ${run.error}`),
    "",
  ].join("\n")
}
