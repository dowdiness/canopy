import { expect, test, type Locator, type Page } from "@playwright/test"

const documentText = "# Heading\n\nFirst thought\n\nSecond thought\n\nThird thought"

test.beforeEach(async ({ page }) => {
  await page.route("**/api/account", route => route.fulfill({ status: 401 }))
})

async function openFocusMode(page: Page) {
  await page.goto("/")
  await page.getByRole("button", { name: "Focus Mode", exact: true }).click()
  await expect(page.locator("#loomark-focus-toggle")).toHaveAttribute("aria-pressed", "true")
  // Toggling must not focus the textarea, which would summon a mobile keyboard.
  await expect(page.getByRole("textbox", { name: "Text" })).not.toBeFocused()
}

async function dimmingAtLines(page: Page, lines: number[]) {
  return page.getByRole("textbox", { name: "Text" }).evaluate((element, lines) => {
    const textarea = element as HTMLTextAreaElement
    const bounds = textarea.getBoundingClientRect()
    const style = getComputedStyle(textarea)
    const x = bounds.left + Number.parseFloat(style.paddingLeft) + 4
    const shades = [...document.querySelectorAll<HTMLElement>(".loomark-writing-shade")]
      .map(shade => ({
        bounds: shade.getBoundingClientRect(),
        opacity: Number(getComputedStyle(shade).opacity),
      }))
    return lines.map(line => {
      const y = bounds.top + Number.parseFloat(style.paddingTop)
        + (line + 0.5) * Number.parseFloat(style.lineHeight) - textarea.scrollTop
      return shades.reduce((opacity, shade) => {
        const range = shade.bounds
        const coversText = range.left <= x && x < range.right && range.top <= y && y < range.bottom
        return coversText ? 1 - (1 - opacity) * (1 - shade.opacity) : opacity
      }, 0)
    })
  }, lines)
}

async function dimmingAtLine(page: Page, line: number) {
  const [opacity] = await dimmingAtLines(page, [line])
  return opacity
}

for (const mode of ["Text", "Preview"] as const) {
  test(`Focus Mode exit restores sidebar keyboard focus after resizing in ${mode}`, async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 })
    await page.goto("/")
    await page.getByRole("textbox", { name: "Text" }).fill(documentText)
    await page.getByRole("tab", { name: mode, exact: true }).click()
    const trigger = page.getByRole("button", { name: "Toggle documents" })
    if (await trigger.getAttribute("aria-expanded") !== "true") await trigger.click()
    await page.locator("#loomark-focus-toggle").click()
    await page.setViewportSize({ width: 390, height: 844 })
    await page.keyboard.press("Escape")
    await expect(page.locator("#loomark-focus-toggle")).toHaveAttribute("aria-pressed", "false")
    const sidebar = page.getByRole("complementary", { name: "Documents" })
    await expect(sidebar).toBeVisible()
    await expect.poll(() => sidebar.evaluate(element => element.contains(document.activeElement))).toBe(true)
    await page.keyboard.press("Tab")
    await expect.poll(() => sidebar.evaluate(element => element.contains(document.activeElement))).toBe(true)
  })
}

