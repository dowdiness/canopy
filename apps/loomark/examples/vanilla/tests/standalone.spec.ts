import { expect, test, type Page } from "@playwright/test"

const DOCUMENT_DATABASE_NAME = "loomark"
const DOCUMENT_DATABASE_VERSION = 1
const DOCUMENT_STORE_NAME = "documents"
const ACTIVE_DOCUMENT_KEY = "active"

type StoredDocument = {
  document_id: string
  text: string
}

async function readStoredDocumentRaw(page: Page): Promise<unknown> {
  return page.evaluate(({ databaseName, databaseVersion, storeName, key }) => (
    new Promise<unknown>((resolve, reject) => {
      const open = indexedDB.open(databaseName, databaseVersion)
      open.onupgradeneeded = () => {
        if (!open.result.objectStoreNames.contains(storeName)) {
          open.result.createObjectStore(storeName)
        }
      }
      open.onerror = () => reject(open.error ?? new Error("document database open failed"))
      open.onsuccess = () => {
        const database = open.result
        const transaction = database.transaction(storeName, "readonly")
        let value: unknown
        let settled = false
        const fail = (error: unknown) => {
          if (settled) return
          settled = true
          database.close()
          reject(error)
        }
        transaction.onerror = () => fail(transaction.error ?? new Error("document read failed"))
        transaction.onabort = () => fail(transaction.error ?? new Error("document read aborted"))
        transaction.oncomplete = () => {
          if (settled) return
          settled = true
          database.close()
          resolve(value)
        }
        const request = transaction.objectStore(storeName).get(key)
        request.onerror = () => fail(request.error ?? new Error("document read failed"))
        request.onsuccess = () => { value = request.result }
      }
    })
  ), {
    databaseName: DOCUMENT_DATABASE_NAME,
    databaseVersion: DOCUMENT_DATABASE_VERSION,
    storeName: DOCUMENT_STORE_NAME,
    key: ACTIVE_DOCUMENT_KEY,
  })
}

async function readStoredDocument(page: Page): Promise<StoredDocument | null> {
  const value = await readStoredDocumentRaw(page)
  if (typeof value !== "string") return null
  try {
    const parsed: unknown = JSON.parse(value)
    if (
      parsed === null
      || typeof parsed !== "object"
      || JSON.stringify(Object.keys(parsed).sort()) !== JSON.stringify(["document_id", "text"])
      || !("document_id" in parsed)
      || typeof parsed.document_id !== "string"
      || !("text" in parsed)
      || typeof parsed.text !== "string"
    ) return null
    return { document_id: parsed.document_id, text: parsed.text }
  } catch (_) {
    return null
  }
}

async function writeStoredDocumentRaw(page: Page, value: string): Promise<void> {
  await page.evaluate(({ databaseName, databaseVersion, storeName, key, value }) => (
    new Promise<void>((resolve, reject) => {
      const open = indexedDB.open(databaseName, databaseVersion)
      open.onupgradeneeded = () => {
        if (!open.result.objectStoreNames.contains(storeName)) {
          open.result.createObjectStore(storeName)
        }
      }
      open.onerror = () => reject(open.error ?? new Error("document database open failed"))
      open.onsuccess = () => {
        const database = open.result
        const transaction = database.transaction(storeName, "readwrite")
        let settled = false
        const fail = (error: unknown) => {
          if (settled) return
          settled = true
          database.close()
          reject(error)
        }
        transaction.onerror = () => fail(transaction.error ?? new Error("document write failed"))
        transaction.onabort = () => fail(transaction.error ?? new Error("document write aborted"))
        transaction.oncomplete = () => {
          if (settled) return
          settled = true
          database.close()
          resolve()
        }
        const request = transaction.objectStore(storeName).put(value, key)
        request.onerror = () => fail(request.error ?? new Error("document write failed"))
      }
    })
  ), {
    databaseName: DOCUMENT_DATABASE_NAME,
    databaseVersion: DOCUMENT_DATABASE_VERSION,
    storeName: DOCUMENT_STORE_NAME,
    key: ACTIVE_DOCUMENT_KEY,
    value,
  })
}

