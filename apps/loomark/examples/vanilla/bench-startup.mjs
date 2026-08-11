import { spawn } from "node:child_process"
import { once } from "node:events"
import { readdir, readFile, stat } from "node:fs/promises"
import { fileURLToPath } from "node:url"
import { relative, resolve } from "node:path"
import { chromium } from "./node_modules/playwright/index.mjs"

const port = Number.parseInt(process.env.LOOMARK_STANDALONE_PORT ?? "4317", 10)
const archiveKey = "loomark.active-document-archive"
const sampleCount = parsePositiveInteger(
  process.env.LOOMARK_STARTUP_SAMPLES ?? "20",
  "LOOMARK_STARTUP_SAMPLES",
)
const historyCycles = parseCycles(
  process.env.LOOMARK_STARTUP_CYCLES ?? "0,2,10,20",
)
const markdownCorpusPath = process.env.LOOMARK_STARTUP_CORPUS
const archiveCorpusPath = process.env.LOOMARK_STARTUP_ARCHIVES
const includeCorpusPaths = process.env.LOOMARK_STARTUP_INCLUDE_PATHS === "1"

if (markdownCorpusPath !== undefined && archiveCorpusPath !== undefined) {
  throw new Error("set only one of LOOMARK_STARTUP_CORPUS and LOOMARK_STARTUP_ARCHIVES")
}

const serverPath = fileURLToPath(new URL("./serve-standalone-dist.mjs", import.meta.url))
const server = spawn(process.execPath, [serverPath], {
  env: { ...process.env, LOOMARK_STANDALONE_PORT: String(port) },
  stdio: ["ignore", "pipe", "inherit"],
})

const serverReady = new Promise((resolve, reject) => {
  const timeout = setTimeout(
    () => reject(new Error("standalone static server did not become ready")),
    5_000,
  )
  server.stdout.setEncoding("utf8")
  server.stdout.on("data", chunk => {
    process.stdout.write(chunk)
    if (chunk.includes(`http://127.0.0.1:${port}`)) {
      clearTimeout(timeout)
      resolve()
    }
  })
  server.once("error", error => {
    clearTimeout(timeout)
    reject(error)
  })
  server.once("close", code => {
    clearTimeout(timeout)
    reject(new Error(`standalone static server exited before readiness (${code ?? "signal"})`))
  })
})

function parsePositiveInteger(raw, name) {
  const value = Number.parseInt(raw, 10)
  if (!Number.isInteger(value) || value < 1) {
    throw new Error(`${name} must be a positive integer`)
  }
  return value
}

function parseCycles(raw) {
  const cycles = raw.split(",").map(value => Number.parseInt(value.trim(), 10))
  if (
    cycles.length === 0 ||
    cycles.some(value => !Number.isInteger(value) || value < 0)
  ) {
    throw new Error("LOOMARK_STARTUP_CYCLES must be a comma-separated list of non-negative integers")
  }
  return cycles
}

function browserText(source) {
  // HTML textareas expose LF-normalized values. Keep the source corpus bytes
  // in the report, but compare the mounted editor using its browser value.
  return source.replace(/\r\n?/g, "\n")
}

function percentile(values, percentage) {
  const sorted = [...values].sort((left, right) => left - right)
  const rank = Math.max(0, Math.ceil((percentage / 100) * sorted.length) - 1)
  return Number(sorted[rank].toFixed(1))
}

async function collectFiles(pathname, include) {
  const metadata = await stat(pathname)
  if (metadata.isFile()) return [pathname]
  if (!metadata.isDirectory()) {
    throw new Error(`corpus path is neither a file nor a directory: ${pathname}`)
  }

  const entries = (await readdir(pathname, { withFileTypes: true }))
    .sort((left, right) => left.name.localeCompare(right.name))
  const files = []
  for (const entry of entries) {
    const child = resolve(pathname, entry.name)
    if (entry.isDirectory()) {
      files.push(...await collectFiles(child, include))
    } else if (entry.isSymbolicLink()) {
      const target = await stat(child)
      if (target.isDirectory()) {
        throw new Error(`corpus does not follow symlinked directories: ${child}`)
      }
      if (target.isFile() && include(child)) files.push(child)
    } else if (entry.isFile() && include(child)) {
      files.push(child)
    }
  }
  return files
}

function corpusDocumentName(file, index) {
  return includeCorpusPaths ? relative(process.cwd(), file) : `document-${index + 1}`
}

async function loadMarkdownCorpus(pathname) {
  const root = resolve(pathname)
  const files = await collectFiles(
    root,
    file => /\.(?:md|markdown|mdown)$/i.test(file),
  )
  if (files.length === 0) {
    throw new Error(`Markdown corpus contains no .md, .markdown, or .mdown files: ${root}`)
  }
  return {
    kind: "markdown",
    documents: await Promise.all(files.map(async (file, index) => {
      const source = await readFile(file, "utf8")
      return {
        name: corpusDocumentName(file, index),
        source,
        sourceBytes: Buffer.byteLength(source),
      }
    })),
  }
}

