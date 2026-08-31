import { expect, test, type Page } from "@playwright/test"

const DOCUMENT_DATABASE_NAME = "loomark"
const DOCUMENT_DATABASE_VERSION = 1
const DOCUMENT_STORE_NAME = "documents"
const LEGACY_ACTIVE_KEY = "active"
const SOURCE_KEY_PREFIX = "source/v1/"
const CATALOG_KEY = "catalog/v1"

type StoredDocument = {
  document_id: string
  text: string
}

type StoreRecord = {
  key: string | number
  value: unknown
}

function sourceKey(documentId: string): string {
  return `${SOURCE_KEY_PREFIX}${documentId}`
}

async function scanStoreRecords(page: Page): Promise<StoreRecord[]> {
  return page.evaluate(({ databaseName, databaseVersion, storeName }) => (
    new Promise<StoreRecord[]>((resolve, reject) => {
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
        const records: StoreRecord[] = []
        const fail = (error: unknown) => {
          database.close()
          reject(error)
        }
        transaction.onerror = () => fail(transaction.error ?? new Error("document scan failed"))
        transaction.onabort = () => fail(transaction.error ?? new Error("document scan aborted"))
        transaction.oncomplete = () => {
          database.close()
          resolve(records)
        }
        const request = transaction.objectStore(storeName).openCursor()
        request.onerror = () => fail(request.error ?? new Error("document cursor failed"))
        request.onsuccess = () => {
          const cursor = request.result
          if (!cursor) return
          records.push({
            key: typeof cursor.key === "string" || typeof cursor.key === "number"
              ? cursor.key
              : "[unsupported-key]",
            value: cursor.value,
          })
          cursor.continue()
        }
      }
    })
  ), {
    databaseName: DOCUMENT_DATABASE_NAME,
    databaseVersion: DOCUMENT_DATABASE_VERSION,
    storeName: DOCUMENT_STORE_NAME,
  })
}

async function measureIndexedDbScan(
  page: Page,
): Promise<{ count: number; durationMs: number }> {
  return page.evaluate(({ databaseName, databaseVersion, storeName }) => (
    new Promise<{ count: number; durationMs: number }>((resolve, reject) => {
      const open = indexedDB.open(databaseName, databaseVersion)
      open.onerror = () => reject(open.error ?? new Error("document database open failed"))
      open.onsuccess = () => {
        const database = open.result
        const started = performance.now()
        const transaction = database.transaction(storeName, "readonly")
        let count = 0
        const fail = (error: unknown) => {
          database.close()
          reject(error)
        }
        transaction.onerror = () => fail(transaction.error ?? new Error("document scan failed"))
        transaction.onabort = () => fail(transaction.error ?? new Error("document scan aborted"))
        transaction.oncomplete = () => {
          const durationMs = performance.now() - started
          database.close()
          resolve({ count, durationMs })
        }
        const request = transaction.objectStore(storeName).openCursor()
        request.onerror = () => fail(request.error ?? new Error("document cursor failed"))
        request.onsuccess = () => {
          const cursor = request.result
          if (!cursor) return
          count += 1
          cursor.continue()
        }
      }
    })
  ), {
    databaseName: DOCUMENT_DATABASE_NAME,
    databaseVersion: DOCUMENT_DATABASE_VERSION,
    storeName: DOCUMENT_STORE_NAME,
  })
}

async function measureIndexedDbPut(
  page: Page,
  key: string,
  value: string,
): Promise<number> {
  return page.evaluate(({ databaseName, databaseVersion, storeName, key, value }) => (
    new Promise<number>((resolve, reject) => {
      const open = indexedDB.open(databaseName, databaseVersion)
      open.onerror = () => reject(open.error ?? new Error("document database open failed"))
      open.onsuccess = () => {
        const database = open.result
        const started = performance.now()
        const transaction = database.transaction(storeName, "readwrite")
        const fail = (error: unknown) => {
          database.close()
          reject(error)
        }
        transaction.onerror = () => fail(transaction.error ?? new Error("document write failed"))
        transaction.onabort = () => fail(transaction.error ?? new Error("document write aborted"))
        transaction.oncomplete = () => {
          const durationMs = performance.now() - started
          database.close()
          resolve(durationMs)
        }
        transaction.objectStore(storeName).put(value, key)
      }
    })
  ), {
    databaseName: DOCUMENT_DATABASE_NAME,
    databaseVersion: DOCUMENT_DATABASE_VERSION,
    storeName: DOCUMENT_STORE_NAME,
    key,
    value,
  })
}

function decodeStoredDocument(key: IDBValidKey, value: unknown): StoredDocument | null {
  if (typeof key !== "string" || !key.startsWith(SOURCE_KEY_PREFIX) || typeof value !== "string") {
    return null
  }
  try {
    const parsed: unknown = JSON.parse(value)
    if (
      parsed === null
      || typeof parsed !== "object"
      || JSON.stringify(Object.keys(parsed).sort()) !== JSON.stringify(["document_id", "text"])
      || !("document_id" in parsed)
      || typeof parsed.document_id !== "string"
      || parsed.document_id !== key.slice(SOURCE_KEY_PREFIX.length)
      || !("text" in parsed)
      || typeof parsed.text !== "string"
    ) return null
    return { document_id: parsed.document_id, text: parsed.text }
  } catch (_) {
    return null
  }
}

async function readStoredDocuments(page: Page): Promise<StoredDocument[]> {
  return (await scanStoreRecords(page))
    .map(record => decodeStoredDocument(record.key, record.value))
    .filter((document): document is StoredDocument => document !== null)
    .sort((left, right) => left.document_id < right.document_id ? -1 : left.document_id > right.document_id ? 1 : 0)
}

async function readStoredDocument(page: Page): Promise<StoredDocument | null> {
  return (await readStoredDocuments(page))[0] ?? null
}

async function readStoredDocumentRaw(page: Page, key: string | number): Promise<unknown> {
  return (await scanStoreRecords(page)).find(record => record.key === key)?.value
}

async function writeStoredDocumentRaw(
  page: Page,
  key: string | number,
  value: string,
): Promise<void> {
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
        const fail = (error: unknown) => {
          database.close()
          reject(error)
        }
        transaction.onerror = () => fail(transaction.error ?? new Error("document write failed"))
        transaction.onabort = () => fail(transaction.error ?? new Error("document write aborted"))
        transaction.oncomplete = () => {
          database.close()
          resolve()
        }
        transaction.objectStore(storeName).put(value, key)
      }
    })
  ), {
    databaseName: DOCUMENT_DATABASE_NAME,
    databaseVersion: DOCUMENT_DATABASE_VERSION,
    storeName: DOCUMENT_STORE_NAME,
    key,
    value,
  })
}

