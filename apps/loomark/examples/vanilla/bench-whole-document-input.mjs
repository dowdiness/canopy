import { execFileSync, spawn } from "node:child_process"
import { createHash } from "node:crypto"
import { once } from "node:events"
import { writeFile } from "node:fs/promises"
import { cpus, platform, release } from "node:os"
import { dirname, resolve } from "node:path"
import { performance as nodePerformance } from "node:perf_hooks"
import { fileURLToPath } from "node:url"
import { chromium } from "./node_modules/playwright/index.mjs"

const here = dirname(fileURLToPath(import.meta.url))
const projectRoot = resolve(here, "../../../..")
const serverPath = resolve(here, "serve-standalone-dist.mjs")
const localTextKey = "loomark.active-document-text"
const databaseName = "loomark.local-repository"
const storeName = "archives"
const settleMs = 400
const sizes = parseSizes(process.env.LOOMARK_WHOLE_DOCUMENT_SIZES ?? "65536,262144,1048576")
const warmups = parseCount(process.env.LOOMARK_WHOLE_DOCUMENT_WARMUPS ?? "5", "LOOMARK_WHOLE_DOCUMENT_WARMUPS", 0)
const samples = parseCount(process.env.LOOMARK_WHOLE_DOCUMENT_SAMPLES ?? "30", "LOOMARK_WHOLE_DOCUMENT_SAMPLES", 1)
const traceSamples = parseCount(
  process.env.LOOMARK_WHOLE_DOCUMENT_TRACE_SAMPLES ?? "0",
  "LOOMARK_WHOLE_DOCUMENT_TRACE_SAMPLES",
  0,
)
const requirePersistence = process.env.LOOMARK_WHOLE_DOCUMENT_REQUIRE_PERSISTENCE !== "0"
const outputPath = process.env.LOOMARK_WHOLE_DOCUMENT_OUTPUT

function parseCount(raw, name, minimum) {
  const value = Number.parseInt(raw, 10)
  if (!Number.isSafeInteger(value) || value < minimum) {
    throw new Error(`${name} must be an integer greater than or equal to ${minimum}`)
  }
  return value
}

function parseSizes(raw) {
  const values = raw.split(",").map(value => Number.parseInt(value.trim(), 10))
  if (values.length === 0 || values.some(value => !Number.isSafeInteger(value) || value < 1)) {
    throw new Error("LOOMARK_WHOLE_DOCUMENT_SIZES must contain positive comma-separated integers")
  }
  return [...new Set(values)]
}

function percentile(values, percentage) {
  if (values.length === 0) return null
  const sorted = [...values].sort((left, right) => left - right)
  const rank = Math.max(0, Math.ceil((percentage / 100) * sorted.length) - 1)
  return Number(sorted[rank].toFixed(3))
}

function summarize(values) {
  return {
    samples: values.length,
    p50_ms: percentile(values, 50),
    p95_ms: percentile(values, 95),
    maximum_ms: values.length === 0 ? null : Number(Math.max(...values).toFixed(3)),
  }
}

function fixture(size) {
  const line = "paragraph alpha beta gamma delta epsilon\n\n"
  const source = line.repeat(Math.ceil(size / line.length)).slice(0, size)
  return {
    source,
    utf16_length: source.length,
    utf8_bytes: Buffer.byteLength(source),
    sha256: createHash("sha256").update(source).digest("hex"),
  }
}

