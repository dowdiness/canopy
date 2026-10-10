import { createHash } from "node:crypto"
import { writeFile } from "node:fs/promises"
import { expect, test, type Locator, type Page, type TestInfo } from "@playwright/test"

const INPUT_BUDGET_MS = 10
const DOCUMENT_BYTES = 1024 * 1024
const WARMUP_ROUNDS = 5
const SAMPLE_ROUNDS = 20
const EDIT_KEYS = ["a", "Backspace", "Control+z"] as const

type NativeSample = {
  inputType: string
  trusted: boolean
  beforeInputMs: number
  betweenEventsMs: number
  inputMs: number
  totalMs: number
  inputToFirstFrameMs: number | null
  inputToSecondFrameMs: number | null
  focusBoundsMs: number
  focusBoundsCalls: number
  focusMutationRecords: number
}

declare global {
  interface Window {
    __loomarkTypingMeasurements: {
      samples: NativeSample[]
      stop: () => void
    }
  }
}

function summarize(values: number[]) {
  if (values.length === 0) throw new Error("No timing samples were recorded")
  const sorted = [...values].sort((left, right) => left - right)
  const middle = Math.floor(sorted.length / 2)
  return {
    samples: sorted.length,
    medianMs: sorted.length % 2 === 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle],
    p95Ms: sorted[Math.ceil(sorted.length * 0.95) - 1],
    maxMs: sorted[sorted.length - 1],
    over10Ms: sorted.filter(value => value > INPUT_BUDGET_MS).length,
  }
}

async function attachMeasurements(info: TestInfo, data: object) {
  const path = info.outputPath("measurements.json")
  await writeFile(path, JSON.stringify(data, null, 2))
  await info.attach("measurements.json", {
    path,
    contentType: "application/json",
  })
}

async function openDocument(page: Page, source: string) {
  await page.goto("/")
  await page.getByLabel("Import Markdown").setInputFiles({
    name: "long-document.md",
    mimeType: "text/markdown",
    buffer: Buffer.from(source),
  })
  const text = page.getByRole("textbox", { name: "Text" })
  await expect(text).toHaveValue(source)
  await page.evaluate(async () => {
    await document.fonts.ready
    await new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve())))
  })
  const release = await page.request.get("/index.js")
  expect(release.ok()).toBe(true)
  return {
    text,
    environment: {
      browser: page.context().browser()!.version(),
      viewport: page.viewportSize(),
      sourceBytes: Buffer.byteLength(source),
      releaseSha256: createHash("sha256").update(await release.body()).digest("hex"),
      userAgent: await page.evaluate(() => navigator.userAgent),
      rendering: await text.evaluate(element => {
        const style = getComputedStyle(element)
        return {
          devicePixelRatio,
          font: style.font,
          lineHeight: style.lineHeight,
          textareaWidth: element.clientWidth,
        }
      }),
    },
  }
}

test("1 MiB synchronous replacement retains the complete 10 ms budget", async ({ page }, info) => {
  const source = `# Equality fixture\n${"x".repeat(DOCUMENT_BYTES)}`
  const { text, environment } = await openDocument(page, source)
  const samples = await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    const original = area.value.at(-1)!
    const replace = (replacement: string) => {
      const started = performance.now()
      const end = area.value.length
      area.setSelectionRange(end - 1, end)
      const selected = performance.now()
      area.dispatchEvent(new InputEvent("beforeinput", {
        bubbles: true, cancelable: true, composed: true,
        data: replacement, inputType: "insertReplacementText",
      }))
      const beforeInputEnded = performance.now()
      area.setRangeText(replacement, end - 1, end, "end")
      const replaced = performance.now()
      area.dispatchEvent(new InputEvent("input", {
        bubbles: true, composed: true,
        data: replacement, inputType: "insertReplacementText",
      }))
      const finished = performance.now()
      return {
        operation: replacement === original ? "revert" : "edit",
        selectionMs: selected - started,
        beforeInputMs: beforeInputEnded - selected,
        textareaMs: replaced - beforeInputEnded,
        inputMs: finished - replaced,
        totalMs: finished - started,
      }
    }
    for (let round = 0; round < 10; round++) { replace("y"); replace(original) }
    return Array.from({ length: 25 }, () => [replace("y"), replace(original)]).flat()
  })
  const summary = {
    selection: summarize(samples.map(sample => sample.selectionMs)),
    beforeInput: summarize(samples.map(sample => sample.beforeInputMs)),
    textarea: summarize(samples.map(sample => sample.textareaMs)),
    input: summarize(samples.map(sample => sample.inputMs)),
    total: summarize(samples.map(sample => sample.totalMs)),
  }
  await attachMeasurements(info, { environment, budgetMs: INPUT_BUDGET_MS, summary, samples })
  await expect(text).toHaveValue(source)
  expect(summary.total.maxMs, JSON.stringify(summary)).toBeLessThanOrEqual(INPUT_BUDGET_MS)
})