function archiveStatsFromEncoded(encoded) {
  const archive = JSON.parse(encoded)
  const markdown = typeof archive.portable_markdown === "string"
    ? archive.portable_markdown
    : ""
  const history = typeof archive.history === "string" ? archive.history : ""
  return {
    archiveBytes: Buffer.byteLength(encoded),
    markdownBytes: Buffer.byteLength(markdown),
    historyBytes: Buffer.byteLength(history),
    historyChars: history.length,
  }
}

async function loadArchiveCorpus(pathname) {
  const root = resolve(pathname)
  const files = await collectFiles(root, file => file.toLowerCase().endsWith(".json"))
  if (files.length === 0) {
    throw new Error(`Archive corpus contains no .json files: ${root}`)
  }
  return {
    kind: "archive",
    documents: await Promise.all(files.map(async (file, index) => {
      const encoded = await readFile(file, "utf8")
      const archive = JSON.parse(encoded)
      const fields = archive === null || typeof archive !== "object"
        ? []
        : Object.keys(archive).sort()
      const expectedFields = [
        "document_id",
        "extensions",
        "history",
        "portable_markdown",
        "schema_version",
      ]
      if (
        JSON.stringify(fields) !== JSON.stringify(expectedFields) ||
        archive.schema_version !== "1" ||
        typeof archive.document_id !== "string" ||
        archive.document_id.length === 0 ||
        typeof archive.portable_markdown !== "string" ||
        typeof archive.history !== "string" ||
        archive.extensions === null ||
        typeof archive.extensions !== "object" ||
        Array.isArray(archive.extensions) ||
        Object.keys(archive.extensions).length !== 0
      ) {
        throw new Error(`archive fixture is not a complete v1 envelope: ${file}`)
      }
      return {
        name: corpusDocumentName(file, index),
        encoded,
        finalValue: browserText(archive.portable_markdown),
        sourceBytes: Buffer.byteLength(archive.portable_markdown),
        stats: archiveStatsFromEncoded(encoded),
      }
    })),
  }
}

async function loadCorpus() {
  if (archiveCorpusPath !== undefined) return loadArchiveCorpus(archiveCorpusPath)
  if (markdownCorpusPath !== undefined) return loadMarkdownCorpus(markdownCorpusPath)
  return {
    kind: "markdown",
    documents: [{
      name: "synthetic",
      source: "# Startup benchmark\n\nSame final document\n",
      sourceBytes: Buffer.byteLength("# Startup benchmark\n\nSame final document\n"),
    }],
  }
}

async function stopServer() {
  if (server.exitCode !== null) return
  server.kill("SIGTERM")
  await Promise.race([
    once(server, "close"),
    new Promise(resolve => setTimeout(resolve, 1_000)),
  ])
  if (server.exitCode === null) server.kill("SIGKILL")
}

async function replaceRawValue(page, value) {
  const previousHistoryBytes = await page.evaluate(key => {
    const raw = localStorage.getItem(key) ?? ""
    const archive = JSON.parse(raw)
    return new TextEncoder().encode(archive.history ?? "").length
  }, archiveKey)
  await page.locator("#loomark-input").evaluate((element, nextValue) => {
    const textarea = element
    const currentLength = textarea.value.length
    textarea.setSelectionRange(0, currentLength, "forward")
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
  await page.waitForTimeout(100)
  try {
    await page.waitForFunction(({ expected, minimumHistoryBytes, key }) => {
      const input = document.querySelector("#loomark-input")
      const raw = localStorage.getItem(key)
      if (input === null || raw === null) return false
      const archive = JSON.parse(raw)
      return input.value === expected &&
        archive.portable_markdown === expected &&
        new TextEncoder().encode(archive.history ?? "").length > minimumHistoryBytes
    }, { expected: value, minimumHistoryBytes: previousHistoryBytes, key: archiveKey })
  } catch (error) {
    const observed = await page.evaluate(key => {
      const input = document.querySelector("#loomark-input")
      const raw = localStorage.getItem(key)
      if (raw === null) {
        return { inputLength: input?.value.length ?? null, archivePresent: false }
      }
      const archive = JSON.parse(raw)
      return {
        inputLength: input?.value.length ?? null,
        archivePresent: true,
        archiveBytes: new TextEncoder().encode(raw).length,
        markdownLength: (archive.portable_markdown ?? "").length,
        historyBytes: new TextEncoder().encode(archive.history ?? "").length,
      }
    }, archiveKey)
    throw new Error(
      `archive did not settle for ${value.length} input characters: ${JSON.stringify(observed)}; ${error.message}`,
    )
  }
}

async function archiveStats(page) {
  const encoded = await page.evaluate(key => localStorage.getItem(key), archiveKey)
  if (encoded === null) throw new Error("Loomark did not create an active archive")
  return { encoded, stats: archiveStatsFromEncoded(encoded) }
}

async function buildArchive(browser, document, cycles) {
  const context = await browser.newContext()
  const page = await context.newPage()
  const finalValue = browserText(document.source)

  await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: "commit" })
  await page.locator("#loomark-root").waitFor({ state: "visible" })
  if (finalValue.length > 0) await replaceRawValue(page, finalValue)

  for (let index = 0; index < cycles; index += 1) {
    await replaceRawValue(page, `${finalValue}intermediate revision ${index}\n`)
    await replaceRawValue(page, finalValue)
  }

  const archive = await archiveStats(page)
  await context.close()
  return {
    ...archive,
    finalValue,
    historyChangingOperations: (finalValue.length === 0 ? 0 : 1) + cycles * 2,
  }
}

