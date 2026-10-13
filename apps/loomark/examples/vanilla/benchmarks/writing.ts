import assert from "node:assert/strict"
import { spawn } from "node:child_process"
import { createHash } from "node:crypto"
import { once } from "node:events"
import { mkdir, readFile, writeFile } from "node:fs/promises"
import { arch, cpus, platform, release } from "node:os"
import { resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { parseArgs } from "node:util"
import { chromium, type Browser, type Locator, type Page } from "@playwright/test"
import { compareRuns, INPUT_TARGET_MS, markdownReport, type Run, type Sample } from "./writing-report.ts"

const DOCUMENT_BYTES = 1024 * 1024
const WARMUP_ROUNDS = 5
const SAMPLE_ROUNDS = 20
const REPETITIONS = 2
const VIEWPORT = { width: 1280, height: 900 }
const EDITS = [
  { key: "a", operation: "insert", inputType: "insertText" },
  { key: "Backspace", operation: "backspace", inputType: "deleteContentBackward" },
  { key: "Control+z", operation: "undo", inputType: "historyUndo" },
]

type NativeSample = { inputType: string; trusted: boolean; complete: boolean; timings: Record<string, number> }
declare global {
  interface Window {
    __loomarkWritingBenchmark: { samples: NativeSample[]; stop: () => void }
  }
}

type ServedRelease = { url: string; stop: () => Promise<void> }

async function serve(dist: string) {
  const server = spawn(process.execPath, [fileURLToPath(new URL("../serve-standalone-dist.mjs", import.meta.url))], {
    env: { ...process.env, LOOMARK_STANDALONE_DIST: dist, LOOMARK_STANDALONE_PORT: "0" },
    stdio: ["ignore", "pipe", "inherit"],
  })
  const stop = async () => {
    if (server.exitCode !== null || server.signalCode !== null) return
    const closed = once(server, "close")
    const timer = setTimeout(() => server.kill("SIGKILL"), 1_000)
    server.kill("SIGTERM")
    try { await closed } finally { clearTimeout(timer) }
  }
  try {
    const url = await new Promise<string>((done, fail) => {
      const timer = setTimeout(() => fail(new Error("Benchmark server did not become ready")), 5_000)
      let output = ""
      server.stdout.setEncoding("utf8")
      server.stdout.on("data", chunk => {
        output += chunk
        const match = output.match(/http:\/\/127\.0\.0\.1:\d+/)
        if (match) { clearTimeout(timer); done(match[0]) }
      })
      server.once("error", error => { clearTimeout(timer); fail(error) })
      server.once("close", code => { clearTimeout(timer); fail(new Error(`Benchmark server exited (${code})`)) })
    })
    return { url, stop }
  } catch (error) {
    await stop()
    throw error
  }
}

async function frameBoundary(page: Page) {
  await page.evaluate(() => new Promise<void>(done => requestAnimationFrame(() => requestAnimationFrame(() => done()))))
}

async function openDocument(page: Page, url: string, source: string) {
  await page.goto(url)
  await page.getByLabel("Import Markdown").setInputFiles({
    name: "writing-benchmark.md", mimeType: "text/markdown", buffer: Buffer.from(source),
  })
  const text = page.getByRole("textbox", { name: "Text" })
  await page.waitForFunction(source => document.querySelector<HTMLTextAreaElement>("#loomark-text")?.value === source, source)
  await page.evaluate(() => document.fonts.ready.then(() => undefined))
  await frameBoundary(page)
  const rendering = await text.evaluate(element => {
    const style = getComputedStyle(element)
    return {
      devicePixelRatio, font: style.font, lineHeight: style.lineHeight,
      textareaWidth: element.clientWidth, textareaHeight: element.clientHeight,
      userAgent: navigator.userAgent,
      focusMeasurementPresent: document.querySelector(".loomark-writing-measure") !== null,
    }
  })
  return { text, rendering }
}

async function observeInput(text: Locator) {
  await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    // Baseline releases may not implement Writing Focus. Absence is recorded in run metadata.
    const layout = document.querySelector(".loomark-writing-measure")
    const samples: NativeSample[] = []
    let active: NativeSample | null = null
    let started = 0
    let beforeInputEnded = 0
    let inputStarted = 0
    const listeners = new AbortController()
    const bounds = Element.prototype.getBoundingClientRect
    Element.prototype.getBoundingClientRect = function () {
      const sample = active
      if (!sample || !layout?.contains(this)) return bounds.call(this)
      const begin = performance.now()
      try { return bounds.call(this) } finally {
        sample.timings.focusBoundsMs += performance.now() - begin
        sample.timings.focusBoundsCalls++
      }
    }
    const mutations = new MutationObserver(records => {
      if (active) active.timings.focusMutationRecords += records.length
    })
    if (layout) mutations.observe(layout, { subtree: true, childList: true, characterData: true, attributes: true })
    window.addEventListener("beforeinput", event => {
      if (event.target !== area) return
      started = performance.now()
      active = {
        inputType: (event as InputEvent).inputType, trusted: event.isTrusted, complete: false,
        timings: {
          beforeInputMs: 0, betweenEventsMs: 0, inputMs: 0, totalMs: 0,
          inputToFirstFrameMs: 0, inputToSecondFrameMs: 0,
          focusBoundsMs: 0, focusBoundsCalls: 0, focusMutationRecords: 0,
        },
      }
    }, { capture: true, signal: listeners.signal })
    window.addEventListener("beforeinput", event => {
      if (event.target !== area || !active) return
      beforeInputEnded = performance.now()
      active.timings.beforeInputMs = beforeInputEnded - started
    }, { signal: listeners.signal })
    window.addEventListener("input", event => {
      if (event.target !== area || !active) return
      inputStarted = performance.now()
      active.timings.betweenEventsMs = inputStarted - beforeInputEnded
    }, { capture: true, signal: listeners.signal })
    window.addEventListener("input", event => {
      if (event.target !== area || !active) return
      const finished = performance.now()
      const sample = active
      sample.trusted &&= event.isTrusted
      sample.timings.inputMs = finished - inputStarted
      sample.timings.totalMs = finished - started
      samples.push(sample)
      // These callbacks observe scheduling, not paint completion.
      requestAnimationFrame(() => {
        sample.timings.inputToFirstFrameMs = performance.now() - finished
        requestAnimationFrame(() => {
          sample.timings.inputToSecondFrameMs = performance.now() - finished
          sample.complete = true
          active = null
        })
      })
    }, { signal: listeners.signal })
    window.__loomarkWritingBenchmark = {
      samples,
      stop: () => {
        listeners.abort()
        mutations.disconnect()
        Element.prototype.getBoundingClientRect = bounds
      },
    }
  })
}