async function observeNativeInput(text: Locator) {
  await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    const layout = document.querySelector(".loomark-writing-measure")
    if (!layout) throw new Error("Writing Focus measurement element is not mounted")
    const samples: NativeSample[] = []
    let active: NativeSample | null = null
    let started = 0
    let beforeInputEnded = 0
    let inputStarted = 0
    const listeners = new AbortController()
    const bounds = Element.prototype.getBoundingClientRect
    Element.prototype.getBoundingClientRect = function () {
      const sample = active
      if (!sample || !layout.contains(this)) return bounds.call(this)
      const begin = performance.now()
      try {
        return bounds.call(this)
      } finally {
        sample.focusBoundsMs += performance.now() - begin
        sample.focusBoundsCalls++
      }
    }
    const mutations = new MutationObserver(records => {
      if (active) active.focusMutationRecords += records.length
    })
    mutations.observe(layout, { subtree: true, childList: true, characterData: true, attributes: true })
    window.addEventListener("beforeinput", event => {
      if (event.target !== area) return
      started = performance.now()
      active = {
        inputType: (event as InputEvent).inputType,
        trusted: event.isTrusted,
        beforeInputMs: 0, betweenEventsMs: 0, inputMs: 0, totalMs: 0,
        inputToFirstFrameMs: null, inputToSecondFrameMs: null,
        focusBoundsMs: 0, focusBoundsCalls: 0, focusMutationRecords: 0,
      }
    }, { capture: true, signal: listeners.signal })
    window.addEventListener("beforeinput", event => {
      if (event.target !== area || !active) return
      beforeInputEnded = performance.now()
      active.beforeInputMs = beforeInputEnded - started
    }, { signal: listeners.signal })
    window.addEventListener("input", event => {
      if (event.target !== area || !active) return
      inputStarted = performance.now()
      active.betweenEventsMs = inputStarted - beforeInputEnded
    }, { capture: true, signal: listeners.signal })
    window.addEventListener("input", event => {
      if (event.target !== area || !active) return
      const finished = performance.now()
      const sample = active
      sample.trusted &&= event.isTrusted
      sample.inputMs = finished - inputStarted
      sample.totalMs = finished - started
      samples.push(sample)
      // Frame callbacks are scheduling observations, not paint-completion timestamps.
      requestAnimationFrame(() => {
        sample.inputToFirstFrameMs = performance.now() - finished
        requestAnimationFrame(() => {
          sample.inputToSecondFrameMs = performance.now() - finished
          active = null
        })
      })
    }, { signal: listeners.signal })
    window.__loomarkTypingMeasurements = {
      samples,
      stop: () => {
        listeners.abort()
        mutations.disconnect()
        Element.prototype.getBoundingClientRect = bounds
      },
    }
  })
}

for (const shape of ["giant-paragraph", "many-paragraphs"] as const) {
  for (const position of ["end", "middle"] as const) {
    test(`1 MiB ${shape} native editing at ${position} stays within 10 ms`, async ({ page }, info) => {
      const heading = "# Native input\n\n"
      const paragraph = "A paragraph for long document editing. ".repeat(16) + "\n\n"
      const body = shape === "giant-paragraph"
        ? "x".repeat(DOCUMENT_BYTES - heading.length)
        : paragraph.repeat(Math.ceil(DOCUMENT_BYTES / paragraph.length)).slice(0, DOCUMENT_BYTES - heading.length)
      const source = heading + body
      const { text, environment } = await openDocument(page, source)
      const offset = position === "end" ? source.length : Math.floor(source.length / 2)
      await text.focus()
      await text.evaluate((element, offset) => (element as HTMLTextAreaElement).setSelectionRange(offset, offset), offset)
      await page.evaluate(() => new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))))
      await observeNativeInput(text)
      const samples: NativeSample[] = []
      const errors: string[] = []
      page.on("pageerror", error => errors.push(error.message))
      try {
        for (let round = 0; round < WARMUP_ROUNDS + SAMPLE_ROUNDS; round++) {
          // Keep each deletion/Undo pair in its own native undo group.
          await text.press("ArrowLeft")
          await text.press("ArrowRight")
          for (const key of EDIT_KEYS) {
            await text.press(key)
            const sample = await page.waitForFunction(index => {
              const entry = window.__loomarkTypingMeasurements.samples[index]
              return entry && entry.inputToSecondFrameMs !== null ? entry : false
            }, samples.length)
            samples.push(await sample.jsonValue() as NativeSample)
            await sample.dispose()
          }
        }
      } finally {
        const measured = samples.slice(WARMUP_ROUNDS * EDIT_KEYS.length)
        const summary = measured.length === 0 ? null : {
          beforeInput: summarize(measured.map(sample => sample.beforeInputMs)),
          betweenEvents: summarize(measured.map(sample => sample.betweenEventsMs)),
          input: summarize(measured.map(sample => sample.inputMs)),
          total: summarize(measured.map(sample => sample.totalMs)),
          inputToFirstFrame: summarize(measured.map(sample => sample.inputToFirstFrameMs!)),
          inputToSecondFrame: summarize(measured.map(sample => sample.inputToSecondFrameMs!)),
          focusBounds: summarize(measured.map(sample => sample.focusBoundsMs)),
          focusBoundsCalls: measured.reduce((sum, sample) => sum + sample.focusBoundsCalls, 0),
          focusMutationRecords: measured.reduce((sum, sample) => sum + sample.focusMutationRecords, 0),
        }
        await attachMeasurements(info, {
          environment, shape, position, budgetMs: INPUT_BUDGET_MS,
          warmupSamples: WARMUP_ROUNDS * EDIT_KEYS.length, summary, samples, errors,
        })
        await text.evaluate(() => window.__loomarkTypingMeasurements.stop())
      }
      expect(errors).toEqual([])
      expect(samples).toHaveLength((WARMUP_ROUNDS + SAMPLE_ROUNDS) * EDIT_KEYS.length)
      expect(samples.every(sample => sample.trusted)).toBe(true)
      await expect(text).toHaveValue(source.slice(0, offset) + "a".repeat(WARMUP_ROUNDS + SAMPLE_ROUNDS) + source.slice(offset))
      const total = summarize(samples.slice(WARMUP_ROUNDS * EDIT_KEYS.length).map(sample => sample.totalMs))
      expect(total.maxMs, JSON.stringify(total)).toBeLessThanOrEqual(INPUT_BUDGET_MS)
    })
  }
}