function instrumentPage({ key, traceEnabled }) {
  const state = {
    active: null,
    longTasks: [],
    sequence: 0,
  }
  globalThis.__loomarkWholeDocumentBench = state

  document.addEventListener("beforeinput", event => {
    if (state.active === null || !(event.target instanceof HTMLTextAreaElement)) return
    state.active.beforeinput = performance.now()
    if (traceEnabled) performance.mark("loomark-whole:beforeinput")
  }, { capture: true })

  document.addEventListener("input", event => {
    if (state.active === null || !(event.target instanceof HTMLTextAreaElement)) return
    const active = state.active
    active.input = performance.now()
    if (traceEnabled) performance.mark("loomark-whole:input")
    queueMicrotask(() => {
      active.microtask = performance.now()
      if (traceEnabled) performance.mark("loomark-whole:microtask")
    })
  }, { capture: true })

  try {
    new PerformanceObserver(list => {
      for (const entry of list.getEntries()) {
        state.longTasks.push({ start: entry.startTime, duration: entry.duration })
      }
    }).observe({ type: "longtask", buffered: true })
  } catch {}

  const originalPut = IDBObjectStore.prototype.put
  IDBObjectStore.prototype.put = function(value, recordKey) {
    const request = originalPut.apply(this, arguments)
    const active = state.active
    if (active !== null && recordKey === key) {
      const put = {
        request: performance.now(),
        acknowledgment: null,
        outcome: "pending",
      }
      active.puts.push(put)
      if (traceEnabled) performance.mark("loomark-whole:put-request")
      request.addEventListener("success", () => {
        put.acknowledgment = performance.now()
        put.outcome = "stored"
      })
      request.addEventListener("error", () => {
        put.acknowledgment = performance.now()
        put.outcome = "failed"
      })
    }
    return request
  }
}

async function startServer() {
  const server = spawn(process.execPath, [serverPath], {
    env: { ...process.env, LOOMARK_STANDALONE_PORT: "0" },
    stdio: ["ignore", "pipe", "inherit"],
  })
  let output = ""
  const origin = await new Promise((resolveOrigin, reject) => {
    const timeout = setTimeout(() => reject(new Error("standalone server did not become ready")), 5_000)
    server.stdout.setEncoding("utf8")
    server.stdout.on("data", chunk => {
      output += chunk
      const match = output.match(/http:\/\/127\.0\.0\.1:\d+/)
      if (match !== null) {
        clearTimeout(timeout)
        resolveOrigin(match[0])
      }
    })
    server.once("error", error => {
      clearTimeout(timeout)
      reject(error)
    })
    server.once("close", code => {
      clearTimeout(timeout)
      reject(new Error(`standalone server exited before readiness (${code ?? "signal"})`))
    })
  })
  return { server, origin }
}

async function stopServer(server) {
  if (server.exitCode !== null) return
  server.kill("SIGTERM")
  await Promise.race([once(server, "close"), new Promise(resolveTimeout => setTimeout(resolveTimeout, 1_000))])
  if (server.exitCode === null) server.kill("SIGKILL")
}

async function seedLocalText(page, source, documentId) {
  const encoded = JSON.stringify({
    format: "loomark-local-text-v1",
    document_id: documentId,
    portable_markdown: source,
  })
  await page.evaluate(async ({ databaseName, storeName, key, encoded }) => {
    await new Promise((resolveSeed, reject) => {
      const open = indexedDB.open(databaseName, 1)
      open.onupgradeneeded = () => {
        if (!open.result.objectStoreNames.contains(storeName)) {
          open.result.createObjectStore(storeName)
        }
      }
      open.onerror = () => reject(open.error ?? new Error("database open failed"))
      open.onsuccess = () => {
        const database = open.result
        const transaction = database.transaction(storeName, "readwrite")
        transaction.objectStore(storeName).put(encoded, key)
        transaction.oncomplete = () => {
          database.close()
          resolveSeed()
        }
        transaction.onerror = () => reject(transaction.error ?? new Error("fixture seed failed"))
        transaction.onabort = () => reject(transaction.error ?? new Error("fixture seed aborted"))
      }
    })
  }, { databaseName, storeName, key: localTextKey, encoded })
}

async function beginSample(page) {
  await page.evaluate(() => {
    const state = globalThis.__loomarkWholeDocumentBench
    state.active = {
      sequence: ++state.sequence,
      command: performance.now(),
      beforeinput: null,
      input: null,
      microtask: null,
      puts: [],
    }
  })
}