async function replaceStoreRecords(page: Page, records: StoreRecord[]): Promise<void> {
  await page.evaluate(({ databaseName, databaseVersion, storeName, records }) => (
    new Promise<void>((resolve, reject) => {
      const open = indexedDB.open(databaseName, databaseVersion)
      open.onerror = () => reject(open.error ?? new Error("document database open failed"))
      open.onsuccess = () => {
        const database = open.result
        const transaction = database.transaction(storeName, "readwrite")
        const fail = (error: unknown) => {
          database.close()
          reject(error)
        }
        transaction.onerror = () => fail(transaction.error ?? new Error("document replace failed"))
        transaction.onabort = () => fail(transaction.error ?? new Error("document replace aborted"))
        transaction.oncomplete = () => {
          database.close()
          resolve()
        }
        const store = transaction.objectStore(storeName)
        store.clear()
        for (const record of records) store.put(record.value, record.key)
      }
    })
  ), {
    databaseName: DOCUMENT_DATABASE_NAME,
    databaseVersion: DOCUMENT_DATABASE_VERSION,
    storeName: DOCUMENT_STORE_NAME,
    records,
  })
}

function encodeStoredDocument(document: StoredDocument): string {
  return JSON.stringify(document)
}

function installDocumentPutFailure(target: string | { prefix: string }): void {
  const state = globalThis as typeof globalThis & {
    __loomarkDocumentPutFailure?: boolean
    __loomarkDocumentPutFailureCalls?: number
    __loomarkDocumentPutOriginal?: typeof IDBObjectStore.prototype.put
  }
  if (state.__loomarkDocumentPutFailure) return
  const prototype = IDBObjectStore.prototype as any
  const originalPut = prototype.put
  state.__loomarkDocumentPutOriginal = originalPut
  state.__loomarkDocumentPutFailureCalls = 0
  prototype.put = function(this: IDBObjectStore, value: unknown, recordKey?: IDBValidKey) {
    const matches = typeof target === "string"
      ? recordKey === target
      : typeof recordKey === "string" && recordKey.startsWith(target.prefix)
    if (matches) {
      state.__loomarkDocumentPutFailureCalls = (state.__loomarkDocumentPutFailureCalls ?? 0) + 1
      throw new DOMException("full", "QuotaExceededError")
    }
    return originalPut.call(this, value, recordKey)
  }
  state.__loomarkDocumentPutFailure = true
}

async function waitForRepositoryOpen(page: Page): Promise<void> {
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue("# Untitled\n")
  await expect.poll(() => readStoredDocument(page)).not.toBeNull()
}

function installDelayedDocumentAbort(targetKey: string): void {
  const state = globalThis as typeof globalThis & {
    __loomarkDelayedAbortStarted?: boolean
    __loomarkDelayedAbortFinished?: boolean
    __loomarkDelayedAbortOriginal?: typeof IDBObjectStore.prototype.put
  }
  const prototype = IDBObjectStore.prototype as any
  const originalPut = prototype.put
  state.__loomarkDelayedAbortOriginal = originalPut
  state.__loomarkDelayedAbortStarted = false
  state.__loomarkDelayedAbortFinished = false
  prototype.put = function(
    this: IDBObjectStore,
    value: unknown,
    recordKey?: IDBValidKey,
  ) {
    const request = originalPut.call(this, value, recordKey)
    if (recordKey === targetKey) {
      state.__loomarkDelayedAbortStarted = true
      const store = this
      const transaction = this.transaction
      const started = performance.now()
      const keepAlive = () => {
        if (performance.now() - started >= 500) {
          transaction.abort()
          state.__loomarkDelayedAbortFinished = true
          return
        }
        const keepAliveRequest = store.get(recordKey)
        keepAliveRequest.addEventListener("success", keepAlive)
        keepAliveRequest.addEventListener("error", keepAlive)
      }
      keepAlive()
    }
    return request
  }
}