function installDocumentPutFailure(key: string): void {
  const state = globalThis as typeof globalThis & {
    __loomarkDocumentPutFailure?: boolean
    __loomarkDocumentPutOriginal?: typeof IDBObjectStore.prototype.put
  }
  if (state.__loomarkDocumentPutFailure) return
  const prototype = IDBObjectStore.prototype as any
  const originalPut = prototype.put
  state.__loomarkDocumentPutOriginal = originalPut
  prototype.put = function(this: IDBObjectStore, value: unknown, recordKey?: IDBValidKey) {
    if (recordKey === key) throw new DOMException("full", "QuotaExceededError")
    return originalPut.call(this, value, recordKey)
  }
  state.__loomarkDocumentPutFailure = true
}

function removeDocumentPutFailure(): void {
  const state = globalThis as typeof globalThis & {
    __loomarkDocumentPutFailure?: boolean
    __loomarkDocumentPutOriginal?: typeof IDBObjectStore.prototype.put
  }
  if (!state.__loomarkDocumentPutFailure || !state.__loomarkDocumentPutOriginal) return
  IDBObjectStore.prototype.put = state.__loomarkDocumentPutOriginal
  delete state.__loomarkDocumentPutFailure
  delete state.__loomarkDocumentPutOriginal
}

test("fresh production opens Text mode and preserves its textarea across modes", async ({ page }) => {
  const workerUrls: string[] = []
  page.on("worker", worker => workerUrls.push(worker.url()))

  await page.goto("/")
  await page.waitForLoadState("networkidle")

  const text = page.getByRole("textbox", { name: "Text" })
  const textTab = page.getByRole("tab", { name: "Text" })
  const previewTab = page.getByRole("tab", { name: "Preview" })
  const splitTab = page.getByRole("tab", { name: "Split" })
  const preview = page.getByRole("region", { name: "Markdown preview" })

  await expect(text).toBeVisible()
  await expect(text).toBeFocused()
  await expect(text).toHaveValue("")
  await expect(textTab).toHaveAttribute("aria-selected", "true")
  await expect(previewTab).toHaveAttribute("aria-selected", "false")
  await expect(splitTab).toHaveAttribute("aria-selected", "false")
  await expect.poll(() => readStoredDocument(page)).toEqual({
    document_id: expect.any(String),
    text: "",
  })
  await text.evaluate(element => {
    ;(globalThis as typeof globalThis & { __loomarkTextArea?: HTMLTextAreaElement })
      .__loomarkTextArea = element as HTMLTextAreaElement
  })
  await text.pressSequentially("abc")
  await text.evaluate(element => (element as HTMLTextAreaElement).setSelectionRange(1, 2))

  await previewTab.click()
  await expect(text).toBeHidden()
  await expect(preview).toBeVisible()
  expect(await page.evaluate(() => (
    (globalThis as typeof globalThis & { __loomarkTextArea?: HTMLTextAreaElement })
      .__loomarkTextArea === document.getElementById("loomark-text")
  ))).toBe(true)

  await splitTab.click()
  await expect(text).toBeVisible()
  await expect(preview).toBeVisible()
  await expect(page.getByRole("separator")).toHaveCount(1)
  await expect(page.getByRole("slider", { name: "Resize editor and preview" }))
    .toHaveCount(1)
  await expect(page.locator('[data-slot="resizable-handle-grip"]')).toBeVisible()
  expect(await page.evaluate(() => (
    (globalThis as typeof globalThis & { __loomarkTextArea?: HTMLTextAreaElement })
      .__loomarkTextArea === document.getElementById("loomark-text")
  ))).toBe(true)

  await textTab.click()
  await expect(text).toBeVisible()
  await expect(preview).toBeHidden()
  expect(await page.evaluate(() => (
    (globalThis as typeof globalThis & { __loomarkTextArea?: HTMLTextAreaElement })
      .__loomarkTextArea === document.getElementById("loomark-text")
  ))).toBe(true)
  expect(await text.evaluate(element => ({
    start: (element as HTMLTextAreaElement).selectionStart,
    end: (element as HTMLTextAreaElement).selectionEnd,
  }))).toEqual({ start: 1, end: 2 })
  await text.focus()
  await page.keyboard.press("Control+Z")
  await expect(text).toHaveValue("")
  expect(workerUrls).toEqual([])
})

