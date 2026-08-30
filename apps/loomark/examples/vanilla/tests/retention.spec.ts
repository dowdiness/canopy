import { expect, test } from "@playwright/test"

type HeapSample = {
  edits: number
  used: number
}

test("Preview preserves unchanged DOM subtrees", async ({ page }) => {
  const source = "Alpha.\n\nBeta.\n\nGamma.\n"
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill(source)
  await page.getByRole("tab", { name: "Split" }).click()
  const preview = page.getByRole("region", { name: "Markdown preview" })
  await expect(preview).toContainText("Gamma.")

  await preview.evaluate(element => {
    const state = globalThis as typeof globalThis & { __retainedParagraphs?: Element[] }
    state.__retainedParagraphs = Array.from(element.querySelectorAll("p"))
  })
  await text.evaluate((element, position) => {
    const textarea = element as HTMLTextAreaElement
    textarea.setSelectionRange(position, position + 1)
    textarea.dispatchEvent(new InputEvent("beforeinput", {
      bubbles: true,
      cancelable: true,
      composed: true,
      data: "Z",
      inputType: "insertText",
    }))
    textarea.setRangeText("Z", position, position + 1, "end")
    textarea.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      composed: true,
      data: "Z",
      inputType: "insertText",
    }))
  }, source.indexOf("Beta"))
  await expect(preview).toContainText("Zeta.")

  const identity = await preview.evaluate(element => {
    const state = globalThis as typeof globalThis & { __retainedParagraphs?: Element[] }
    const before = state.__retainedParagraphs ?? []
    const after = Array.from(element.querySelectorAll("p"))
    return after.map((node, index) => node === before[index])
  })
  expect(identity[0]).toBe(true)
  expect(identity[2]).toBe(true)
})

test("Preview does not retain complete source generations", async ({ page }) => {
  const blockCount = 2_500
  const source = Array.from(
    { length: blockCount },
    (_, index) => `Paragraph ${String(index).padStart(4, "0")} value A.\n\n`,
  ).join("")

  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill(source)
  await page.getByRole("tab", { name: "Split" }).click()
  const preview = page.getByRole("region", { name: "Markdown preview" })
  await expect(preview).toContainText("Paragraph 0000 value A.")

  const samples = await text.evaluate(async (element, { blockCount }) => {
    const textarea = element as HTMLTextAreaElement
    const runtime = globalThis as typeof globalThis & { gc?: () => void }
    const memory = performance as Performance & {
      memory?: { usedJSHeapSize: number }
    }
    if (runtime.gc === undefined || memory.memory === undefined) {
      throw new Error("explicit Chromium GC or precise memory information unavailable")
    }

    const positions: number[] = []
    let offset = 0
    for (let index = 0; index < blockCount; index += 1) {
      const unit = `Paragraph ${String(index).padStart(4, "0")} value A.\n\n`
      positions.push(offset + unit.indexOf("A."))
      offset += unit.length
    }

    const collect = async (edits: number): Promise<HeapSample> => {
      for (let attempt = 0; attempt < 3; attempt += 1) {
        runtime.gc?.()
        await new Promise<void>(resolve => requestAnimationFrame(() => resolve()))
      }
      return { edits, used: memory.memory?.usedJSHeapSize ?? 0 }
    }

    const samples: HeapSample[] = [await collect(0)]
    for (let edit = 1; edit <= 5_000; edit += 1) {
      const position = positions[(edit - 1) % positions.length]
      const replacement = textarea.value[position] === "A" ? "B" : "A"
      textarea.setSelectionRange(position, position + 1)
      textarea.dispatchEvent(new InputEvent("beforeinput", {
        bubbles: true,
        cancelable: true,
        composed: true,
        data: replacement,
        inputType: "insertText",
      }))
      textarea.setRangeText(replacement, position, position + 1, "end")
      textarea.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        composed: true,
        data: replacement,
        inputType: "insertText",
      }))
      await new Promise<void>(resolve => requestAnimationFrame(() => resolve()))
      if (edit === 1_000 || edit === 5_000) {
        samples.push(await collect(edit))
      }
    }

    const finalPosition = positions[positions.length - 1]
    textarea.setSelectionRange(finalPosition, finalPosition + 1)
    textarea.dispatchEvent(new InputEvent("beforeinput", {
      bubbles: true,
      cancelable: true,
      composed: true,
      data: "B",
      inputType: "insertText",
    }))
    textarea.setRangeText("B", finalPosition, finalPosition + 1, "end")
    textarea.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      composed: true,
      data: "B",
      inputType: "insertText",
    }))
    return samples
  }, { blockCount })
  await expect(preview).toContainText("Paragraph 2499 value B.")

  const [initial, afterThousand, afterFiveThousand] = samples
  const mib = (bytes: number) => bytes / (1024 * 1024)
  console.log(
    `Preview explicit-GC heap: initial=${mib(initial.used).toFixed(2)} MiB, ` +
    `1000=${mib(afterThousand.used).toFixed(2)} MiB, ` +
    `5000=${mib(afterFiveThousand.used).toFixed(2)} MiB`,
  )
  expect(afterFiveThousand.used - initial.used).toBeLessThan(96 * 1024 * 1024)
  expect(afterFiveThousand.used - afterThousand.used).toBeLessThan(48 * 1024 * 1024)
})