function installDelayedDocumentCommit(targetKey: string): void {
  const state = globalThis as typeof globalThis & {
    __loomarkDelayedCommitActive?: boolean
    __loomarkDelayedCommitCompletions?: number
    __loomarkDelayedCommitConcurrentPuts?: number
    __loomarkDelayedCommitInputs?: number
    __loomarkDelayedCommitPuts?: PutObservation[]
  }
  const prototype = IDBObjectStore.prototype as any
  const originalPut = prototype.put
  state.__loomarkDelayedCommitActive = false
  state.__loomarkDelayedCommitCompletions = 0
  state.__loomarkDelayedCommitConcurrentPuts = 0
  state.__loomarkDelayedCommitInputs = 0
  state.__loomarkDelayedCommitPuts = []
  document.addEventListener("input", () => {
    if (state.__loomarkDelayedCommitActive) {
      state.__loomarkDelayedCommitInputs =
        (state.__loomarkDelayedCommitInputs ?? 0) + 1
    }
  })
  prototype.put = function(
    this: IDBObjectStore,
    value: unknown,
    recordKey?: IDBValidKey,
  ) {
    const request = originalPut.call(this, value, recordKey)
    if (recordKey === targetKey && typeof value === "string") {
      if (state.__loomarkDelayedCommitActive) {
        state.__loomarkDelayedCommitConcurrentPuts =
          (state.__loomarkDelayedCommitConcurrentPuts ?? 0) + 1
      }
      state.__loomarkDelayedCommitPuts?.push({
        at: performance.now(),
        value,
      })
      state.__loomarkDelayedCommitActive = true
      const store = this
      const transaction = this.transaction
      transaction.addEventListener("complete", () => {
        state.__loomarkDelayedCommitActive = false
        state.__loomarkDelayedCommitCompletions =
          (state.__loomarkDelayedCommitCompletions ?? 0) + 1
      })
      transaction.addEventListener("abort", () => {
        state.__loomarkDelayedCommitActive = false
      })
      const started = performance.now()
      const keepAlive = () => {
        if (performance.now() - started >= 500) return
        const keepAliveRequest = store.get(recordKey)
        keepAliveRequest.addEventListener("success", keepAlive)
      }
      keepAlive()
    }
    return request
  }
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

type PutObservation = {
  at: number
  value: string
}

function installDocumentPutLog(targetKey: string): void {
  const state = globalThis as typeof globalThis & {
    __loomarkDocumentPutLog?: PutObservation[]
  }
  const originalPut = IDBObjectStore.prototype.put
  state.__loomarkDocumentPutLog = []
  IDBObjectStore.prototype.put = function(
    this: IDBObjectStore,
    value: unknown,
    recordKey?: IDBValidKey,
  ) {
    if (recordKey === targetKey && typeof value === "string") {
      state.__loomarkDocumentPutLog?.push({ at: performance.now(), value })
    }
    return originalPut.call(this, value, recordKey)
  }
}

async function readDocumentPutLog(page: Page): Promise<PutObservation[]> {
  return page.evaluate(() => (
    (globalThis as typeof globalThis & {
      __loomarkDocumentPutLog?: PutObservation[]
    }).__loomarkDocumentPutLog ?? []
  ))
}

test("fresh production opens Text mode and preserves its textarea and undo history across modes", async ({ page }) => {
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
  await expect(text).toHaveValue("# Untitled\n")
  await expect(textTab).toHaveAttribute("aria-selected", "true")
  await expect(previewTab).toHaveAttribute("aria-selected", "false")
  await expect(splitTab).toHaveAttribute("aria-selected", "false")
  await expect.poll(() => readStoredDocument(page)).toEqual({
    document_id: expect.any(String),
    text: "# Untitled\n",
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
  if (await text.inputValue() !== "# Untitled\n") {
    await page.keyboard.press("Control+Z")
  }
  await expect(text).toHaveValue("# Untitled\n")
  expect(workerUrls).toEqual([])
})

test("baseline quota reports storage full without creating a Source", async ({ page }) => {
  await page.addInitScript(installDocumentPutFailure, { prefix: SOURCE_KEY_PREFIX })
  await page.goto("/")
  await expect(page.getByRole("heading", { name: "Document recovery" })).toBeVisible()
  await expect(page.getByText("Browser storage is full.")).toBeVisible()
  expect(await scanStoreRecords(page)).toEqual([])
})

test("opening and saving persist only authoritative Source records", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await expect(text).toHaveValue("# Untitled\n")
  await expect.poll(() => readStoredDocument(page)).not.toBeNull()
  const baseline = await readStoredDocument(page)
  if (!baseline) throw new Error("baseline Source missing")

  await text.fill("# Source only\n")
  await expect.poll(() => readStoredDocument(page)).toEqual({
    document_id: baseline.document_id,
    text: "# Source only\n",
  })
  await page.reload()
  await expect(text).toHaveValue("# Source only\n")
  expect(await scanStoreRecords(page)).toEqual([{
    key: sourceKey(baseline.document_id),
    value: encodeStoredDocument({
      document_id: baseline.document_id,
      text: "# Source only\n",
    }),
  }])
})

test("several Sources select the first lexical Document ID without writing metadata", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const documentA = { document_id: "document-a", text: "# Same\n" }
  const documentB = { document_id: "document-b", text: "# Same\n" }
  const documentC = { document_id: "document-c", text: "Body only\n" }
  await replaceStoreRecords(page, [
    { key: sourceKey(documentB.document_id), value: encodeStoredDocument(documentB) },
    { key: sourceKey(documentA.document_id), value: encodeStoredDocument(documentA) },
    { key: sourceKey(documentC.document_id), value: encodeStoredDocument(documentC) },
    { key: "source/v2/future", value: "future" },
  ])

  await page.reload()
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue(documentA.text)
  const documents = page.getByRole("complementary", { name: "Documents" })
  await expect(documents.getByRole("button", { name: "Same (1 of 2)" }))
    .toBeVisible()
  await expect(documents.getByRole("button", { name: "Same (2 of 2)" }))
    .toBeVisible()
  await expect(documents.getByRole("button", { name: "Unnamed document" }))
    .toBeVisible()
  expect(await readStoredDocumentRaw(page, CATALOG_KEY)).toBeUndefined()
  expect(await readStoredDocumentRaw(page, "source/v2/future")).toBe("future")
})

test("Document Sidebar switches saved Sources A to B to A without cross-document undo", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const documentA = { document_id: "document-a", text: "# A\n" }
  const documentB = { document_id: "document-b", text: "# B\n" }
  await replaceStoreRecords(page, [
    { key: sourceKey(documentA.document_id), value: encodeStoredDocument(documentA) },
    { key: sourceKey(documentB.document_id), value: encodeStoredDocument(documentB) },
  ])

  await page.reload()
  const documents = page.getByRole("complementary", { name: "Documents" })
  const text = page.getByRole("textbox", { name: "Text" })
  await expect(documents.getByRole("button", { name: "A", exact: true }))
    .toHaveAttribute("data-state", "active")
  await expect(documents.getByRole("button", { name: "B", exact: true }))
    .toBeVisible()

  await text.fill("# A edited\n")
  await expect.poll(() => readStoredDocumentRaw(page, sourceKey(documentA.document_id)))
    .toBe(encodeStoredDocument({ ...documentA, text: "# A edited\n" }))
  await page.getByRole("tab", { name: "Split" }).click()
  await expect(page.getByRole("heading", { name: "A edited" })).toBeVisible()

  await documents.getByRole("button", { name: "B", exact: true }).click()
  await expect(text).toHaveValue(documentB.text)
  await expect(page.getByRole("tab", { name: "Split" })).toHaveAttribute(
    "aria-selected",
    "true",
  )
  await expect(page.getByRole("heading", { name: "B" })).toBeVisible()
  await expect(page.getByRole("heading", { name: "A edited" })).toHaveCount(0)
  await text.focus()
  await page.keyboard.press("Control+Z")
  await expect(text).toHaveValue(documentB.text)

  await documents.getByRole("button", { name: "A edited", exact: true }).click()
  await expect(text).toHaveValue("# A edited\n")
  await expect(page.getByRole("heading", { name: "A edited" })).toBeVisible()
  expect(await readStoredDocumentRaw(page, sourceKey(documentB.document_id)))
    .toBe(encodeStoredDocument(documentB))
})

test("New Document commits one baseline Source before activating it", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const before = await readStoredDocuments(page)
  expect(before).toHaveLength(1)

  const documents = page.getByRole("complementary", { name: "Documents" })
  await page.getByRole("button", { name: "New document" }).click()
  await expect.poll(() => readStoredDocuments(page).then(documents => documents.length)).toBe(2)
  const after = await readStoredDocuments(page)
  const created = after.find(document => document.document_id !== before[0].document_id)
  if (!created) throw new Error("created Source missing")
  expect(created.text).toBe("# Untitled\n")
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue("# Untitled\n")
  await expect(documents.getByRole("button", { name: /^Untitled/ })).toHaveCount(2)
  await expect(documents.locator('[data-state="active"]')).toContainText("Untitled")

  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Project notes\n")
  await expect.poll(() => readStoredDocumentRaw(page, sourceKey(created.document_id)))
    .toBe(encodeStoredDocument({ ...created, text: "# Project notes\n" }))
  await expect(documents.locator('[data-state="active"]')).toContainText("Project notes")
  const renamed = await readStoredDocuments(page)

  await page.reload()
  await expect(documents.getByRole("button", { name: "Untitled", exact: true }))
    .toBeVisible()
  await expect(documents.getByRole("button", { name: "Project notes", exact: true }))
    .toBeVisible()
  expect(await readStoredDocuments(page)).toEqual(renamed)
})

test("creation failure preserves the active document and can retry", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const baseline = await readStoredDocument(page)
  if (!baseline) throw new Error("baseline Source missing")
  await page.evaluate(installDocumentPutFailure, { prefix: SOURCE_KEY_PREFIX })

  await page.getByRole("button", { name: "New document" }).click()
  await expect(page.getByRole("alert")).toContainText(
    "A new document could not be created. Browser storage is full.",
  )
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue(baseline.text)
  await expect(page.getByRole("complementary", { name: "Documents" })
    .locator('[data-state="active"]')).toContainText("Untitled")
  expect(await readStoredDocuments(page)).toEqual([baseline])

  await page.evaluate(removeDocumentPutFailure)
  await page.getByRole("button", { name: "Retry creating" }).click()
  await expect(page.getByRole("alert")).toHaveCount(0)
  await expect.poll(() => readStoredDocuments(page).then(documents => documents.length)).toBe(2)
})

test("Document controls remain accessible without horizontal overflow at 390 px", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto("/")
  await waitForRepositoryOpen(page)
  await expect(page.getByRole("button", { name: "Toggle documents" }))
    .toHaveAttribute("aria-expanded", "false")
  await page.getByRole("button", { name: "Documents", exact: true }).click()
  await expect(page.getByRole("button", { name: "New document" })).toBeVisible()
  await expect(page.getByRole("tab", { name: "Text" })).toBeVisible()
  await expect(page.getByRole("tab", { name: "Preview" })).toBeVisible()
  await expect(page.getByRole("tab", { name: "Split" })).toBeVisible()
  expect(await page.evaluate(() => ({
    viewport: window.innerWidth,
    scrollWidth: document.documentElement.scrollWidth,
  }))).toEqual({ viewport: 390, scrollWidth: 390 })
})