test("Preview prepares after its status paints and refreshes typed Markdown", async ({ page }) => {
  await page.goto("/")

  const source = [
    "# Preview heading",
    "",
    "[Canopy](https://example.test)",
    "",
    '<div id="unsafe-preview">raw HTML</div>',
    "",
  ].join("\n")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill(source)
  await page.evaluate(() => {
    const state = globalThis as typeof globalThis & {
      __loomarkPreparingObserved?: boolean
    }
    state.__loomarkPreparingObserved = false
    const observer = new MutationObserver(() => {
      if (document.body.textContent?.includes("Preparing preview…")) {
        state.__loomarkPreparingObserved = true
        observer.disconnect()
      }
    })
    observer.observe(document.body, { childList: true, subtree: true })
  })
  await page.getByRole("tab", { name: "Preview" }).click()

  await expect.poll(() => page.evaluate(() => (
    (globalThis as typeof globalThis & { __loomarkPreparingObserved?: boolean })
      .__loomarkPreparingObserved ?? false
  ))).toBe(true)
  await expect(page.getByRole("heading", { name: "Preview heading" })).toBeVisible()
  const link = page.getByRole("link", { name: "Canopy" })
  await expect(link).toHaveAttribute("href", "https://example.test")
  await expect(link).toHaveAttribute("target", "_blank")
  await expect(link).toHaveAttribute("rel", "noopener noreferrer")
  await expect(page.getByText('<div id="unsafe-preview">raw HTML</div>')).toBeVisible()
  await expect(page.locator("#unsafe-preview")).toHaveCount(0)

  await page.getByRole("tab", { name: "Split" }).click()
  await text.fill("# Updated heading\n")
  await expect(page.getByRole("heading", { name: "Preview heading" })).toBeVisible()
  await page.getByRole("tab", { name: "Text" }).click()
  await page.getByRole("tab", { name: "Preview" }).click()
  await expect(page.getByRole("heading", { name: "Updated heading" })).toBeVisible()
  await expect(page.getByRole("heading", { name: "Preview heading" })).toHaveCount(0)
})

test("mode tabs move focus without activation and activate with Enter or Space", async ({ page }) => {
  await page.goto("/")

  const textTab = page.getByRole("tab", { name: "Text" })
  const previewTab = page.getByRole("tab", { name: "Preview" })
  const splitTab = page.getByRole("tab", { name: "Split" })
  const preview = page.getByRole("region", { name: "Markdown preview" })

  await textTab.focus()
  await page.keyboard.press("ArrowRight")
  await expect(previewTab).toBeFocused()
  await expect(textTab).toHaveAttribute("aria-selected", "true")
  await expect(preview).toBeHidden()

  await page.keyboard.press("Enter")
  await expect(previewTab).toBeFocused()
  await expect(previewTab).toHaveAttribute("aria-selected", "true")
  await expect(preview).toBeVisible()
  await page.keyboard.press("Tab")
  await expect(preview).toBeFocused()
  await page.keyboard.press("Shift+Tab")
  await expect(previewTab).toBeFocused()

  await page.keyboard.press("ArrowRight")
  await expect(splitTab).toBeFocused()
  await expect(previewTab).toHaveAttribute("aria-selected", "true")
  await page.keyboard.press("Space")
  await expect(splitTab).toBeFocused()
  await expect(splitTab).toHaveAttribute("aria-selected", "true")
  await page.keyboard.press("Tab")
  await expect(page.getByRole("textbox", { name: "Text" })).toBeFocused()
})

