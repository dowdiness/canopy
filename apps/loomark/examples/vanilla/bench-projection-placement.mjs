import { chromium } from "@playwright/test"
import { createServer } from "node:http"
import { spawn } from "node:child_process"
import { readFile, stat } from "node:fs/promises"
import { extname, join, normalize } from "node:path"
import process from "node:process"

const dist = new URL("../../dist/", import.meta.url)
const samples = Number.parseInt(process.env.LOOMARK_PROJECTION_SAMPLES ?? "3", 10)
const sizes = (process.env.LOOMARK_PROJECTION_SIZES ?? "2000,10000,50000")
  .split(",")
  .map(Number)
const placements = (process.env.LOOMARK_PROJECTION_PLACEMENTS ?? "worker,in-process,synchronous")
  .split(",")
const latinSquare = placements.length === 3
  ? [
      ["worker", "in-process", "synchronous"],
      ["in-process", "synchronous", "worker"],
      ["synchronous", "worker", "in-process"],
    ]
  : [placements]
const mainThreadTraceEnabled = process.env.LOOMARK_MAIN_THREAD_TRACE === "1"

const mime = new Map([
  [".css", "text/css"],
  [".html", "text/html"],
  [".js", "text/javascript"],
  [".json", "application/json"],
  [".svg", "image/svg+xml"],
  [".wasm", "application/wasm"],
])

function corpus(lines) {
  return Array.from(
    { length: lines },
    (_, index) => index % 2 === 0 ? `Paragraph ${index / 2} alpha beta gamma.` : "",
  ).join("\n")
}

function percentile(values, fraction) {
  if (values.length === 0) return null
  const sorted = [...values].sort((a, b) => a - b)
  return sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * fraction))]
}

function summarize(values) {
  return {
    samples: values.length,
    median_ms: percentile(values, 0.5),
    p95_ms: percentile(values, 0.95),
    min_ms: values.length === 0 ? null : Math.min(...values),
    max_ms: values.length === 0 ? null : Math.max(...values),
  }
}

async function serve() {
  const root = normalize(dist.pathname)
  const server = createServer(async (request, response) => {
    try {
      const pathname = new URL(request.url ?? "/", "http://localhost").pathname
      let file = join(root, pathname === "/" ? "index.html" : pathname)
      if (!(await stat(file)).isFile()) file = join(root, "index.html")
      response.writeHead(200, { "content-type": mime.get(extname(file)) ?? "application/octet-stream" })
      response.end(await readFile(file))
    } catch {
      response.writeHead(404)
      response.end("Not found")
    }
  })
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve))
  const address = server.address()
  if (typeof address !== "object" || address === null) throw new Error("server did not bind")
  return { server, origin: `http://127.0.0.1:${address.port}` }
}
async function startMainThreadTrace(context, page) {
  if (!mainThreadTraceEnabled) return null
  const session = await context.newCDPSession(page)
  const events = []
  session.on("Tracing.dataCollected", ({ value }) => events.push(...value))
  await session.send("Tracing.start", {
    categories: "blink.user_timing,devtools.timeline,v8",
    options: "sampling-frequency=10000",
  })
  return { session, events }
}

async function stopMainThreadTrace(trace) {
  if (trace === null) return null
  const complete = new Promise(resolve => trace.session.once("Tracing.tracingComplete", resolve))
  await trace.session.send("Tracing.end")
  await complete
  await trace.session.detach()
  return summarizeMainThreadTrace(trace.events)
}

function summarizeMainThreadTrace(events) {
  const userTimingEvents = events.filter(event => (
    event.cat?.includes("blink.user_timing") &&
    event.name.startsWith("loomark:")
  ))
  const marks = new Map(userTimingEvents.map(event => [event.name, event]))
  const intervals = []
  for (const [name, start] of marks) {
    if (!name.startsWith("loomark:") || !name.endsWith(":start")) continue
    const scenario = name.slice("loomark:".length, -":start".length)
    const end = marks.get(`loomark:${scenario}:end`)
    if (end === undefined || end.tid !== start.tid || end.ts < start.ts) continue
    const selected = events.filter(event => (
      event.tid === start.tid &&
      typeof event.dur === "number" &&
      event.ts >= start.ts &&
      event.ts + event.dur <= end.ts
    ))
    const durationFor = names => selected
      .filter(event => names.has(event.name))
      .reduce((sum, event) => sum + event.dur, 0) / 1000
    intervals.push({
      scenario,
      elapsed_ms: (end.ts - start.ts) / 1000,
      function_call_ms: durationFor(new Set(["FunctionCall"])),
      style_layout_ms: durationFor(new Set(["UpdateLayoutTree", "Layout"])),
      paint_ms: durationFor(new Set(["PrePaint", "Paint", "CompositeLayers"])),
      run_task_ms: durationFor(new Set(["RunTask"])),
      event_count: selected.length,
    })
  }
  return {
    intervals: intervals.sort((left, right) => left.scenario.localeCompare(right.scenario)),
    mark_shapes: [...new Set(userTimingEvents.map(event => `${event.ph}:${event.cat}`))],
  }
}


