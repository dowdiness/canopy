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

test("fresh production opens an empty Text layout without workers", async ({ page }) => {
  const workerUrls: string[] = []
  page.on("worker", worker => workerUrls.push(worker.url()))

  await page.goto("/")
  await page.waitForLoadState("networkidle")

  const text = page.getByRole("textbox", { name: "Text" })
  await expect(text).toBeVisible()
  await expect(text).toBeFocused()
  await expect(text).toHaveValue("")
  await expect.poll(() => readStoredDocument(page)).toEqual({
    document_id: expect.any(String),
    text: "",
  })
  await expect(page.getByRole("button", { name: "Text" })).toHaveAttribute(
    "aria-pressed",
    "true",
  )
  await expect(page.getByRole("button", { name: "Preview" })).toBeVisible()
  await expect(page.getByRole("button", { name: "Split" })).toBeVisible()
  await expect(page.getByRole("tab")).toHaveCount(0)
  expect(workerUrls).toEqual([])
})

test("Preview presents safe typed Markdown without becoming an editor", async ({ page }) => {
  await page.goto("/")
  const source = [
    "# Preview heading",
    "",
    "Paragraph with **strong text**, [label](https://example.com/path),",
    "and ![alternative](https://example.com/image.png).",
    "",
    "<button id=\"unsafe-preview-button\">unsafe</button>",
  ].join("\n")
  await page.getByRole("textbox", { name: "Text" }).fill(source)

  const previewControl = page.getByRole("button", { name: "Preview" })
  await previewControl.click()
  await expect(previewControl).toHaveAttribute("aria-pressed", "true")

  const preview = page.getByRole("region", { name: "Preview result" })
  await expect(preview).toBeVisible()
  await expect(preview.getByRole("heading", { name: "Preview heading" })).toBeVisible()
  await expect(preview.locator("strong")).toHaveText("strong text")
  await expect(preview).toContainText("label")
  await expect(preview).toContainText("https://example.com/path")
  await expect(preview).toContainText("alternative")
  await expect(preview).toContainText("https://example.com/image.png")
  await expect(preview).toContainText('<button id="unsafe-preview-button">unsafe</button>')
  await expect(preview.locator("a[href]")).toHaveCount(0)
  await expect(preview.locator("img")).toHaveCount(0)
  await expect(preview.locator("#unsafe-preview-button")).toHaveCount(0)
})

test("Preview intent prepares without changing layout and Text return does not focus", async ({
  page,
}) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Prepared before activation\n")
  await page.evaluate(() => performance.clearMeasures())

  const previewControl = page.getByRole("button", { name: "Preview" })
  await previewControl.hover()
  await expect(page.getByRole("button", { name: "Text" })).toHaveAttribute(
    "aria-pressed",
    "true",
  )
  await expect.poll(() => page.evaluate(() => (
    performance.getEntriesByName("loomark-preview-total").length
  ))).toBeGreaterThan(0)

  await previewControl.click()
  await expect(
    page.getByRole("region", { name: "Preview result" })
      .getByRole("heading", { name: "Prepared before activation" }),
  ).toBeVisible()

  await page.getByRole("button", { name: "Text" }).click()
  const returnedText = page.getByRole("textbox", { name: "Text" })
  await expect(returnedText).toBeVisible()
  await expect(returnedText).not.toBeFocused()
})

test("Split converges to latest text and defers Preview during IME composition", async ({
  page,
}) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Initial\n")
  await page.getByRole("button", { name: "Split" }).click()
  const preview = page.getByRole("region", { name: "Preview result" })
  await expect(preview.getByRole("heading", { name: "Initial" })).toBeVisible()

  await page.evaluate(() => performance.clearMeasures())
  await text.evaluate(element => {
    const textarea = element as HTMLTextAreaElement
    textarea.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true }))
    textarea.value = "# 変換中"
    textarea.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      composed: true,
      data: "変換中",
      inputType: "insertCompositionText",
    }))
  })
  await page.waitForTimeout(50)
  expect(await page.evaluate(() => (
    performance.getEntriesByName("loomark-preview-total").length
  ))).toBe(0)
  await expect(preview.getByRole("heading", { name: "Initial" })).toBeVisible()

  await text.evaluate(element => {
    element.dispatchEvent(new CompositionEvent("compositionend", {
      bubbles: true,
      data: "変換中",
    }))
  })
  await expect(preview.getByRole("heading", { name: "変換中" })).toBeVisible()

  await text.evaluate(element => {
    const textarea = element as HTMLTextAreaElement
    for (const value of ["# First", "# Second", "# Latest"]) {
      textarea.value = value
      textarea.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        composed: true,
        data: value,
        inputType: "insertText",
      }))
    }
  })
  await expect(text).toHaveValue("# Latest")
  await expect(preview.getByRole("heading", { name: "Latest" })).toBeVisible()
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

  await text.evaluate(element => {
    element.dispatchEvent(new CompositionEvent("compositionend", {
      bubbles: true,
      data: "変換中",
    }))
  })
  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe("変換中")
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
