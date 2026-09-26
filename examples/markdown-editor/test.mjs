import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { createServer } from "node:http"
import { join } from "node:path"
import { fileURLToPath } from "node:url"
import { chromium } from "../../apps/loomark/examples/vanilla/node_modules/playwright/index.mjs"

const dist = fileURLToPath(new URL("./dist/", import.meta.url))
const server = createServer(async (request, response) => {
  const name = request.url === "/" ? "index.html" : request.url?.slice(1)
  if (!["index.html", "index.js", "preview.css", "editor.css", "styles.css"].includes(name)) {
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
  await page.goto(`http://127.0.0.1:${server.address().port}/`)
  const left = page.getByRole("region", { name: "Draft A" })
  const right = page.getByRole("region", { name: "Draft B" })
  await right.getByRole("heading", { name: "Second draft" }).waitFor()
  await left.getByRole("button", { name: "Split" }).click()
  await left.getByRole("heading", { name: "First draft" }).waitFor()

  const leftInput = left.getByRole("textbox", { name: "Draft A Markdown text" })
  await leftInput.click()
  await leftInput.press("ControlOrMeta+a")
  await leftInput.pressSequentially("# Only A\n")
  await left.getByRole("heading", { name: "Only A" }).waitFor()
  assert.equal(await right.getByRole("heading", { name: "Second draft" }).count(), 1)

  await leftInput.evaluate(element => {
    window.leftTextarea = element
    element.setSelectionRange(3, 3)
  })
  await left.getByRole("button", { name: "Preview" }).click()
  await left.getByRole("button", { name: "Text" }).click()
  assert.deepEqual(await page.evaluate(() => ({
    sameNode: window.leftTextarea === document.querySelector("#draft-a-text"),
    selection: window.leftTextarea.selectionStart,
  })), { sameNode: true, selection: 3 })

  const rightInput = right.getByRole("textbox", { name: "Draft B Markdown text" })
  await rightInput.evaluate(element => {
    element.setSelectionRange(0, element.value.length)
    element.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true }))
    element.value = "# 日本語\n"
    element.dispatchEvent(new InputEvent("input", {
      bubbles: true, composed: true, data: "# 日本語\n", inputType: "insertCompositionText",
    }))
  })
  await page.waitForTimeout(90)
  assert.equal(await right.getByRole("heading", { name: "Second draft" }).count(), 1)
  assert.equal(await right.getByRole("heading", { name: "日本語" }).count(), 0)
  await rightInput.evaluate(element => {
    element.dispatchEvent(new CompositionEvent("compositionend", {
      bubbles: true, data: "# 日本語\n",
    }))
    element.dispatchEvent(new InputEvent("input", {
      bubbles: true, composed: true, data: "# 日本語\n", inputType: "insertText",
    }))
  })
  await right.getByRole("heading", { name: "日本語" }).waitFor()
  assert.equal(await leftInput.inputValue(), "# Only A\n")
  assert.deepEqual(errors, [])
  console.log("Independent surfaces, mode/selection and composition-to-preview: passed")
} finally {
  await browser?.close()
  await new Promise(resolve => server.close(resolve))
}