for (const mode of ["Text", "Split", "Preview"]) {
  test(`Focus Mode is opt-in and preserves ${mode} without losing selection or undo`, async ({ page }) => {
    await page.goto("/")
    const text = page.locator("#loomark-text")
    const toggle = page.locator("#loomark-focus-toggle")
    await text.fill(documentText)
    await text.press("Control+Home")
    await expect.poll(() => dimmingAtLines(page, [0, 2, 4])).toEqual([0, 0, 0])
    await text.press("Control+End")
    await text.pressSequentially(" revised")
    await text.evaluate(element => (element as HTMLTextAreaElement).setSelectionRange(12, 17))
    await page.getByRole("tab", { name: mode, exact: true }).click()
    if (mode === "Split") {
      await page.getByRole("button", { name: "Toggle documents" }).click()
    }
    await toggle.focus()
    await toggle.press("Enter")
    await expect(toggle).toHaveAttribute("aria-pressed", "true")
    await expect(toggle).toBeFocused()
    await expect(page.locator('[role="tab"][aria-selected="true"]')).toHaveAttribute("aria-label", mode)
    await expect(text).toBeVisible({ visible: mode !== "Preview" })
    expect(await text.evaluate(element => {
      const area = element as HTMLTextAreaElement
      return [area.selectionStart, area.selectionEnd]
    })).toEqual([12, 17])
    await expect(page.getByRole("button", { name: "More actions" })).toBeHidden()
    await expect(page.getByRole("button", { name: "Toggle documents" })).toBeHidden()
    await expect(page.getByRole("tablist", { name: "Editor mode" })).toBeHidden()
    await expect(page.locator("#loomark-preview-scroll")).toBeVisible({ visible: mode !== "Text" })
    await page.keyboard.press("Escape")
    await expect(toggle).toHaveAttribute("aria-pressed", "false")
    await expect(page.getByRole("tab", { name: mode, exact: true })).toHaveAttribute("aria-selected", "true")
    if (mode === "Split") {
      await expect(page.getByRole("button", { name: "Toggle documents" })).toHaveAttribute("aria-expanded", "true")
    }
    await page.getByRole("tab", { name: "Text", exact: true }).click()
    await expect(text).toBeVisible()
    await text.press("Control+Z")
    await expect(text).toHaveValue(documentText)
    await expect.poll(() => dimmingAtLine(page, 2)).toBe(0)
    await toggle.click()
    await page.reload()
    await expect(toggle).toHaveAttribute("aria-pressed", "false")
  })
}

for (const reducedMotion of ["no-preference", "reduce"] as const) {
  test(`rapid Focus Mode reversals preserve keyboard editing with motion ${reducedMotion}`, async ({ page }) => {
    await page.emulateMedia({ reducedMotion })
    await page.goto("/")
    const text = page.getByRole("textbox", { name: "Text" })
    const toggle = page.locator("#loomark-focus-toggle")
    await text.fill(documentText)
    // Control the animation clock so the reversal happens before the fade ends.
    const midpoint = await toggle.evaluate(async element => {
      (element as HTMLButtonElement).click()
      await new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve())))
      const toolbar = document.querySelector<HTMLElement>(".loomark-topbar")!
      const animations = toolbar.getAnimations()
      for (const animation of animations) {
        animation.pause()
        animation.currentTime = 60
      }
      return { opacity: Number(getComputedStyle(toolbar).opacity), inert: toolbar.inert, animations: animations.length }
    })
    expect(midpoint.inert).toBe(true)
    if (reducedMotion === "reduce") {
      expect(midpoint.animations).toBe(0)
    } else {
      expect(midpoint.opacity).toBeGreaterThan(0)
      expect(midpoint.opacity).toBeLessThan(1)
    }
    await toggle.evaluate(element => (element as HTMLButtonElement).click())
    await expect(toggle).toHaveAttribute("aria-pressed", "false")
    await expect.poll(() => page.locator(".loomark-topbar").evaluate(element => getComputedStyle(element).opacity)).toBe("1")
    for (const pressed of ["true", "false", "true"]) {
      await toggle.click()
      await expect(toggle).toHaveAttribute("aria-pressed", pressed)
    }
    await expect(toggle).toBeFocused()
    await text.press("Tab")
    await expect(toggle).toBeFocused()
    await toggle.press("Escape")
    await expect(toggle).toHaveAttribute("aria-pressed", "false")
    await expect(toggle).toBeFocused()
    await expect(text).toHaveValue(documentText)
    await expect(page.getByRole("button", { name: "More actions" })).toBeVisible()
  })
}