async function finishSample(page, requirePersistence) {
  await page.waitForTimeout(settleMs)
  if (requirePersistence) {
    await page.waitForFunction(key => {
      const active = globalThis.__loomarkWholeDocumentBench?.active
      const matching = active?.puts?.filter(put => put.outcome !== "pending") ?? []
      return matching.length > 0
    }, localTextKey, { timeout: 2_000 })
  }
  return page.evaluate(({ settleMs, requirePersistence }) => {
    const state = globalThis.__loomarkWholeDocumentBench
    const active = state.active
    if (active?.beforeinput === null || active?.input === null || active?.microtask === null) {
      throw new Error("input timing marks are incomplete")
    }
    const puts = active.puts.filter(put => put.acknowledgment !== null)
    if (requirePersistence && puts.length === 0) throw new Error("LocalText persistence was not observed")
    const firstPut = puts[0] ?? null
    const longTasks = state.longTasks
      .filter(task => task.start >= active.input && task.start <= active.input + settleMs)
      .map(task => ({
        offset_ms: Number((task.start - active.input).toFixed(3)),
        duration_ms: Number(task.duration.toFixed(3)),
      }))
    state.active = null
    return {
      native_mutation_ms: Number((active.input - active.beforeinput).toFixed(3)),
      input_handler_ms: Number((active.microtask - active.input).toFixed(3)),
      put_request_offset_ms: firstPut === null
        ? null
        : Number((firstPut.request - active.input).toFixed(3)),
      put_acknowledgment_ms: firstPut === null
        ? null
        : Number((firstPut.acknowledgment - firstPut.request).toFixed(3)),
      put_outcome: firstPut?.outcome ?? null,
      long_tasks: longTasks,
    }
  }, { settleMs, requirePersistence })
}

async function typeSample(page, character, requirePersistence) {
  await beginSample(page)
  const started = nodePerformance.now()
  await page.keyboard.type(character)
  const commandWallMs = nodePerformance.now() - started
  const measured = await finishSample(page, requirePersistence)
  return {
    ...measured,
    browser_command_wall_ms: Number(commandWallMs.toFixed(3)),
  }
}

async function runNative(browser, source, surface, warmupCount, sampleCount) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 720 } })
  await context.addInitScript(instrumentPage, { key: localTextKey, traceEnabled: false })
  const page = await context.newPage()
  const nativeStyle = `${surface.style};width:${surface.width}px`
  const html = `<!doctype html><meta charset="utf-8"><textarea id="native-input" style="${nativeStyle.replaceAll("&", "&amp;").replaceAll('"', "&quot;")}"></textarea>`
  await page.goto(`data:text/html;charset=utf-8,${encodeURIComponent(html)}`)
  await page.locator("#native-input").evaluate((textarea, value) => {
    textarea.value = value
    textarea.setSelectionRange(value.length, value.length)
    textarea.focus()
  }, source)
  const rows = []
  for (let index = 0; index < warmupCount + sampleCount; index += 1) {
    const row = await typeSample(page, index % 2 === 0 ? "x" : "y", false)
    if (index >= warmupCount) rows.push(row)
  }
  await context.close()
  return rows
}

async function runLoomark(browser, origin, source, documentId, warmupCount, sampleCount) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 720 } })
  await context.addInitScript(instrumentPage, { key: localTextKey, traceEnabled: false })
  const page = await context.newPage()
  // Seed from an inert same-origin asset so the application's first-visit
  // baseline write cannot race and overwrite the benchmark fixture.
  await page.goto(`${origin}/favicon.svg`, { waitUntil: "load" })
  await seedLocalText(page, source, documentId)
  await page.goto(origin, { waitUntil: "load" })
  const input = page.locator("#loomark-input")
  await input.waitFor({ state: "visible", timeout: 30_000 })
  await page.waitForFunction(expected => document.querySelector("#loomark-input")?.value === expected, source, {
    timeout: 120_000,
  })
  const surface = await input.evaluate(textarea => ({
    style: textarea.getAttribute("style"),
    width: textarea.getBoundingClientRect().width,
  }))
  if (surface.style === null) throw new Error("Loomark textarea has no inline style")
  await input.evaluate((textarea, offset) => {
    textarea.setSelectionRange(offset, offset)
    textarea.focus()
  }, source.length)
  const rows = []
  for (let index = 0; index < warmupCount + sampleCount; index += 1) {
    const row = await typeSample(page, index % 2 === 0 ? "x" : "y", requirePersistence)
    if (index >= warmupCount) rows.push(row)
  }
  await context.close()
  return { rows, surface }
}

async function startTrace(context, page) {
  const session = await context.newCDPSession(page)
  const events = []
  session.on("Tracing.dataCollected", ({ value }) => events.push(...value))
  await session.send("Tracing.start", {
    categories: "blink.user_timing,devtools.timeline,v8",
    options: "sampling-frequency=10000",
  })
  return { session, events }
}

