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
  browser = await chromium.launch({ headless: true })
  context = await browser.newContext()
  await context.addInitScript(encoded => {
    localStorage.setItem("loomark.active-document-archive", encoded)
  }, archiveJson)
  page = await context.newPage()
  await page.goto(`http://127.0.0.1:${port}/`)
  const input = page.locator("#loomark-input")
  await input.waitFor({ state: "visible", timeout: 30000 })
  const browserText = archive.portable_markdown.replace(/\r\n?/g, "\n")
  await page.waitForFunction(({ expectedText, expectedArchive }) => {
    const textarea = document.querySelector("#loomark-input")
    return textarea instanceof HTMLTextAreaElement &&
      textarea.value === expectedText &&
      localStorage.getItem("loomark.active-document-archive") === expectedArchive
  }, { expectedText: browserText, expectedArchive: archiveJson }, { timeout: 30000 })

  await input.focus()
  await input.evaluate(element => {
    const length = element.value.length
    element.setSelectionRange(length, length, "forward")
  })
  await page.keyboard.type("x")
  const expectedAfter = `${archive.portable_markdown}x`
  await page.waitForFunction(expected => {
    const encoded = localStorage.getItem("loomark.active-document-archive")
    return encoded != null && JSON.parse(encoded).portable_markdown === expected
  }, expectedAfter, { timeout: 30000 })
  await page.waitForTimeout(100)

  const acceptedArchiveJson = await page.evaluate(() => (
    localStorage.getItem("loomark.active-document-archive")
  ))
  if (acceptedArchiveJson == null) throw new Error("accepted archive is missing")
  const acceptedArchive = JSON.parse(acceptedArchiveJson)
  const acceptedHistory = JSON.parse(acceptedArchive.history)
  if (acceptedHistory.operations.length !== expectedCount + 1) {
    throw new Error(`post-edit operation count ${acceptedHistory.operations.length} != ${expectedCount + 1}`)
  }

  await context.close()
  await browser.close()
  browser = await chromium.launch({ headless: true })
  context = await browser.newContext()
  await context.addInitScript(encoded => {
    localStorage.setItem("loomark.active-document-archive", encoded)
  }, acceptedArchiveJson)
  page = await context.newPage()
  await page.goto(`http://127.0.0.1:${port}/`)
  await page.locator("#loomark-input").waitFor({ state: "visible", timeout: 30000 })
  await page.waitForFunction(expected => {
    const textarea = document.querySelector("#loomark-input")
    return textarea instanceof HTMLTextAreaElement && textarea.value === expected
  }, expectedAfter.replace(/\r\n?/g, "\n"), { timeout: 30000 })

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
    const stored = await page.evaluate(() => localStorage.getItem("loomark.active-document-archive"))
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