async function installObservers(page) {
  await page.addInitScript(() => {
    const state = { longTasks: [], frameGaps: [], lastFrame: 0 }
    globalThis.__loomarkPlacementBench = state
    try {
      new PerformanceObserver(list => {
        for (const entry of list.getEntries()) state.longTasks.push(entry.duration)
      }).observe({ type: "longtask", buffered: true })
    } catch {}
    const frame = now => {
      if (state.lastFrame !== 0) state.frameGaps.push(now - state.lastFrame)
      state.lastFrame = now
      requestAnimationFrame(frame)
    }
    requestAnimationFrame(frame)
  })
}

async function replaceRaw(page, value) {
  await page.locator("#loomark-input").evaluate((element, nextValue) => {
    const textarea = element
    textarea.setSelectionRange(0, textarea.value.length, "forward")
    textarea.dispatchEvent(new InputEvent("beforeinput", {
      bubbles: true,
      cancelable: true,
      composed: true,
      data: nextValue,
      inputType: "insertText",
    }))
    textarea.value = nextValue
    textarea.setSelectionRange(nextValue.length, nextValue.length)
    textarea.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      composed: true,
      data: nextValue,
      inputType: "insertText",
    }))
  }, value)
}

async function insertRaw(page, offset, text) {
  await page.locator("#loomark-input").evaluate((element, edit) => {
    const textarea = element
    const nextValue = `${textarea.value.slice(0, edit.offset)}${edit.text}${
      textarea.value.slice(edit.offset)
    }`
    textarea.setSelectionRange(edit.offset, edit.offset, "forward")
    textarea.dispatchEvent(new InputEvent("beforeinput", {
      bubbles: true,
      cancelable: true,
      composed: true,
      data: edit.text,
      inputType: "insertText",
    }))
    textarea.value = nextValue
    const nextOffset = edit.offset + edit.text.length
    textarea.setSelectionRange(nextOffset, nextOffset)
    textarea.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      composed: true,
      data: edit.text,
      inputType: "insertText",
    }))
  }, { offset, text })
}

async function waitForPreview(page, source, renderedMarker) {
  await page.waitForFunction(
    expected => {
      const preview = document.querySelector("#loomark-preview")
      return preview?.getAttribute("data-loomark-source") === expected.source &&
        preview.textContent?.includes(expected.renderedMarker)
    },
    { source, renderedMarker },
    { timeout: 120_000 },
  )
}

async function measured(page, name, action, settle) {
  await page.evaluate(scenario => {
    const state = globalThis.__loomarkPlacementBench
    state.longTasks.length = 0
    state.frameGaps.length = 0
    performance.mark(`loomark:${scenario}:start`)
  }, name)
  const started = await page.evaluate(() => performance.now())
  await action()
  await settle()
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
  const observed = await page.evaluate((input) => {
    const state = globalThis.__loomarkPlacementBench
    performance.mark(`loomark:${input.name}:end`)
    return {
      duration_ms: performance.now() - input.started,
      long_task_count: state.longTasks.length,
      long_task_total_ms: state.longTasks.reduce((sum, value) => sum + value, 0),
      max_frame_gap_ms: Math.max(0, ...state.frameGaps),
    }
  }, { name, started })
  return { name, ...observed }
}