async function stopTrace(trace) {
  const complete = new Promise(resolveComplete => {
    trace.session.once("Tracing.tracingComplete", resolveComplete)
  })
  await trace.session.send("Tracing.end")
  await complete
  await trace.session.detach()
  return trace.events
}

function summarizeTrace(events) {
  const marks = new Map(events
    .filter(event => event.cat?.includes("blink.user_timing") && event.name.startsWith("loomark-whole:"))
    .map(event => [event.name, event]))
  const beforeinput = marks.get("loomark-whole:beforeinput")
  const input = marks.get("loomark-whole:input")
  const microtask = marks.get("loomark-whole:microtask")
  const put = marks.get("loomark-whole:put-request")
  if (beforeinput === undefined || input === undefined || microtask === undefined || put === undefined) {
    throw new Error("trace is missing a required benchmark mark")
  }
  const windows = [
    ["w0_immediate", beforeinput.ts, microtask.ts],
    ["w1_preview", input.ts, input.ts + 100_000],
    // Start 10 ms before the nominal timer so scheduling jitter cannot hide
    // the beginning of the 250 ms flush task. This is a probe window, not the
    // flush duration itself.
    ["w2_probe_240ms_to_put", input.ts + 240_000, put.ts],
  ]
  const names = {
    function_call_ms: new Set(["FunctionCall"]),
    run_task_ms: new Set(["RunTask"]),
    style_layout_ms: new Set(["UpdateLayoutTree", "Layout"]),
    paint_ms: new Set(["PrePaint", "Paint", "CompositeLayers"]),
    gc_ms: new Set(["MajorGC", "MinorGC", "V8.GC_MAJOR", "V8.GC_MINOR"]),
  }
  return Object.fromEntries(windows.map(([name, start, end]) => {
    const overlapping = events.filter(event => (
      event.tid === input.tid &&
      typeof event.dur === "number" &&
      event.ts < end &&
      event.ts + event.dur > start
    ))
    const durationFor = selectedNames => overlapping.reduce((sum, event) => {
      if (!selectedNames.has(event.name)) return sum
      const overlap = Math.max(0, Math.min(event.ts + event.dur, end) - Math.max(event.ts, start))
      return sum + overlap
    }, 0) / 1000
    return [name, {
      elapsed_ms: Number(((end - start) / 1000).toFixed(3)),
      ...Object.fromEntries(Object.entries(names).map(([metric, selectedNames]) => [
        metric,
        Number(durationFor(selectedNames).toFixed(3)),
      ])),
    }]
  }))
}

async function runLoomarkTraces(browser, origin, source, documentId, count) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 720 } })
  await context.addInitScript(instrumentPage, { key: localTextKey, traceEnabled: true })
  const page = await context.newPage()
  await page.goto(`${origin}/favicon.svg`, { waitUntil: "load" })
  await seedLocalText(page, source, documentId)
  await page.goto(origin, { waitUntil: "load" })
  const input = page.locator("#loomark-input")
  await input.waitFor({ state: "visible", timeout: 30_000 })
  await page.waitForFunction(expected => document.querySelector("#loomark-input")?.value === expected, source, {
    timeout: 120_000,
  })
  await input.evaluate((textarea, offset) => {
    textarea.setSelectionRange(offset, offset)
    textarea.focus()
  }, source.length)

  // Keep initialization and first-use compilation outside the representative traces.
  await typeSample(page, "w", true)
  const traces = []
  for (let index = 0; index < count; index += 1) {
    await page.evaluate(() => performance.clearMarks())
    const trace = await startTrace(context, page)
    const measured = await typeSample(page, index % 2 === 0 ? "x" : "y", true)
    const events = await stopTrace(trace)
    traces.push({ measured, summary: summarizeTrace(events) })
  }
  await context.close()
  return traces
}

async function withBrowser(action) {
  const selected = await chromium.launch({ headless: true })
  try {
    return await action(selected)
  } finally {
    await selected.close()
  }
}

