import { chromium } from "@playwright/test"

const baseUrl = process.env.LOOMARK_STANDALONE_URL ?? "http://127.0.0.1:4317"
const repetitions = Number.parseInt(process.env.LOOMARK_PREVIEW_REPETITIONS ?? "5", 10)
const phaseNames = [
  "loomark-preview-parser-edit",
  "loomark-preview-parser",
  "loomark-preview-semantic",
  "loomark-preview-materialize",
  "loomark-preview-total",
]

function fixture(unitCount = 250) {
  return Array.from({ length: unitCount }, (_, index) => (
    `## Heading ${index}\n\n`
    + `Paragraph ${index} with **bold**, `
    + `[link](https://example.com/${index}), and 日本語 😀.\n`
  )).join("\n")
}

async function installStoredSource(page, source) {
  await page.evaluate(async text => {
    const open = indexedDB.open("loomark", 1)
    const database = await new Promise((resolve, reject) => {
      open.onerror = () => reject(open.error)
      open.onsuccess = () => resolve(open.result)
    })
    const existing = await new Promise((resolve, reject) => {
      const request = database.transaction("documents", "readonly")
        .objectStore("documents").get("active")
      request.onerror = () => reject(request.error)
      request.onsuccess = () => resolve(request.result)
    })
    const documentId = typeof existing === "string"
      ? JSON.parse(existing).document_id
      : crypto.randomUUID()
    await new Promise((resolve, reject) => {
      const transaction = database.transaction("documents", "readwrite")
      transaction.onerror = () => reject(transaction.error)
      transaction.oncomplete = () => resolve()
      transaction.objectStore("documents").put(JSON.stringify({
        document_id: documentId,
        text,
      }), "active")
    })
    database.close()
  }, source)
  await page.reload()
}

function scenario(source, operation, block) {
  const paragraph = `Paragraph ${block}`
  const paragraphStart = source.indexOf(paragraph)
  if (paragraphStart < 0) throw new Error(`missing fixture paragraph ${block}`)
  if (operation === "insert") {
    const start = paragraphStart + paragraph.length
    const inserted = " inserted"
    return {
      start,
      end: start,
      inserted,
      expected: `${paragraph} inserted`,
      reverseStart: start,
      reverseEnd: start + inserted.length,
      reverseInserted: "",
    }
  }
  const original = operation === "delete" ? "with" : "bold"
  const inserted = operation === "delete" ? "" : "strong"
  const start = source.indexOf(original, paragraphStart)
  return {
    start,
    end: start + original.length,
    inserted,
    expected: operation === "delete" ? `${paragraph}  bold` : `${paragraph} with strong`,
    reverseStart: start,
    reverseEnd: start + inserted.length,
    reverseInserted: original,
  }
}

async function performNativeEdit(page, edit) {
  const textarea = page.locator("#loomark-text")
  await textarea.focus()
  await textarea.evaluate((element, range) => {
    element.setSelectionRange(range.start, range.end)
  }, { start: edit.start, end: edit.end })
  const before = await page.evaluate(() => (
    performance.getEntriesByName("loomark-preview-total").length
  ))
  if (edit.inserted === "") {
    await page.keyboard.press("Backspace")
  } else {
    await page.keyboard.insertText(edit.inserted)
  }
  await page.waitForFunction(count => (
    performance.getEntriesByName("loomark-preview-total").length > count
  ), before)
}

async function latestPhases(page) {
  return page.evaluate(names => Object.fromEntries(names.map(name => {
    const entries = performance.getEntriesByName(name)
    return [name, entries.at(-1)?.duration ?? null]
  })), phaseNames)
}

const browser = await chromium.launch({ headless: true })
try {
  const page = await browser.newPage()
  await page.goto(baseUrl)
  await page.getByRole("textbox", { name: "Text" }).waitFor()
  const source = fixture()
  await installStoredSource(page, source)
  await page.getByRole("textbox", { name: "Text" }).waitFor()
  await page.getByRole("button", { name: "Split" }).click()
  await page.getByRole("region", { name: "Preview result" })
    .getByRole("heading", { name: "Heading 249" })
    .waitFor()

  const scenarios = [
    ["beginning", 0],
    ["middle", 125],
    ["end", 249],
  ].flatMap(([position, block]) => (
    ["insert", "delete", "replace"].map(operation => ({
      position,
      block,
      operation,
    }))
  ))
  const samples = []
  for (const item of scenarios) {
    const edit = scenario(source, item.operation, item.block)
    for (let repetition = 0; repetition < repetitions; repetition += 1) {
      await page.evaluate(() => performance.clearMeasures())
      await performNativeEdit(page, edit)
      const phases = await latestPhases(page)
      const previewText = await page.getByRole("region", { name: "Preview result" })
        .textContent()
      if (!previewText?.includes(edit.expected)) {
        throw new Error(`Preview did not converge for ${item.operation}/${item.position}`)
      }
      samples.push({ ...item, repetition, phases })
      await performNativeEdit(page, {
        start: edit.reverseStart,
        end: edit.reverseEnd,
        inserted: edit.reverseInserted,
      })
    }
  }

  const metrics = await page.locator(".loomark-input-metrics").textContent()
  process.stdout.write(`${JSON.stringify({
    measuredAt: new Date().toISOString(),
    browser: await browser.version(),
    node: process.version,
    fixture: {
      units: 250,
      utf16CodeUnits: source.length,
      lines: source.split("\n").length,
      approximateMarkdownBlocks: 500,
    },
    repetitions,
    metrics,
    notes: [
      "The practical corpus is installed through browser storage before measurement.",
      "Every measured operation and its unmeasured inverse use native beforeinput/input events.",
      "No complete textarea value is read and no complete-source diff is called on the measured path.",
      "loomark-preview-total is after-render wall time and includes frame scheduling wait.",
    ],
    samples,
  }, null, 2)}\n`)
} finally {
  await browser.close()
}