test("document action attempted before save stays on the active Source", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const documentA = { document_id: "document-a", text: "# A\n" }
  const documentB = { document_id: "document-b", text: "# B\n" }
  await replaceStoreRecords(page, [
    { key: sourceKey(documentA.document_id), value: encodeStoredDocument(documentA) },
    { key: sourceKey(documentB.document_id), value: encodeStoredDocument(documentB) },
  ])

  await page.reload()
  const text = page.getByRole("textbox", { name: "Text" })
  const documents = page.getByRole("complementary", { name: "Documents" })
  const documentAButton = documents.getByRole("button", { name: "A", exact: true })
  const documentBButton = documents.getByRole("button", { name: "B", exact: true })
  await text.pressSequentially("x")
  await expect(documentAButton).toBeEnabled()
  await expect(documentBButton).toBeDisabled()
  await expect(documentBButton).toHaveCSS("opacity", "0.5")
  await expect(page.getByRole("button", { name: "New document" })).toBeDisabled()
  await expect(documentAButton).toHaveAttribute("data-state", "active")
  await expect(text).toHaveValue("# A\nx")
  await expect(page.getByText("Wait for saving to finish.")).toHaveCount(0)
  await expect.poll(() => readStoredDocumentRaw(page, sourceKey(documentA.document_id)))
    .toBe(encodeStoredDocument({ ...documentA, text: "# A\nx" }))
  await expect(documentBButton).toBeEnabled()
  await expect(documentBButton).toHaveCSS("opacity", "1")
  await expect(page.getByRole("button", { name: "New document" })).toBeEnabled()
  await documentBButton.click()
  await expect(text).toHaveValue(documentB.text)
})

test("legacy active record migrates atomically and is removed", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const legacy = { document_id: "legacy-document", text: "# Legacy\n" }
  const encoded = encodeStoredDocument(legacy)
  await replaceStoreRecords(page, [{ key: LEGACY_ACTIVE_KEY, value: encoded }])

  await page.reload()
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue(legacy.text)
  await expect.poll(() => readStoredDocumentRaw(page, LEGACY_ACTIVE_KEY)).toBeUndefined()
  expect(await readStoredDocumentRaw(page, sourceKey(legacy.document_id))).toBe(encoded)
})

test("legacy collision preserves both records and opens a fresh baseline", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const legacy = { document_id: "legacy-collision", text: "# Legacy\n" }
  const encoded = encodeStoredDocument(legacy)
  const targetKey = sourceKey(legacy.document_id)
  await replaceStoreRecords(page, [
    { key: LEGACY_ACTIVE_KEY, value: encoded },
    { key: targetKey, value: "corrupt-target" },
  ])

  await page.reload()
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue("# Untitled\n")
  expect(await readStoredDocumentRaw(page, LEGACY_ACTIVE_KEY)).toBe(encoded)
  expect(await readStoredDocumentRaw(page, targetKey)).toBe("corrupt-target")
})

test("legacy migration failure rolls back the Source put and preserves active", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const legacy = { document_id: "legacy-rollback", text: "# Preserve\n" }
  const encoded = encodeStoredDocument(legacy)
  await replaceStoreRecords(page, [{ key: LEGACY_ACTIVE_KEY, value: encoded }])
  await page.addInitScript(key => {
    const prototype = IDBObjectStore.prototype
    const originalDelete = prototype.delete
    Object.defineProperty(prototype, "delete", {
      configurable: true,
      writable: true,
      value(this: IDBObjectStore, recordKey: IDBValidKey | IDBKeyRange) {
        if (recordKey === key) throw new DOMException("blocked", "InvalidStateError")
        return originalDelete.call(this, recordKey)
      },
    })
  }, LEGACY_ACTIVE_KEY)

  await page.reload()
  await expect(page.getByRole("heading", { name: "Document recovery" })).toBeVisible()
  expect(await readStoredDocumentRaw(page, LEGACY_ACTIVE_KEY)).toBe(encoded)
  expect(await readStoredDocumentRaw(page, sourceKey(legacy.document_id))).toBeUndefined()
})

test("unknown metadata is preserved and cannot override a Source", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const document = { document_id: "document-a", text: "# Current\n" }
  const metadata = JSON.stringify({
    entries: [{ document_id: "document-a", name: "Stale" }],
  })
  await replaceStoreRecords(page, [
    { key: sourceKey(document.document_id), value: encodeStoredDocument(document) },
    { key: CATALOG_KEY, value: metadata },
  ])

  await page.reload()
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue(document.text)
  expect(await readStoredDocumentRaw(page, CATALOG_KEY)).toBe(metadata)
})

test("IndexedDB cursor scan measures 10, 100, and 1000 Source records", async ({ page }, testInfo) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const largeBody = "Representative large Markdown paragraph.\n\n".repeat(256)
  for (const count of [10, 100, 1000]) {
    const records = Array.from({ length: count }, (_, index): StoreRecord => {
      const document = {
        document_id: `scan-${index}`,
        text: `# Scan ${index}\n\n${index % 100 === 0 ? largeBody : "Small body.\n"}`,
      }
      return {
        key: sourceKey(document.document_id),
        value: encodeStoredDocument(document),
      }
    })
    await replaceStoreRecords(page, records)
    const samples: number[] = []
    for (let sample = 0; sample < 5; sample += 1) {
      const measurement = await measureIndexedDbScan(page)
      expect(measurement.count).toBe(count)
      samples.push(measurement.durationMs)
    }
    samples.sort((left, right) => left - right)
    const median = samples[Math.floor(samples.length / 2)]
    testInfo.annotations.push({
      type: "indexeddb-scan-median",
      description: `${count} Sources: ${median.toFixed(3)} ms`,
    })
    console.log(`IndexedDB scan ${count} Sources median: ${median.toFixed(3)} ms`)
  }
})