test("Split uses RUI keyboard resizing and preserves textarea across orientation", async ({ page }) => {
  await page.setViewportSize({ width: 900, height: 700 })
  await page.goto("/")

  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Stable textarea\n")
  await text.evaluate(element => {
    ;(globalThis as typeof globalThis & { __loomarkTextArea?: HTMLTextAreaElement })
      .__loomarkTextArea = element as HTMLTextAreaElement
  })
  await page.getByRole("tab", { name: "Split" }).click()

  const separator = page.getByRole("separator")
  const resize = page.getByRole("slider", { name: "Resize editor and preview" })
  await expect(separator).toHaveAttribute("aria-orientation", "vertical")
  await expect(resize).toHaveValue("50")
  await resize.focus()
  await page.keyboard.press("ArrowRight")
  await expect(resize).toHaveValue("51")

  const groupBox = await page.locator("#loomark-editor-panels").boundingBox()
  const gripBox = await page.locator('[data-slot="resizable-handle-grip"]')
    .boundingBox()
  expect(groupBox).not.toBeNull()
  expect(gripBox).not.toBeNull()
  if (!groupBox || !gripBox) throw new Error("Split resize geometry missing")
  await page.mouse.move(gripBox.x + gripBox.width / 2, gripBox.y + gripBox.height / 2)
  await page.mouse.down()
  await page.mouse.move(groupBox.x + groupBox.width * 0.9, groupBox.y + groupBox.height / 2)
  await page.mouse.up()
  await expect(resize).toHaveValue("75")

  await page.setViewportSize({ width: 640, height: 700 })
  await expect(separator).toHaveAttribute("aria-orientation", "horizontal")
  await expect(resize).toHaveValue("50")
  expect(await page.evaluate(() => (
    (globalThis as typeof globalThis & { __loomarkTextArea?: HTMLTextAreaElement })
      .__loomarkTextArea === document.getElementById("loomark-text")
  ))).toBe(true)
  await expect(text).toHaveValue("# Stable textarea\n")
  await resize.focus()
  await page.keyboard.press("ArrowDown")
  await expect(resize).toHaveValue("51")
})

test("quiet Autosave restores exact Saved text after reload", async ({ page }) => {
  const savedText = "# Saved locally\n\nExact text.\n"
  await page.goto("/")

  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill(savedText)
  await expect(text).toHaveValue(savedText)
  await expect.poll(() => readStoredDocument(page)).toEqual({
    document_id: expect.any(String),
    text: savedText,
  })

  const saved = await readStoredDocument(page)
  expect(saved?.document_id).not.toBe("")
  await page.reload()
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue(savedText)
  expect((await readStoredDocument(page))?.document_id).toBe(saved?.document_id)
})

test("rapid Text input writes only the latest text", async ({ page }) => {
  await page.goto("/")
  await expect.poll(() => readStoredDocument(page).then(document => document?.text)).toBe("")
  await page.evaluate(key => {
    const scope = globalThis as typeof globalThis & { __loomarkStoredValues?: string[] }
    const originalPut = IDBObjectStore.prototype.put
    scope.__loomarkStoredValues = []
    IDBObjectStore.prototype.put = function(
      this: IDBObjectStore,
      value: unknown,
      recordKey?: IDBValidKey,
    ) {
      if (recordKey === key && typeof value === "string") {
        scope.__loomarkStoredValues?.push(value)
      }
      return originalPut.call(this, value, recordKey)
    }
  }, ACTIVE_DOCUMENT_KEY)

  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("A")
  await text.fill("B")
  await text.fill("A")
  await expect.poll(() => readStoredDocument(page).then(document => document?.text)).toBe("A")
  const writtenTexts = await page.evaluate(() => (
    (globalThis as typeof globalThis & { __loomarkStoredValues?: string[] })
      .__loomarkStoredValues ?? []
  )).then(values => values.map(value => (JSON.parse(value) as StoredDocument).text))
  expect(writtenTexts).toEqual(["A"])
})

test("IME composition saves only after composition ends", async ({ page }) => {
  await page.goto("/")
  await expect.poll(() => readStoredDocument(page).then(document => document?.text)).toBe("")

  const text = page.getByRole("textbox", { name: "Text" })
  await text.evaluate(element => {
    const textarea = element as HTMLTextAreaElement
    textarea.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true }))
    textarea.value = "変換中"
    textarea.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      composed: true,
      data: "変換中",
      inputType: "insertCompositionText",
    }))
  })
  await expect(text).toHaveValue("変換中")
  await page.waitForTimeout(300)
  expect((await readStoredDocument(page))?.text).toBe("")

  const terminalValueReads = await text.evaluate(element => {
    const descriptor = Object.getOwnPropertyDescriptor(
      HTMLTextAreaElement.prototype,
      "value",
    )
    if (!descriptor?.get || !descriptor.set) throw new Error("textarea value descriptor missing")
    let reads = 0
    Object.defineProperty(HTMLTextAreaElement.prototype, "value", {
      configurable: true,
      enumerable: descriptor.enumerable,
      get() {
        reads += 1
        return descriptor.get?.call(this)
      },
      set(value: string) {
        descriptor.set?.call(this, value)
      },
    })
    element.dispatchEvent(new CompositionEvent("compositionend", {
      bubbles: true,
      data: "変換中",
    }))
    element.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      composed: true,
      data: "変換中",
      inputType: "insertText",
    }))
    Object.defineProperty(HTMLTextAreaElement.prototype, "value", descriptor)
    return reads
  })
  expect(terminalValueReads).toBe(0)
  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe("変換中")
})