test("Focus Mode toggle hides with a simulated mobile keyboard like the view controls", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await openFocusMode(page)
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill(documentText)
  // Exercise visual-viewport occlusion, not an actual OS keyboard.
  const keyboard = (height: number, offsetTop: number) => page.evaluate(({ height, offsetTop }) => {
    for (const [key, value] of Object.entries({ height, offsetTop })) {
      Object.defineProperty(window.visualViewport!, key, { configurable: true, get: () => value })
    }
    window.visualViewport!.dispatchEvent(new Event("resize"))
  }, { height, offsetTop })
  const toggle = page.locator("#loomark-focus-toggle")
  await keyboard(360, 24)
  await expect(toggle).toBeHidden()
  await expect(page.locator(".loomark-footer")).toBeHidden()
  // No on-screen keyboard can be open without textarea focus, so a mistaken
  // detection must not remove the only Focus Mode exit.
  await text.blur()
  await expect(toggle).toBeVisible()
  await keyboard(844, 0)
  await expect(toggle).toBeVisible()
  await toggle.click()
  await expect(page.getByRole("button", { name: "Focus Mode", exact: true })).toBeVisible()
  await expect(text).not.toBeFocused()
  await expect(text).toHaveValue(documentText)
})

test("typing intent dims other writing groups and blur restores reading", async ({ page }) => {
  await openFocusMode(page)
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill(documentText)
  // Verify active dimming before testing its removal, not the initial empty layer.
  await expect.poll(() => dimmingAtLine(page, 0)).toBe(0.5)
  await text.blur()
  await expect(text).not.toBeFocused()
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0)
  await expect(text).not.toBeFocused()
  await text.press("Control+Home")
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0.5)
  expect(await dimmingAtLine(page, 0)).toBe(0)
  await page.getByRole("button", { name: "Exit Focus Mode", exact: true }).focus()
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0)
  await expect(text).toHaveValue(documentText)
})

test("wrapped paragraphs dim along the textarea's own line breaks", async ({ page }) => {
  await openFocusMode(page)
  const text = page.getByRole("textbox", { name: "Text" })
  const paragraph = "Quiet tools leave room for long thoughts that wrap. ".repeat(14).trim()
  await text.fill(paragraph)
  await page.evaluate(() => document.fonts.ready)
  // Count wrapped lines from the textarea itself, independently of the dimming layer.
  const wrapped = await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    const style = getComputedStyle(area)
    area.style.height = "0px"
    const content = area.scrollHeight - Number.parseFloat(style.paddingTop)
      - Number.parseFloat(style.paddingBottom)
    area.style.height = ""
    return Math.round(content / Number.parseFloat(style.lineHeight))
  })
  expect(wrapped).toBeGreaterThan(4)
  await text.fill(`${paragraph}\n\nAfter`)
  await text.press("Control+End")
  await expect.poll(() => dimmingAtLine(page, wrapped - 1)).toBe(0.5)
  expect(await dimmingAtLine(page, wrapped + 1)).toBe(0)
})

test("focus moves between quoted paragraphs separated by a quote-only line", async ({ page }) => {
  await openFocusMode(page)
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("> first\n>\n> second")
  await text.press("Control+Home")
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0.5)
  expect(await dimmingAtLine(page, 0)).toBe(0)
  await text.press("ArrowDown")
  await text.press("ArrowDown")
  await expect.poll(() => dimmingAtLine(page, 0)).toBe(0.5)
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0)
})

test("responsive reflow preserves the active writing paragraph", async ({ page }) => {
  await openFocusMode(page)
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
  await openFocusMode(page)
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
  await openFocusMode(page)
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill(documentText)
  await text.press("Control+Home")
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0.5)
  expect(await page.locator(".loomark-writing-shade").evaluateAll(shades =>
    shades.flatMap(shade => shade.getAnimations()).length)).toBe(0)
  await text.press("ArrowRight")
  await expect(page.locator(".loomark-writing-caret")).toHaveCSS("transition-property", "opacity")
  await page.emulateMedia({ forcedColors: "active" })
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0)
  await page.emulateMedia({ forcedColors: "none" })
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0.5)
})