test("IndexedDB Source put measures small and 1 MiB records", async ({ page }, testInfo) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  for (const [name, text] of [
    ["small", "# Small\n"],
    ["1 MiB", `# Large\n${"x".repeat(1024 * 1024)}`],
  ] as const) {
    const document = { document_id: `put-${name}`, text }
    const key = sourceKey(document.document_id)
    const encoded = encodeStoredDocument(document)
    const samples: number[] = []
    for (let sample = 0; sample < 5; sample += 1) {
      samples.push(await measureIndexedDbPut(page, key, encoded))
    }
    samples.sort((left, right) => left - right)
    const median = samples[Math.floor(samples.length / 2)]
    testInfo.annotations.push({
      type: "indexeddb-put-median",
      description: `${name} Source: ${median.toFixed(3)} ms`,
    })
    console.log(`IndexedDB put ${name} Source median: ${median.toFixed(3)} ms`)
    expect(await readStoredDocumentRaw(page, key)).toBe(encoded)
  }
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
  await page.context().route("https://example.test/", route => route.fulfill({
    status: 200,
    contentType: "text/html",
    body: "External preview link opened",
  }))
  const popupPromise = page.waitForEvent("popup")
  await link.click()
  const popup = await popupPromise
  await expect.poll(() => popup.url()).toBe("https://example.test/")
  await popup.close()
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

test("Preview keeps incomplete Markdown literal without parser chrome", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("𐐀[unclosed\n")
  await page.getByRole("tab", { name: "Preview" }).click()

  const preview = page.getByRole("region", { name: "Markdown preview" })
  await expect(preview).toContainText("𐐀[unclosed")
  await expect(preview).not.toContainText("Recovered Markdown")
  await expect(preview).not.toContainText("Raw Markdown")
  await expect(preview.locator('[data-loomark-preview-fallback]')).toHaveCount(0)
  await expect(preview.locator('[data-loomark-preview-diagnostic]')).toHaveCount(0)
  await expect(preview.locator("p > div")).toHaveCount(0)

  await page.getByRole("tab", { name: "Text" }).click()
  await text.fill("[text](\n")
  await page.getByRole("tab", { name: "Preview" }).click()
  await expect(preview).toContainText("[text](")
  await expect(preview).not.toContainText("Diagnostic:")
})

test("Tailwind Typography and utilities preserve the Loomark shell and reading measure", async ({ page }) => {
  await page.setViewportSize({ width: 900, height: 700 })
  await page.goto("/")
  await expect(page.getByRole("textbox", { name: "Text" })).toBeVisible()

  const styles = await page.evaluate(() => {
    const modeBar = document.querySelector('[role="tablist"]')?.closest("header") as HTMLElement
    const selectedTab = document.querySelector('[role="tab"][aria-selected="true"]') as HTMLElement
    const text = document.getElementById("loomark-text") as HTMLTextAreaElement
    return {
      bodyMargin: getComputedStyle(document.body).margin,
      boxSizing: getComputedStyle(document.documentElement).boxSizing,
      modeBarDisplay: getComputedStyle(modeBar).display,
      modeBarMinHeight: getComputedStyle(modeBar).minHeight,
      selectedBackground: getComputedStyle(selectedTab).backgroundColor,
      textFont: getComputedStyle(text).fontFamily,
      textPaddingLeft: Number.parseFloat(getComputedStyle(text).paddingLeft),
    }
  })
  expect(styles.bodyMargin).toBe("0px")
  expect(styles.boxSizing).toBe("border-box")
  expect(styles.modeBarDisplay).toBe("flex")
  expect(styles.modeBarMinHeight).toBe("44px")
  expect(styles.selectedBackground).not.toBe("rgba(0, 0, 0, 0)")
  expect(styles.textFont).toContain("ui-monospace")
  expect(styles.textPaddingLeft).toBeGreaterThanOrEqual(48)

  await page.setViewportSize({ width: 640, height: 700 })
  await expect.poll(() => page.locator("#loomark-text").evaluate(element => (
    getComputedStyle(element).paddingLeft
  ))).toBe("12px")

  await page.getByRole("button", {
    name: "Apply Markdown feature tour example",
  }).click()
  await page.getByRole("tab", { name: "Preview" }).click()
  const preview = page.getByRole("region", { name: "Markdown preview" })
  await expect(preview.locator("ul").first()).toBeVisible()
  expect(await preview.locator("ul").first().evaluate(element => (
    getComputedStyle(element).listStyleType
  ))).toBe("disc")
  expect(await preview.locator("ol").first().evaluate(element => (
    getComputedStyle(element).listStyleType
  ))).toBe("decimal")
  expect(await preview.locator("hr").first().evaluate(element => (
    Number.parseFloat(getComputedStyle(element).width)
  ))).toBeGreaterThan(400)
  expect(Number.parseFloat(await preview.locator("pre code").first()
    .evaluate(element => getComputedStyle(element).lineHeight))).toBeCloseTo(17.14, 1)
  expect(await preview.locator("p code").first().evaluate(element => ({
    before: getComputedStyle(element, "::before").content,
    after: getComputedStyle(element, "::after").content,
  }))).toEqual({ before: "none", after: "none" })
  await expect.poll(() => preview.locator("p").first().evaluate(element => (
    getComputedStyle(element).fontSize
  ))).toBe("14px")
  expect(await preview.locator("p").first().evaluate(element => (
    getComputedStyle(element).marginTop
  ))).toBe("18px")
  expect(await preview.locator("h2").first().evaluate(element => (
    getComputedStyle(element).marginTop
  ))).toBe("28px")

  await page.setViewportSize({ width: 1280, height: 700 })
  await expect.poll(() => preview.locator("p").first().evaluate(element => (
    getComputedStyle(element).fontSize
  ))).toBe("18px")
})

test("RUI mode tabs activate with roving keyboard focus", async ({ page }) => {
  await page.goto("/")

  const textTab = page.getByRole("tab", { name: "Text" })
  const previewTab = page.getByRole("tab", { name: "Preview" })
  const splitTab = page.getByRole("tab", { name: "Split" })
  const editorPanel = page.locator("#loomark-editor-panel")
  const preview = page.getByRole("region", { name: "Markdown preview" })

  await expect(textTab).toHaveAttribute("aria-selected", "true")
  await expect(editorPanel).toHaveAttribute("aria-labelledby", "loomark-mode-text")
  await textTab.focus()

  await page.keyboard.press("ArrowRight")
  await expect(previewTab).toBeFocused()
  await expect(previewTab).toHaveAttribute("aria-selected", "true")
  await expect(editorPanel).toHaveAttribute(
    "aria-labelledby",
    "loomark-mode-preview",
  )
  await expect(preview).toBeVisible()

  await page.keyboard.press("ArrowRight")
  await expect(splitTab).toBeFocused()
  await expect(splitTab).toHaveAttribute("aria-selected", "true")
  await expect(editorPanel).toHaveAttribute("aria-labelledby", "loomark-mode-split")
  await expect(page.getByRole("textbox", { name: "Text" })).toBeVisible()
  await expect(preview).toBeVisible()

  await page.keyboard.press("ArrowLeft")
  await expect(previewTab).toBeFocused()
  await expect(previewTab).toHaveAttribute("aria-selected", "true")
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
  const separatorBox = await separator.boundingBox()
  const gripBox = await page.locator('[data-slot="resizable-handle-grip"]')
    .boundingBox()
  expect(groupBox).not.toBeNull()
  expect(separatorBox).not.toBeNull()
  expect(gripBox).not.toBeNull()
  if (!groupBox || !separatorBox || !gripBox) {
    throw new Error("Split resize geometry missing")
  }
  expect(Math.abs(separatorBox.height - groupBox.height)).toBeLessThanOrEqual(1)
  await page.mouse.move(gripBox.x + gripBox.width / 2, gripBox.y + gripBox.height / 2)
  await page.mouse.down()
  await page.mouse.move(groupBox.x + groupBox.width * 0.9, groupBox.y + groupBox.height / 2)
  await page.mouse.up()
  await expect(resize).toHaveValue("75")

  await page.setViewportSize({ width: 640, height: 700 })
  await expect(separator).toHaveAttribute("aria-orientation", "horizontal")
  await expect(resize).toHaveValue("50")
  const compactGroupBox = await page.locator("#loomark-editor-panels").boundingBox()
  const compactSeparatorBox = await separator.boundingBox()
  expect(compactGroupBox).not.toBeNull()
  expect(compactSeparatorBox).not.toBeNull()
  if (!compactGroupBox || !compactSeparatorBox) {
    throw new Error("Compact Split resize geometry missing")
  }
  expect(Math.abs(compactSeparatorBox.width - compactGroupBox.width))
    .toBeLessThanOrEqual(4)
  expect(await page.evaluate(() => (
    (globalThis as typeof globalThis & { __loomarkTextArea?: HTMLTextAreaElement })
      .__loomarkTextArea === document.getElementById("loomark-text")
  ))).toBe(true)
  await expect(text).toHaveValue("# Stable textarea\n")
  await resize.focus()
  await page.keyboard.press("ArrowDown")
  await expect(resize).toHaveValue("51")
})

