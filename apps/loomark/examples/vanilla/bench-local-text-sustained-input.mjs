// PROTOTYPE — disposable 2k/10k sustained-input displacement experiment.
import { spawn } from "node:child_process"
import { once } from "node:events"
import { writeFile } from "node:fs/promises"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { chromium } from "playwright"

const here = dirname(fileURLToPath(import.meta.url))
const sampleCount = Number.parseInt(process.env.LOOMARK_SUSTAINED_SAMPLES ?? "10", 10)
const lineCounts = (process.env.LOOMARK_SUSTAINED_LINE_COUNTS ?? "2000,10000")
  .split(",")
  .map(value => Number.parseInt(value, 10))
const burst = process.env.LOOMARK_SUSTAINED_BURST ?? "XYZABC"
const intervalMs = Number.parseInt(process.env.LOOMARK_SUSTAINED_INTERVAL_MS ?? "500", 10)
const outputPath = process.env.LOOMARK_SUSTAINED_OUTPUT ?? "/tmp/loomark-localtext-sustained-input.json"
const laneOrder = process.env.LOOMARK_SUSTAINED_LANE_ORDER ?? "auto"
const distRoot = process.env.LOOMARK_STANDALONE_DIST
const databaseName = "loomark.local-repository"
const storeName = "archives"
const baselineKey = "loomark.active-document-archive"
const localTextKey = "loomark.prototype-local-text"
const serverPath = fileURLToPath(new URL("./serve-standalone-dist.mjs", import.meta.url))
const queryBase = "?projection-benchmark=1&four-clock-prototype=1"

if (!Number.isSafeInteger(sampleCount) || sampleCount < 3) {
  throw new Error("LOOMARK_SUSTAINED_SAMPLES must be an integer >= 3")
}
if (lineCounts.length === 0 || lineCounts.some(value => !Number.isSafeInteger(value) || value < 1)) {
  throw new Error("LOOMARK_SUSTAINED_LINE_COUNTS must contain positive integers")
}
if (burst.length < 3 || [...burst].some(character => character.length !== 1)) {
  throw new Error("LOOMARK_SUSTAINED_BURST must contain at least three single-code-unit characters")
}
if (!Number.isSafeInteger(intervalMs) || intervalMs < 10) {
  throw new Error("LOOMARK_SUSTAINED_INTERVAL_MS must be an integer >= 10")
}
if (!["auto", "full-first", "local-first"].includes(laneOrder)) {
  throw new Error("LOOMARK_SUSTAINED_LANE_ORDER must be auto, full-first, or local-first")
}

const server = spawn(process.execPath, [serverPath], {
  env: {
    ...process.env,
    LOOMARK_STANDALONE_PORT: "0",
    ...(distRoot == null ? {} : { LOOMARK_STANDALONE_DIST: distRoot }),
  },
  stdio: ["ignore", "pipe", "inherit"],
})
let origin = ""
let readyBuffer = ""
const ready = new Promise((resolveReady, reject) => {
  const timeout = setTimeout(() => reject(new Error("standalone server timeout")), 10_000)
  server.stdout.setEncoding("utf8")
  server.stdout.on("data", chunk => {
    readyBuffer += chunk
    const match = readyBuffer.match(/http:\/\/127\.0\.0\.1:(\d+)/)
    if (match !== null) {
      origin = match[0]
      clearTimeout(timeout)
      resolveReady()
    }
  })
  server.once("error", reject)
  server.once("close", code => reject(new Error(`standalone server exited: ${code}`)))
})

function documentSource(lineCount) {
  const lines = ["# Sustained input displacement fixture", ""]
  for (let index = 0; index < lineCount; index += 1) {
    lines.push(`row-${String(index + 1).padStart(5, "0")} alpha beta`)
  }
  return `${lines.join("\n")}\n`
}

function percentile(values, percent) {
  const sorted = [...values].sort((left, right) => left - right)
  return sorted[Math.max(0, Math.ceil(percent / 100 * sorted.length) - 1)]
}

function rounded(value) {
  return Number(value.toFixed(3))
}

function summarizeValues(values) {
  return {
    p50: rounded(percentile(values, 50)),
    p95: rounded(percentile(values, 95)),
    max: rounded(Math.max(...values)),
    raw: values.map(rounded),
  }
}

function summarize(samples, field) {
  return summarizeValues(samples.map(sample => sample[field]))
}

