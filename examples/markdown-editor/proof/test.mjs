import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { createServer } from "node:http"
import { join } from "node:path"
import { fileURLToPath } from "node:url"
import { chromium } from "../../../apps/loomark/examples/vanilla/node_modules/playwright/index.mjs"

const dist = fileURLToPath(new URL("./dist/", import.meta.url))
const server = createServer(async (request, response) => {
  const name = request.url === "/" ? "index.html" : request.url?.slice(1)
  if (!["index.html", "index.js", "preview.css", "editor.css"].includes(name)) {
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
  await page.getByRole("button", { name: "Old document edit" }).click()
  assert.equal(await page.locator("#proof-text").inputValue(), "# Opened another document\n")
  assert.equal(await page.getByRole("heading", { name: "Opened another document" }).count(), 1)

  await page.goto(baseURL)
  await page.waitForFunction(() => document.querySelector("#proof-text")?.value === "# First document\n")
  await page.getByRole("button", { name: "Replace instance" }).click()
  await page.waitForFunction(() => document.querySelector("#proof-text")?.value === "# New textarea owner\n")
  assert.notEqual(await page.locator("#proof-text").getAttribute("data-rmd-text-area-owner"), originalOwner)
  const replacementOwner = await page.locator("#proof-text").getAttribute("data-rmd-text-area-owner")
  await page.getByRole("button", { name: "Open document" }).click()
  await page.waitForFunction(() => document.querySelector("#proof-text")?.value === "# Opened another document\n")
  assert.equal(await page.locator("#proof-text").getAttribute("data-rmd-text-area-owner"), replacementOwner)
  await page.getByRole("button", { name: "Split" }).click()
  await page.getByRole("region", { name: "Markdown preview" })
    .getByRole("heading", { name: "Opened another document" }).waitFor()
  await page.locator("#proof-text").evaluate(element => {
    const end = "# Opened another document".length
    element.setSelectionRange(end, end)
  })
  await page.locator("#proof-text").pressSequentially("X")
  await page.getByRole("region", { name: "Markdown preview" })
    .getByRole("heading", { name: "Opened another documentX" }).waitFor()
  await page.getByRole("button", { name: "Reject then accept" }).click()
  await page.waitForFunction(() => document.querySelector("#proof-text")?.value === "# Accepted after rejection\n")
  await page.getByRole("region", { name: "Markdown preview" })
    .getByRole("heading", { name: "Accepted after rejection" }).waitFor()
  await page.getByRole("button", { name: "Start rejected native edit" }).click()
  await page.waitForFunction(() => document.querySelector("#proof-text")?.value === "abc")
  assert.equal(await page.locator("#proof-text").getAttribute("data-rmd-text-area-owner"), replacementOwner)

  await page.goto(baseURL)
  await page.waitForFunction(() => document.querySelector("#proof-text")?.value === "# First document\n")
  await page.getByRole("button", { name: "Unmount" }).click()
  await page.getByText("Unmounted").waitFor()
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
  assert.equal(await page.locator("#proof-text").count(), 0)

  await page.goto(baseURL)
  await page.getByRole("button", { name: "Start rejected native edit" }).click()
  await page.waitForFunction(() => document.querySelector("#proof-text")?.value === "abc")
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
  await page.locator("#proof-text").focus()
  await page.evaluate(() => {
    const textarea = document.querySelector("#proof-text")
    window.__inputEvents = []
    for (const type of ["beforeinput", "input"]) {
      textarea.addEventListener(type, event => window.__inputEvents.push({
        type: event.type,
        inputType: event.inputType,
        trusted: event.isTrusted,
      }), { capture: true })
    }
    textarea.setSelectionRange(0, 1)
    const schedule = window.requestAnimationFrame.bind(window)
    window.__heldFrames = []
    window.requestAnimationFrame = callback => {
      window.__heldFrames.push(callback)
      return window.__heldFrames.length
    }
    window.__releaseFrames = () => {
      window.requestAnimationFrame = schedule
      for (const callback of window.__heldFrames) schedule(callback)
    }
  })
  await page.keyboard.press("Backspace")
  const beforeRestore = await page.evaluate(() => ({
    text: document.querySelector("#proof-text").value,
    frames: window.__heldFrames.length,
  }))
  assert.equal(beforeRestore.text, "abc", "the rejected native deletion must be restored before another input task")
  assert.ok(beforeRestore.frames > 0, "the next render must remain held during the second input")
  await page.locator("#proof-text").evaluate(element => {
    element.setSelectionRange(element.value.length, element.value.length)
  })
  await page.keyboard.type("X")
  const race = await page.evaluate(() => ({
    text: document.querySelector("#proof-text").value,
    events: window.__inputEvents,
  }))
  assert.equal(race.text, "abcX", "the second native input must use the restored baseline")
  assert.deepEqual(race.events.map(event => event.type), [
    "beforeinput", "input", "beforeinput", "input",
  ])
  assert.ok(race.events.every(event => event.trusted), "exercise browser input, not dispatched events")
  assert.equal(race.events[0].inputType, "deleteContentBackward")
  assert.equal(race.events[2].inputType, "insertText")
  await page.evaluate(() => window.__releaseFrames())
  await page.getByText("Rejected first edit").waitFor()
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
  const accepted = await page.locator("p").filter({ hasText: /^Accepted text:/ }).textContent()
  assert.equal(accepted, "Accepted text: abcX")

  // A second native input can also arrive re-entrantly, before Rabbita drains
  // the first Edit message. It must not be accepted from the rejected baseline.
  await page.goto(baseURL)
  await page.getByRole("button", { name: "Start rejected native edit" }).click()
  await page.waitForFunction(() => document.querySelector("#proof-text")?.value === "abc")
  await page.locator("#proof-text").focus()
  await page.evaluate(() => {
    const textarea = document.querySelector("#proof-text")
    textarea.setSelectionRange(0, 1)
    window.__nestedInput = []
    textarea.addEventListener("input", event => {
      window.__nestedInput.push({ trusted: event.isTrusted, inputType: event.inputType })
      if (window.__nestedInput.length !== 1) return
      textarea.setSelectionRange(textarea.value.length, textarea.value.length)
      window.__nestedInserted = document.execCommand("insertText", false, "X")
    })
  })
  await page.keyboard.press("Backspace")
  const nested = await page.evaluate(() => ({
    inserted: window.__nestedInserted,
    events: window.__nestedInput,
  }))
  assert.equal(nested.inserted, true)
  assert.deepEqual(nested.events.map(event => event.inputType), ["deleteContentBackward", "insertText"])
  assert.ok(nested.events.every(event => event.trusted))
  await page.getByText("Rejected first edit").waitFor()
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
  const nestedAccepted = await page.locator("p").filter({ hasText: /^Accepted text:/ }).textContent()
  assert.ok(
    nestedAccepted === "Accepted text: abc" || nestedAccepted === "Accepted text: abcX",
    `a same-task edit must not include rejected content, got ${nestedAccepted}`,
  )

  // Unlike two keyboard calls, these browser edits both fire in one JS task.
  // Rabbita cannot process the first Edit before the second input is emitted.
  await page.goto(baseURL)
  await page.getByRole("button", { name: "Start rejected native edit" }).click()
  await page.waitForFunction(() => document.querySelector("#proof-text")?.value === "abc")
  const queued = await page.evaluate(() => {
    const textarea = document.querySelector("#proof-text")
    const events = []
    for (const type of ["beforeinput", "input"]) {
      textarea.addEventListener(type, event => events.push({
        type: event.type,
        inputType: event.inputType,
        trusted: event.isTrusted,
      }), { capture: true })
    }
    textarea.focus()
    textarea.setSelectionRange(0, 1)
    const deleted = document.execCommand("delete")
    textarea.setSelectionRange(textarea.value.length, textarea.value.length)
    const inserted = document.execCommand("insertText", false, "X")
    return { deleted, inserted, beforeDrain: textarea.value, events }
  })
  assert.equal(queued.deleted, true)
  assert.equal(queued.inserted, true)
  assert.equal(queued.beforeDrain, "bcX")
  // Chromium execCommand emits trusted input events but no beforeinput. This
  // covers the adapter's ReplaceAll fallback, not its beforeinput range path.
  assert.deepEqual(queued.events.map(event => event.type), ["input", "input"])
  assert.deepEqual(queued.events.map(event => event.inputType), ["deleteContentBackward", "insertText"])
  assert.ok(queued.events.every(event => event.trusted))
  await page.getByText("Rejected first edit").waitFor()
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
  const queuedAccepted = await page.locator("p").filter({ hasText: /^Accepted text:/ }).textContent()
  assert.equal(queuedAccepted, "Accepted text: abc", "the edit queued before rejection must be discarded")
  assert.equal(await page.locator("#proof-text").inputValue(), "abc")

  // Without a rejection, both edits from one task must still be admitted.
  await page.goto(baseURL)
  await page.waitForFunction(() => document.querySelector("#proof-text")?.value === "# First document\n")
  const consecutive = await page.evaluate(() => {
    const textarea = document.querySelector("#proof-text")
    textarea.focus()
    textarea.setSelectionRange(textarea.value.length, textarea.value.length)
    return [
      document.execCommand("insertText", false, "X"),
      document.execCommand("insertText", false, "Y"),
    ]
  })
  assert.deepEqual(consecutive, [true, true])
  await page.waitForFunction(() => document.querySelector("p")?.textContent === "Accepted text: # First document\nXY")
  assert.equal(await page.locator("#proof-text").inputValue(), "# First document\nXY")
  assert.deepEqual(errors, [])
  console.log("Restore race, queued edits, document switch, owner replacement, unmount and app-owned mode: passed")
} finally {
  await browser?.close()
  await new Promise(resolve => server.close(resolve))
}