async function runSample(browser, origin, placement, blocks, round) {
  const context = await browser.newContext()
  const page = await context.newPage()
  await installObservers(page)
  await page.goto(`${origin}/?projection-placement=${placement}&projection-benchmark=1`)
  await page.locator("#loomark-split-toggle").click()
  await page.locator("#loomark-preview").waitFor()
  const mainThreadTrace = await startMainThreadTrace(context, page)


  const base = corpus(blocks)
  const scenarios = []

  let current = base
  const coldMarker = `Paragraph ${Math.ceil(blocks / 2) - 1}`
  scenarios.push(await measured(page, "cold-seed-preview", () => replaceRaw(page, current), () => waitForPreview(page, current, coldMarker)))

  current = `§${current}`
  scenarios.push(await measured(page, "local-edit-start", () => insertRaw(page, 0, "§"), () => waitForPreview(page, current, "§")))

  const middleOffset = Math.floor(current.length / 2)
  current = `${current.slice(0, middleOffset)}¶${current.slice(middleOffset)}`
  scenarios.push(await measured(page, "local-edit-middle", () => insertRaw(page, middleOffset, "¶"), () => waitForPreview(page, current, "¶")))

  const endOffset = current.length
  current = `${current}Ω`
  scenarios.push(await measured(page, "local-edit-end", () => insertRaw(page, endOffset, "Ω"), () => waitForPreview(page, current, "Ω")))

  let burstCurrent = current
  const burstFinal = `${current}xxxxxxxx`
  scenarios.push(await measured(
    page,
    "sustained-typing-8-edits",
    async () => {
      for (let index = 0; index < 8; index += 1) {
        await insertRaw(page, burstCurrent.length, "x")
        burstCurrent += "x"
      }
    },
    () => waitForPreview(page, burstFinal, "Ωxxxxxxxx"),
  ))
  current = burstFinal
  scenarios.push(await measured(
    page,
    "source-equal-advance",
    () => replaceRaw(page, current),
    () => page.waitForTimeout(0),
  ))
  const mainThread = await stopMainThreadTrace(mainThreadTrace)


  await page.locator("#loomark-projection-trace-dump").dispatchEvent("click")
  const traceRaw = await page.locator("html").getAttribute("data-loomark-projection-trace")
  const trace = JSON.parse(traceRaw ?? "{}")
  const heap = await page.evaluate(() => {
    if (typeof globalThis.gc === "function") globalThis.gc()
    const memory = performance.memory
    return memory ? memory.usedJSHeapSize : null
  })
  await context.close()
  return {
    placement,
    lines: blocks,
    round,
    source_bytes: Buffer.byteLength(base),
    scenarios,
    trace,
    main_thread: mainThread,
    post_gc_heap_bytes: heap,
  }
}

async function childMain() {
  const placement = process.env.LOOMARK_PROJECTION_CHILD_PLACEMENT
  const lines = Number(process.env.LOOMARK_PROJECTION_CHILD_LINES)
  const round = Number(process.env.LOOMARK_PROJECTION_CHILD_ROUND)
  const { server, origin } = await serve()
  const browser = await chromium.launch({
    headless: true,
    args: ["--js-flags=--expose-gc", "--enable-precise-memory-info"],
  })
  try {
    const result = await runSample(browser, origin, placement, lines, round)
    process.stdout.write(JSON.stringify(result))
  } finally {
    await browser.close()
    await new Promise(resolve => server.close(resolve))
  }
}

function runIsolated(placement, lines, round) {
  const deadlineMs = lines <= 2000 ? 180_000 : 120_000
  return new Promise(resolve => {
    const child = spawn(process.execPath, [new URL(import.meta.url).pathname], {
      detached: true,
      env: {
        ...process.env,
        LOOMARK_PROJECTION_CHILD: "1",
        LOOMARK_PROJECTION_CHILD_PLACEMENT: placement,
        LOOMARK_PROJECTION_CHILD_LINES: String(lines),
        LOOMARK_PROJECTION_CHILD_ROUND: String(round),
      },
      stdio: ["ignore", "pipe", "pipe"],
    })
    let stdout = ""
    let stderr = ""
    let censored = false
    child.stdout.setEncoding("utf8")
    child.stderr.setEncoding("utf8")
    child.stdout.on("data", chunk => { stdout += chunk })
    child.stderr.on("data", chunk => { stderr += chunk })
    const timer = setTimeout(() => {
      censored = true
      try {
        process.kill(-child.pid, "SIGKILL")
      } catch {}
    }, deadlineMs)
    child.on("close", code => {
      clearTimeout(timer)
      if (censored) {
        resolve({
          placement,
          lines,
          round,
          censored_timeout_ms: deadlineMs,
          error: `release-browser scenario exceeded ${deadlineMs} ms`,
        })
        return
      }
      if (code !== 0) {
        resolve({
          placement,
          lines,
          round,
          error: `isolated benchmark exited ${code}: ${stderr.trim()}`,
        })
        return
      }
      try {
        resolve(JSON.parse(stdout))
      } catch (error) {
        resolve({
          placement,
          lines,
          round,
          error: `invalid isolated benchmark output: ${
            error instanceof Error ? error.message : String(error)
          }`,
        })
      }
    })
  })
}