async function putRecord(page, key, value) {
  await page.evaluate(async ({ databaseName, storeName, key, value }) => await new Promise((resolvePut, reject) => {
    const request = indexedDB.open(databaseName, 1)
    request.onupgradeneeded = () => {
      if (!request.result.objectStoreNames.contains(storeName)) request.result.createObjectStore(storeName)
    }
    request.onerror = () => reject(request.error ?? new Error("database open failed"))
    request.onsuccess = () => {
      const database = request.result
      const transaction = database.transaction(storeName, "readwrite")
      transaction.objectStore(storeName).put(value, key)
      transaction.oncomplete = () => {
        database.close()
        resolvePut()
      }
      transaction.onerror = () => reject(transaction.error ?? new Error("record seed failed"))
      transaction.onabort = () => reject(transaction.error ?? new Error("record seed aborted"))
    }
  }), { databaseName, storeName, key, value })
}

async function getRecord(page, key) {
  return page.evaluate(async ({ databaseName, storeName, key }) => await new Promise((resolveGet, reject) => {
    const request = indexedDB.open(databaseName, 1)
    request.onerror = () => reject(request.error ?? new Error("database open failed"))
    request.onsuccess = () => {
      const database = request.result
      const transaction = database.transaction(storeName, "readonly")
      const get = transaction.objectStore(storeName).get(key)
      get.onsuccess = () => {
        database.close()
        resolveGet(get.result ?? null)
      }
      get.onerror = () => reject(get.error ?? new Error("record read failed"))
    }
  }), { databaseName, storeName, key })
}

async function waitForRecordText(page, key, expected, timeout = 300_000) {
  const deadline = Date.now() + timeout
  while (Date.now() < deadline) {
    const encoded = await getRecord(page, key)
    if (encoded !== null) {
      const record = JSON.parse(encoded)
      if (record.portable_markdown === expected) return encoded
    }
    await page.waitForTimeout(10)
  }
  throw new Error(`timed out waiting for persisted text on ${key}`)
}

function localTextRecord(archive) {
  return JSON.stringify({
    prototype_format: "loomark-local-text-prototype-v1",
    document_id: archive.document_id,
    portable_markdown: archive.portable_markdown,
  })
}

async function replaceWholeSource(page, source) {
  await page.locator("#loomark-input").evaluate((element, nextValue) => {
    element.setSelectionRange(0, element.value.length, "forward")
    element.dispatchEvent(new InputEvent("beforeinput", {
      bubbles: true,
      cancelable: true,
      composed: true,
      data: nextValue,
      inputType: "insertText",
    }))
    element.value = nextValue
    element.setSelectionRange(nextValue.length, nextValue.length, "forward")
    element.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      composed: true,
      data: nextValue,
      inputType: "insertText",
    }))
  }, source)
}

async function createFullHistorySeed(browser, source, lineCount) {
  process.stderr.write(`prepare ${lineCount}-line full-history seed\n`)
  const context = await browser.newContext()
  const page = await context.newPage()
  page.setDefaultTimeout(300_000)
  await page.goto(`${origin}/${queryBase}`, { waitUntil: "commit" })
  const input = page.locator("#loomark-input")
  await input.waitFor({ state: "visible" })
  const initial = await input.inputValue()
  await waitForRecordText(page, baselineKey, initial)
  await replaceWholeSource(page, source)
  await page.waitForFunction(expected => document.querySelector("#loomark-input")?.value === expected, source)
  const encoded = await waitForRecordText(page, baselineKey, source)
  const archive = JSON.parse(encoded)
  if (archive.portable_markdown !== source) throw new Error("generated archive source mismatch")
  await context.close()
  return encoded
}