test("Example documents immediately replace the active Document", async ({ page }) => {
  await page.goto("/")

  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Work in progress\n")
  const examples = page.getByRole("toolbar", { name: "Example documents" })

  await examples.getByRole("button", {
    name: "Apply Markdown feature tour example",
  }).click()
  await expect(text).toHaveValue(/^# Markdown Feature Tour\n/)

  await examples.getByRole("button", { name: "Apply Hello example" }).click()
  await expect(text).toHaveValue(
    "# Hello World\n\nWelcome to Loomark.\n\n" +
      "Use Text to edit Markdown, Preview to read the rendered document, " +
      "and Split to work with both at once.\n",
  )

  await examples.getByRole("button", { name: "Guide: Apply Blog example" }).click()
  await expect(text).toHaveValue(
    "# Getting Started\n\nLoomark is a source-first incremental Markdown editor.\n\n" +
      "## Features\n\nText remains the editing authority.\n\n" +
      "Preview and Split share one read-only rendered result that updates " +
      "from precise browser edits.",
  )

  await examples.getByRole("button", { name: "Apply List example" }).click()
  await expect(text).toHaveValue(
    "# Shopping List\n\nThings to pick up:\n\n" +
      "- Apples\n- Bread\n- Coffee\n- Dark chocolate",
  )

  await examples.getByRole("button", { name: "Apply Code example" }).click()
  await expect(text).toHaveValue(/^# README\n/)
  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toMatch(/^# README\n/)
})

test("Split keeps Text and Preview independently scrollable", async ({ page }) => {
  await page.setViewportSize({ width: 900, height: 700 })
  await page.goto("/")

  const source = Array.from({ length: 80 }, (_, index) => (
    `## Section ${index}\n\nParagraph ${index} with enough text for both panes.`
  )).join("\n\n")
  const text = page.getByRole("textbox", { name: "Text" })
  const preview = page.getByRole("region", { name: "Markdown preview" })
  await text.fill(source)
  await page.getByRole("tab", { name: "Split" }).click()
  await expect(preview.getByRole("heading", { name: "Section 79" })).toBeVisible()

  const assertIndependentScroll = async () => {
    const metrics = await page.evaluate(() => {
      const textarea = document.getElementById("loomark-text") as HTMLTextAreaElement
      const textPane = document.getElementById("loomark-text-pane") as HTMLElement
      const previewScroll = document.getElementById("loomark-preview-scroll") as HTMLElement
      const textareaBox = textarea.getBoundingClientRect()
      const textPaneBox = textPane.getBoundingClientRect()
      textarea.scrollTop = 120
      previewScroll.scrollTop = 240
      return {
        text: {
          clientHeight: textarea.clientHeight,
          scrollHeight: textarea.scrollHeight,
          scrollTop: textarea.scrollTop,
          rightEdgeOffset: Math.abs(textareaBox.right - textPaneBox.right),
        },
        preview: {
          clientHeight: previewScroll.clientHeight,
          scrollHeight: previewScroll.scrollHeight,
          scrollTop: previewScroll.scrollTop,
        },
      }
    })
    expect(metrics.text.scrollHeight).toBeGreaterThan(metrics.text.clientHeight)
    expect(metrics.preview.scrollHeight).toBeGreaterThan(metrics.preview.clientHeight)
    expect(metrics.text.scrollTop).toBeGreaterThan(0)
    expect(metrics.text.rightEdgeOffset).toBeLessThanOrEqual(1)
    expect(metrics.preview.scrollTop).toBeGreaterThan(0)
  }

  await assertIndependentScroll()
  await page.setViewportSize({ width: 640, height: 700 })
  await expect(page.getByRole("separator")).toHaveAttribute(
    "aria-orientation",
    "horizontal",
  )
  await assertIndependentScroll()
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

test("exact acknowledged revert restores Saved without a redundant put", async ({ page }) => {
  await page.goto("/")
  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe("# Untitled\n")
  const baseline = await readStoredDocument(page)
  if (!baseline) throw new Error("baseline Source missing")
  await page.evaluate(installDocumentPutLog, sourceKey(baseline.document_id))

  const text = page.getByRole("textbox", { name: "Text" })
  await text.evaluate(element => {
    const textarea = element as HTMLTextAreaElement
    for (const value of ["# Draft\n", "# Untitled\n"]) {
      textarea.value = value
      textarea.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        composed: true,
        data: value,
        inputType: "insertText",
      }))
    }
  })

  await expect(page.getByRole("button", { name: "New document" })).toBeEnabled()
  await page.waitForTimeout(2_250)
  expect(await readDocumentPutLog(page)).toEqual([])
  expect((await readStoredDocument(page))?.text).toBe("# Untitled\n")
})

test("equal-text ABA still receives a full trailing quiet window", async ({ page }) => {
  await page.goto("/")
  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe("# Untitled\n")
  const baseline = await readStoredDocument(page)
  if (!baseline) throw new Error("baseline Source missing")
  await page.evaluate(installDocumentPutLog, sourceKey(baseline.document_id))

  const text = page.getByRole("textbox", { name: "Text" })
  const finalInputAt = await text.evaluate(async element => {
    const textarea = element as HTMLTextAreaElement
    const values = ["# B\n", "# C\n", "# B\n"]
    let finalInputAt = 0
    for (const [index, value] of values.entries()) {
      textarea.value = value
      finalInputAt = performance.now()
      textarea.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        composed: true,
        data: value,
        inputType: "insertText",
      }))
      if (index < values.length - 1) {
        await new Promise(resolve => setTimeout(resolve, 100))
      }
    }
    return finalInputAt
  })

  await page.waitForTimeout(150)
  expect(await readDocumentPutLog(page)).toEqual([])
  await expect.poll(() => readDocumentPutLog(page)).toHaveLength(1)
  const [put] = await readDocumentPutLog(page)
  expect(put.at - finalInputAt).toBeGreaterThanOrEqual(250)
})