test("Preview schedules no new work until IME composition commits", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Before\n")
  await page.getByRole("tab", { name: "Split" }).click()
  await expect(page.getByRole("heading", { name: "Before" })).toBeVisible()

  await text.evaluate(element => {
    const textarea = element as HTMLTextAreaElement
    textarea.setSelectionRange(0, textarea.value.length)
    textarea.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true }))
    textarea.value = "# During\n"
    textarea.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      composed: true,
      data: "# During\n",
      inputType: "insertCompositionText",
    }))
  })
  await page.waitForTimeout(100)
  await expect(page.getByRole("heading", { name: "Before" })).toBeVisible()
  await expect(page.getByRole("heading", { name: "During" })).toHaveCount(0)

  await text.evaluate(element => {
    const textarea = element as HTMLTextAreaElement
    textarea.value = "# After\n"
    textarea.dispatchEvent(new CompositionEvent("compositionend", {
      bubbles: true,
      data: "# After\n",
    }))
    textarea.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      composed: true,
      data: "# After\n",
      inputType: "insertText",
    }))
  })
  await expect(page.getByRole("heading", { name: "After" })).toBeVisible()
  await expect(page.getByRole("heading", { name: "Before" })).toHaveCount(0)
})

test("save failure keeps Text editable and Retry saves the latest text", async ({ page }) => {
  await page.goto("/")
  await expect.poll(() => readStoredDocument(page)).toEqual({
    document_id: expect.any(String),
    text: "",
  })
  await page.evaluate(installDocumentPutFailure, ACTIVE_DOCUMENT_KEY)

  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Not saved\n")
  await expect(page.getByRole("alert")).toContainText(
    "Changes are not saved in this browser. Browser storage is full.",
  )
  await text.fill("# Latest text\n")
  await expect(text).toHaveValue("# Latest text\n")
  await page.waitForTimeout(300)
  expect((await readStoredDocument(page))?.text).toBe("")

  await page.evaluate(removeDocumentPutFailure)
  await page.getByRole("button", { name: "Retry saving" }).click()
  await expect(page.getByRole("alert")).toHaveCount(0)
  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe("# Latest text\n")
  await page.reload()
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue("# Latest text\n")
})

test("invalid stored document opens Recovery without overwriting it", async ({ page }) => {
  const invalidDocument = "not-json"
  await page.goto("/")
  await expect.poll(() => readStoredDocument(page)).not.toBeNull()
  await writeStoredDocumentRaw(page, invalidDocument)

  await page.reload()
  await expect(page.getByRole("heading", { name: "Document recovery" })).toBeVisible()
  await expect(page.getByText("The stored document is invalid and was not overwritten."))
    .toBeVisible()
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveCount(0)
  expect(await readStoredDocumentRaw(page)).toBe(invalidDocument)
})