async function installMeasurement(context, measuredKey) {
  await context.addInitScript(({ storeName, measuredKey }) => {
    const originalTransaction = IDBDatabase.prototype.transaction
    const originalOpenCursor = IDBObjectStore.prototype.openCursor
    const originalPut = IDBObjectStore.prototype.put
    const transactionRecords = new WeakMap()
    const state = {
      inputs: [],
      causalMarks: [],
      transactions: [],
      longTasks: [],
      frameGaps: [],
      lastFrame: 0,
    }
    globalThis.__loomarkSustainedInputMeasurement = state

    IDBDatabase.prototype.transaction = function(storeNames, mode, options) {
      const transaction = Reflect.apply(originalTransaction, this, [storeNames, mode, options])
      const names = typeof storeNames === "string" ? [storeNames] : Array.from(storeNames)
      if (names.includes(storeName)) {
        const record = { kind: "other", mode, start_ms: performance.now(), end_ms: null, terminal: null }
        transactionRecords.set(transaction, record)
        state.transactions.push(record)
        const finish = terminal => {
          if (record.end_ms !== null) return
          record.end_ms = performance.now()
          record.terminal = terminal
        }
        transaction.addEventListener("complete", () => finish("complete"), { once: true })
        transaction.addEventListener("abort", () => finish("abort"), { once: true })
        transaction.addEventListener("error", () => finish("error"), { once: true })
      }
      return transaction
    }
    const classify = (store, kind) => {
      const record = transactionRecords.get(store.transaction)
      if (record !== undefined) record.kind = kind
    }
    IDBObjectStore.prototype.openCursor = function(query, direction) {
      if (this.name === storeName && query === measuredKey) classify(this, "application_read")
      return originalOpenCursor.call(this, query, direction)
    }
    IDBObjectStore.prototype.put = function(value, key) {
      if (this.name === storeName && key === measuredKey) classify(this, "application_write")
      return originalPut.call(this, value, key)
    }

    document.addEventListener("beforeinput", event => {
      if (event.target?.id !== "loomark-input") return
      state.inputs.push({
        ordinal: state.inputs.length,
        data: event.data,
        before_ms: performance.now(),
        input_ms: null,
        visible_ms: null,
        causal_sequence_before: Number(
          document.documentElement.dataset.loomarkCausalReadySequence ?? "0",
        ),
      })
    }, true)
    document.addEventListener("input", event => {
      if (event.target?.id !== "loomark-input") return
      const record = [...state.inputs].reverse().find(candidate => candidate.input_ms === null)
      if (record === undefined) return
      record.input_ms = performance.now()
      requestAnimationFrame(() => requestAnimationFrame(() => {
        record.visible_ms = performance.now()
      }))
    }, true)

    try {
      new PerformanceObserver(list => {
        for (const entry of list.getEntries()) {
          state.longTasks.push({ start_ms: entry.startTime, duration_ms: entry.duration })
        }
      }).observe({ type: "longtask", buffered: true })
    } catch {}
    const frame = now => {
      if (state.lastFrame !== 0) state.frameGaps.push({ start_ms: state.lastFrame, duration_ms: now - state.lastFrame })
      state.lastFrame = now
      requestAnimationFrame(frame)
    }
    requestAnimationFrame(frame)
  }, { storeName, measuredKey })
}

async function scheduleBurst(cdp, characters) {
  const nodeStart = performance.now()
  const sends = characters.map((character, ordinal) => new Promise((resolveSend, reject) => {
    setTimeout(() => {
      const sendOffsetMs = performance.now() - nodeStart
      cdp.send("Input.insertText", { text: character }).then(
        () => resolveSend({ ordinal, send_offset_ms: rounded(sendOffsetMs) }),
        reject,
      )
    }, ordinal * intervalMs)
  }))
  return Promise.all(sends)
}

async function resetMeasurement(page) {
  await page.evaluate(() => {
    const state = globalThis.__loomarkSustainedInputMeasurement
    state.inputs.length = 0
    state.causalMarks.length = 0
    state.transactions.length = 0
    state.longTasks.length = 0
    state.frameGaps.length = 0
  })
}

async function prepareInput(page) {
  const input = page.locator("#loomark-input")
  await input.focus()
  await input.evaluate(element => {
    const end = element.value.length
    element.setSelectionRange(end, end, "forward")
  })
  return input
}

