// PROTOTYPE — disposable LocalText/four-clock browser experiment.
import { spawn } from "node:child_process"
import { once } from "node:events"
import { readFile, writeFile } from "node:fs/promises"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { chromium } from "playwright"

const here = dirname(fileURLToPath(import.meta.url))
const fixtureRoot = resolve(here, "fixtures/r0-browser-v1")
const catalog = JSON.parse(await readFile(resolve(fixtureRoot, "browser-fixture-catalog-v1.json"), "utf8"))
const sampleCount = Number.parseInt(process.env.LOOMARK_LOCALTEXT_SAMPLES ?? "20", 10)
const outputPath = process.env.LOOMARK_LOCALTEXT_OUTPUT ?? "/tmp/loomark-localtext-four-clocks.json"
const distRoot = process.env.LOOMARK_STANDALONE_DIST
const databaseName = "loomark.local-repository"
const storeName = "archives"
const baselineKey = "loomark.active-document-archive"
const localTextKey = "loomark.prototype-local-text"
const serverPath = fileURLToPath(new URL("./serve-standalone-dist.mjs", import.meta.url))

if (!Number.isSafeInteger(sampleCount) || sampleCount < 3) {
  throw new Error("LOOMARK_LOCALTEXT_SAMPLES must be an integer >= 3")
}