test("native range edits avoid complete value access and native undo reads once", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.waitFor()
  await page.evaluate(() => {
    const descriptor = Object.getOwnPropertyDescriptor(
      HTMLTextAreaElement.prototype,
      "value",
    )
    if (!descriptor?.get || !descriptor.set) throw new Error("textarea value descriptor missing")
    ;(globalThis as any).__loomarkValueDescriptor = descriptor
    ;(globalThis as any).__loomarkValueReads = 0
    ;(globalThis as any).__loomarkValueWrites = 0
    Object.defineProperty(HTMLTextAreaElement.prototype, "value", {
      configurable: true,
      enumerable: descriptor.enumerable,
      get() {
        ;(globalThis as any).__loomarkValueReads += 1
        return descriptor.get?.call(this)
      },
      set(value: string) {
        ;(globalThis as any).__loomarkValueWrites += 1
        descriptor.set?.call(this, value)
      },
    })
  })

  await text.focus()
  await page.keyboard.type("abc")
  await text.evaluate(element => (element as HTMLTextAreaElement).setSelectionRange(1, 2))
  await page.keyboard.insertText("X")
  await page.keyboard.press("Backspace")
  await page.keyboard.press("End")
  await page.keyboard.press("Enter")
  await page.keyboard.insertText("🤣é")

  expect(await page.evaluate(() => ({
    reads: (globalThis as any).__loomarkValueReads as number,
    writes: (globalThis as any).__loomarkValueWrites as number,
  }))).toEqual({ reads: 0, writes: 0 })

  await page.keyboard.press("Control+Z")
  expect(await page.evaluate(() => ({
    reads: (globalThis as any).__loomarkValueReads as number,
    writes: (globalThis as any).__loomarkValueWrites as number,
  }))).toEqual({ reads: 1, writes: 0 })

  const browserText = await page.evaluate(() => {
    const descriptor = (globalThis as any).__loomarkValueDescriptor as PropertyDescriptor
    Object.defineProperty(HTMLTextAreaElement.prototype, "value", descriptor)
    return (document.getElementById("loomark-text") as HTMLTextAreaElement).value
  })
  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe(browserText)
})

test("mismatched insertion facts recover from the current textarea value", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.waitFor()

  await text.evaluate(element => {
    const textarea = element as HTMLTextAreaElement
    textarea.dispatchEvent(new InputEvent("beforeinput", {
      bubbles: true,
      cancelable: true,
      composed: true,
      data: "before",
      inputType: "insertText",
    }))
    textarea.value = "after!"
    textarea.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      composed: true,
      data: "after!",
      inputType: "insertText",
    }))
  })

  await expect(text).toHaveValue("after!")
  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe("after!")
})

test("Text input stays within 10 ms with per-edit Parser transitions", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# A")
  await page.getByRole("tab", { name: "Preview" }).click()
  await expect(page.getByRole("heading", { name: "A" })).toBeVisible()
  await page.getByRole("tab", { name: "Text" }).click()

  const durations = await text.evaluate(element => {
    const textarea = element as HTMLTextAreaElement
    const dispatchExactInsert = () => {
      const start = textarea.value.length
      textarea.setSelectionRange(start, start)
      textarea.dispatchEvent(new InputEvent("beforeinput", {
        bubbles: true,
        cancelable: true,
        composed: true,
        data: "x",
        inputType: "insertText",
      }))
      textarea.value += "x"
      textarea.setSelectionRange(start + 1, start + 1)
      textarea.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        composed: true,
        data: "x",
        inputType: "insertText",
      }))
    }
    for (let index = 0; index < 10; index += 1) dispatchExactInsert()
    return Array.from({ length: 50 }, () => {
      const started = performance.now()
      dispatchExactInsert()
      return performance.now() - started
    })
  })
  const sorted = [...durations].sort((left, right) => left - right)
  expect(sorted[Math.ceil(sorted.length * 0.95) - 1]).toBeLessThanOrEqual(10)
  expect(sorted[sorted.length - 1]).toBeLessThanOrEqual(10)

  await page.waitForTimeout(100)
  await page.getByRole("tab", { name: "Preview" }).click()
  await expect(page.getByRole("heading", { name: `A${"x".repeat(60)}` })).toBeVisible()
})

test("Text input processing stays within 10 ms", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  const durations = await text.evaluate(element => {
    const textarea = element as HTMLTextAreaElement
    const dispatch = (value: string) => {
      textarea.value = value
      textarea.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        composed: true,
        data: value,
        inputType: "insertText",
      }))
    }
    for (let index = 0; index < 10; index += 1) dispatch(`warmup-${index}`)
    return Array.from({ length: 50 }, (_, index) => {
      const started = performance.now()
      dispatch(`sample-${index}`)
      return performance.now() - started
    })
  })
  const sorted = [...durations].sort((left, right) => left - right)
  const p95 = sorted[Math.ceil(sorted.length * 0.95) - 1]
  const maximum = sorted[sorted.length - 1]
  expect(p95).toBeLessThanOrEqual(10)
  expect(maximum).toBeLessThanOrEqual(10)
})
