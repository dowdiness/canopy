import { spawn } from "node:child_process"
import { once } from "node:events"
import { fileURLToPath } from "node:url"
import { chromium } from "./node_modules/playwright/index.mjs"

const port = Number.parseInt(process.env.LOOMARK_STANDALONE_PORT ?? "4317", 10)
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
  const previousHistoryBytes = await page.evaluate(() => {
    const raw = localStorage.getItem("loomark.active-document-archive") ?? ""
    const archive = JSON.parse(raw)
    return new TextEncoder().encode(archive.history ?? "").length
  })
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
  await page.waitForFunction(({ expected, minimumHistoryBytes }) => {
    const raw = localStorage.getItem("loomark.active-document-archive")
    if (raw === null) return false
    const archive = JSON.parse(raw)
    return archive.portable_markdown === expected &&
      new TextEncoder().encode(archive.history ?? "").length > minimumHistoryBytes
  }, { expected: value, minimumHistoryBytes: previousHistoryBytes })
}

async function archiveStats(page) {
  return page.evaluate(() => {
    const raw = localStorage.getItem("loomark.active-document-archive") ?? ""
    const archive = JSON.parse(raw)
    const encoder = new TextEncoder()
    return {
      archiveBytes: encoder.encode(raw).length,
      markdownBytes: encoder.encode(archive.portable_markdown ?? "").length,
      historyBytes: encoder.encode(archive.history ?? "").length,
      historyChars: (archive.history ?? "").length,
    }
  })
}

async function runScenario(browser, cycles) {
  const context = await browser.newContext()
  const page = await context.newPage()
  const finalValue = "# Startup benchmark\n\nSame final document\n"

  await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: "commit" })
  await page.locator("#loomark-root").waitFor({ state: "visible" })
  await replaceRawValue(page, finalValue)

  for (let index = 0; index < cycles; index += 1) {
    await replaceRawValue(page, `${finalValue}intermediate revision ${index}\n`)
    await replaceRawValue(page, finalValue)
  }

  const archive = await archiveStats(page)
  const reloadStartedAt = performance.now()
  await page.reload({ waitUntil: "commit" })
  await page.locator("#loomark-root").waitFor({ state: "visible" })
  const restoredValue = await page.locator("#loomark-input").inputValue()
  if (restoredValue !== finalValue) {
    throw new Error("startup benchmark did not restore the final document")
  }
  const reloadRootVisibleMs = performance.now() - reloadStartedAt
  const navigation = await page.evaluate(() => {
    const entry = performance.getEntriesByType("navigation")[0]
    const script = performance
      .getEntriesByType("resource")
      .find(resource => resource.name.endsWith("/index.js"))
    return {
      appReadyMs: performance.now(),
      domContentLoadedMs: entry?.domContentLoadedEventEnd ?? null,
      indexJsTransferBytes: script?.transferSize ?? null,
      indexJsDecodedBytes: script?.decodedBodySize ?? null,
    }
  })
  const restored = await archiveStats(page)
  await context.close()
  return {
    cycles,
    historyChangingOperations: 1 + cycles * 2,
    ...archive,
    reloadRootVisibleMs: Number(reloadRootVisibleMs.toFixed(1)),
    ...navigation,
    restoredArchiveBytes: restored.archiveBytes,
    restoredDocument: restoredValue.length,
  }
}

try {
  await serverReady
  const browser = await chromium.launch({ headless: true })
  const results = []
  for (const cycles of [0, 2, 10, 20]) {
    results.push(await runScenario(browser, cycles))
  }
  await browser.close()
  console.table(results)
  for (const result of results) console.log(JSON.stringify(result))
} finally {
  await stopServer()
}