const server = spawn(process.execPath, [serverPath], {
  env: {
    ...process.env,
    LOOMARK_STANDALONE_PORT: "0",
    LOOMARK_R0_BROWSER_FIXTURE_ROOT: fixtureRoot,
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

function browserText(source) {
  return source.replace(/\r\n?/g, "\n")
}

function percentile(values, percent) {
  const sorted = [...values].sort((a, b) => a - b)
  return sorted[Math.max(0, Math.ceil(percent / 100 * sorted.length) - 1)]
}

function rounded(value) {
  return Number(value.toFixed(3))
}

function summarize(samples, field) {
  const values = samples.map(sample => sample[field])
  return {
    p50: rounded(percentile(values, 50)),
    p95: rounded(percentile(values, 95)),
    max: rounded(Math.max(...values)),
    raw: values.map(rounded),
  }
}

async function putRecord(page, key, value) {
  await page.evaluate(async ({ databaseName, storeName, key, value }) => await new Promise((resolvePut, reject) => {
    const request = indexedDB.open(databaseName, 1)
    request.onupgradeneeded = () => {
      if (!request.result.objectStoreNames.contains(storeName)) {
        request.result.createObjectStore(storeName)
      }
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

async function waitForRecordText(page, key, expected, timeout = 30_000) {
  const deadline = Date.now() + timeout
  while (Date.now() < deadline) {
    const encoded = await getRecord(page, key)
    if (encoded !== null) {
      const record = JSON.parse(encoded)
      if (record.portable_markdown === expected) return encoded
    }
    await page.waitForTimeout(5)
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

async function measureLane(browser, fixture, encodedArchive, lane, measurementOrder) {
  const archive = JSON.parse(encodedArchive)
  const expected = browserText(fixture.expected_text)
  const expectedAfter = browserText(fixture.expected_text_after_edit)
  const seed = lane.name === "local_text" ? localTextRecord(archive) : encodedArchive
  const key = lane.name === "local_text" ? localTextKey : baselineKey
  const context = await browser.newContext()
  await context.addInitScript(({ storeName, measuredKey }) => {
    const originalTransaction = IDBDatabase.prototype.transaction
    const originalOpenCursor = IDBObjectStore.prototype.openCursor
    const originalPut = IDBObjectStore.prototype.put
    const transactionRecords = new WeakMap()
    const state = {
      transactions: [],
      beforeInputMs: null,
      inputVisibleMs: null,
      causalSequenceBefore: null,
    }
    globalThis.__loomarkLocalTextMeasurement = state

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
      state.beforeInputMs = performance.now()
      state.inputVisibleMs = null
      state.causalSequenceBefore = Number(
        document.documentElement.dataset.loomarkCausalReadySequence ?? "0",
      )
      delete document.documentElement.dataset.loomarkCausalReadyMs
    }, true)
    document.addEventListener("input", event => {
      if (event.target?.id !== "loomark-input") return
      requestAnimationFrame(() => requestAnimationFrame(() => {
        if (state.beforeInputMs !== null) state.inputVisibleMs = performance.now()
      }))
    }, true)
  }, { storeName, measuredKey: key })

  const page = await context.newPage()
  const fixtureUrl = `${origin}/fixtures/r0-browser-v1/${fixture.archive_path.split("/").at(-1)}`
  await page.goto(fixtureUrl, { waitUntil: "commit" })
  await putRecord(page, key, seed)
  await page.goto(`${origin}/${lane.query}`, { waitUntil: "commit" })
  await page.locator("#loomark-input").waitFor({ state: "visible", timeout: 30_000 })
  await page.waitForFunction(value => document.querySelector("#loomark-input")?.value === value, expected)

  // Warm the complete edit and selected durable-write path once before any
  // measured sample, then every sample reseeds the original immutable record.
  const warmupInput = page.locator("#loomark-input")
  await warmupInput.focus()
  await warmupInput.evaluate(element => {
    const end = element.value.length
    element.setSelectionRange(end, end, "forward")
  })
  await page.keyboard.type("Z")
  await waitForRecordText(page, key, fixture.expected_text_after_edit)

  const samples = []
  for (let sample = 0; sample < sampleCount; sample += 1) {
    await putRecord(page, key, seed)
    await page.reload({ waitUntil: "commit" })
    const input = page.locator("#loomark-input")
    await input.waitFor({ state: "visible", timeout: 30_000 })
    await page.waitForFunction(value => document.querySelector("#loomark-input")?.value === value, expected)
    const contentVisibleMs = await page.evaluate(() => performance.now())
    await input.focus()
    await input.evaluate(element => {
      const end = element.value.length
      element.setSelectionRange(end, end, "forward")
      globalThis.__loomarkLocalTextMeasurement.beforeInputMs = null
      globalThis.__loomarkLocalTextMeasurement.inputVisibleMs = null
      globalThis.__loomarkLocalTextMeasurement.causalSequenceBefore = null
      delete document.documentElement.dataset.loomarkCausalReadyMs
    })
    await page.keyboard.type("Z")
    await page.waitForFunction(value => {
      const state = globalThis.__loomarkLocalTextMeasurement
      const causalSequence = Number(
        document.documentElement.dataset.loomarkCausalReadySequence ?? "0",
      )
      return document.querySelector("#loomark-input")?.value === value &&
        state.beforeInputMs !== null && state.inputVisibleMs !== null &&
        state.causalSequenceBefore !== null &&
        causalSequence === state.causalSequenceBefore + 1 &&
        document.documentElement.dataset.loomarkCausalReadyMs !== undefined
    }, expectedAfter, { timeout: 30_000 })
    const persisted = await waitForRecordText(
      page,
      key,
      fixture.expected_text_after_edit,
    )
    const timing = await page.evaluate(contentVisibleMs => {
      const state = globalThis.__loomarkLocalTextMeasurement
      const beforeInputMs = state.beforeInputMs
      const causalReadyMs = Number(document.documentElement.dataset.loomarkCausalReadyMs)
      const reads = state.transactions.filter(record => record.kind === "application_read" && record.terminal === "complete")
      const writes = state.transactions.filter(record => (
        record.kind === "application_write" && record.terminal === "complete" &&
        record.start_ms >= beforeInputMs
      ))
      if (reads.length !== 1 || writes.length !== 1) {
        throw new Error(`four-clock transaction mismatch: reads=${reads.length} writes=${writes.length}`)
      }
      const read = reads[0]
      const write = writes[0]
      return {
        content_visible_ms: contentVisibleMs,
        storage_read_ms: read.end_ms - read.start_ms,
        restore_after_storage_ms: contentVisibleMs - read.end_ms,
        input_visible_ms: state.inputVisibleMs - beforeInputMs,
        causal_ready_ms: causalReadyMs - beforeInputMs,
        durable_ms: write.end_ms - beforeInputMs,
      }
    }, contentVisibleMs)
    samples.push({
      sample,
      ...Object.fromEntries(Object.entries(timing).map(([name, value]) => [name, rounded(value)])),
      persisted_bytes: new TextEncoder().encode(persisted).length,
    })
  }
  await context.close()
  return {
    lane: lane.name,
    measurement_order: measurementOrder,
    fixture_id: fixture.fixture_id,
    source_bytes: new TextEncoder().encode(archive.portable_markdown).length,
    seed_bytes: new TextEncoder().encode(seed).length,
    samples,
    summary: Object.fromEntries([
      "content_visible_ms",
      "storage_read_ms",
      "restore_after_storage_ms",
      "input_visible_ms",
      "causal_ready_ms",
      "durable_ms",
      "persisted_bytes",
    ].map(field => [field, summarize(samples, field)])),
  }
}

let browser
try {
  await ready
  browser = await chromium.launch({ headless: true })
  const lanes = [
    { name: "full_history_v1", query: "?projection-benchmark=1&four-clock-prototype=1" },
    { name: "local_text", query: "?projection-benchmark=1&four-clock-prototype=1&local-text-prototype=1" },
  ]
  const results = []
  for (const [fixtureIndex, fixture] of catalog.fixtures.entries()) {
    const encoded = await readFile(resolve(fixtureRoot, fixture.archive_path.split("/").at(-1)), "utf8")
    const orderedLanes = fixtureIndex % 2 === 0 ? lanes : [...lanes].reverse()
    for (const [laneIndex, lane] of orderedLanes.entries()) {
      process.stderr.write(`measure ${fixture.fixture_id} ${lane.name}\n`)
      results.push(await measureLane(browser, fixture, encoded, lane, laneIndex + 1))
    }
  }
  const output = {
    schema_version: 1,
    prototype: true,
    question: "Does text-only persistence remove Loomark input and reopen latency without changing the editor implementation?",
    sample_count: sampleCount,
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
