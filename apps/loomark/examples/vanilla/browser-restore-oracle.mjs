import { spawn } from "node:child_process"
import { once } from "node:events"
import { readFile } from "node:fs/promises"
import { createHash } from "node:crypto"
import { fileURLToPath } from "node:url"
import { chromium } from "playwright"

const [archivePath, caseId, expectedCountRaw, distRoot] = process.argv.slice(2)
if (archivePath == null || caseId == null || expectedCountRaw == null) {
  throw new Error("usage: browser-restore-oracle.mjs ARCHIVE CASE EXPECTED_COUNT [DIST_ROOT]")
}
const expectedCount = Number.parseInt(expectedCountRaw, 10)
if (!Number.isSafeInteger(expectedCount) || expectedCount < 0) {
  throw new Error("expected operation count must be a non-negative integer")
}
const archiveJson = await readFile(archivePath, "utf8")
const archive = JSON.parse(archiveJson)
const history = JSON.parse(archive.history)
if (history.operations.length !== expectedCount) {
  throw new Error(`archive operation count ${history.operations.length} != ${expectedCount}`)
}

const ARCHIVE_DATABASE = "loomark.local-repository"
const ARCHIVE_STORE = "archives"
const ARCHIVE_KEY = "loomark.active-document-archive"

async function seedArchive(context, origin, encoded) {
  const seedPage = await context.newPage()
  try {
    await seedPage.goto(`${origin}/__loomark_idb_seed__`)
    await seedPage.evaluate(async ({ value, databaseName, storeName, key }) => {
      await new Promise((resolve, reject) => {
        const request = indexedDB.open(databaseName, 1)
        request.onupgradeneeded = () => {
          const database = request.result
          if (!database.objectStoreNames.contains(storeName)) {
            database.createObjectStore(storeName)
          }
        }
        request.onerror = () => reject(request.error ?? new Error("archive database open failed"))
        request.onsuccess = () => {
          const database = request.result
          const transaction = database.transaction(storeName, "readwrite")
          transaction.objectStore(storeName).put(value, key)
          transaction.oncomplete = () => {
            database.close()
            resolve()
          }
          transaction.onerror = () => reject(transaction.error ?? new Error("archive seed failed"))
          transaction.onabort = () => reject(transaction.error ?? new Error("archive seed aborted"))
        }
      })
    }, { value: encoded, databaseName: ARCHIVE_DATABASE, storeName: ARCHIVE_STORE, key: ARCHIVE_KEY })
  } finally {
    await seedPage.close()
  }
}

async function readArchive(page) {
  return page.evaluate(async ({ databaseName, storeName, key }) => await new Promise((resolve, reject) => {
    const request = indexedDB.open(databaseName, 1)
    request.onerror = () => reject(request.error ?? new Error("archive database open failed"))
    request.onsuccess = () => {
      const database = request.result
      const transaction = database.transaction(storeName, "readonly")
      const read = transaction.objectStore(storeName).get(key)
      read.onsuccess = () => {
        database.close()
        resolve(read.result ?? null)
      }
      read.onerror = () => reject(read.error ?? new Error("archive read failed"))
    }
  }), { databaseName: ARCHIVE_DATABASE, storeName: ARCHIVE_STORE, key: ARCHIVE_KEY })
}

async function waitForArchive(page, matches, timeout = 30000) {
  const deadline = Date.now() + timeout
  while (Date.now() < deadline) {
    const encoded = await readArchive(page)
    if (encoded != null) {
      const parsed = JSON.parse(encoded)
      if (matches(parsed, encoded)) return encoded
    }
    await page.waitForTimeout(100)
  }
  throw new Error("timed out waiting for IndexedDB archive")
}