test("uninterrupted input reaches maximum eligibility without final quiet", async ({ page }) => {
  await page.goto("/")
  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe("# Untitled\n")
  const baseline = await readStoredDocument(page)
  if (!baseline) throw new Error("baseline Source missing")
  const text = page.getByRole("textbox", { name: "Text" })
  await page.evaluate(installDocumentPutLog, sourceKey(baseline.document_id))

  const stream = await text.evaluate(async element => {
    const textarea = element as HTMLTextAreaElement
    const started = performance.now()
    let previousInput = started
    const inputGaps: number[] = []
    for (let index = 0; index < 46; index += 1) {
      const inputStarted = performance.now()
      if (index > 0) inputGaps.push(inputStarted - previousInput)
      previousInput = inputStarted
      const value = `${textarea.value}x`
      textarea.value = value
      textarea.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        composed: true,
        data: "x",
        inputType: "insertText",
      }))
      await new Promise(resolve => setTimeout(resolve, 50))
    }
    return {
      started,
      finalText: textarea.value,
      maximumInputGap: Math.max(...inputGaps),
    }
  })

  expect(stream.maximumInputGap).toBeLessThan(250)
  const duringStream = await readDocumentPutLog(page)
  expect(duringStream.length).toBeGreaterThanOrEqual(1)
  const firstPutOffset = duringStream[0].at - stream.started
  expect(firstPutOffset).toBeGreaterThanOrEqual(1_800)
  expect(firstPutOffset).toBeLessThan(3_000)

  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe(stream.finalText)
  const completed = await readDocumentPutLog(page)
  expect(completed.length).toBe(2)
})

test("large active-write overlap remains coalesced", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const baseline = await readStoredDocument(page)
  if (!baseline) throw new Error("baseline Source missing")
  const largeText = `# Large\n${"x".repeat(1024 * 1024)}`
  await replaceStoreRecords(page, [
    {
      key: sourceKey(baseline.document_id),
      value: encodeStoredDocument({ ...baseline, text: largeText }),
    },
  ])
  await page.reload()
  const text = page.getByRole("textbox", { name: "Text" })
  await expect(text).toHaveValue(largeText)
  await page.evaluate(
    installDelayedDocumentCommit,
    sourceKey(baseline.document_id),
  )

  const stream = await text.evaluate(async element => {
    const textarea = element as HTMLTextAreaElement
    const started = performance.now()
    let previousInput = started
    const inputGaps: number[] = []
    for (let index = 0; index < 46; index += 1) {
      const inputStarted = performance.now()
      if (index > 0) inputGaps.push(inputStarted - previousInput)
      previousInput = inputStarted
      textarea.value = `${textarea.value}x`
      textarea.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        composed: true,
        data: "x",
        inputType: "insertText",
      }))
      await new Promise(resolve => setTimeout(resolve, 50))
    }
    return {
      duration: performance.now() - started,
      finalText: textarea.value,
      maximumInputGap: Math.max(...inputGaps),
    }
  })

  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe(stream.finalText)
  const overlap = await page.evaluate(() => {
    const state = globalThis as typeof globalThis & {
      __loomarkDelayedCommitCompletions?: number
      __loomarkDelayedCommitConcurrentPuts?: number
      __loomarkDelayedCommitInputs?: number
      __loomarkDelayedCommitPuts?: PutObservation[]
    }
    return {
      completions: state.__loomarkDelayedCommitCompletions ?? 0,
      concurrentPuts: state.__loomarkDelayedCommitConcurrentPuts ?? 0,
      inputs: state.__loomarkDelayedCommitInputs ?? 0,
      puts: state.__loomarkDelayedCommitPuts ?? [],
    }
  })
  expect(stream.maximumInputGap).toBeLessThan(250)
  expect(overlap.inputs).toBeGreaterThan(0)
  expect(overlap.completions).toBeGreaterThanOrEqual(1)
  expect(overlap.concurrentPuts).toBe(0)
  expect(overlap.puts.length).toBeGreaterThanOrEqual(2)
  const maximumPolicyWrites = Math.ceil(stream.duration / 2_000) + 1
  expect(overlap.puts.length).toBeLessThanOrEqual(maximumPolicyWrites)
  expect((JSON.parse(overlap.puts[0].value) as StoredDocument).text)
    .not.toBe(stream.finalText)
  expect((JSON.parse(overlap.puts.at(-1)?.value ?? "null") as StoredDocument).text)
    .toBe(stream.finalText)
})

test("hidden visibility makes pending text eligible before quiet", async ({ page }) => {
  await page.goto("/")
  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe("# Untitled\n")
  const baseline = await readStoredDocument(page)
  if (!baseline) throw new Error("baseline Source missing")
  await page.evaluate(installDocumentPutLog, sourceKey(baseline.document_id))
  const text = page.getByRole("textbox", { name: "Text" })
  const changedAt = await text.evaluate(async element => {
    const textarea = element as HTMLTextAreaElement
    textarea.value = "# Hidden checkpoint\n"
    const changedAt = performance.now()
    textarea.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      composed: true,
      data: textarea.value,
      inputType: "insertText",
    }))
    Object.defineProperty(document, "hidden", {
      configurable: true,
      get: () => true,
    })
    document.dispatchEvent(new Event("visibilitychange"))
    return changedAt
  })
  await expect.poll(() => page.evaluate(() => document.hidden)).toBe(true)
  await expect.poll(() => readDocumentPutLog(page).then(log => log.length))
    .toBeGreaterThanOrEqual(1)
  const [firstPut] = await readDocumentPutLog(page)
  expect(firstPut.at - changedAt).toBeLessThan(250)
  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe("# Hidden checkpoint\n")
  await page.evaluate(() => {
    delete (document as unknown as { hidden?: boolean }).hidden
  })
})

test("rapid Text input writes only the latest text", async ({ page }) => {
  await page.goto("/")
  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe("# Untitled\n")
  const initial = await readStoredDocument(page)
  if (!initial) throw new Error("baseline Source missing")
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
  }, sourceKey(initial.document_id))

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
  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe("# Untitled\n")

  const text = page.getByRole("textbox", { name: "Text" })
  await text.evaluate(element => {
    const textarea = element as HTMLTextAreaElement
    textarea.setSelectionRange(0, textarea.value.length)
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
  expect((await readStoredDocument(page))?.text).toBe("# Untitled\n")

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

test("no-op IME composition arms no Autosave checkpoint", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const baseline = await readStoredDocument(page)
  if (!baseline) throw new Error("baseline Source missing")
  await page.evaluate(installDocumentPutLog, sourceKey(baseline.document_id))

  const text = page.getByRole("textbox", { name: "Text" })
  await text.evaluate(element => {
    const textarea = element as HTMLTextAreaElement
    textarea.dispatchEvent(new CompositionEvent("compositionstart", {
      bubbles: true,
    }))
    textarea.dispatchEvent(new CompositionEvent("compositionend", {
      bubbles: true,
      data: textarea.value,
    }))
  })

  await page.waitForTimeout(2_250)
  expect(await readDocumentPutLog(page)).toEqual([])
  expect((await readStoredDocument(page))?.text).toBe(baseline.text)
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
    text: "# Untitled\n",
  })
  const baseline = await readStoredDocument(page)
  if (!baseline) throw new Error("baseline Source missing")
  await page.evaluate(installDocumentPutFailure, sourceKey(baseline.document_id))

  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Not saved\n")
  await expect(page.getByRole("alert")).toContainText(
    "Changes are not saved in this browser. Browser storage is full.",
  )
  await text.fill("# Latest text\n")
  await expect(text).toHaveValue("# Latest text\n")
  await page.waitForTimeout(300)
  expect((await readStoredDocument(page))?.text).toBe("# Untitled\n")

  await page.evaluate(removeDocumentPutFailure)
  await page.getByRole("button", { name: "Retry saving" }).click()
  await expect(page.getByRole("alert")).toHaveCount(0)
  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe("# Latest text\n")
  await page.reload()
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue("# Latest text\n")
})