async function nativeEditing(page: Page, text: Locator, source: string, offset: number, samples: Sample[]) {
  await text.focus()
  await text.evaluate((element, position) => (element as HTMLTextAreaElement).setSelectionRange(position, position), offset)
  await frameBoundary(page)
  await observeInput(text)
  try {
    for (let round = 0; round < WARMUP_ROUNDS + SAMPLE_ROUNDS; round++) {
      // Keep each deletion/Undo pair in its own native undo group.
      await text.press("ArrowLeft")
      await text.press("ArrowRight")
      for (const edit of EDITS) {
        await text.press(edit.key)
        const handle = await page.waitForFunction(index => {
          const sample = window.__loomarkWritingBenchmark.samples[index]
          return sample?.complete ? sample : false
        }, samples.length)
        const sample = await handle.jsonValue() as NativeSample
        await handle.dispose()
        samples.push({ operation: edit.operation, warmup: round < WARMUP_ROUNDS,
          timings: sample.timings, trusted: sample.trusted, inputType: sample.inputType })
        assert.equal(sample.trusted, true, "Native benchmark requires trusted input events")
        assert.equal(sample.inputType, edit.inputType, `Unexpected input sequence for ${edit.operation}`)
        const inserted = round + (edit.operation === "backspace" ? 0 : 1)
        assert.equal(await text.inputValue(), source.slice(0, offset) + "a".repeat(inserted) + source.slice(offset),
          `Incorrect text after ${edit.operation}, round ${round}`)
      }
    }
  } finally {
    await text.evaluate(() => window.__loomarkWritingBenchmark.stop())
  }
}