function summarizeRows(rows) {
  const metrics = [
    "native_mutation_ms",
    "input_handler_ms",
    "put_request_offset_ms",
    "put_acknowledgment_ms",
    "browser_command_wall_ms",
  ]
  return Object.fromEntries(metrics.map(metric => [
    metric,
    summarize(rows.map(row => row[metric]).filter(value => value !== null)),
  ]).concat([[
    "long_tasks",
    {
      samples_with_long_tasks: rows.filter(row => row.long_tasks.length > 0).length,
      count: rows.reduce((sum, row) => sum + row.long_tasks.length, 0),
      maximum_ms: rows.flatMap(row => row.long_tasks.map(task => task.duration_ms)).reduce(
        (maximum, value) => Math.max(maximum, value),
        0,
      ),
    },
  ]]))
}

let server
let browser
try {
  const started = await startServer()
  server = started.server
  browser = await chromium.launch({ headless: true })
  const browserVersion = browser.version()
  await browser.close()
  browser = undefined
  const result = {
    schema: "loomark-whole-document-input-v1",
    environment: {
      commit: execFileSync("git", ["rev-parse", "HEAD"], { cwd: projectRoot, encoding: "utf8" }).trim(),
      browser: browserVersion,
      node: process.version,
      platform: platform(),
      os_release: release(),
      architecture: process.arch,
      cpu: cpus()[0]?.model ?? "unknown",
      headless: true,
      viewport: { width: 1280, height: 720 },
      warmups,
      samples,
      trace_samples: traceSamples,
      settle_ms: settleMs,
      persistence_required: requirePersistence,
    },
    invocation: {
      sizes,
      environment: {
        LOOMARK_WHOLE_DOCUMENT_SIZES: process.env.LOOMARK_WHOLE_DOCUMENT_SIZES ?? null,
        LOOMARK_WHOLE_DOCUMENT_WARMUPS: process.env.LOOMARK_WHOLE_DOCUMENT_WARMUPS ?? null,
        LOOMARK_WHOLE_DOCUMENT_SAMPLES: process.env.LOOMARK_WHOLE_DOCUMENT_SAMPLES ?? null,
        LOOMARK_WHOLE_DOCUMENT_TRACE_SAMPLES:
          process.env.LOOMARK_WHOLE_DOCUMENT_TRACE_SAMPLES ?? null,
        LOOMARK_WHOLE_DOCUMENT_REQUIRE_PERSISTENCE:
          process.env.LOOMARK_WHOLE_DOCUMENT_REQUIRE_PERSISTENCE ?? null,
      },
    },
    fixtures: [],
    scenarios: [],
    traces: [],
  }

  for (const size of sizes) {
    const generated = fixture(size)
    result.fixtures.push({
      requested_utf16: size,
      utf16_length: generated.utf16_length,
      utf8_bytes: generated.utf8_bytes,
      sha256: generated.sha256,
    })
    const documentId = `whole-document-input-${size}`
    const loomark = await withBrowser(selected => runLoomark(
      selected,
      started.origin,
      generated.source,
      documentId,
      warmups,
      samples,
    ))
    const nativeRows = await withBrowser(selected => runNative(
      selected,
      generated.source,
      loomark.surface,
      warmups,
      samples,
    ))
    result.scenarios.push({
      size_utf16: size,
      surface: "native_textarea",
      matched_width_px: loomark.surface.width,
      summary: summarizeRows(nativeRows),
      samples: nativeRows,
    })
    result.scenarios.push({
      size_utf16: size,
      surface: "loomark_production",
      matched_width_px: loomark.surface.width,
      summary: summarizeRows(loomark.rows),
      samples: loomark.rows,
    })
  }

  if (traceSamples > 0) {
    const tracedSize = Math.max(...sizes)
    const tracedFixture = fixture(tracedSize)
    result.traces = await withBrowser(selected => runLoomarkTraces(
      selected,
      started.origin,
      tracedFixture.source,
      `whole-document-trace-${tracedSize}`,
      traceSamples,
    ))
  }

  const encoded = `${JSON.stringify(result, null, 2)}\n`
  if (outputPath !== undefined) await writeFile(outputPath, encoded)
  process.stdout.write(encoded)
} finally {
  if (browser !== undefined) await browser.close()
  if (server !== undefined) await stopServer(server)
}