test("failed attempt exact acknowledged revert restores truthful Saved", async ({ page }) => {
  await page.goto("/")
  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe("# Untitled\n")
  const baseline = await readStoredDocument(page)
  if (!baseline) throw new Error("baseline Source missing")
  await page.evaluate(installDocumentPutFailure, sourceKey(baseline.document_id))

  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Not saved\n")
  await expect(page.getByRole("alert")).toContainText("Changes are not saved")
  const failedCalls = await page.evaluate(() => (
    (globalThis as typeof globalThis & {
      __loomarkDocumentPutFailureCalls?: number
    }).__loomarkDocumentPutFailureCalls ?? 0
  ))
  expect(failedCalls).toBe(1)

  await text.fill("# Untitled\n")
  await expect(page.getByRole("alert")).toHaveCount(0)
  await expect(page.getByRole("button", { name: "New document" })).toBeEnabled()
  await page.waitForTimeout(300)
  const callsAfterRevert = await page.evaluate(() => (
    (globalThis as typeof globalThis & {
      __loomarkDocumentPutFailureCalls?: number
    }).__loomarkDocumentPutFailureCalls ?? 0
  ))
  expect(callsAfterRevert).toBe(failedCalls)
  expect((await readStoredDocument(page))?.text).toBe("# Untitled\n")
})

test("active failure after acknowledged revert restores truthful Saved", async ({ page }) => {
  await page.goto("/")
  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe("# Untitled\n")
  const baseline = await readStoredDocument(page)
  if (!baseline) throw new Error("baseline Source missing")
  await page.evaluate(installDelayedDocumentAbort, sourceKey(baseline.document_id))

  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# In flight\n")
  await expect.poll(() => page.evaluate(() => (
    (globalThis as typeof globalThis & {
      __loomarkDelayedAbortStarted?: boolean
    }).__loomarkDelayedAbortStarted ?? false
  ))).toBe(true)
  await text.fill("# Untitled\n")
  await expect.poll(() => page.evaluate(() => (
    (globalThis as typeof globalThis & {
      __loomarkDelayedAbortFinished?: boolean
    }).__loomarkDelayedAbortFinished ?? false
  ))).toBe(true)

  await expect(page.getByRole("alert")).toHaveCount(0)
  await expect(page.getByRole("button", { name: "New document" })).toBeEnabled()
  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe("# Untitled\n")
})

test("saving one Source preserves unrelated Sources and unknown metadata", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const documentA = { document_id: "document-a", text: "# A\n" }
  const documentB = { document_id: "document-b", text: "# B\n" }
  const encodedB = encodeStoredDocument(documentB)
  const catalogMetadata = "opaque-catalog"
  const futureMetadata = "opaque-future"
  await replaceStoreRecords(page, [
    { key: sourceKey(documentA.document_id), value: encodeStoredDocument(documentA) },
    { key: sourceKey(documentB.document_id), value: encodedB },
    { key: CATALOG_KEY, value: catalogMetadata },
    { key: "metadata/v2/future", value: futureMetadata },
  ])

  await page.reload()
  const text = page.getByRole("textbox", { name: "Text" })
  await expect(text).toHaveValue(documentA.text)
  await text.fill("# Updated A\n")
  await expect.poll(() => readStoredDocumentRaw(page, sourceKey(documentA.document_id)))
    .toBe(encodeStoredDocument({ ...documentA, text: "# Updated A\n" }))
  await page.reload()
  await expect(text).toHaveValue("# Updated A\n")
  expect(await readStoredDocumentRaw(page, sourceKey(documentB.document_id))).toBe(encodedB)
  expect(await readStoredDocumentRaw(page, CATALOG_KEY)).toBe(catalogMetadata)
  expect(await readStoredDocumentRaw(page, "metadata/v2/future")).toBe(futureMetadata)
  expect((await scanStoreRecords(page)).map(record => record.key)).toEqual([
    CATALOG_KEY,
    "metadata/v2/future",
    sourceKey(documentA.document_id),
    sourceKey(documentB.document_id),
  ])
})

test("valid and corrupt Source records coexist without overwriting corruption", async ({ page }) => {
  const invalidDocument = "not-json"
  const corruptKey = sourceKey("corrupt-document")
  await page.goto("/")
  await expect.poll(() => readStoredDocument(page)).not.toBeNull()
  const baseline = await readStoredDocument(page)
  if (!baseline) throw new Error("baseline Source missing")
  await writeStoredDocumentRaw(page, corruptKey, invalidDocument)

  await page.reload()
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue(baseline.text)
  await expect(page.getByRole("heading", { name: "Document recovery" })).toHaveCount(0)
  expect(await readStoredDocumentRaw(page, corruptKey)).toBe(invalidDocument)
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

test("1 MiB exact Saved comparison stays within 10 ms", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const baseline = await readStoredDocument(page)
  if (!baseline) throw new Error("baseline Source missing")
  const largeText = `# Equality fixture\n${"x".repeat(1024 * 1024)}`
  await replaceStoreRecords(page, [
    {
      key: sourceKey(baseline.document_id),
      value: encodeStoredDocument({ ...baseline, text: largeText }),
    },
  ])
  await page.reload()
  const text = page.getByRole("textbox", { name: "Text" })
  await expect(text).toHaveValue(largeText)
  await page.evaluate(installDocumentPutLog, sourceKey(baseline.document_id))

  const durations = await text.evaluate(element => {
    const textarea = element as HTMLTextAreaElement
    const baseLast = textarea.value.at(-1)
    if (!baseLast) throw new Error("large fixture is empty")
    const dispatchReplacement = (replacement: string) => {
      const end = textarea.value.length
      textarea.setSelectionRange(end - 1, end)
      textarea.dispatchEvent(new InputEvent("beforeinput", {
        bubbles: true,
        cancelable: true,
        composed: true,
        data: replacement,
        inputType: "insertReplacementText",
      }))
      textarea.setRangeText(replacement, end - 1, end, "end")
      textarea.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        composed: true,
        data: replacement,
        inputType: "insertReplacementText",
      }))
    }
    for (let index = 0; index < 10; index += 1) {
      dispatchReplacement("y")
      dispatchReplacement(baseLast)
    }
    return Array.from({ length: 25 }, () => {
      const dirtyStarted = performance.now()
      dispatchReplacement("y")
      const dirtyDuration = performance.now() - dirtyStarted
      const revertStarted = performance.now()
      dispatchReplacement(baseLast)
      return [dirtyDuration, performance.now() - revertStarted]
    }).flat()
  })

  const sorted = [...durations].sort((left, right) => left - right)
  expect(sorted[Math.ceil(sorted.length * 0.95) - 1]).toBeLessThanOrEqual(10)
  expect(sorted[sorted.length - 1]).toBeLessThanOrEqual(10)
  await expect(page.getByRole("button", { name: "New document" })).toBeEnabled()
  await page.waitForTimeout(350)
  expect(await readDocumentPutLog(page)).toEqual([])
})