async function synchronousReplacement(text: Locator, source: string): Promise<Sample[]> {
  const samples = await text.evaluate((element, rounds) => {
    const area = element as HTMLTextAreaElement
    const original = area.value.at(-1)!
    const samples: Sample[] = []
    for (let round = 0; round < rounds.warmup + rounds.measured; round++) {
      for (const replacement of ["y", original]) {
        const started = performance.now()
        const end = area.value.length
        area.setSelectionRange(end - 1, end)
        const selected = performance.now()
        area.dispatchEvent(new InputEvent("beforeinput", { bubbles: true, cancelable: true, composed: true,
          data: replacement, inputType: "insertReplacementText" }))
        const beforeInputEnded = performance.now()
        area.setRangeText(replacement, end - 1, end, "end")
        const replaced = performance.now()
        area.dispatchEvent(new InputEvent("input", { bubbles: true, composed: true,
          data: replacement, inputType: "insertReplacementText" }))
        const finished = performance.now()
        samples.push({ operation: replacement === original ? "revert" : "replace", warmup: round < rounds.warmup,
          trusted: false, timings: { selectionMs: selected - started, beforeInputMs: beforeInputEnded - selected,
            textareaMs: replaced - beforeInputEnded, inputMs: finished - replaced, totalMs: finished - started } })
        if (area.value.length !== end || area.value.at(-1) !== replacement) throw new Error("Replacement corrupted text")
      }
    }
    return samples
  }, { warmup: WARMUP_ROUNDS, measured: SAMPLE_ROUNDS })
  assert.equal(await text.inputValue(), source, "Synchronous replacement did not restore the source")
  return samples
}

async function measure(browser: Browser, url: string, run: Run) {
  const context = await browser.newContext({ viewport: VIEWPORT, deviceScaleFactor: 1,
    colorScheme: "light", reducedMotion: "no-preference", locale: "en-US" })
  const page = await context.newPage()
  page.setDefaultTimeout(15_000)
  const javascriptErrors: string[] = []
  const browserDiagnostics: string[] = []
  page.on("pageerror", error => javascriptErrors.push(error.message))
  page.on("console", message => {
    if (message.type() !== "error") return
    const diagnostic = `${message.location().url}: ${message.text()}`
    // Static releases have no account backend; resource diagnostics are not JavaScript failures.
    if (message.args().length === 0) browserDiagnostics.push(diagnostic)
    else javascriptErrors.push(diagnostic)
  })
  try {
    const heading = "# Native input\n\n"
    const paragraph = "A paragraph for long document editing. ".repeat(16) + "\n\n"
    const source = heading + (run.scenario.startsWith("many-paragraphs")
      ? paragraph.repeat(Math.ceil(DOCUMENT_BYTES / paragraph.length)).slice(0, DOCUMENT_BYTES - heading.length)
      : "x".repeat(DOCUMENT_BYTES - heading.length))
    const { text, rendering } = await openDocument(page, url, source)
    run.environment = { sourceBytes: Buffer.byteLength(source), ...rendering, browserDiagnostics }
    if (run.scenario === "synchronous-replacement") {
      run.samples = await synchronousReplacement(text, source)
    } else {
      await nativeEditing(page, text, source, run.scenario.endsWith("middle") ? Math.floor(source.length / 2) : source.length, run.samples)
    }
    await frameBoundary(page)
    assert.deepEqual(javascriptErrors, [], "JavaScript errors invalidate benchmark results")
  } finally {
    await context.close()
  }
}

