import { expect, test, type Locator, type Page } from "@playwright/test"

const documentText = "# Heading\n\nFirst thought\n\nSecond thought\n\nThird thought"

async function dimmingAtLine(page: Page, line: number) {
  return page.getByRole("textbox", { name: "Text" }).evaluate((element, line) => {
    const textarea = element as HTMLTextAreaElement
    const bounds = textarea.getBoundingClientRect()
    const style = getComputedStyle(textarea)
    const x = bounds.left + Number.parseFloat(style.paddingLeft) + 4
    const y = bounds.top + Number.parseFloat(style.paddingTop)
      + (line + 0.5) * Number.parseFloat(style.lineHeight) - textarea.scrollTop
    return [...document.querySelectorAll<HTMLElement>(".loomark-writing-shade")]
      .reduce((opacity, shade) => {
        const range = shade.getBoundingClientRect()
        const coversText = range.left <= x && x < range.right && range.top <= y && y < range.bottom
        return coversText ? 1 - (1 - opacity) * (1 - Number(getComputedStyle(shade).opacity)) : opacity
      }, 0)
  }, line)
}

test("typing intent dims other writing groups and blur restores reading", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill(documentText)
  await text.blur()
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0)
  await text.press("Control+Home")
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0.5)
  expect(await dimmingAtLine(page, 0)).toBe(0)
  await page.getByRole("button", { name: "More actions", exact: true }).click()
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0)
  await expect(text).toHaveValue(documentText)
})

test("responsive reflow preserves the active writing paragraph", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill(documentText)
  await text.press("Control+Home")
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0.5)
  for (const width of [390, 1280]) {
    await page.setViewportSize({ width, height: 844 })
    await page.evaluate(() => new Promise<void>(resolve =>
      requestAnimationFrame(() => requestAnimationFrame(() => resolve()))))
    await expect.poll(() => dimmingAtLine(page, 2)).toBe(0.5)
    expect(await dimmingAtLine(page, 0)).toBe(0)
  }
})

test("a selection keeps every selected paragraph readable", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill(documentText)
  await text.press("Control+Home")
  await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    area.setSelectionRange(area.value.indexOf("First"), area.value.indexOf("Third"))
  })
  await expect.poll(() => dimmingAtLine(page, 0)).toBe(0.5)
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0)
  await expect.poll(() => dimmingAtLine(page, 4)).toBe(0)
  await expect.poll(() => dimmingAtLine(page, 6)).toBe(0.5)
})

test("reduced motion settles immediately and forced colors removes dimming", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" })
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill(documentText)
  await text.press("Control+Home")
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0.5)
  expect(await page.locator(".loomark-writing-dimming").evaluate(element =>
    element.getAnimations({ subtree: true }).length)).toBe(0)
  await page.emulateMedia({ forcedColors: "active" })
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0)
  await page.emulateMedia({ forcedColors: "none" })
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0.5)
})

test("a retired document cannot change the current writing focus", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill(documentText)
  await text.press("Control+Home")
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0.5)
  const retired = await text.elementHandle()
  await page.getByRole("button", { name: "New document", exact: true }).first().click()
  await expect(text).toHaveValue("")
  await text.fill(documentText)
  await text.press("Control+Home")
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0.5)
  await retired!.evaluate(element => {
    const area = element as HTMLTextAreaElement
    area.setSelectionRange(area.value.indexOf("First"), area.value.indexOf("First"))
    area.dispatchEvent(new Event("input"))
    area.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown" }))
  })
  await text.press("ArrowRight")
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0.5)
  await expect.poll(() => dimmingAtLine(page, 0)).toBe(0)
  await expect(text).toHaveValue(documentText)
})

test("deleting across paragraphs preserves the browser's native undo transactions", async ({ page }) => {
  const deletionCount = 16
  const deleteAcrossParagraphs = async (text: Locator) => {
    await text.press("Control+End")
    for (let index = 0; index < deletionCount; index++) {
      await text.press("Backspace", { delay: 10 })
    }
    await expect(text).toHaveValue(documentText.slice(0, -deletionCount))
  }

  await page.setContent('<textarea aria-label="Text"></textarea>')
  const nativeText = page.getByRole("textbox", { name: "Text" })
  await nativeText.fill(documentText)
  await deleteAcrossParagraphs(nativeText)
  const nativeUndoStates: string[] = []
  for (let index = 0; index < deletionCount; index++) {
    await nativeText.press("Control+Z")
    const restored = await nativeText.inputValue()
    nativeUndoStates.push(restored)
    if (restored === documentText) break
  }
  await expect(nativeText).toHaveValue(documentText)

  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill(documentText)
  await expect.poll(() => dimmingAtLine(page, 0)).toBe(0.5)
  await deleteAcrossParagraphs(text)
  for (const expected of nativeUndoStates) {
    await text.press("Control+Z")
    await expect(text).toHaveValue(expected)
  }
})