async function waitForRestoredDocument(page, finalValue) {
  await page.waitForFunction(() => {
    return document.querySelector("#loomark-root") !== null ||
      document.querySelector("#loomark-recovery-root") !== null
  })
  const recovery = page.locator("#loomark-recovery-root")
  if (await recovery.count() > 0) {
    const category = await recovery.getAttribute("data-loomark-recovery-category")
    throw new Error(`archive restore entered recovery (${category ?? "unknown"})`)
  }
  await page.locator("#loomark-root").waitFor({ state: "visible" })
  await page.waitForFunction(expected => {
    return document.querySelector("#loomark-input")?.value === expected
  }, finalValue)
}

async function measureReloads(browser, encoded, finalValue) {
  const context = await browser.newContext()
  const page = await context.newPage()

  // Seed and admit the fixture before the measured reloads. In particular, do
  // not rewrite the archive from an init script on every measured navigation.
  await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: "commit" })
  await page.locator("#loomark-root").waitFor({ state: "visible" })
  await page.evaluate(({ key, value }) => {
    localStorage.setItem(key, value)
  }, { key: archiveKey, value: encoded })
  await page.reload({ waitUntil: "commit" })
  await waitForRestoredDocument(page, finalValue)

  const measurements = []
  for (let index = 0; index < sampleCount; index += 1) {
    await page.reload({ waitUntil: "commit" })
    await waitForRestoredDocument(page, finalValue)
    measurements.push(await page.evaluate(() => {
      const entry = performance.getEntriesByType("navigation")[0]
      const script = performance
        .getEntriesByType("resource")
        .find(resource => resource.name.endsWith("/index.js"))
      return {
        reloadRestoredDocumentMs: performance.now(),
        domContentLoadedMs: entry?.domContentLoadedEventEnd ?? null,
        indexJsTransferBytes: script?.transferSize ?? null,
        indexJsDecodedBytes: script?.decodedBodySize ?? null,
      }
    }))
  }
  await context.close()

  const restoredDocument = measurements.map(
    measurement => measurement.reloadRestoredDocumentMs,
  )
  const domContentLoaded = measurements
    .map(measurement => measurement.domContentLoadedMs)
    .filter(value => value !== null)
  const network = measurements.find(measurement => measurement.indexJsDecodedBytes !== null) ?? measurements[0]
  return {
    reloadRestoredDocumentSamples: restoredDocument.map(value => Number(value.toFixed(1))),
    reloadRestoredDocumentP50Ms: percentile(restoredDocument, 50),
    reloadRestoredDocumentP95Ms: percentile(restoredDocument, 95),
    domContentLoadedP50Ms: domContentLoaded.length === 0
      ? null
      : percentile(domContentLoaded, 50),
    domContentLoadedP95Ms: domContentLoaded.length === 0
      ? null
      : percentile(domContentLoaded, 95),
    indexJsTransferBytes: network?.indexJsTransferBytes ?? null,
    indexJsDecodedBytes: network?.indexJsDecodedBytes ?? null,
  }
}

async function runScenario(browser, document, cycles, kind) {
  const prepared = kind === "archive"
    ? document
    : await buildArchive(browser, document, cycles)
  const measurements = await measureReloads(browser, prepared.encoded, prepared.finalValue)
  return {
    corpusDocument: document.name,
    corpusKind: kind,
    sourceBytes: document.sourceBytes,
    cycles: kind === "archive" ? null : cycles,
    historyChangingOperations: kind === "archive"
      ? null
      : prepared.historyChangingOperations,
    ...prepared.stats,
    ...measurements,
    restoredDocument: prepared.finalValue.length,
  }
}

try {
  await serverReady
  const corpus = await loadCorpus()
  console.log(
    `Startup benchmark corpus: ${corpus.kind} (${corpus.documents.length} document${corpus.documents.length === 1 ? "" : "s"}), ` +
      `${sampleCount} reload samples`,
  )
  const browser = await chromium.launch({ headless: true })
  const results = []
  if (corpus.kind === "archive") {
    for (const document of corpus.documents) {
      results.push(await runScenario(browser, document, null, corpus.kind))
    }
  } else {
    for (const document of corpus.documents) {
      for (const cycles of historyCycles) {
        results.push(await runScenario(browser, document, cycles, corpus.kind))
      }
    }
  }
  await browser.close()
  console.table(results.map(result => {
    const { reloadRestoredDocumentSamples, ...summary } = result
    return summary
  }))
  for (const result of results) console.log(JSON.stringify(result))
} finally {
  await stopServer()
}