const { values } = parseArgs({ options: {
  baseline: { type: "string" }, candidate: { type: "string" }, output: { type: "string", default: "benchmark-results/writing" },
  "baseline-revision": { type: "string" }, "candidate-revision": { type: "string" },
} })
if (!values.baseline || !values.candidate) {
  throw new Error("Usage: npm run benchmark:writing -- --baseline <production-dist> --candidate <production-dist> [--output <directory>]")
}
const output = resolve(values.output!)
await mkdir(output, { recursive: true })
const identities = await Promise.all((["baseline", "candidate"] as const).map(async variant => {
  const dist = resolve(values[variant]!)
  const hashes = await Promise.all(["index.js", "styles.css", "index.html"].map(async file =>
    [file, createHash("sha256").update(await readFile(resolve(dist, file))).digest("hex")]))
  return { variant, dist, revision: values[`${variant}-revision`] ?? null, sha256: Object.fromEntries(hashes) }
}))
const runs: Run[] = []
const report = {
  schemaVersion: 1, complete: false, startedAt: new Date().toISOString(),
  inputTarget: { milliseconds: INPUT_TARGET_MS, enforced: false },
  protocol: { warmupRounds: WARMUP_ROUNDS, sampleRounds: SAMPLE_ROUNDS, repetitions: REPETITIONS,
    order: "baseline/candidate, then candidate/baseline for each scenario", viewport: VIEWPORT },
  environment: { node: process.version, platform: platform(), release: release(), arch: arch(),
    cpu: cpus()[0]?.model, cpuCount: cpus().length, browser: "" },
  releases: identities, runs,
}
const save = async () => {
  await writeFile(resolve(output, "measurements.json"), JSON.stringify({ ...report, comparison: compareRuns(runs) }, null, 2))
  await writeFile(resolve(output, "summary.md"), markdownReport(runs, report.complete))
}
const servers: ServedRelease[] = []
let browser: Browser | undefined
const cleanup = async () => {
  try { await browser?.close() }
  finally { await Promise.all(servers.map(server => server.stop())) }
}
const cancellation = new AbortController()
for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, () => {
    cancellation.abort(new Error(`Benchmark interrupted by ${signal}`))
    process.exitCode = signal === "SIGINT" ? 130 : 143
    // Unwind the measurement; its finally blocks own checkpoint writes and cleanup.
    void browser?.close().catch(error => {
      console.error("Failed to interrupt the benchmark browser:", error)
      process.exitCode = 1
    })
  })
}
try {
  await save()
  for (const identity of identities) {
    cancellation.signal.throwIfAborted()
    servers.push(await serve(identity.dist))
  }
  cancellation.signal.throwIfAborted()
  browser = await chromium.launch()
  cancellation.signal.throwIfAborted()
  report.environment.browser = browser.version()
  const scenarios = ["synchronous-replacement", "giant-paragraph-end", "giant-paragraph-middle", "many-paragraphs-end", "many-paragraphs-middle"]
  for (const scenario of scenarios) {
    for (let repetition = 0; repetition < REPETITIONS; repetition++) {
      for (const variantIndex of repetition % 2 === 0 ? [0, 1] : [1, 0]) {
        cancellation.signal.throwIfAborted()
        const identity = identities[variantIndex]
        const run: Run = { variant: identity.variant, scenario, repetition, environment: {}, samples: [] }
        runs.push(run)
        console.log(`${scenario}: ${run.variant}, repetition ${repetition + 1}`)
        try {
          await measure(browser, servers[variantIndex].url, run)
          cancellation.signal.throwIfAborted()
        } catch (error) {
          const failure = cancellation.signal.aborted ? cancellation.signal.reason : error
          run.error = failure instanceof Error ? failure.stack ?? failure.message : String(failure)
          throw failure
        } finally { await save() }
      }
    }
  }
  cancellation.signal.throwIfAborted()
  report.complete = true
} catch (error) {
  if (!cancellation.signal.aborted || error !== cancellation.signal.reason) throw error
} finally {
  try { await save() } finally { await cleanup() }
}
console.log(markdownReport(runs, report.complete))
console.log(`Benchmark artifacts: ${output}`)