if (process.env.LOOMARK_PROJECTION_CHILD === "1") {
  await childMain()
  process.exit(0)
}

const runs = []
for (const blocks of sizes) {
  for (let round = 0; round < samples; round += 1) {
    for (const placement of latinSquare[round % latinSquare.length]) {
      console.error(`benchmark lines=${blocks} round=${round + 1}/${samples} placement=${placement}`)
      runs.push(await runIsolated(placement, blocks, round))
    }
  }
}

const summaries = []
for (const blocks of sizes) {
  for (const placement of placements) {
    for (const name of [
      "cold-seed-preview",
      "local-edit-start",
      "local-edit-middle",
      "local-edit-end",
      "sustained-typing-8-edits",
      "source-equal-advance",
    ]) {
      const matching = runs
        .filter(run => (
          run.lines === blocks &&
          run.placement === placement &&
          Array.isArray(run.scenarios)
        ))
        .map(run => run.scenarios.find(scenario => scenario.name === name))
        .filter(Boolean)
      summaries.push({
        lines: blocks,
        placement,
        scenario: name,
        duration: summarize(matching.map(result => result.duration_ms)),
        long_task_total: summarize(matching.map(result => result.long_task_total_ms)),
        max_frame_gap: summarize(matching.map(result => result.max_frame_gap_ms)),
      })
    }
  }
}

const report = {
  schema_version: 2,
  generated_at: new Date().toISOString(),
  environment: {
    commit_sha: process.env.LOOMARK_PROJECTION_COMMIT ?? "unrecorded",
    node: process.version,
    playwright: "1.61.1",
    samples,
    sizes,
    placements,
    run_order: placements.length === 3
      ? "3x3 Latin square rotated by sample within each corpus size"
      : "configured placement order repeated for each sample and corpus size",
    edit_protocol: "cold whole-source Seed followed by one-character native insertText edits",
    forced_gc: "Chromium --js-flags=--expose-gc before post_gc_heap_bytes",
  },
  controls: {
    tracing_requested: true,
    main_thread_tracing_requested: mainThreadTraceEnabled,
    all_main_thread_intervals_complete: !mainThreadTraceEnabled || runs.every(
      run => run.main_thread?.intervals?.length === 6,
    ),
    all_main_thread_positive_controls: !mainThreadTraceEnabled || runs.every(run => {
      const cold = run.main_thread?.intervals?.find(
        interval => interval.scenario === "cold-seed-preview",
      )
      const noOp = run.main_thread?.intervals?.find(
        interval => interval.scenario === "source-equal-advance",
      )
      return cold?.function_call_ms > 0 && cold?.elapsed_ms > noOp?.elapsed_ms
    }),
    all_runs_completed: runs.every(run => !run.error),
    all_traces_enabled: runs.every(run => run.trace?.enabled === true),
    all_traces_nonempty: runs.every(run => run.trace?.count > 0),
    all_traces_lossless: runs.every(run => (
      run.trace?.dropped_count === 0 && run.trace?.overflowed === false
    )),
    all_trace_contracts_valid: runs.every(
      run => run.trace?.contract_violated === false,
    ),
  },
  summaries,
  runs,
}
const output = process.env.LOOMARK_PROJECTION_OUTPUT ?? `/tmp/loomark-projection-placement-${Date.now()}.json`
await import("node:fs/promises").then(({ writeFile }) => writeFile(output, `${JSON.stringify(report, null, 2)}\n`))
console.table(summaries.map(summary => ({
  lines: summary.lines,
  placement: summary.placement,
  scenario: summary.scenario,
  median_ms: summary.duration.median_ms?.toFixed(1),
  p95_ms: summary.duration.p95_ms?.toFixed(1),
  long_task_p95_ms: summary.long_task_total.p95_ms?.toFixed(1),
  frame_gap_p95_ms: summary.max_frame_gap.p95_ms?.toFixed(1),
})))
console.log(`Raw benchmark evidence: ${output}`)