// The caret centres on its glyph box, which the font may place up to a pixel
// off the line box centre.
async function caretOffset(page: Page, line: number) {
  return page.getByRole("textbox", { name: "Text" }).evaluate((element, line) => {
    const textarea = element as HTMLTextAreaElement
    const bounds = textarea.getBoundingClientRect()
    const style = getComputedStyle(textarea)
    const caret = document.querySelector(".loomark-writing-caret")!.getBoundingClientRect()
    const x = bounds.left + Number.parseFloat(style.paddingLeft)
    const y = bounds.top + Number.parseFloat(style.paddingTop)
      + (line + 0.5) * Number.parseFloat(style.lineHeight) - textarea.scrollTop
    return Math.max(Math.abs(caret.left - x), Math.abs(caret.top + caret.height / 2 - y))
  }, line)
}

test("the drawn caret replaces the native caret only while it is shown", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  const caret = page.locator(".loomark-writing-caret")
  await text.fill(documentText)
  await text.press("Control+Home")
  await expect.poll(() => caretOffset(page, 0)).toBeLessThan(1)
  await expect(text).toHaveCSS("caret-color", "rgba(0, 0, 0, 0)")
  await text.press("ArrowDown")
  await text.press("ArrowDown")
  await expect.poll(() => caretOffset(page, 2)).toBeLessThan(1)
  await expect(caret).toHaveCSS("transition-property", "opacity, transform")
  await text.press("x")
  await expect(caret).toHaveCSS("transition-property", "opacity")
  await text.press("Backspace")
  await text.press("Shift+ArrowRight")
  await expect(caret).toBeHidden()
  await text.press("ArrowRight")
  await expect(caret).toBeVisible()
  // The browser reports an IME composition caret as a collapsed selection and a
  // converted clause as a range, so composition needs no separate state.
  const ime = await page.context().newCDPSession(page)
  const caretLeft = () => caret.evaluate(element => element.getBoundingClientRect().left)
  const beforeComposition = await caretLeft()
  await ime.send("Input.imeSetComposition", { text: "かん", selectionStart: 2, selectionEnd: 2 })
  await expect.poll(caretLeft).toBeGreaterThan(beforeComposition + 20)
  await ime.send("Input.imeSetComposition", { text: "漢字", selectionStart: 0, selectionEnd: 2 })
  await expect(caret).toBeHidden()
  await expect(text).not.toHaveCSS("caret-color", "rgba(0, 0, 0, 0)")
  await ime.send("Input.insertText", { text: "漢字" })
  await expect(caret).toBeVisible()
  await text.blur()
  await expect(caret).toBeHidden()
})

test("a retired document cannot change the current writing focus", async ({ page }) => {
  await openFocusMode(page)
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill(documentText)
  await text.press("Control+Home")
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0.5)
  const retired = await text.elementHandle()
  await page.getByRole("button", { name: "Exit Focus Mode", exact: true }).click()
  await page.getByRole("button", { name: "New document", exact: true }).first().click()
  await expect(text).toHaveValue("")
  await page.getByRole("button", { name: "Focus Mode", exact: true }).click()
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

  await openFocusMode(page)
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
  await openFocusMode(page)
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
  await openFocusMode(page)
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
  await openFocusMode(page)
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
  await openFocusMode(page)
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
  await expect.poll(() => dimmingAtLines(page, [0, 2, 4])).toEqual([0.5, 0.5, 0])
  await expect(text).toHaveValue("# Heading\n\nFirst\n\nLast revised")
})