test("whole-document selection clears dimming and restores paragraph focus after resizing", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill(documentText)
  await text.press("Control+Home")
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0.5)
  await text.press("Control+A")
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0)
  await page.setViewportSize({ width: 390, height: 844 })
  await text.press("Control+End")
  await expect.poll(() => dimmingAtLine(page, 0)).toBe(0.5)
  expect(await dimmingAtLine(page, 6)).toBe(0)
  await expect(text).toHaveValue(documentText)
})

test("editing a single paragraph then adding another focuses the current text", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("First")
  await text.pressSequentially(" revised", { delay: 20 })
  await text.press("Enter")
  await text.press("Enter")
  await text.pressSequentially("Second", { delay: 20 })
  await expect(text).toHaveValue("First revised\n\nSecond")
  await expect.poll(() => dimmingAtLine(page, 0)).toBe(0.5)
  expect(await dimmingAtLine(page, 2)).toBe(0)
  await text.press("Control+Home")
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0.5)
  expect(await dimmingAtLine(page, 0)).toBe(0)
})

test("deferred tail edits preserve focus after paragraph insertion deletion and undo", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Heading\n\nFirst\n\nLast")
  await text.press("Control+End")
  await text.pressSequentially(" revised")
  await text.press("Enter")
  await text.press("Enter")
  await text.pressSequentially("New")
  const expanded = "# Heading\n\nFirst\n\nLast revised\n\nNew"
  await expect(text).toHaveValue(expanded)
  await expect.poll(() => dimmingAtLine(page, 4)).toBe(0.5)
  expect(await dimmingAtLine(page, 6)).toBe(0)
  await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    area.setSelectionRange(area.value.indexOf("First"), area.value.indexOf("Last"))
  })
  await text.press("Backspace")
  await expect(text).toHaveValue("# Heading\n\nLast revised\n\nNew")
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0)
  expect(await dimmingAtLine(page, 4)).toBe(0.5)
  await text.press("Control+Z")
  await expect(text).toHaveValue(expanded)
  await expect.poll(() => dimmingAtLine(page, 4)).toBe(0.5)
  expect(await dimmingAtLine(page, 2)).toBe(0)
})

test("layout changes relocate focus after unmeasured tail edits", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Heading\n\nFirst\n\nLast")
  await text.press("Control+End")
  await text.pressSequentially(" revised")
  await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    area.style.fontSize = "12px"
    area.style.lineHeight = "1.5"
  })
  await page.setViewportSize({ width: 390, height: 844 })
  await expect.poll(() => dimmingAtLine(page, 4)).toBe(0)
  expect(await dimmingAtLine(page, 2)).toBe(0.5)
  await expect(text).toHaveValue("# Heading\n\nFirst\n\nLast revised")
})

test("restoring text and caret before paint dims the following paragraph again", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  const original = "Before\n\nWriting\n\nAfter"
  await text.fill(original)
  await text.press("Control+Home")
  await expect.poll(() => dimmingAtLine(page, 4)).toBe(0.5)
  await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    area.setSelectionRange(8, 8)
  })
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0)
  await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    area.setSelectionRange(15, area.value.length)
  })
  await text.press("Backspace")
  await expect(text).toHaveValue("Before\n\nWriting")
  await expect.poll(() => dimmingAtLine(page, 0)).toBe(0.5)
  await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    area.addEventListener("input", () => area.setSelectionRange(8, 8), { once: true })
  })
  await text.press("Control+Z")
  await expect(text).toHaveValue(original)
  await expect.poll(() => dimmingAtLine(page, 4)).toBe(0.5)
  expect(await dimmingAtLine(page, 2)).toBe(0)
})

test("font changes during whole-text focus invalidate earlier line measurements", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("Before\n\nWriting\n\nAfter")
  await text.evaluate(element => (element as HTMLTextAreaElement).setSelectionRange(8, 8))
  await expect.poll(() => dimmingAtLine(page, 0)).toBe(0.5)
  expect(await dimmingAtLine(page, 2)).toBe(0)
  await text.press("Control+A")
  await expect.poll(() => dimmingAtLine(page, 0)).toBe(0)
  await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    area.style.fontSize = "26px"
    area.style.lineHeight = "1.5"
    document.fonts.dispatchEvent(new Event("loadingdone"))
  })
  await page.evaluate(() => new Promise<void>(resolve => {
    requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
  }))
  await text.evaluate(element => (element as HTMLTextAreaElement).setSelectionRange(8, 8))
  await expect.poll(() => dimmingAtLine(page, 0)).toBe(0.5)
  expect(await dimmingAtLine(page, 2)).toBe(0)
  expect(await dimmingAtLine(page, 4)).toBe(0.5)
})
