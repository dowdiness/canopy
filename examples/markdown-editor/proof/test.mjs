import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { createServer } from "node:http"
import { join } from "node:path"
import { fileURLToPath } from "node:url"
import { chromium } from "../../../apps/loomark/examples/vanilla/node_modules/playwright/index.mjs"

const dist = fileURLToPath(new URL("./dist/", import.meta.url))
const server = createServer(async (request, response) => {
  const name = request.url === "/" ? "index.html" : request.url?.slice(1)
  if (!["index.html", "index.js", "preview.css"].includes(name)) {
    response.writeHead(404).end()
    return
  }
  const body = await readFile(join(dist, name))
  const contentType = name.endsWith(".js") ? "text/javascript" :
    name.endsWith(".css") ? "text/css" : "text/html"
  response.writeHead(200, { "content-type": contentType }).end(body)
})

await new Promise(resolve => server.listen(0, "127.0.0.1", resolve))
let browser
try {
  browser = await chromium.launch()
  const page = await browser.newPage()
  const errors = []
  page.on("pageerror", error => errors.push(error.message))
  const baseURL = `http://127.0.0.1:${server.address().port}`

  await page.goto(baseURL)
  await page.waitForFunction(() => document.querySelector("#proof-text")?.value === "# First document\n")
  const originalOwner = await page.locator("#proof-text").getAttribute("data-rmd-text-area-owner")
  await page.getByRole("button", { name: "Reject then accept" }).click()
  await page.waitForFunction(() => document.querySelector("#proof-text")?.value === "# Accepted after rejection\n")
  // A stale after-render write would change the value back on the next frame.
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
  assert.equal(await page.locator("#proof-text").inputValue(), "# Accepted after rejection\n")

  await page.locator("#proof-text").evaluate(element => {
    window.__proofText = element
    element.setSelectionRange(4, 4)
  })
  await page.getByRole("button", { name: "Split" }).click()
  await page.getByRole("region", { name: "Markdown preview" })
    .getByRole("heading", { name: "Accepted after rejection" }).waitFor()
  await page.getByRole("button", { name: "Preview", exact: true }).click()
  await page.getByRole("button", { name: "Text", exact: true }).click()
  assert.deepEqual(await page.evaluate(() => ({
    sameNode: window.__proofText === document.querySelector("#proof-text"),
    selection: window.__proofText.selectionStart,
  })), { sameNode: true, selection: 4 })

  await page.getByRole("button", { name: "Split" }).click()
  await page.locator("#proof-text").pressSequentially("X")
  await page.getByRole("region", { name: "Markdown preview" })
    .getByRole("heading", { name: "AcXcepted after rejection" }).waitFor()
  await page.getByRole("button", { name: "Open document" }).click()
  await page.waitForFunction(() => document.querySelector("#proof-text")?.value === "# Opened another document\n")
  await page.getByRole("region", { name: "Markdown preview" })
    .getByRole("heading", { name: "Opened another document" }).waitFor()

  await page.goto(baseURL)
  await page.waitForFunction(() => document.querySelector("#proof-text")?.value === "# First document\n")
  await page.getByRole("button", { name: "Replace instance" }).click()
  await page.waitForFunction(() => document.querySelector("#proof-text")?.value === "# New textarea owner\n")
  assert.notEqual(await page.locator("#proof-text").getAttribute("data-rmd-text-area-owner"), originalOwner)

  await page.goto(baseURL)
  await page.waitForFunction(() => document.querySelector("#proof-text")?.value === "# First document\n")
  await page.getByRole("button", { name: "Unmount" }).click()
  await page.getByText("Unmounted").waitFor()
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
  assert.equal(await page.locator("#proof-text").count(), 0)
  assert.deepEqual(errors, [])
  console.log("Restore race, document switch, owner replacement, unmount and app-owned mode: passed")
} finally {
  await browser?.close()
  await new Promise(resolve => server.close(resolve))
}