async function measureLane(browser, document, lane, encodedArchive, measurementOrder) {
  const archive = JSON.parse(encodedArchive)
  const seed = lane.name === "local_text" ? localTextRecord(archive) : encodedArchive
  const key = lane.name === "local_text" ? localTextKey : baselineKey
  const context = await browser.newContext()
  await installMeasurement(context, key)
  const page = await context.newPage()
  page.setDefaultTimeout(300_000)
  const cdp = await context.newCDPSession(page)
  await page.goto(origin, { waitUntil: "commit" })

  // Complete one unmeasured reload/edit/write cycle in this exact lane.
  await putRecord(page, key, seed)
  await page.goto(`${origin}/${lane.query}`, { waitUntil: "commit" })
  await page.locator("#loomark-input").waitFor({ state: "visible" })
  await page.waitForFunction(expected => document.querySelector("#loomark-input")?.value === expected, document.source)
  await prepareInput(page)
  await cdp.send("Input.insertText", { text: "W" })
  await waitForRecordText(page, key, `${document.source}W`)

  const samples = []
  for (let sample = 0; sample < sampleCount; sample += 1) {
    process.stderr.write(`measure ${document.line_count} ${lane.name} ${sample + 1}/${sampleCount}\n`)
    await putRecord(page, key, seed)
    await page.reload({ waitUntil: "commit" })
    await page.locator("#loomark-input").waitFor({ state: "visible" })
    await page.waitForFunction(expected => document.querySelector("#loomark-input")?.value === expected, document.source)
    const contentVisibleMs = await page.evaluate(() => performance.now())
    await prepareInput(page)
    await resetMeasurement(page)
    const causalSequenceStart = await page.evaluate(() => Number(
      document.documentElement.dataset.loomarkCausalReadySequence ?? "0",
    ))
    const sendSchedule = await scheduleBurst(cdp, [...burst])
    const expected = `${document.source}${burst}`
    try {
      await page.waitForFunction(({ expected, count, causalSequenceStart }) => {
        const state = globalThis.__loomarkSustainedInputMeasurement
        const marks = state.causalMarks.filter(mark => mark.sequence > causalSequenceStart)
        return document.querySelector("#loomark-input")?.value === expected &&
          state.inputs.length === count &&
          state.inputs.every(record => record.visible_ms !== null) &&
          marks.some(mark => mark.committedLength >= expected.length)
      }, { expected, count: burst.length, causalSequenceStart }, { timeout: 60_000 })
    } catch (error) {
      const diagnostic = await page.evaluate(() => {
        const state = globalThis.__loomarkSustainedInputMeasurement
        return {
          value_suffix: document.querySelector("#loomark-input")?.value.slice(-20),
          causal_sequence: document.documentElement.dataset.loomarkCausalReadySequence,
          inputs: state.inputs,
          causal_marks: state.causalMarks,
          selected_transactions: state.transactions.filter(record => record.kind !== "other"),
        }
      })
      throw new Error(`sustained-input completion mismatch: ${JSON.stringify(diagnostic)}`, { cause: error })
    }
    const persisted = await waitForRecordText(page, key, expected)
    const timing = await page.evaluate(({ count, causalSequenceStart, contentVisibleMs, baseLength, sendOffsets }) => {
      const state = globalThis.__loomarkSustainedInputMeasurement
      const inputs = state.inputs.slice(0, count)
      const firstBeforeMs = inputs[0].before_ms
      const causalMarks = state.causalMarks.filter(mark => mark.sequence > causalSequenceStart)
      const perInput = inputs.map((record, ordinal) => {
        const targetOffsetMs = sendOffsets[ordinal] - sendOffsets[0]
        const expectedCommittedLength = baseLength + ordinal + 1
        const causalMark = causalMarks.find(mark => mark.committedLength >= expectedCommittedLength)
        if (causalMark === undefined) throw new Error(`missing causal mark ${ordinal}`)
        const causalMs = causalMark.now
        return {
          ordinal,
          data: record.data,
          send_offset_ms: sendOffsets[ordinal],
          expected_committed_length: expectedCommittedLength,
          causal_sequence: causalMark.sequence,
          causal_committed_length: causalMark.committedLength,
          delivery_lag_ms: record.before_ms - firstBeforeMs - targetOffsetMs,
          input_visible_ms: record.visible_ms - record.before_ms,
          scheduled_input_visible_ms: record.visible_ms - firstBeforeMs - targetOffsetMs,
          causal_ready_ms: causalMs - record.before_ms,
          scheduled_causal_ready_ms: causalMs - firstBeforeMs - targetOffsetMs,
        }
      })
      const writes = state.transactions.filter(record => (
        record.kind === "application_write" &&
        record.terminal === "complete" &&
        record.start_ms >= firstBeforeMs
      ))
      if (writes.length < 1) throw new Error("sustained-input write missing")
      const lastWrite = writes.reduce((latest, candidate) => (
        candidate.end_ms > latest.end_ms ? candidate : latest
      ))
      const longTasks = state.longTasks.filter(record => record.start_ms >= firstBeforeMs)
      const frameGaps = state.frameGaps.filter(record => record.start_ms >= firstBeforeMs)
      return {
        content_visible_ms: contentVisibleMs,
        burst_durable_ms: lastWrite.end_ms - firstBeforeMs,
        write_count: writes.length,
        causal_commit_count: causalMarks.length,
        max_long_task_ms: longTasks.length === 0 ? 0 : Math.max(...longTasks.map(record => record.duration_ms)),
        max_frame_gap_ms: frameGaps.length === 0 ? 0 : Math.max(...frameGaps.map(record => record.duration_ms)),
        per_input: perInput,
      }
    }, {
      count: burst.length,
      causalSequenceStart,
      contentVisibleMs,
      baseLength: document.source.length,
      sendOffsets: sendSchedule.map(record => record.send_offset_ms),
    })
    const laterInputs = timing.per_input.slice(1)
    samples.push({
      sample,
      send_schedule: sendSchedule,
      content_visible_ms: rounded(timing.content_visible_ms),
      second_delivery_lag_ms: rounded(timing.per_input[1].delivery_lag_ms),
      later_delivery_lag_max_ms: rounded(Math.max(...laterInputs.map(record => record.delivery_lag_ms))),
      later_scheduled_input_visible_max_ms: rounded(Math.max(...laterInputs.map(record => record.scheduled_input_visible_ms))),
      later_input_visible_max_ms: rounded(Math.max(...laterInputs.map(record => record.input_visible_ms))),
      later_causal_ready_max_ms: rounded(Math.max(...laterInputs.map(record => record.causal_ready_ms))),
      burst_durable_ms: rounded(timing.burst_durable_ms),
      write_count: timing.write_count,
      causal_commit_count: timing.causal_commit_count,
      max_long_task_ms: rounded(timing.max_long_task_ms),
      max_frame_gap_ms: rounded(timing.max_frame_gap_ms),
      persisted_bytes: new TextEncoder().encode(persisted).length,
      per_input: timing.per_input.map(record => Object.fromEntries(
        Object.entries(record).map(([name, value]) => [name, typeof value === "number" ? rounded(value) : value]),
      )),
    })
  }
  await context.close()
  const summaryFields = [
    "content_visible_ms",
    "second_delivery_lag_ms",
    "later_delivery_lag_max_ms",
    "later_scheduled_input_visible_max_ms",
    "later_input_visible_max_ms",
    "later_causal_ready_max_ms",
    "burst_durable_ms",
    "write_count",
    "causal_commit_count",
    "max_long_task_ms",
    "max_frame_gap_ms",
    "persisted_bytes",
  ]
  return {
    lane: lane.name,
    measurement_order: measurementOrder,
    line_count: document.line_count,
    source_bytes: new TextEncoder().encode(document.source).length,
    seed_bytes: new TextEncoder().encode(seed).length,
    samples,
    summary: Object.fromEntries(summaryFields.map(field => [field, summarize(samples, field)])),
    per_ordinal_summary: [...burst].map((character, ordinal) => ({
      ordinal,
      character,
      delivery_lag_ms: summarizeValues(samples.map(sample => sample.per_input[ordinal].delivery_lag_ms)),
      input_visible_ms: summarizeValues(samples.map(sample => sample.per_input[ordinal].input_visible_ms)),
      scheduled_input_visible_ms: summarizeValues(samples.map(sample => sample.per_input[ordinal].scheduled_input_visible_ms)),
      causal_ready_ms: summarizeValues(samples.map(sample => sample.per_input[ordinal].causal_ready_ms)),
      scheduled_causal_ready_ms: summarizeValues(samples.map(sample => sample.per_input[ordinal].scheduled_causal_ready_ms)),
    })),
  }
}