test("restoring text and caret before paint dims the following paragraph again", async ({ page }) => {
  await openFocusMode(page)
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
  await openFocusMode(page)
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("Before\n\nWriting\n\nAfter")
  await text.evaluate(element => (element as HTMLTextAreaElement).setSelectionRange(8, 8))
  await expect.poll(() => dimmingAtLines(page, [0, 2, 4])).toEqual([0.5, 0, 0.5])
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

test("a reader's line-height override keeps dimming on the writing group", async ({ page }) => {
  const failures: string[] = []
  page.on("console", message => {
    if (message.type() === "error" && message.text().includes("writing focus")) failures.push(message.text())
  })
  await openFocusMode(page)
  const text = page.getByRole("textbox", { name: "Text" })
  // Paragraph 9 sits on line 16, far enough down that old and new line
  // heights disagree by more than a line.
  await text.fill(Array.from({ length: 12 }, (_, i) => `Paragraph ${i + 1}`).join("\n\n"))
  await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    const end = area.value.indexOf("Paragraph 9") + "Paragraph 9".length
    area.setSelectionRange(end, end)
  })
  await expect.poll(() => dimmingAtLines(page, [14, 16, 18])).toEqual([0.5, 0, 0.5])
  // Text-spacing tools change line height without resizing the textarea.
  await page.addStyleTag({ content: "* { line-height:1.5 !important }" })
  await text.pressSequentially(" more")
  await expect.poll(() => dimmingAtLines(page, [14, 16, 18])).toEqual([0.5, 0, 0.5])
  expect(failures).toEqual([])
})

test("Split reflow updates the unchanged writing selection after reading-position measurement", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("\n\nBefore\n\nWriting\n\nAfter\n\n")
  await page.getByRole("tab", { name: "Split" }).click()
  await page.getByRole("button", { name: "Focus Mode", exact: true }).click()
  await text.focus()
  await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    const start = area.value.indexOf("Writing")
    area.setSelectionRange(start, start)
    area.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true }))
  })
  await expect.poll(() => dimmingAtLines(page, [2, 4, 6])).toEqual([0.5, 0, 0.5])
  await expect.poll(() => caretOffset(page, 4)).toBeLessThan(1)
  await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    area.style.lineHeight = "46px"
    // Split measures synchronously on scroll; the writing layer draws on the
    // next frame, with unchanged text and selection. Neither cache may go stale.
    area.dispatchEvent(new Event("scroll"))
  })
  await expect.poll(() => dimmingAtLines(page, [2, 4, 6])).toEqual([0.5, 0, 0.5])
  await expect.poll(() => caretOffset(page, 4)).toBeLessThan(1)
  await expect(text).toHaveValue("\n\nBefore\n\nWriting\n\nAfter\n\n")
})

test("a layout notification during measurement cannot commit geometry into the new layout", async ({ page }) => {
  await openFocusMode(page)
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("Before\n\nWriting\n\nAfter")
  await expect.poll(() => dimmingAtLine(page, 2)).toBe(0.5)
  await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    const mirror = document.querySelector<HTMLElement>(".loomark-writing-measure")!
    const measure = mirror.getBoundingClientRect
    mirror.getBoundingClientRect = function () {
      delete (mirror as Partial<HTMLElement>).getBoundingClientRect
      area.style.lineHeight = "60px"
      document.fonts.dispatchEvent(new Event("loadingdone"))
      return measure.call(mirror)
    }
    area.setSelectionRange(8, 8)
  })
  await expect.poll(() => dimmingAtLines(page, [0, 2, 4])).toEqual([0.5, 0, 0.5])
  expect(await text.evaluate(element => getComputedStyle(element).lineHeight)).toBe("60px")
})

