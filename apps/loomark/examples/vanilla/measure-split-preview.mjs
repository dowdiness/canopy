import { chromium } from "@playwright/test"

const baseUrl = process.env.LOOMARK_STANDALONE_URL ?? "http://127.0.0.1:4317"
const repetitions = Number.parseInt(process.env.LOOMARK_PREVIEW_REPETITIONS ?? "5", 10)
const phaseNames = [
  "loomark-preview-diff",
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

function mutation(source, operation, block) {
  const paragraph = `Paragraph ${block}`
  if (operation === "insert") {
    return {
      before: source,
      after: source.replace(paragraph, `${paragraph} inserted`),
      expected: `${paragraph} inserted`,
    }
  }
  if (operation === "delete") {
    return {
      before: source.replace(paragraph, `${paragraph} removable`),
      after: source,
      expected: `${paragraph} with`,
    }
  }
  return {
    before: source,
    after: source.replace(
      `${paragraph} with **bold**`,
      `${paragraph} with **strong**`,
    ),
    expected: `${paragraph} with strong`,
  }
}

async function dispatchAndWait(page, value) {
  return page.locator("#loomark-text").evaluate(async (element, nextValue) => {
    const textarea = element
    if (textarea.value === nextValue) return
    const before = performance.getEntriesByName("loomark-preview-total").length
    const completed = new Promise((resolve, reject) => {
      const timeout = window.setTimeout(() => {
        observer.disconnect()
        reject(new Error("Preview timing entry did not complete"))
      }, 10_000)
      const observer = new PerformanceObserver(() => {
        if (performance.getEntriesByName("loomark-preview-total").length > before) {
          window.clearTimeout(timeout)
          observer.disconnect()
          resolve(undefined)
        }
      })
      observer.observe({ type: "measure", buffered: true })
    })
    textarea.value = nextValue
    textarea.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      composed: true,
      data: null,
      inputType: "insertText",
    }))
    await completed
  }, value)
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
  const source = fixture()
  await page.getByRole("textbox", { name: "Text" }).fill(source)
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
  for (const scenario of scenarios) {
    const change = mutation(source, scenario.operation, scenario.block)
    for (let repetition = 0; repetition < repetitions; repetition += 1) {
      await dispatchAndWait(page, change.before)
      await page.evaluate(() => performance.clearMeasures())
      await dispatchAndWait(page, change.after)
      const phases = await latestPhases(page)
      const previewText = await page.getByRole("region", { name: "Preview result" })
        .textContent()
      if (!previewText?.includes(change.expected)) {
        throw new Error(`Preview did not converge for ${scenario.operation}/${scenario.position}`)
      }
      samples.push({ ...scenario, repetition, phases })
    }
  }

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
    notes: [
      "Each measured sample follows a completed unmeasured setup transition.",
      "loomark-preview-total is wall time through Rabbita after-render and includes frame scheduling wait.",
      "The sum of diff/parser/semantic/materialize excludes Rabbita propagation, VDOM diff, DOM patch, layout, and paint.",
    ],
    samples,
  }, null, 2)}\n`)
} finally {
  await browser.close()
}