let browser
try {
  await ready
  browser = await chromium.launch({ headless: true })
  const lanes = [
    { name: "full_history_v1", query: queryBase },
    { name: "local_text", query: `${queryBase}&local-text-prototype=1` },
  ]
  const results = []
  for (const [documentIndex, lineCount] of lineCounts.entries()) {
    const document = { line_count: lineCount, source: documentSource(lineCount) }
    const encodedArchive = await createFullHistorySeed(browser, document.source, lineCount)
    const orderedLanes = laneOrder === "full-first"
      ? lanes
      : laneOrder === "local-first"
        ? [...lanes].reverse()
        : documentIndex % 2 === 0 ? lanes : [...lanes].reverse()
    for (const [laneIndex, lane] of orderedLanes.entries()) {
      results.push(await measureLane(browser, document, lane, encodedArchive, laneIndex + 1))
    }
  }
  const output = {
    schema_version: 1,
    prototype: true,
    question: "Does synchronous full-history preparation displace second and later inputs on 2k/10k-line documents?",
    sample_count: sampleCount,
    burst,
    intended_input_interval_ms: intervalMs,
    lane_order: laneOrder,
    browser_version: browser.version(),
    results,
  }
  await writeFile(outputPath, `${JSON.stringify(output, null, 2)}\n`)
  process.stdout.write(`${outputPath}\n`)
} finally {
  await browser?.close()
  if (server.exitCode === null) {
    server.kill("SIGTERM")
    await Promise.race([once(server, "close"), new Promise(resolveWait => setTimeout(resolveWait, 1_000))])
    if (server.exitCode === null) server.kill("SIGKILL")
  }
}