test("native composition retains its text, selection and focus through reflow", async ({ page }) => {
  await openFocusMode(page)
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill(documentText)
  await expect.poll(() => dimmingAtLine(page, 0)).toBe(0.5)
  const original = await text.elementHandle()
  const browser = await page.context().newCDPSession(page)
  await browser.send("Input.imeSetComposition", {
    text: "変換中",
    selectionStart: 3,
    selectionEnd: 3,
  })
  await expect(text).toHaveValue(documentText + "変換中")
  await text.dispatchEvent("keydown", { key: "Escape", isComposing: true })
  await expect(page.locator("#loomark-focus-toggle")).toHaveAttribute("aria-pressed", "true")
  await page.setViewportSize({ width: 390, height: 844 })
  await expect.poll(() => dimmingAtLine(page, 0)).toBe(0.5)
  await expect.poll(() => dimmingAtLine(page, 6)).toBe(0)
  expect(await text.evaluate((element, original) => element === original, original)).toBe(true)
  expect(await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    return [area.selectionStart, area.selectionEnd]
  })).toEqual([documentText.length + 3, documentText.length + 3])
  await browser.send("Input.insertText", { text: "確定" })
  await expect(text).toHaveValue(documentText + "確定")
  await page.setViewportSize({ width: 1280, height: 900 })
  await expect.poll(() => dimmingAtLine(page, 0)).toBe(0.5)
  expect(await dimmingAtLine(page, 6)).toBe(0)
  await browser.detach()
  await original?.dispose()
})

test("dimming fades the text around the writing group but not the dot grid", async ({ page }) => {
  await page.emulateMedia({ colorScheme: "light" })
  await page.setViewportSize({ width: 1280, height: 800 })
  await openFocusMode(page)
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill(Array.from({ length: 120 }, (_, i) => `Paragraph ${i + 1}`).join("\n\n"))
  await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    const start = area.value.indexOf("Paragraph 80")
    area.setSelectionRange(start, start)
    area.scrollTop = 4321
  })
  await text.pressSequentially("x")
  const tallestShade = () => page.evaluate(() => {
    const shades = [...document.querySelectorAll<HTMLElement>(".loomark-writing-shade:not([hidden])")]
      .filter(shade => getComputedStyle(shade).opacity === "0.5")
      .map(shade => shade.getBoundingClientRect())
    return shades.sort((a, b) => b.height - a.height)[0]?.toJSON() as DOMRect | undefined
  })
  await expect.poll(async () => (await tallestShade())?.height ?? 0).toBeGreaterThan(200)
  const shade = (await tallestShade())!
  const column = await text.evaluate(element => {
    const bounds = element.getBoundingClientRect(), style = getComputedStyle(element)
    return {
      left: bounds.left + Number.parseFloat(style.paddingLeft),
      right: bounds.right - Number.parseFloat(style.paddingRight),
    }
  })
  const rows = { top: shade.top + 40, bottom: shade.bottom - 40 }
  // The margin sits outside the shades; past the short paragraphs, the text
  // column under a shade holds only dots.
  const [margin, shaded] = await darknessIn(page, [
    { ...rows, left: 20, right: column.left - 20 },
    { ...rows, left: column.left + 160, right: column.right - 10 },
  ])
  expect(margin.darkest, "the margin shows dots").toBeLessThan(margin.paper - 8)
  expect(Math.abs(shaded.darkest - margin.darkest), "dots under a shade match margin dots").toBeLessThanOrEqual(2)
})

type Region = { top: number; bottom: number; left: number; right: number }

async function darknessIn(page: Page, regions: Region[]) {
  const image = await page.screenshot({ scale: "css" })
  return page.evaluate(async ({ encoded, regions }) => {
    const bytes = Uint8Array.from(atob(encoded), value => value.charCodeAt(0))
    const bitmap = await createImageBitmap(new Blob([bytes], { type: "image/png" }))
    const canvas = new OffscreenCanvas(bitmap.width, bitmap.height)
    const context = canvas.getContext("2d")!
    context.drawImage(bitmap, 0, 0)
    const { data, width } = context.getImageData(0, 0, bitmap.width, bitmap.height)
    bitmap.close()
    const brightness = (x: number, y: number) => data[(y * width + x) * 4 + 1]
    return regions.map(region => {
      let darkest = 255, paper = 0
      for (let y = Math.ceil(region.top); y < region.bottom; y++) {
        for (let x = Math.ceil(region.left); x < region.right; x++) {
          darkest = Math.min(darkest, brightness(x, y))
          paper = Math.max(paper, brightness(x, y))
        }
      }
      return { darkest, paper }
    })
  }, { encoded: image.toString("base64"), regions })
}