const port = 4400 + Math.floor(Math.random() * 1000)
const serverPath = fileURLToPath(new URL("./serve-standalone-dist.mjs", import.meta.url))
const server = spawn(process.execPath, [serverPath], {
  env: {
    ...process.env,
    LOOMARK_STANDALONE_PORT: String(port),
    ...(distRoot == null ? {} : { LOOMARK_STANDALONE_DIST: distRoot }),
  },
  stdio: ["ignore", "pipe", "inherit"],
})
const ready = new Promise((resolve, reject) => {
  const timeout = setTimeout(() => reject(new Error("standalone server timeout")), 5000)
  server.stdout.setEncoding("utf8")
  server.stdout.on("data", chunk => {
    if (chunk.includes(`http://127.0.0.1:${port}`)) {
      clearTimeout(timeout)
      resolve()
    }
  })
  server.once("error", reject)
  server.once("close", code => reject(new Error(`standalone server exited: ${code}`)))
})

let browser
let context
let page
try {
  await ready
  const origin = `http://127.0.0.1:${port}`
  browser = await chromium.launch({ headless: true })
  context = await browser.newContext()
  await seedArchive(context, origin, archiveJson)
  page = await context.newPage()
  await page.goto(`${origin}/`)
  const input = page.locator("#loomark-input")
  await input.waitFor({ state: "visible", timeout: 30000 })
  const browserText = archive.portable_markdown.replace(/\r\n?/g, "\n")
  await page.waitForFunction(expectedText => {
    const textarea = document.querySelector("#loomark-input")
    return textarea instanceof HTMLTextAreaElement && textarea.value === expectedText
  }, browserText, { timeout: 30000 })
  await waitForArchive(page, (_parsed, encoded) => encoded === archiveJson)

  await input.focus()
  await input.evaluate(element => {
    const length = element.value.length
    element.setSelectionRange(length, length, "forward")
  })
  await page.keyboard.type("x")
  const expectedAfter = `${archive.portable_markdown}x`
  const acceptedArchiveJson = await waitForArchive(
    page,
    parsed => parsed.portable_markdown === expectedAfter,
  )
  await page.waitForTimeout(100)

  const acceptedArchive = JSON.parse(acceptedArchiveJson)
  const acceptedHistory = JSON.parse(acceptedArchive.history)
  if (acceptedHistory.operations.length !== expectedCount + 1) {
    throw new Error(`post-edit operation count ${acceptedHistory.operations.length} != ${expectedCount + 1}`)
  }

  await context.close()
  await browser.close()
  browser = await chromium.launch({ headless: true })
  context = await browser.newContext()
  await seedArchive(context, origin, acceptedArchiveJson)
  page = await context.newPage()
  await page.goto(`${origin}/`)
  await page.locator("#loomark-input").waitFor({ state: "visible", timeout: 30000 })
  await page.waitForFunction(expected => {
    const textarea = document.querySelector("#loomark-input")
    return textarea instanceof HTMLTextAreaElement && textarea.value === expected
  }, expectedAfter.replace(/\r\n?/g, "\n"), { timeout: 30000 })
  await waitForArchive(page, parsed => parsed.portable_markdown === expectedAfter)

  process.stdout.write(`${JSON.stringify({
    schema_version: 1,
    run_id: "gate-r0-v1",
    case_id: caseId,
    producer: "loomark_fresh_browser_oracle",
    status: "pass",
    payload: {
      record: "browser_oracle_result",
      operation_count: expectedCount,
      post_edit_operation_count: acceptedHistory.operations.length,
      restored_text_sha256: createHash("sha256").update(archive.portable_markdown).digest("hex"),
      edit_persisted_after_fresh_process: true,
      fresh_page: true,
    },
  })}\n`)
  await context.close()
} catch (error) {
  if (page != null) {
    const observed = await page.locator("#loomark-input").inputValue().catch(() => "")
    process.stderr.write(`browser input: ${JSON.stringify({ length: observed.length, prefix: observed.slice(0, 16), suffix: observed.slice(-16) })}\n`)
    const stored = await readArchive(page).catch(() => null)
    process.stderr.write(`browser archive bytes: ${stored == null ? 0 : Buffer.byteLength(stored)}\n`)
  }
  throw error
} finally {
  if (browser != null) await browser.close()
  if (server.exitCode == null) {
    server.kill("SIGTERM")
    await Promise.race([once(server, "close"), new Promise(resolve => setTimeout(resolve, 1000))])
    if (server.exitCode == null) server.kill("SIGKILL")
  }
}
