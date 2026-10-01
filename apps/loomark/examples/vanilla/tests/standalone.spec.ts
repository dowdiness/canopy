import { expect, test, type Locator, type Page } from "@playwright/test"

const DOCUMENT_DATABASE_NAME = "loomark"
const DOCUMENT_DATABASE_VERSION = 1
const DOCUMENT_STORE_NAME = "documents"
const LEGACY_ACTIVE_KEY = "active"
const EDITING_DOCUMENT_KEY = "editing-document"
const SOURCE_KEY_PREFIX = "source/v1/"
const REPLICA_KEY_PREFIX = "replica/"
const CATALOG_KEY = "catalog/v1"

test("document activation lets keyboard users continue writing immediately", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# First document\n")
  await expect.poll(() => readStoredDocument(page)).toMatchObject({ text: "# First document\n" })
  const create = page.getByRole("button", { name: "New document", exact: true }).first()
  await create.focus()
  await create.press("Enter")
  await expect(text).toHaveValue("")
  await expect(text).toBeFocused()
  await page.keyboard.type("# Second document\n")
  await expect(text).toHaveValue("# Second document\n")
  await expect.poll(() => readStoredDocuments(page)).toHaveLength(2)
  const first = page.getByRole("button", { name: "First document", exact: true })
  await first.focus()
  await first.press("Enter")
  await expect(text).toHaveValue("# First document\n")
  await expect(text).toBeFocused()
  await page.keyboard.press("Control+End")
  await page.keyboard.type("Continued")
  await expect(text).toHaveValue("# First document\nContinued")
})

test("responsive reflow preserves native text selection and undo", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await page.getByRole("button", { name: "Toggle documents" }).click()
  await text.fill("# Writing\n\n日本語 and English\n")
  await text.press("Control+End")
  await text.pressSequentially("continued")
  await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    area.setSelectionRange(2, 7, "backward")
    ;(window as typeof window & { __continuityArea?: HTMLTextAreaElement }).__continuityArea = area
  })
  for (const width of [390, 1280, 390, 1280]) {
    await page.setViewportSize({ width, height: 844 })
    await expect(text).toHaveValue("# Writing\n\n日本語 and English\ncontinued")
    expect(await text.evaluate(element => ({
      same: element === (window as typeof window & { __continuityArea?: HTMLTextAreaElement }).__continuityArea,
      start: (element as HTMLTextAreaElement).selectionStart,
      end: (element as HTMLTextAreaElement).selectionEnd,
      direction: (element as HTMLTextAreaElement).selectionDirection,
    }))).toEqual({ same: true, start: 2, end: 7, direction: "backward" })
  }
  await text.focus()
  await page.keyboard.press("Control+Z")
  await expect(text).toHaveValue("# Writing\n\n日本語 and English\n")
})

test("Escape from More actions returns keyboard focus to its trigger", async ({ page }) => {
  await page.goto("/")
  await expect(page.getByRole("textbox", { name: "Text" })).toBeVisible()
  const more = page.getByRole("button", { name: "More actions", exact: true })
  await more.focus()
  await more.press("Enter")
  await expect(more).toHaveAttribute("aria-expanded", "true")
  const exportAction = page.locator(".loomark-menu").getByRole("button", { name: "Export Markdown" })
  await exportAction.focus()
  await page.keyboard.press("Escape")
  await expect(more).toHaveAttribute("aria-expanded", "false")
  await expect(more).toBeFocused()
  await page.keyboard.press("Enter")
  await expect(exportAction).toBeVisible()
})

test("compact document activation closes navigation and Preview retains a keyboard destination", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Mobile document\n")
  await expect.poll(() => readStoredDocument(page)).toMatchObject({ text: "# Mobile document\n" })
  await page.getByRole("button", { name: "New document", exact: true }).press("Enter")
  await expect(text).toHaveValue("")
  await expect(text).toBeFocused()
  const toggle = page.getByRole("button", { name: "Toggle documents" })
  await toggle.click()
  await page.getByRole("button", { name: "Mobile document", exact: true }).press("Enter")
  await expect(toggle).toHaveAttribute("aria-expanded", "false")
  await expect(text).toBeFocused()
  await expect(text).toHaveValue("# Mobile document\n")

  const preview = page.getByRole("tab", { name: "Preview", exact: true })
  await preview.click()
  await page.getByRole("button", { name: "New document", exact: true }).press("Enter")
  await expect(preview).toBeFocused()
  await expect(preview).toHaveAttribute("aria-selected", "true")
  await expect(text).toBeHidden()
  await preview.press("ArrowLeft")
  await expect(page.getByRole("tab", { name: "Split", exact: true })).toBeFocused()
  await expect(text).toBeVisible()
  await expect(text).toHaveValue("")
})

test("compact sidebar preserves keyboard traversal and toggle recovery", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Keyboard navigation\n")
  const toggle = page.getByRole("button", { name: "Toggle documents" })
  await toggle.click()
  const sidebar = page.locator("#loomark-document-sidebar")
  await expect(sidebar).toHaveAttribute("aria-hidden", "false")
  const controls = sidebar.locator('button:visible:not([disabled]):not([tabindex="-1"]), a[href]:visible:not([tabindex="-1"]), input:visible:not([disabled]):not([tabindex="-1"])')
  await expect.poll(() => controls.count()).toBeGreaterThan(1)
  await expect(controls.first()).toBeFocused()
  await page.keyboard.press("Tab")
  await expect(controls.nth(1)).toBeFocused()
  await page.keyboard.press("Shift+Tab")
  await expect(controls.first()).toBeFocused()
  await toggle.focus()
  await page.keyboard.press("Enter")
  await expect(sidebar).toHaveAttribute("aria-hidden", "true")
  await expect(toggle).toBeFocused()
  await expect(text).toHaveValue("# Keyboard navigation\n")
})

test("keyboard focus remains visible on sidebar and delete confirmation controls", async ({ page }) => {
  await page.goto("/")
  await page.getByRole("textbox", { name: "Text" }).fill("# Focus review\n")
  const toggle = page.getByRole("button", { name: "Toggle documents" })
  await toggle.focus()
  // Enter keyboard modality before inspecting the actual rendered focus ring.
  await page.keyboard.press("Shift")
  const visibleOutline = async (control: Locator) => control.evaluate(element => {
    const style = getComputedStyle(element)
    return element.matches(":focus-visible") && style.outlineStyle !== "none" && parseFloat(style.outlineWidth) >= 2
  })
  expect(await visibleOutline(toggle)).toBe(true)
  const remove = page.getByRole("button", { name: 'Delete "Focus review"', exact: true })
  await remove.focus()
  expect(await visibleOutline(remove)).toBe(true)
  await page.keyboard.press("Enter")
  const dialog = page.getByRole("alertdialog")
  const cancel = dialog.getByRole("button", { name: "Cancel", exact: true })
  await expect(cancel).toBeFocused()
  expect(await visibleOutline(cancel)).toBe(true)
  await page.keyboard.press("Tab")
  const confirm = dialog.getByRole("button", { name: "Delete document", exact: true })
  await expect(confirm).toBeFocused()
  expect(await visibleOutline(confirm)).toBe(true)
  await page.keyboard.press("Shift+Tab")
  await expect(cancel).toBeFocused()
  await page.keyboard.press("Escape")
  await expect(remove).toBeFocused()
})

test("deletion closes More actions and Escape returns to the deletion trigger", async ({ page }) => {
  await page.goto("/")
  await page.getByRole("textbox", { name: "Text" }).fill("# Keep this document\n")
  const more = page.getByRole("button", { name: "More actions" })
  await more.click()
  const remove = page.getByRole("button", { name: 'Delete "Keep this document"', exact: true })
  await remove.focus()
  await page.keyboard.press("Enter")
  const dialog = page.getByRole("alertdialog")
  await expect(dialog.getByRole("button", { name: "Cancel", exact: true })).toBeFocused()
  await expect(more).toHaveAttribute("aria-expanded", "false")
  await page.keyboard.press("Escape")
  await expect(dialog).toHaveCount(0)
  await expect(remove).toBeFocused()
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue("# Keep this document\n")
})

test("More actions remains reachable above the mode controls in short viewports", async ({ page }) => {
  await page.setViewportSize({ width: 568, height: 240 })
  await page.goto("/")
  await expect(page.getByRole("textbox", { name: "Text" })).toBeVisible()
  const more = page.getByRole("button", { name: "More actions" })
  await more.focus()
  await page.keyboard.press("Enter")
  await expect(more).toHaveAttribute("aria-expanded", "true")
  const menu = page.locator(".loomark-menu")
  const exportAction = menu.getByRole("button", { name: "Export Markdown" })
  // Reach the action through the real Tab order, which must scroll the panel.
  for (let i = 0; i < 5 && !(await exportAction.evaluate(e => e === document.activeElement)); i++) {
    await page.keyboard.press("Tab")
  }
  await expect(exportAction).toBeFocused()
  expect(await exportAction.evaluate(element => {
    const box = element.getBoundingClientRect()
    const hit = document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2)
    return box.top >= 0 && box.bottom <= innerHeight && (hit === element || element.contains(hit))
  })).toBe(true)
  const download = page.waitForEvent("download")
  await page.keyboard.press("Enter")
  expect((await download).suggestedFilename()).toBe("untitled.md")
  await page.keyboard.press("Escape")
  await expect(more).toBeFocused()
})

test("large native clipboard paste preserves exact text through Undo, reload, and Export", async ({ page }) => {
  await page.context().grantPermissions(["clipboard-read", "clipboard-write"])
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text", exact: true })
  const source = "# Paste continuity\n\n" + "日本語と English. Keep the writing flowing.\n".repeat(4000)
  await expect(text).toBeVisible()
  await page.evaluate(value => navigator.clipboard.writeText(value), source)
  await text.press("Control+V")
  await expect(text).toHaveValue(source)
  await text.press("Control+Z")
  await expect(text).toHaveValue("")
  await text.press("Control+Shift+Z")
  await expect(text).toHaveValue(source)
  await expect.poll(async () => (await readStoredDocument(page))?.text).toBe(source)
  await page.reload()
  await expect(text).toHaveValue(source)
  await page.getByRole("button", { name: "More actions" }).click()
  const downloadPromise = page.waitForEvent("download")
  await page.locator(".loomark-menu").getByRole("button", { name: "Export Markdown" }).click()
  const stream = await (await downloadPromise).createReadStream()
  stream.setEncoding("utf8")
  let downloaded = ""
  for await (const chunk of stream) downloaded += chunk
  expect(downloaded).toBe(source)
})

test("sign-in preparation visibly disables creation and Import until cancelled", async ({ page }) => {
  let finishPreparation: (() => void) | undefined
  await page.route("**/api/auth/sign-in/social", async route => {
    await new Promise<void>(resolve => { finishPreparation = resolve })
    await route.fulfill({ status: 503 })
  })
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text", exact: true })
  await text.fill("# Keep writing after cancellation\n")
  const create = page.locator("header").getByRole("button", { name: "New document", exact: true })
  await expect(create).toHaveCSS("opacity", "1")
  await page.getByRole("button", { name: "More actions" }).click()
  const importLabel = page.locator('label[for="loomark-menu-import"]')
  await expect(importLabel).toHaveCSS("opacity", "1")
  await page.getByRole("button", { name: "Sign in with Google" }).click()
  await expect(text).toBeDisabled()
  await expect(create).toBeDisabled()
  await expect(create).toHaveCSS("opacity", "0.5")
  await expect(importLabel.locator("input")).toBeDisabled()
  await expect(importLabel).toHaveCSS("opacity", "0.5")
  await page.getByRole("button", { name: "Cancel sign-in" }).click()
  await expect(text).toBeEnabled()
  await expect(text).toBeFocused()
  await expect(create).toHaveCSS("opacity", "1")
  await expect(importLabel).toHaveCSS("opacity", "1")
  await expect(importLabel.locator("input")).toBeEnabled()
  finishPreparation?.()
  await expect(text).toHaveValue("# Keep writing after cancellation\n")
})

test("first-write hint stays outside document text and preserves native editing", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  for (const width of [1280, 390, 320, 1280]) {
    await page.setViewportSize({ width, height: 844 })
    await expect(text).toHaveAttribute("placeholder", "Start writing…")
    await expect(text).toHaveAccessibleName("Text")
    await expect(text).toHaveValue("")
  }
  expect(await readStoredDocuments(page)).toEqual([])
  await text.evaluate(element => {
    ;(window as typeof window & { firstWriteArea?: Element }).firstWriteArea = element
  })
  await text.focus()
  await text.pressSequentially("First words")
  await expect.poll(() => readStoredDocuments(page).then(documents => documents[0]?.text)).toBe("First words")
  expect(await text.evaluate(element => element === (
    window as typeof window & { firstWriteArea?: Element }
  ).firstWriteArea)).toBe(true)
  await expect(text).not.toHaveAttribute("placeholder", "Start writing…")
  // Native typing may create several undo groups; every group must remain undoable.
  for (let remaining = 11; remaining > 0 && await text.inputValue() !== ""; remaining--) {
    await text.press("Control+Z")
  }
  await expect(text).toHaveValue("")
  await expect.poll(() => readStoredDocuments(page).then(documents => documents[0]?.text)).toBe("")
  await expect(text).not.toHaveAttribute("placeholder", "Start writing…")
  await page.reload()
  await expect(text).toHaveValue("")
  await expect(text).not.toHaveAttribute("placeholder", "Start writing…")

  await page.getByRole("button", { name: "New document", exact: true }).first().click()
  await expect(text).toHaveAttribute("placeholder", "Start writing…")
  await page.getByRole("button", { name: "More actions" }).click()
  const downloadPromise = page.waitForEvent("download")
  await page.locator(".loomark-menu").getByRole("button", { name: "Export Markdown" }).click()
  const download = await downloadPromise
  const stream = await download.createReadStream()
  stream.setEncoding("utf8")
  let downloaded = ""
  for await (const chunk of stream) downloaded += chunk
  expect(downloaded).toBe("")
  expect(await readStoredDocuments(page)).toHaveLength(1)
})

test("visible save caption waits for durable acknowledgement without moving the editor", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  const status = page.locator(".loomark-save-status")
  await expect(text).toBeVisible()
  await expect(status).toHaveCount(0)
  await text.pressSequentially("Draft")
  await expect(status).toHaveAccessibleName("Saved on this device")
  await expect(status).toHaveText("Saved on this device")
  const storedDocument = await readStoredDocument(page)
  if (!storedDocument) throw new Error("saved document missing")
  await page.evaluate(installDelayedDocumentCommit, sourceKey(storedDocument.document_id))
  await page.evaluate(() => {
    ;(globalThis as typeof globalThis & { __loomarkDelayedCommitHeld?: boolean })
      .__loomarkDelayedCommitHeld = true
  })
  const before = await text.boundingBox()
  await text.pressSequentially(" revised")
  await expect(status).toHaveText("Saving on this device")
  await expect(status).toHaveAccessibleName("Saving on this device")
  expect(await text.boundingBox()).toEqual(before)
  await page.evaluate(() => {
    ;(globalThis as typeof globalThis & { __loomarkDelayedCommitHeld?: boolean })
      .__loomarkDelayedCommitHeld = false
  })
  await expect(status).toHaveText("Saved on this device")
  expect(await text.boundingBox()).toEqual(before)
  // Inspect the writing workspace, with navigation closed before compact reflow.
  await page.getByRole("button", { name: "Toggle documents" }).click()
  for (const width of [320, 390, 1280]) {
    await page.setViewportSize({ width, height: 844 })
    await expect(status.locator(".loomark-save-caption")).toBeVisible()
    await expect.poll(() => status.evaluate(element => {
      const right = element.getBoundingClientRect().right
      const modesLeft = document.querySelector(".loomark-bottom-actions")!.getBoundingClientRect().left
      return right + 8 <= modesLeft && document.body.scrollWidth <= innerWidth
    })).toBe(true)
  }
})

test("New document explains when local saving begins", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await expect(text).toHaveValue("")
  await page.getByRole("button", { name: "More actions" }).click()
  const menu = page.locator(".loomark-menu")
  await expect(menu).not.toContainText("Saved on this device")
  await expect(menu).toContainText("Write to save on this device")
  expect(await readStoredDocuments(page)).toEqual([])
  await text.fill("# First words\n")
  await expect(menu).toContainText("Saved on this device")
  await expect(menu).not.toContainText("Write to save on this device")
  await text.fill("")
  await expect.poll(async () => (await readStoredDocuments(page))[0]?.text).toBe("")
  await expect(menu).toContainText("Saved on this device")
})

type StoredDocument = {
  document_id: string
  text: string
}

type StoreRecord = {
  key: string | number
  value: unknown
}

type PendingTimerObservation = {
  scheduled: number
  canceled: number
  fired: number
}

function installPendingTimerProbe(): void {
  const state = globalThis as typeof globalThis & {
    __loomarkPendingTimerProbe?: PendingTimerObservation
  }
  if (state.__loomarkPendingTimerProbe) return
  const originalSetTimeout = window.setTimeout.bind(window)
  const originalClearTimeout = window.clearTimeout.bind(window)
  const pending = new Set<number>()
  state.__loomarkPendingTimerProbe = { scheduled: 0, canceled: 0, fired: 0 }
  window.setTimeout = ((handler: TimerHandler, timeout?: number, ...args: any[]) => {
    if (timeout !== 250 || typeof handler !== "function") {
      return originalSetTimeout(handler, timeout, ...args)
    }
    let handle = 0
    const wrapped = (...callbackArgs: any[]) => {
      pending.delete(handle)
      state.__loomarkPendingTimerProbe!.fired += 1
      handler(...callbackArgs)
    }
    handle = Number(originalSetTimeout(wrapped, timeout, ...args))
    pending.add(handle)
    state.__loomarkPendingTimerProbe!.scheduled += 1
    return handle
  }) as typeof window.setTimeout
  window.clearTimeout = ((handle?: number) => {
    if (typeof handle === "number" && pending.delete(handle)) {
      state.__loomarkPendingTimerProbe!.canceled += 1
    }
    return originalClearTimeout(handle)
  }) as typeof window.clearTimeout
}

async function resetPendingTimerObservation(page: Page): Promise<void> {
  await page.evaluate(() => {
    const state = globalThis as typeof globalThis & {
      __loomarkPendingTimerProbe?: PendingTimerObservation
    }
    if (state.__loomarkPendingTimerProbe) {
      state.__loomarkPendingTimerProbe = { scheduled: 0, canceled: 0, fired: 0 }
    }
  })
}

async function openDeleteConfirmation(page: Page, label: string): Promise<void> {
  const toggle = page.getByRole("button", { name: "Toggle documents" })
  if (await toggle.getAttribute("aria-expanded") === "false") await toggle.click()
  const row = page.getByRole("button", { name: label, exact: true }).locator("..")
  await row.getByRole("button", { name: `Delete "${label}"`, exact: true }).click()
}

async function pendingTimerObservation(page: Page): Promise<PendingTimerObservation> {
  return page.evaluate(() => (
    (globalThis as typeof globalThis & {
      __loomarkPendingTimerProbe?: PendingTimerObservation
    }).__loomarkPendingTimerProbe ?? { scheduled: 0, canceled: 0, fired: 0 }
  ))
}

function sourceKey(documentId: string): string {
  return `${SOURCE_KEY_PREFIX}${documentId}`
}

function replicaKey(accountId: string, documentId: string): string {
  return `${REPLICA_KEY_PREFIX}${accountId.length}/${accountId}/${documentId}`
}

function fixtureDocumentId(value: string): string {
  const bytes = new TextEncoder().encode(value)
  let hash = 0
  for (const byte of bytes) hash = (hash * 131 + byte) & 0xffff
  const identity = Array.from({ length: 16 }, (_, index) => (
    index < 14 ? bytes[index] ?? 0 : index === 14 ? hash >>> 8 : hash & 0xff
  ))
  const digits = identity
    .map(byte => byte.toString(16).padStart(2, "0"))
    .join("")
    .split("")
  digits[12] = "4"
  digits[16] = "8"
  const hex = digits.join("")
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
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
      || JSON.stringify(Object.keys(parsed).sort()) !== JSON.stringify([
        "document_id",
        "text",
      ])
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

function encodeReadyReplica(
  accountId: string,
  document: StoredDocument,
): string {
  const header = JSON.stringify({
    account_id: accountId,
    document_id: document.document_id,
    generation: 0,
    state: {
      kind: "live",
      current: 0,
      baseline: { kind: "missing" },
      phase: { kind: "ready" },
    },
    recovery_document_id: null,
    text_lengths: [document.text.length],
  })
  return `loomark-replica\n${header.length}\n${header}${document.text}`
}

function replicaCurrentText(value: unknown): string | null {
  if (typeof value !== "string" || !value.startsWith("loomark-replica\n")) return null
  const lengthStart = "loomark-replica\n".length
  const lengthEnd = value.indexOf("\n", lengthStart)
  if (lengthEnd < 0) return null
  const headerLength = Number(value.slice(lengthStart, lengthEnd))
  if (!Number.isSafeInteger(headerLength) || headerLength < 0) return null
  const headerStart = lengthEnd + 1
  try {
    const header = JSON.parse(value.slice(headerStart, headerStart + headerLength)) as {
      state?: { kind?: unknown; current?: unknown }
      text_lengths?: unknown
    }
    if (
      header.state?.kind !== "live"
      || !Number.isSafeInteger(header.state.current)
      || !Array.isArray(header.text_lengths)
      || !header.text_lengths.every(length => Number.isSafeInteger(length) && length >= 0)
    ) return null
    const current = header.state.current as number
    if (current < 0 || current >= header.text_lengths.length) return null
    const lengths = header.text_lengths as number[]
    const start = headerStart + headerLength
      + lengths.slice(0, current).reduce((sum, length) => sum + length, 0)
    return value.slice(start, start + lengths[current])
  } catch (_) {
    return null
  }
}

async function openStoredDocuments(page: Page, documents: StoredDocument[]): Promise<void> {
  await page.goto("/")
  await expect(page.getByRole("textbox", { name: "Text" })).toBeVisible()
  await replaceStoreRecords(page, documents.map(document => ({
    key: sourceKey(document.document_id),
    value: encodeStoredDocument(document),
  })))
  await page.reload()
}

async function expectStoredDocument(
  page: Page,
  document: StoredDocument,
): Promise<void> {
  await expect.poll(async () => {
    const raw = await readStoredDocumentRaw(page, sourceKey(document.document_id))
    if (typeof raw !== "string") return null
    const parsed = JSON.parse(raw) as Record<string, unknown>
    return parsed.document_id === document.document_id && parsed.text === document.text
      ? parsed
      : null
  }).not.toBeNull()
  const raw = await readStoredDocumentRaw(page, sourceKey(document.document_id))
  if (typeof raw !== "string") throw new Error("stored Source missing")
  const parsed = JSON.parse(raw) as Record<string, unknown>
  expect(parsed).toEqual(document)
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
  const text = page.getByRole("textbox", { name: "Text" })
  await expect(text).toHaveValue("")
  await expect.poll(() => readStoredDocuments(page)).toEqual([])
  await text.fill("# Untitled\n")
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
    __loomarkDelayedCommitHeld?: boolean
    __loomarkDelayedCommitCompletions?: number
    __loomarkDelayedCommitInputs?: number
    __loomarkDelayedCommitPuts?: PutObservation[]
  }
  const prototype = IDBObjectStore.prototype as any
  const originalPut = prototype.put
  state.__loomarkDelayedCommitActive = false
  state.__loomarkDelayedCommitHeld = false
  state.__loomarkDelayedCommitCompletions = 0
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
        if (!state.__loomarkDelayedCommitHeld && performance.now() - started >= 500) return
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

type StoreMutationObservation = {
  method: "put" | "delete"
  key?: IDBValidKey
}

function installStoreMutationLog(): void {
  const state = globalThis as typeof globalThis & {
    __loomarkStoreMutationLog?: StoreMutationObservation[]
  }
  const prototype = IDBObjectStore.prototype as any
  const originalPut = prototype.put
  const originalDelete = prototype.delete
  state.__loomarkStoreMutationLog = []
  prototype.put = function(
    this: IDBObjectStore,
    value: unknown,
    recordKey?: IDBValidKey,
  ) {
    state.__loomarkStoreMutationLog?.push({ method: "put", key: recordKey })
    return originalPut.call(this, value, recordKey)
  }
  prototype.delete = function(this: IDBObjectStore, recordKey: IDBValidKey) {
    state.__loomarkStoreMutationLog?.push({ method: "delete", key: recordKey })
    return originalDelete.call(this, recordKey)
  }
}

async function readStoreMutationLog(page: Page): Promise<StoreMutationObservation[]> {
  return page.evaluate(() => (
    (globalThis as typeof globalThis & {
      __loomarkStoreMutationLog?: StoreMutationObservation[]
    }).__loomarkStoreMutationLog ?? []
  ))
}

test.beforeEach(async ({ page }) => {
  // Static assets have no account endpoint; tests override this signed-out baseline.
  await page.route("**/api/account", route => route.fulfill({ status: 401 }))
})

test("save indicator distinguishes an empty new document from a stored empty document", async ({ page }) => {
  await page.goto("/")
  const indicator = page.locator(".loomark-save-status")
  const text = page.getByRole("textbox", { name: "Text" })
  await expect(text).toHaveValue("")
  await expect(page.getByText("No documents yet")).toBeVisible()
  await expect(indicator).toHaveCount(0)

  await text.fill("# Written here\n")
  await expect(indicator).toHaveAttribute("title", "Saving on this device")
  await expect(indicator).toHaveAttribute("title", "Saved on this device")
  await expect.poll(() => readStoredDocuments(page)).toHaveLength(1)

  await text.fill("")
  await expect(indicator).toHaveAttribute("title", "Saving on this device")
  await expect(indicator).toHaveAttribute("title", "Saved on this device")
  await expect.poll(async () => (await readStoredDocuments(page))[0]?.text).toBe("")
  await page.reload()
  await expect(text).toHaveValue("")
  await expect(indicator).toHaveAttribute("title", "Saved on this device")
})

test("Export downloads the current Document text with its Derived name", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  const source = "## Export name\n\nCurrent text\n"
  await text.fill(source)

  const downloadPromise = page.waitForEvent("download")
  await page.getByRole("button", { name: "More actions" }).click()
  const menu = page.locator(".loomark-menu")
  await expect(menu.getByRole("toolbar", { name: "Example documents" })).toHaveCount(0)
  await expect(menu.locator('label[title="Import Markdown"] .i-lucide-upload')).toBeVisible()
  await expect(menu.getByText("Import", { exact: true })).toBeVisible()
  await expect(menu.locator('label[title="Import Markdown"] input[aria-label="Import Markdown"]')).toHaveCount(1)
  const exportAction = menu.getByRole("button", { name: "Export Markdown" })
  await expect(exportAction.locator(".i-lucide-download")).toBeVisible()
  await expect(menu.getByText("Export", { exact: true })).toBeVisible()
  await exportAction.click()
  const download = await downloadPromise

  expect(download.suggestedFilename()).toBe("Export name.md")
  const stream = await download.createReadStream()
  stream.setEncoding("utf8")
  let downloaded = ""
  for await (const chunk of stream) downloaded += chunk
  expect(downloaded).toBe(source)
})

async function downloadCurrentMarkdown(page: Page): Promise<{ filename: string; text: string }> {
  await page.getByRole("button", { name: "More actions" }).click()
  const pending = page.waitForEvent("download")
  await page.locator(".loomark-menu").getByRole("button", { name: "Export Markdown" }).click()
  const download = await pending
  const stream = await download.createReadStream()
  stream.setEncoding("utf8")
  let text = ""
  for await (const chunk of stream) text += chunk
  return { filename: download.suggestedFilename(), text }
}

for (const persistence of ["failed", "held"] as const) {
  test(`Export rescues latest selection replacement while local save is ${persistence}`, async ({ page }) => {
    await page.goto("/")
    const editor = page.getByRole("textbox", { name: "Text" })
    const original = "# Rescue\n\nOriginal paragraph\n"
    await editor.fill(original)
    await expect.poll(async () => (await readStoredDocument(page))?.text).toBe(original)
    const stored = await readStoredDocument(page)
    if (!stored) throw new Error("saved baseline missing")
    if (persistence === "failed") {
      await page.evaluate(installDocumentPutFailure, sourceKey(stored.document_id))
    } else {
      await page.evaluate(installDelayedDocumentCommit, sourceKey(stored.document_id))
      await page.evaluate(() => {
        ;(globalThis as typeof globalThis & { __loomarkDelayedCommitHeld?: boolean })
          .__loomarkDelayedCommitHeld = true
      })
    }
    await editor.evaluate(element => {
      const area = element as HTMLTextAreaElement
      area.focus()
      const start = area.value.indexOf("Original")
      area.setSelectionRange(start, start + "Original".length)
    })
    await page.keyboard.insertText("最新の本文")
    await editor.press("Control+End")
    await editor.pressSequentially("Last edit")
    const latest = "# Rescue\n\n最新の本文 paragraph\nLast edit"
    await expect(editor).toHaveValue(latest)
    const status = page.locator(".loomark-save-status")
    await expect(status).toHaveAccessibleName(persistence === "failed" ? "Not saved" : "Saving on this device")
    if (persistence === "held") {
      await expect.poll(() => page.evaluate(() => (
        globalThis as typeof globalThis & { __loomarkDelayedCommitActive?: boolean }
      ).__loomarkDelayedCommitActive)).toBe(true)
    }
    try {
      expect(await downloadCurrentMarkdown(page)).toEqual({ filename: "Rescue.md", text: latest })
      await expect(editor).toHaveValue(latest)
      await expect(status).not.toHaveAccessibleName("Saved on this device")
      if (persistence === "failed") {
        await expect(page.getByRole("alert")).toBeVisible()
        expect((await readStoredDocument(page))?.text).toBe(original)
      } else {
        expect(await page.evaluate(() => (
          globalThis as typeof globalThis & { __loomarkDelayedCommitCompletions?: number }
        ).__loomarkDelayedCommitCompletions)).toBe(0)
      }
    } finally {
      // Release the test transaction only after rescue assertions; export must not depend on it.
      if (persistence === "held") await page.evaluate(() => {
        ;(globalThis as typeof globalThis & { __loomarkDelayedCommitHeld?: boolean })
          .__loomarkDelayedCommitHeld = false
      })
    }
  })
}

test("a loaded offline editor saves and exports locally before reconnecting", async ({ page, context }) => {
  await page.goto("/")
  const editor = page.getByRole("textbox", { name: "Text" })
  await editor.fill("# Offline\n")
  await expect.poll(async () => (await readStoredDocument(page))?.text).toBe("# Offline\n")
  const latest = "# Offline\nWritten without a network connection."
  await context.setOffline(true)
  try {
    await editor.press("Control+End")
    await editor.pressSequentially("Written without a network connection.")
    await expect(page.locator(".loomark-save-status")).toHaveAccessibleName("Saved on this device")
    await expect.poll(async () => (await readStoredDocument(page))?.text).toBe(latest)
    expect(await downloadCurrentMarkdown(page)).toEqual({ filename: "Offline.md", text: latest })
  } finally {
    await context.setOffline(false)
  }
  await page.reload()
  await expect(editor).toHaveValue(latest)
})

test("Import creates a new Document without changing the existing Document", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  const existingText = "# Existing document\n\nKeep this text.\n"
  const normalized = "Imported\ntext\n"
  await text.fill(existingText)
  await expect.poll(() => readStoredDocuments(page)).toHaveLength(1)
  const [existing] = await readStoredDocuments(page)

  await page.getByLabel("Import Markdown")
    .setInputFiles("tests/fixtures/import-bom-crlf.bin")

  await expect(text).toHaveValue(normalized)
  await expect.poll(() => readStoredDocuments(page)).toHaveLength(2)
  const documents = await readStoredDocuments(page)
  expect(documents).toContainEqual(existing)
  expect(documents).toContainEqual({
    document_id: expect.not.stringMatching(existing.document_id),
    text: normalized,
  })
})

test("menu Import uses the same Markdown file action as the sidebar", async ({ page }) => {
  await page.goto("/")
  await page.getByRole("button", { name: "More actions" }).click()
  await page.locator(".loomark-menu").getByLabel("Import Markdown")
    .setInputFiles("tests/fixtures/import-bom-crlf.bin")
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue("Imported\ntext\n")
})

test("importing the same file twice creates two Documents", async ({ page }) => {
  await page.goto("/")
  const file = page.getByLabel("Import Markdown")
  const selected = "tests/fixtures/import-bom-crlf.bin"

  await file.setInputFiles(selected)
  await expect.poll(() => readStoredDocuments(page)).toHaveLength(1)
  await file.setInputFiles(selected)
  await expect.poll(() => readStoredDocuments(page)).toHaveLength(2)
})

test("delayed imports preserve composition and remain available after later navigation", async ({ page }) => {
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Document A\n")
  await expect.poll(() => readStoredDocuments(page)).toHaveLength(1)
  await page.evaluate(() => {
    const original = Blob.prototype.arrayBuffer
    const scope = window as typeof window & { releaseImports?: (() => void)[] }
    scope.releaseImports = []
    Blob.prototype.arrayBuffer = async function () {
      const bytes = await original.call(this)
      await new Promise<void>(resolve => scope.releaseImports!.push(resolve))
      return bytes
    }
  })
  for (const name of ["Imported B", "Imported C"]) {
    await page.getByLabel("Import Markdown").setInputFiles({
      name: `${name}.md`, mimeType: "text/markdown", buffer: Buffer.from(`# ${name}\n`),
    })
  }
  await expect.poll(() => page.evaluate(() => (
    window as typeof window & { releaseImports?: (() => void)[] }
  ).releaseImports?.length)).toBe(2)
  await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    ;(window as typeof window & { composingArea?: HTMLTextAreaElement }).composingArea = area
    area.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true }))
    area.value = "# Composing A\n"
    area.dispatchEvent(new InputEvent("input", {
      bubbles: true, composed: true, data: area.value, inputType: "insertCompositionText",
    }))
  })
  // Resolve in reverse order: each import survives; neither may replace the composing textarea.
  await page.evaluate(() => {
    const releases = (window as typeof window & { releaseImports: (() => void)[] }).releaseImports
    for (const release of releases.reverse()) release()
  })
  await expect.poll(() => readStoredDocuments(page)).toHaveLength(3)
  await expect(text).toHaveValue("# Composing A\n")
  expect(await text.evaluate(element => element === (
    window as typeof window & { composingArea?: HTMLTextAreaElement }
  ).composingArea)).toBe(true)
  await text.evaluate(element => element.dispatchEvent(new CompositionEvent("compositionend", {
    bubbles: true, data: "# Composing A\n",
  })))
  await expect.poll(() => readStoredDocuments(page).then(documents => documents.map(document => document.text).sort()))
    .toEqual(["# Composing A\n", "# Imported B\n", "# Imported C\n"])
  await expect(text).toHaveValue("# Composing A\n")
  await openDeleteConfirmation(page, "Composing A")
  await page.getByRole("alertdialog").getByRole("button", { name: "Cancel" }).click()
  await expect(text).toHaveValue("# Composing A\n")
  await page.getByRole("button", { name: "New document", exact: true }).first().click()
  await expect(text).toHaveValue("")
  for (const name of ["Imported B", "Imported C", "Composing A"]) {
    await page.getByRole("button", { name, exact: true }).click()
    await expect(text).toHaveValue(`# ${name}\n`)
  }
  await page.reload()
  await expect(text).toHaveValue("# Composing A\n")
})

test("dismissing an import error restores the current writing destination", async ({ page }) => {
  await page.goto("/")
  const text = page.locator("#loomark-text")
  await text.fill("# Keep my writing\n")
  await text.evaluate(element => (element as HTMLTextAreaElement).setSelectionRange(2, 6, "backward"))
  for (const mode of ["Text", "Split", "Preview"] as const) {
    await page.getByRole("tab", { name: mode, exact: true }).click()
    await page.getByLabel("Import Markdown")
      .setInputFiles("tests/fixtures/import-malformed-utf8.md")
    const dismiss = page.getByRole("alert").getByRole("button", { name: "Dismiss" })
    await dismiss.focus()
    await dismiss.press("Enter")
    await expect(page.getByRole("alert")).toHaveCount(0)
    await expect(mode === "Preview" ? page.getByRole("tab", { name: mode, exact: true }) : text)
      .toBeFocused()
    await expect(text).toHaveValue("# Keep my writing\n")
    expect(await text.evaluate(element => {
      const area = element as HTMLTextAreaElement
      return [area.selectionStart, area.selectionEnd, area.selectionDirection]
    })).toEqual([2, 6, "backward"])
  }
})

test("Import rejects malformed UTF-8 without creating a Source", async ({ page }) => {
  await page.goto("/")
  await page.getByLabel("Import Markdown")
    .setInputFiles("tests/fixtures/import-malformed-utf8.md")

  await expect(page.getByRole("alert")).toBeVisible()
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue("")
  expect(await readStoredDocuments(page)).toEqual([])
})

test("fresh production opens Text mode and preserves its textarea and undo history across modes", async ({ page }) => {
  const workerUrls: string[] = []
  page.on("worker", worker => workerUrls.push(worker.url()))

  await page.goto("/")
  await page.waitForLoadState("networkidle")
  await expect(page.getByRole("textbox", { name: "Text" }))
    .toHaveAttribute("autocomplete", "off")
  await expect(page.getByRole("textbox", { name: "Text" }))
    .toHaveAttribute("autocorrect", "off")

  const text = page.getByRole("textbox", { name: "Text" })
  const textTab = page.getByRole("tab", { name: "Text" })
  const previewTab = page.getByRole("tab", { name: "Preview" })
  const splitTab = page.getByRole("tab", { name: "Split" })
  const preview = page.getByRole("region", { name: "Markdown preview" })

  await expect(textTab.locator(".i-lucide-pencil")).toHaveCount(1)
  await expect(splitTab.locator(".i-lucide-columns-2")).toHaveCount(1)
  await expect(previewTab.locator(".i-lucide-eye")).toHaveCount(1)
  await expect(text).toBeVisible()
  await expect(text).toBeFocused()
  await expect(text).toHaveValue("")
  expect(await readStoredDocuments(page)).toEqual([])
  await text.fill("# Untitled\n")
  await expect.poll(() => readStoredDocument(page)).not.toBeNull()
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

test("quiet editor keeps its source and sidebar toggle in place across views", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await page.goto("/")
  const source = page.getByRole("textbox", { name: "Text" })
  const content = "# Notes\n\n日本語と emoji 🌿\n\n- [ ] Another line\n"
  await source.fill(content)
  await expect.poll(() => readStoredDocument(page)).toMatchObject({ text: content })
  const toggle = page.getByRole("button", { name: "Toggle documents" })
  const before = await toggle.boundingBox()
  await expect(toggle).toHaveAttribute("aria-expanded", "true")
  expect(await source.evaluate(element => element.getBoundingClientRect().left)).toBeGreaterThan(0)
  await toggle.click()
  await expect(toggle).toHaveAttribute("aria-expanded", "false")
  expect(await toggle.boundingBox()).toEqual(before)
  await expect.poll(() => source.evaluate(element => element.getBoundingClientRect().left)).toBe(0)

  await source.evaluate(element => {
    const input = element as HTMLTextAreaElement
    input.focus()
    input.setSelectionRange(2, 7, "backward")
    ;(window as typeof window & { __source?: HTMLTextAreaElement }).__source = input
  })
  await page.getByRole("tab", { name: "Split" }).click()
  await expect(page.getByRole("region", { name: "Markdown preview" })).toContainText("日本語と emoji 🌿")
  await page.getByRole("tab", { name: "Preview" }).click()
  await page.getByRole("tab", { name: "Text" }).click()
  expect(await source.evaluate(element => ({
    same: element === (window as typeof window & { __source?: HTMLTextAreaElement }).__source,
    start: (element as HTMLTextAreaElement).selectionStart,
    end: (element as HTMLTextAreaElement).selectionEnd,
    direction: (element as HTMLTextAreaElement).selectionDirection,
  }))).toEqual({ same: true, start: 2, end: 7, direction: "backward" })
  await expect(page.getByRole("button", { name: "Focus mode" })).toHaveCount(0)
  await expect(page.getByRole("tab", { name: "Text" })).toBeVisible()
  await expect(page.getByRole("tab", { name: "Split" })).toBeVisible()
  await expect(page.getByRole("tab", { name: "Preview" })).toBeVisible()
  await page.reload()
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue(content)
  await toggle.click()
  await expect.poll(() => source.evaluate(element => element.getBoundingClientRect().left)).toBe(0)

  const metrics = await source.evaluate(element => ({
    top: element.getBoundingClientRect().top,
    paddingTop: getComputedStyle(element).paddingTop,
    paddingLeft: getComputedStyle(element).paddingLeft,
  }))
  expect(metrics).toEqual({ top: 56, paddingTop: "14px", paddingLeft: "340px" })
  await page.setViewportSize({ width: 390, height: 844 })
  await page.getByRole("tab", { name: "Split" }).click()
  await expect(page.getByRole("separator")).toHaveAttribute("aria-orientation", "horizontal")
})

test("forced colors keep writing controls and the selected mode distinguishable", async ({ page }) => {
  await page.emulateMedia({ forcedColors: "active" })
  await page.setViewportSize({ width: 320, height: 360 })
  await page.goto("/")
  await page.getByRole("textbox", { name: "Text" }).fill("Contrast check")
  await expect(page.getByRole("status", { name: "Saved on this device", exact: true })).toBeVisible()
  for (const mode of ["Text", "Split", "Preview"]) {
    await page.getByRole("tab", { name: mode, exact: true }).click()
    const icons = await page.locator('#loomark-editor [class*="i-lucide-"]:visible').evaluateAll(elements => (
      elements.map(element => {
        const style = getComputedStyle(element)
        return { painted: style.backgroundColor === style.color, mask: style.maskImage !== "none" }
      })
    ))
    expect(icons.length).toBeGreaterThanOrEqual(6)
    expect(icons.every(icon => icon.painted && icon.mask)).toBe(true)
    await expect.poll(() => page.locator('.loomark-mode-button[aria-selected="true"]').evaluate(element => (
      getComputedStyle(element).backgroundColor !== getComputedStyle(
        document.querySelector('.loomark-mode-button[aria-selected="false"]')!,
      ).backgroundColor
    ))).toBe(true)
  }
  const more = page.getByRole("button", { name: "More actions" })
  await more.focus()
  await more.press("Enter")
  const exportAction = page.locator(".loomark-menu").getByRole("button", { name: "Export Markdown" })
  await exportAction.focus()
  await expect(exportAction).toHaveCSS("outline-width", "2px")
  await page.keyboard.press("Escape")
  await expect(more).toBeFocused()
})

test("increased text spacing preserves status icons and native caret navigation", async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 360 })
  await page.goto("/")
  await page.addStyleTag({ content: "* { line-height:1.5 !important; letter-spacing:.12em !important; word-spacing:.16em !important; } p { margin-bottom:2em !important; }" })
  const editor = page.getByRole("textbox", { name: "Text" })
  const text = Array.from({ length: 100 }, (_, i) => `Line ${i}`).join("\n")
  await editor.fill(text)
  const status = page.getByRole("status", { name: "Saved on this device", exact: true })
  await expect(status).toBeVisible()
  const layout = await status.evaluate(element => {
    const rect = element.getBoundingClientRect()
    const icon = element.querySelector('[aria-hidden="true"]')!.getBoundingClientRect()
    const caption = element.querySelector(".loomark-save-caption")!.getBoundingClientRect()
    return { iconWidth: icon.width, contained: caption.right <= rect.right && caption.top >= rect.top && caption.bottom <= rect.bottom }
  })
  expect(layout.iconWidth).toBe(16)
  expect(layout.contained).toBe(true)
  for (const mode of ["Text", "Split"]) {
    await page.getByRole("tab", { name: mode, exact: true }).click()
    if (mode === "Split") await expect.poll(() => editor.evaluate(element => element.getBoundingClientRect().bottom)).toBe(180)
    for (const key of ["Control+End", "PageUp", "Control+Home", "PageDown", "Shift+PageDown", "Control+Shift+End"]) {
      await editor.press(key)
      await expect.poll(() => editor.evaluate(element => {
        const area = element as HTMLTextAreaElement, rect = area.getBoundingClientRect(), style = getComputedStyle(area)
        const endpoint = area.selectionDirection === "backward" ? area.selectionStart : area.selectionEnd
        // Short lines remain unwrapped with these spacing overrides.
        const line = area.value.slice(0, endpoint).split("\n").length - 1
        const y = rect.top + Number.parseFloat(style.paddingTop) + (line + 0.5) * Number.parseFloat(style.lineHeight) - area.scrollTop
        return document.elementFromPoint(rect.left + Number.parseFloat(style.paddingLeft) + 8, y) === area
      })).toBe(true)
      await expect(editor).toHaveValue(text)
    }
  }
})

for (const mode of ["Text", "Split"] as const) {
  test(`current native writing line stays visible outside chrome in ${mode}`, async ({ page }) => {
    for (const { width, height, failure, minimumSplit = false } of [
      { width: 1280, height: 900, failure: false },
      { width: 390, height: 844, failure: false },
      { width: 320, height: 640, failure: false },
      { width: 320, height: 360, failure: false },
      { width: 320, height: 360, failure: true },
      { width: 320, height: 360, failure: true, minimumSplit: true },
    ]) {
      await page.setViewportSize({ width, height })
      await page.goto("/")
      const editor = page.getByRole("textbox", { name: "Text" })
      const toggle = page.getByRole("button", { name: "Toggle documents" })
      if (await toggle.getAttribute("aria-expanded") === "true") await toggle.click()
      await page.getByRole("tab", { name: mode, exact: true }).click()
      expect(await editor.evaluate(element => element.getBoundingClientRect().top
        + Number.parseFloat(getComputedStyle(element).paddingTop))).toBe(width <= 520 ? 68 : 70)
      if (mode === "Split" && minimumSplit) {
        await page.getByRole("slider", { name: "Resize editor and preview" }).fill("25")
      }
      if (failure) await page.evaluate(installDocumentPutFailure, { prefix: SOURCE_KEY_PREFIX })
      await editor.fill("# Long writing\n\n" + "Short line.\n".repeat(80))
      if (failure) await expect(page.getByRole("alert")).toBeVisible()
      await editor.press("Control+End")
      await editor.pressSequentially("Current line")
      if (failure) await expect(page.getByRole("alert")).toBeVisible()
      const visible = await editor.evaluate(element => {
        const area = element as HTMLTextAreaElement
        const style = getComputedStyle(area), rect = area.getBoundingClientRect()
        // Every fixture line fits without wrapping. Check the actual selected line,
        // not scrollHeight or the amount of padding after the document.
        const line = area.value.slice(0, area.selectionStart).split("\n").length - 1
        const y = rect.top + Number.parseFloat(style.paddingTop)
          + (line + 0.5) * Number.parseFloat(style.lineHeight) - area.scrollTop
        const x = rect.left + Number.parseFloat(style.paddingLeft) + 8
        const footer = document.querySelector(".loomark-footer")!.getBoundingClientRect()
        const header = document.querySelector(".loomark-topbar")!.getBoundingClientRect()
        return {
          atEnd: area.selectionStart === area.value.length,
          lineOutsideChrome: y > header.bottom && y < footer.top,
          lineInsideInput: y > rect.top && y < rect.bottom,
          unobscured: document.elementFromPoint(x, y) === area,
          mask: style.maskImage,
        }
      })
      expect(visible).toEqual({ atEnd: true, lineOutsideChrome: true, lineInsideInput: true, unobscured: true, mask: "none" })
      if (mode === "Split" && minimumSplit) {
        const panes = await page.locator("#loomark-editor-panels").evaluate(group => {
          const text = group.querySelector<HTMLElement>("#loomark-text-pane")!
          const preview = group.querySelector<HTMLElement>('[data-side="second"]')!
          return {
            writingHeight: text.getBoundingClientRect().height,
            previewContained: preview.getBoundingClientRect().bottom <= group.getBoundingClientRect().bottom + 1,
          }
        })
        expect(panes.writingHeight).toBeGreaterThanOrEqual(112)
        expect(panes.previewContained).toBe(true)
      }
    }
  })
}

test("Text stays outside fixed controls while Preview keeps softened viewport edges", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  await page.goto("/")
  const source = page.getByRole("textbox", { name: "Text" })
  await source.fill(Array.from({ length: 90 }, (_, i) => `Line ${i + 1}`).join("\n"))
  const bounds = async (selector: string) => page.locator(selector).evaluate(element => {
    const { top, bottom } = element.getBoundingClientRect()
    return { top, bottom }
  })
  expect(await bounds("#loomark-text")).toEqual({ top: 56, bottom: 836 })
  expect(await bounds(".loomark-topbar")).toEqual({ top: 0, bottom: 48 })
  expect(await bounds(".loomark-footer")).toEqual({ top: 836, bottom: 900 })
  await expect.poll(() => source.evaluate(element => getComputedStyle(element).paddingTop))
    .toBe("14px")
  expect(await page.locator("#loomark-editor").evaluate(element => (
    getComputedStyle(element, "::before").backdropFilter
  ))).toBe("blur(2px)")
  expect(await source.evaluate(element => getComputedStyle(element).maskImage)).toBe("none")

  await page.getByRole("tab", { name: "Preview" }).click()
  await expect.poll(() => bounds("#loomark-preview-scroll"))
    .toEqual({ top: 0, bottom: 900 })
  expect(await page.locator("#loomark-preview-scroll").evaluate(element => getComputedStyle(element).maskImage))
    .toContain("rgb(0, 0, 0) 52px, rgb(0, 0, 0) calc(100% - 56px)")
  await expect.poll(() => page.locator("#loomark-preview-scroll .rmd-preview-content")
    .evaluate(element => getComputedStyle(element).paddingTop)).toBe("70px")
  const preview = page.locator("#loomark-preview-scroll")
  await preview.evaluate(element => { element.scrollTop = element.scrollHeight })
  const lastLine = await bounds("#loomark-preview-scroll .rmd-preview-content > :last-child")
  expect(lastLine.bottom).toBeLessThan((await bounds(".loomark-footer")).top)

  await page.setViewportSize({ width: 390, height: 844 })
  await page.getByRole("button", { name: "Toggle documents" }).click()
  await page.getByRole("tab", { name: "Split" }).click()
  await expect.poll(() => bounds("#loomark-text")).toEqual({ top: 56, bottom: 422 })
  await expect.poll(() => bounds("#loomark-preview-scroll")).toEqual({ top: 422, bottom: 844 })
  await expect.poll(() => source.evaluate(element => getComputedStyle(element).paddingTop))
    .toBe("12px")
  await expect.poll(() => page.locator("#loomark-preview-scroll .rmd-preview-content")
    .evaluate(element => getComputedStyle(element).paddingTop)).toBe("16px")
  expect(await source.evaluate(element => getComputedStyle(element).maskImage))
    .not.toContain("calc(100% - 56px)")
  expect(await preview.evaluate(element => getComputedStyle(element).maskImage))
    .not.toContain("rgb(0, 0, 0) 52px")
})

test("first edit reports quota full without creating a Source", async ({ page }) => {
  await page.addInitScript(installDocumentPutFailure, { prefix: SOURCE_KEY_PREFIX })
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await expect(text).toHaveValue("")
  expect(await readStoredDocuments(page)).toEqual([])
  await text.fill("# Full\n")
  await expect(page.getByRole("alert")).toBeVisible()
  await expect(page.getByRole("button", { name: "Retry saving" })).toBeEnabled()
  await expect(page.getByRole("heading", { name: "Document recovery" })).toHaveCount(0)
  expect(await readStoredDocuments(page)).toEqual([])
  await page.getByRole("button", { name: "More actions" }).click()
  await expect(page.locator(".loomark-menu")).toContainText("Not saved")
  await expect(page.locator(".loomark-menu")).not.toContainText("Write to save")
})

test("opening and saving persist only authoritative Source records", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const text = page.getByRole("textbox", { name: "Text" })
  const baseline = await readStoredDocument(page)
  if (!baseline) throw new Error("baseline Source missing")

  await text.fill("# Source only\n")
  await expect.poll(() => readStoredDocument(page)).toEqual({
    document_id: baseline.document_id,
    text: "# Source only\n",
  })
  await page.reload()
  await expect(text).toHaveValue("# Source only\n")
  const savedRaw = await readStoredDocumentRaw(page, sourceKey(baseline.document_id))
  expect(savedRaw).toEqual(expect.stringContaining('"document_id":"' + baseline.document_id + '"'))
  expect(savedRaw).toEqual(expect.stringContaining('"text":"# Source only\\n"'))
  expect(JSON.parse(savedRaw as string)).toEqual({
    document_id: baseline.document_id,
    text: "# Source only\n",
  })
})

test("Sync atomically starts document sync without replacing its textarea", async ({ page }) => {
  const accountId = "account-a"
  await page.route("**/api/account", route => route.fulfill({
    status: 200,
    contentType: "application/json",
    body: JSON.stringify({ id: accountId, name: "Account A" }),
  }))
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Local\n")
  await expect.poll(() => readStoredDocument(page)).not.toBeNull()
  const document = await readStoredDocument(page)
  if (!document) throw new Error("baseline Source missing")
  const key = replicaKey(accountId, document.document_id)
  await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    area.setSelectionRange(1, 3)
    ;(globalThis as typeof globalThis & { __syncStartTextArea?: HTMLTextAreaElement })
      .__syncStartTextArea = area
  })

  await page.getByRole("button", { name: "More actions" }).click()
  await page.getByRole("button", { name: "Sync", exact: true }).click()
  await expect.poll(() => readStoredDocumentRaw(page, sourceKey(document.document_id)))
    .toBeUndefined()
  await expect.poll(async () => replicaCurrentText(
    await readStoredDocumentRaw(page, key),
  )).toBe("# Local\n")
  expect(await text.evaluate(element => (
    element === (globalThis as typeof globalThis & {
      __syncStartTextArea?: HTMLTextAreaElement
    }).__syncStartTextArea
  ))).toBe(true)
  expect(await text.evaluate(element => ({
    start: (element as HTMLTextAreaElement).selectionStart,
    end: (element as HTMLTextAreaElement).selectionEnd,
  }))).toEqual({ start: 1, end: 3 })
})

test("account retry remains available in the narrow layout", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  let available = false
  await page.route("**/api/account", route => route.fulfill({
    status: available ? 401 : 503,
  }))
  await page.goto("/")
  await page.getByRole("button", { name: "More actions" }).click()
  const retry = page.getByRole("button", { name: "Check account connection" })
  await expect(retry).toBeInViewport()
  await expect(page.getByText("Sign-in status is unavailable. You can keep editing documents on this device.")).toBeVisible()
  await expect(page.getByRole("button", { name: "Sign in with Google" })).toHaveCount(0)
  await expect(page.getByRole("button", { name: "Retry account" })).toHaveCount(0)
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Kept while account lookup recovers\n")
  available = true
  await retry.click()
  await expect(page.getByRole("button", { name: "Sign in with Google" })).toBeEnabled()
  await expect(text).toHaveValue("# Kept while account lookup recovers\n")
})

test("an absent account endpoint does not imply signed out or interrupt local editing", async ({ page }) => {
  let lookups = 0
  await page.route("**/api/account", route => {
    lookups += 1
    return route.fulfill({ status: 404 })
  })
  await page.goto("/")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Local document\n")
  await expect(page.locator(".loomark-save-status")).toHaveAttribute("title", "Saved on this device")
  await page.getByRole("button", { name: "More actions" }).click()
  await expect(page.getByText("Sign-in status is unavailable. You can keep editing documents on this device.")).toBeVisible()
  await expect(page.getByRole("button", { name: "Sign in with Google" })).toHaveCount(0)
  await page.getByRole("button", { name: "Check account connection" }).click()
  await expect.poll(() => lookups).toBe(2)
  await expect(text).toHaveValue("# Local document\n")
  await expect(page.getByRole("button", { name: "Check account connection" })).toHaveCount(1)
})

test("failed document discovery can be retried without reloading or signing out", async ({ page }) => {
  let available = false
  let discoveries = 0
  await page.route("**/api/account", route => route.fulfill({
    contentType: "application/json",
    body: JSON.stringify({ id: "account-a", name: "Account A" }),
  }))
  await page.route("**/api/documents", route => {
    discoveries += 1
    return route.fulfill(available ? {
      contentType: "application/json",
      body: JSON.stringify({
        documents: [{
          id: fixtureDocumentId("recovered"), revision: 1,
          deleted: false, preview: "Recovered remote",
        }],
        next: null,
      }),
    } : { status: 503 })
  })
  await page.goto("/")
  await expect.poll(() => discoveries).toBe(1)
  await page.getByRole("button", { name: "More actions" }).click()
  const retry = page.locator(".loomark-menu").getByRole("button", { name: "Retry document connection" })
  await expect(retry).toBeVisible()
  available = true
  await retry.click()
  await expect.poll(() => discoveries).toBe(2)
  await expect(page.getByRole("complementary", { name: "Documents" })
    .getByRole("button", { name: "Recovered remote", exact: true })).toBeVisible()
})

test("Google sign-in waits for committed local text before preparing the redirect", async ({ page }) => {
  await page.route("**/api/account", route => route.fulfill({ status: 401 }))
  const provider = "https://accounts.google.com/o/oauth2/v2/auth?state=departure-test"
  await page.route("https://accounts.google.com/**", route => route.fulfill({
    contentType: "text/html",
    body: "<title>Authorization destination</title>",
  }))
  let preparedText: string | undefined
  await page.route("**/api/auth/sign-in/social", async route => {
    preparedText = (await readStoredDocument(page))?.text
    await route.fulfill({
      contentType: "application/json",
      body: JSON.stringify({ url: provider }),
    })
  })
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const document = await readStoredDocument(page)
  if (!document) throw new Error("baseline Source missing")
  await page.evaluate(installDelayedDocumentCommit, sourceKey(document.document_id))
  await page.getByRole("textbox", { name: "Text" }).fill("# Depart with this text\n")
  await page.getByRole("button", { name: "More actions" }).click()
  await page.getByRole("button", { name: "Sign in with Google" }).click()
  await expect(page.getByRole("textbox", { name: "Text" })).toBeDisabled()
  await expect(page).toHaveURL(provider)
  expect(preparedText).toBe("# Depart with this text\n")
})

// Exercise Chromium's real BFCache rather than a reload or synthetic pageshow.
const historyTest = test.extend({
  channel: "chromium",
  launchOptions: { ignoreDefaultArgs: ["--disable-back-forward-cache"] },
})

historyTest("ordinary Back and Forward preserve locally saved writing across repeated visits", async ({ page }) => {
  const away = "https://loomark-history.test/away"
  await page.route("https://loomark-history.test/**", route => route.fulfill({
    contentType: "text/html", body: "<title>Local history fixture</title><p>Another page</p>",
  }))
  await page.goto("/")
  const editor = page.getByRole("textbox", { name: "Text" })
  const source = "# Return here\nKeep this writing."
  await editor.fill(source)
  await expect.poll(async () => (await readStoredDocument(page))?.text).toBe(source)
  await page.goto(away)
  for (let visit = 0; visit < 2; visit++) {
    await page.goBack({ waitUntil: "commit" })
    await expect(editor).toHaveValue(source)
    await expect(editor).toBeEditable()
    await expect(page.locator(".loomark-save-status")).toHaveAccessibleName("Saved on this device")
    await page.goForward({ waitUntil: "commit" })
    await expect(page).toHaveURL(away)
  }
  await page.goBack({ waitUntil: "commit" })
  await expect(editor).toHaveValue(source)
  await editor.press("Control+End")
  await editor.pressSequentially(" Continued.")
  await expect.poll(async () => (await readStoredDocument(page))?.text).toBe(source + " Continued.")
})

historyTest("Back from Google restores editing and refreshes the account from BFCache", async ({ page }) => {
  // The test server uses no-store; make this document eligible for BFCache.
  await page.route("/", async route => {
    const response = await route.fetch()
    await route.fulfill({
      response,
      headers: { ...response.headers(), "cache-control": "no-cache" },
    })
  })
  await page.addInitScript(() => {
    window.addEventListener("pageshow", event => {
      ;(globalThis as typeof globalThis & { __restoredFromBFCache?: boolean })
        .__restoredFromBFCache = event.persisted
    })
  })
  let signedIn = false
  await page.route("**/api/account", route => route.fulfill({
    status: signedIn ? 200 : 401,
    contentType: "application/json",
    body: signedIn ? JSON.stringify({ id: "account-a", name: "Account A" }) : "",
  }))
  const provider = "https://accounts.google.com/o/oauth2/v2/auth?state=history-test"
  await page.route("https://accounts.google.com/**", route => route.fulfill({
    contentType: "text/html",
    body: "<title>Authorization destination</title>",
  }))
  await page.route("**/api/auth/sign-in/social", route => route.fulfill({
    contentType: "application/json",
    body: JSON.stringify({ url: provider }),
  }))
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const document = await readStoredDocument(page)
  if (!document) throw new Error("baseline Source missing")
  const text = page.getByRole("textbox", { name: "Text" })
  const source = "# Keep this when returning from Google\n"
  await text.fill(source)
  await text.evaluate(element => {
    ;(globalThis as typeof globalThis & { __historyTextArea?: Element })
      .__historyTextArea = element
  })
  await page.getByRole("button", { name: "More actions" }).click()
  await page.getByRole("button", { name: "Sign in with Google" }).click()
  await expect(page).toHaveURL(provider)
  signedIn = true
  await page.goBack({ waitUntil: "commit" })

  await expect.poll(() => page.evaluate(() => (
    globalThis as typeof globalThis & { __restoredFromBFCache?: boolean }
  ).__restoredFromBFCache)).toBe(true)
  await expect(text).toBeEnabled()
  await expect(text).toHaveValue(source)
  expect(await text.evaluate(element => element === (
    globalThis as typeof globalThis & { __historyTextArea?: Element }
  ).__historyTextArea)).toBe(true)
  await expect(page.getByRole("button", { name: "Sign out", exact: true })).toBeEnabled()
  await expectStoredDocument(page, { document_id: document.document_id, text: source })

  const edited = `${source}Edited after Back\n`
  await text.fill(edited)
  await expectStoredDocument(page, { document_id: document.document_id, text: edited })
})

test("failed departure save unlocks editing and retries persistence before OAuth", async ({ page }) => {
  await page.route("**/api/account", route => route.fulfill({ status: 401 }))
  let loginRequests = 0
  await page.route("**/api/auth/sign-in/social", async route => {
    loginRequests += 1
    await route.fulfill({ status: 503 })
  })
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const document = await readStoredDocument(page)
  if (!document) throw new Error("baseline Source missing")
  await page.evaluate(installDocumentPutFailure, sourceKey(document.document_id))
  const editor = page.getByRole("textbox", { name: "Text" })
  await editor.fill("# Keep this despite failure\n")
  await page.getByRole("button", { name: "More actions" }).click()
  await page.getByRole("button", { name: "Sign in with Google" }).click()
  await expect(page.getByRole("button", { name: "Retry sign-in" })).toBeVisible()
  await expect(editor).toBeEnabled()
  expect(loginRequests).toBe(0)
  await page.evaluate(() => {
    const state = globalThis as typeof globalThis & {
      __loomarkDocumentPutOriginal?: typeof IDBObjectStore.prototype.put
    }
    if (!state.__loomarkDocumentPutOriginal) throw new Error("failure hook missing")
    IDBObjectStore.prototype.put = state.__loomarkDocumentPutOriginal
  })
  await page.getByRole("button", { name: "Retry sign-in" }).click()
  await expectStoredDocument(page, {
    document_id: document.document_id,
    text: "# Keep this despite failure\n",
  })
  await expect.poll(() => loginRequests).toBe(1)
  await expect(editor).toBeEnabled()
})

test("returning a failed Replica edit to saved text cannot replay obsolete text at sign-in", async ({ page }) => {
  const accountId = "account-a"
  const document = { document_id: fixtureDocumentId("departure-aba"), text: "A" }
  const key = replicaKey(accountId, document.document_id)
  await page.route("**/api/account", route => route.fulfill({
    contentType: "application/json",
    body: JSON.stringify({ id: accountId, name: "Account A" }),
  }))
  await page.route("**/api/documents**", route => route.fulfill({ status: 503 }))
  await page.route("**/api/auth/sign-out", route => route.fulfill({
    contentType: "application/json",
    body: JSON.stringify({ success: true }),
  }))
  let textAtPreparation: string | null = null
  await page.route("**/api/auth/sign-in/social", async route => {
    textAtPreparation = replicaCurrentText(await readStoredDocumentRaw(page, key))
    await route.fulfill({ status: 503 })
  })
  await page.goto("/")
  await replaceStoreRecords(page, [
    { key, value: encodeReadyReplica(accountId, document) },
  ])
  await page.reload()
  await page.getByRole("complementary", { name: "Documents" })
    .getByRole("button", { name: "A", exact: true }).click()
  const editor = page.getByRole("textbox", { name: "Text" })
  await expect(editor).toHaveValue("A")
  await expect(page.getByRole("button", { name: "Retry sync", exact: true }).first()).toBeVisible()
  await page.evaluate(installDocumentPutFailure, key)
  await editor.press("ControlOrMeta+A")
  await editor.pressSequentially("B")
  await expect(page.getByRole("button", { name: "Retry saving", exact: true })).toBeVisible()
  await editor.press("ControlOrMeta+A")
  await editor.pressSequentially("A")
  await page.evaluate(removeDocumentPutFailure)
  await page.getByRole("button", { name: "More actions" }).click()
  await page.getByRole("button", { name: "Sign out", exact: true }).click()
  await page.getByRole("button", { name: "Sign in with Google" }).click()
  await expect(page.getByRole("button", { name: "Retry sign-in" })).toBeVisible()
  expect(textAtPreparation).toBe("A")
  expect(replicaCurrentText(await readStoredDocumentRaw(page, key))).toBe("A")
  await expect(editor).toHaveValue("A")
  await expect(editor).toBeEnabled()
})

test("a new sign-in joins the physical OAuth request after a racing edit", async ({ page, context }) => {
  await page.route("**/api/account", route => route.fulfill({ status: 401 }))
  await page.route("https://accounts.google.com/**", route => route.fulfill({
    contentType: "text/html",
    body: "<title>Authorization destination</title>",
  }))
  let releaseFirst!: () => void
  const firstResponse = new Promise<void>(resolve => { releaseFirst = resolve })
  let loginRequests = 0
  await page.route("**/api/auth/sign-in/social", async route => {
    const attempt = ++loginRequests
    if (attempt === 1) await firstResponse
    await route.fulfill({
      contentType: "application/json",
      headers: { "Set-Cookie": `loomark-test-state=attempt-${attempt}; Path=/; SameSite=Lax` },
      body: JSON.stringify({
        url: `https://accounts.google.com/o/oauth2/v2/auth?state=attempt-${attempt}`,
      }),
    })
  })
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const editor = page.getByRole("textbox", { name: "Text" })
  await page.getByRole("button", { name: "More actions" }).click()
  await page.getByRole("button", { name: "Sign in with Google" }).click()
  await expect.poll(() => loginRequests).toBe(1)
  // Deliver an input accepted before the departure lock, but queued behind it.
  await editor.evaluate(element => {
    const area = element as HTMLTextAreaElement
    const value = "# Newest text\n"
    area.setSelectionRange(0, area.value.length)
    area.dispatchEvent(new InputEvent("beforeinput", {
      bubbles: true, cancelable: true, composed: true, inputType: "insertText", data: value,
    }))
    area.value = value
    area.setSelectionRange(value.length, value.length)
    area.dispatchEvent(new InputEvent("input", {
      bubbles: true, composed: true, inputType: "insertText", data: value,
    }))
  })
  await expect(editor).toBeEnabled()
  await page.getByRole("button", { name: "Sign in with Google" }).click()
  await expect(editor).toBeDisabled()
  expect((await readStoredDocument(page))?.text).toBe("# Newest text\n")
  expect(loginRequests).toBe(1)
  releaseFirst()
  await expect(page).toHaveURL("https://accounts.google.com/o/oauth2/v2/auth?state=attempt-1")
  const cookies = await context.cookies()
  expect(cookies.find(cookie => cookie.name === "loomark-test-state")?.value).toBe("attempt-1")
})

test("account refresh holds an OAuth result until signed-out status is confirmed", async ({ page }) => {
  let releaseLookup!: () => void
  const lookupResponse = new Promise<void>(resolve => { releaseLookup = resolve })
  let accountRequests = 0
  await page.route("**/api/account", async route => {
    if (++accountRequests > 1) await lookupResponse
    await route.fulfill({ status: 401 })
  })
  let releasePrepare!: () => void
  const prepareResponse = new Promise<void>(resolve => { releasePrepare = resolve })
  const provider = "https://accounts.google.com/o/oauth2/v2/auth?state=refresh"
  await page.route("**/api/auth/sign-in/social", async route => {
    await prepareResponse
    await route.fulfill({
      contentType: "application/json",
      body: JSON.stringify({ url: provider }),
    })
  })
  await page.route("https://accounts.google.com/**", route => route.fulfill({
    contentType: "text/html",
    body: "<title>Authorization destination</title>",
  }))
  await page.goto("/")
  await page.getByRole("button", { name: "More actions" }).click()
  await page.getByRole("button", { name: "Sign in with Google" }).click()
  await expect(page.getByRole("textbox", { name: "Text" })).toBeDisabled()
  await page.evaluate(() => document.dispatchEvent(new Event("visibilitychange")))
  await expect.poll(() => accountRequests).toBe(2)
  const prepared = page.waitForResponse("**/api/auth/sign-in/social")
  releasePrepare()
  await (await prepared).finished()
  await expect(page.getByRole("textbox", { name: "Text" })).toBeDisabled()
  releaseLookup()
  await expect(page).toHaveURL(provider)
})

test("an old successful OAuth response cannot bypass a newer pending save", async ({ page, context }) => {
  await page.route("**/api/account", route => route.fulfill({ status: 401 }))
  await page.route("https://accounts.google.com/**", route => route.fulfill({
    contentType: "text/html",
    body: "<title>Authorization destination</title>",
  }))
  let releaseFirst!: () => void
  const firstResponse = new Promise<void>(resolve => { releaseFirst = resolve })
  let loginRequests = 0
  let textAtPreparation: string | undefined
  await page.route("**/api/auth/sign-in/social", async route => {
    const attempt = ++loginRequests
    if (attempt === 1) await firstResponse
    else textAtPreparation = (await readStoredDocument(page))?.text
    await route.fulfill({
      contentType: "application/json",
      headers: { "Set-Cookie": `loomark-test-state=attempt-${attempt}; Path=/; SameSite=Lax` },
      body: JSON.stringify({
        url: `https://accounts.google.com/o/oauth2/v2/auth?state=attempt-${attempt}`,
      }),
    })
  })
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const baseline = await readStoredDocument(page)
  if (!baseline) throw new Error("baseline Source missing")
  await page.evaluate(installDelayedDocumentCommit, sourceKey(baseline.document_id))
  await page.evaluate(() => {
    const state = globalThis as typeof globalThis & { __loomarkDelayedCommitHeld?: boolean }
    state.__loomarkDelayedCommitHeld = true
  })
  const editor = page.getByRole("textbox", { name: "Text" })
  await page.getByRole("button", { name: "More actions" }).click()
  await page.getByRole("button", { name: "Sign in with Google" }).click()
  await expect.poll(() => loginRequests).toBe(1)
  // Deliver an edit accepted before the departure lock, but queued behind it.
  await editor.evaluate(element => {
    const area = element as HTMLTextAreaElement
    const value = "# Saved before the second request\n"
    area.setSelectionRange(0, area.value.length)
    area.dispatchEvent(new InputEvent("beforeinput", {
      bubbles: true, cancelable: true, composed: true, inputType: "insertText", data: value,
    }))
    area.value = value
    area.setSelectionRange(value.length, value.length)
    area.dispatchEvent(new InputEvent("input", {
      bubbles: true, composed: true, inputType: "insertText", data: value,
    }))
  })
  await expect(editor).toBeEnabled()
  await page.getByRole("button", { name: "Sign in with Google" }).click()
  await expect.poll(() => page.evaluate(() =>
    (globalThis as typeof globalThis & { __loomarkDelayedCommitActive?: boolean })
      .__loomarkDelayedCommitActive,
  )).toBe(true)
  const firstCompleted = page.waitForResponse("**/api/auth/sign-in/social")
  releaseFirst()
  await (await firstCompleted).finished()
  await page.evaluate(() => new Promise<void>(resolve =>
    requestAnimationFrame(() => requestAnimationFrame(() => resolve())),
  ))
  await expect(editor).toBeDisabled()
  expect(loginRequests).toBe(1)
  expect(new URL(page.url()).hostname).not.toBe("accounts.google.com")
  await page.evaluate(() => {
    const state = globalThis as typeof globalThis & { __loomarkDelayedCommitHeld?: boolean }
    state.__loomarkDelayedCommitHeld = false
  })
  await expect(page).toHaveURL("https://accounts.google.com/o/oauth2/v2/auth?state=attempt-2")
  expect(loginRequests).toBe(2)
  expect(textAtPreparation).toBe("# Saved before the second request\n")
  const cookies = await context.cookies()
  expect(cookies.find(cookie => cookie.name === "loomark-test-state")?.value).toBe("attempt-2")
})

test("canceling sign-in resumes editing while its physical request stays owned", async ({ page, context }) => {
  await page.route("**/api/account", route => route.fulfill({ status: 401 }))
  await page.route("https://accounts.google.com/**", route => route.fulfill({
    contentType: "text/html",
    body: "<title>Authorization destination</title>",
  }))
  let releaseFirst!: () => void
  const firstResponse = new Promise<void>(resolve => { releaseFirst = resolve })
  let loginRequests = 0
  await page.route("**/api/auth/sign-in/social", async route => {
    const attempt = ++loginRequests
    if (attempt === 1) await firstResponse
    await route.fulfill({
      contentType: "application/json",
      headers: { "Set-Cookie": `loomark-test-state=attempt-${attempt}; Path=/; SameSite=Lax` },
      body: JSON.stringify({
        url: `https://accounts.google.com/o/oauth2/v2/auth?state=attempt-${attempt}`,
      }),
    })
  })
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const editor = page.getByRole("textbox", { name: "Text" })
  const original = await editor.elementHandle()
  const baseline = await editor.inputValue()
  await editor.evaluate(element => (element as HTMLTextAreaElement).setSelectionRange(1, 3))
  await page.getByRole("button", { name: "More actions" }).click()
  await page.getByRole("button", { name: "Sign in with Google" }).click()
  await expect.poll(() => loginRequests).toBe(1)
  await expect(editor).toBeDisabled()
  await page.getByRole("button", { name: "Cancel sign-in" }).press("Enter")
  await expect(editor).toBeEnabled()
  await expect(editor).toHaveValue(baseline)
  await expect(editor).toBeFocused()
  expect(await editor.evaluate(element => {
    const area = element as HTMLTextAreaElement
    return [area.selectionStart, area.selectionEnd]
  })).toEqual([1, 3])
  expect(await original?.evaluate(element => element === document.querySelector("textarea"))).toBe(true)
  await editor.press("ControlOrMeta+A")
  await editor.pressSequentially("# Kept after cancellation")
  await expect.poll(async () => (await readStoredDocument(page))?.text).toBe("# Kept after cancellation")
  await page.getByRole("button", { name: "Sign in with Google" }).click()
  await expect(editor).toBeDisabled()
  expect(loginRequests).toBe(1)
  await page.getByRole("button", { name: "Cancel sign-in" }).click()
  const completed = page.waitForResponse("**/api/auth/sign-in/social")
  releaseFirst()
  await (await completed).finished()
  await page.evaluate(() => new Promise<void>(resolve =>
    requestAnimationFrame(() => requestAnimationFrame(() => resolve())),
  ))
  await expect(editor).toBeEnabled()
  await expect(editor).toHaveValue("# Kept after cancellation")
  expect(new URL(page.url()).hostname).not.toBe("accounts.google.com")
  await page.getByRole("button", { name: "Sign in with Google" }).click()
  await expect(page).toHaveURL("https://accounts.google.com/o/oauth2/v2/auth?state=attempt-2")
  expect(loginRequests).toBe(2)
  const cookies = await context.cookies()
  expect(cookies.find(cookie => cookie.name === "loomark-test-state")?.value).toBe("attempt-2")
})

test("canceling sign-in during saving does not cancel persistence or start OAuth", async ({ page }) => {
  await page.route("**/api/account", route => route.fulfill({ status: 401 }))
  let loginRequests = 0
  await page.route("**/api/auth/sign-in/social", async route => {
    loginRequests++
    await route.fulfill({ status: 503 })
  })
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const baseline = await readStoredDocument(page)
  if (!baseline) throw new Error("baseline Source missing")
  await page.evaluate(installDelayedDocumentCommit, sourceKey(baseline.document_id))
  await page.evaluate(() => {
    const state = globalThis as typeof globalThis & { __loomarkDelayedCommitHeld?: boolean }
    state.__loomarkDelayedCommitHeld = true
  })
  const editor = page.getByRole("textbox", { name: "Text" })
  await editor.press("ControlOrMeta+A")
  await editor.pressSequentially("Still saving")
  await page.getByRole("button", { name: "More actions" }).click()
  await page.getByRole("button", { name: "Sign in with Google" }).click()
  await expect(editor).toBeDisabled()
  await page.getByRole("button", { name: "Cancel sign-in" }).click()
  await expect(editor).toBeEnabled()
  await editor.press("End")
  await editor.pressSequentially(" and still editing")
  await page.evaluate(() => {
    const state = globalThis as typeof globalThis & { __loomarkDelayedCommitHeld?: boolean }
    state.__loomarkDelayedCommitHeld = false
  })
  await expect.poll(async () => (await readStoredDocument(page))?.text).toBe("Still saving and still editing")
  await expect(editor).toHaveValue("Still saving and still editing")
  expect(loginRequests).toBe(0)
})

test("canceling a prepared sign-in during account lookup restores editor focus", async ({ page }) => {
  let releaseLookup!: () => void
  const lookupResponse = new Promise<void>(resolve => { releaseLookup = resolve })
  let accountRequests = 0
  await page.route("**/api/account", async route => {
    if (++accountRequests > 1) await lookupResponse
    await route.fulfill({ status: 401 })
  })
  let releasePrepare!: () => void
  const prepareResponse = new Promise<void>(resolve => { releasePrepare = resolve })
  await page.route("**/api/auth/sign-in/social", async route => {
    await prepareResponse
    await route.fulfill({
      contentType: "application/json",
      body: JSON.stringify({ url: "https://accounts.google.com/o/oauth2/v2/auth?state=canceled" }),
    })
  })
  let redirects = 0
  await page.route("https://accounts.google.com/**", async route => {
    redirects++
    await route.fulfill({ contentType: "text/html", body: "<title>Unexpected redirect</title>" })
  })
  await page.goto("/")
  await page.getByRole("button", { name: "More actions" }).click()
  await page.getByRole("button", { name: "Sign in with Google" }).click()
  await expect(page.getByRole("button", { name: "Cancel sign-in" })).toBeVisible()
  await page.evaluate(() => document.dispatchEvent(new Event("visibilitychange")))
  await expect.poll(() => accountRequests).toBe(2)
  const prepared = page.waitForResponse("**/api/auth/sign-in/social")
  releasePrepare()
  await (await prepared).finished()
  await page.evaluate(() => new Promise<void>(resolve =>
    requestAnimationFrame(() => requestAnimationFrame(() => resolve())),
  ))
  await page.getByRole("button", { name: "Cancel sign-in" }).press("Enter")
  const editor = page.getByRole("textbox", { name: "Text" })
  await expect(editor).toBeEnabled()
  await expect(editor).toBeFocused()
  releaseLookup()
  await expect(page.getByRole("button", { name: "Sign in with Google" })).toBeVisible()
  await editor.press("ControlOrMeta+A")
  await editor.pressSequentially("Keep editing after account lookup")
  await expect.poll(async () => (await readStoredDocument(page))?.text).toBe("Keep editing after account lookup")
  expect(redirects).toBe(0)
})

test("account replica edits persist without creating a Source copy", async ({ page }) => {
  const accountId = "account-a"
  const document = { document_id: fixtureDocumentId("synced"), text: "# Synced\n" }
  const key = replicaKey(accountId, document.document_id)
  await page.route("**/api/account", route => route.fulfill({
    status: 200,
    contentType: "application/json",
    body: JSON.stringify({ id: accountId, name: "Account A" }),
  }))
  await page.goto("/")
  await expect(page.getByRole("textbox", { name: "Text" })).toBeVisible()
  await replaceStoreRecords(page, [{
    key,
    value: encodeReadyReplica(accountId, document),
  }])

  await page.reload()
  const documents = page.getByRole("complementary", { name: "Documents" })
  const synced = documents.getByRole("button", { name: "Synced", exact: true })
  await expect(synced).toBeVisible()
  await synced.click()
  const text = page.getByRole("textbox", { name: "Text" })
  await expect(text).toHaveValue(document.text)

  await text.fill("# Changed\n")
  await expect.poll(async () => {
    const value = await readStoredDocumentRaw(page, key)
    return replicaCurrentText(value)
  }).toBe("# Changed\n")
  expect(await readStoredDocumentRaw(page, sourceKey(document.document_id)))
    .toBeUndefined()
})

test("Replica write failure changes the save indicator until retry succeeds", async ({ page }) => {
  const accountId = "account-a"
  const document = { document_id: fixtureDocumentId("failed-replica"), text: "# Synced\n" }
  const key = replicaKey(accountId, document.document_id)
  await page.route("**/api/account", route => route.fulfill({
    contentType: "application/json",
    body: JSON.stringify({ id: accountId, name: "Account A" }),
  }))
  await page.route("**/api/documents**", route => route.fulfill({ status: 503 }))
  await page.goto("/")
  await replaceStoreRecords(page, [{ key, value: encodeReadyReplica(accountId, document) }])
  await page.reload()
  await page.getByRole("complementary", { name: "Documents" })
    .getByRole("button", { name: "Synced", exact: true }).click()
  const text = page.getByRole("textbox", { name: "Text" })
  const indicator = page.locator(".loomark-save-status")
  await expect(text).toHaveValue(document.text)
  await expect(indicator).toHaveAttribute("title", "Saved on this device")
  await page.evaluate(installDocumentPutFailure, key)
  await text.fill("# Edited\n")
  await expect(page.getByRole("button", { name: "Retry saving", exact: true })).toBeVisible()
  await expect(indicator).toHaveAttribute("title", "Not saved")
  const retry = page.locator(".loomark-footer").getByRole("button", { name: "Retry saving", exact: true })
  await page.getByRole("button", { name: "Toggle documents" }).click()
  for (const width of [320, 390, 1280]) {
    await page.setViewportSize({ width, height: 844 })
    await expect(indicator).toHaveAccessibleName("Not saved")
    if (width <= 641) {
      await expect(indicator.locator(".loomark-save-caption")).toBeHidden()
    } else {
      await expect(indicator.locator(".loomark-save-caption")).toBeVisible()
    }
    await expect.poll(async () => {
      const action = await retry.boundingBox()
      const modes = await page.locator(".loomark-bottom-actions").boundingBox()
      return action !== null && modes !== null && action.x + action.width + 8 <= modes.x
    }).toBe(true)
    const bounds = await retry.boundingBox()
    expect(bounds).not.toBeNull()
    expect(bounds!.height).toBeGreaterThanOrEqual(width <= 641 ? 44 : 32)
    await retry.focus()
    await expect(retry).toBeFocused()
    expect(await retry.evaluate(element => {
      const rect = element.getBoundingClientRect()
      return element.contains(element.ownerDocument.elementFromPoint(rect.x + rect.width / 2, rect.y + rect.height / 2))
    })).toBe(true)
  }
  await page.evaluate(removeDocumentPutFailure)
  await retry.click()
  await expect.poll(async () => replicaCurrentText(await readStoredDocumentRaw(page, key)))
    .toBe("# Edited\n")
  await expect(indicator).toHaveAttribute("title", "Saved on this device")
})

test("duplicate leads select and delete by Document ID", async ({ page }) => {
  const documentA = { document_id: fixtureDocumentId("document-a"), text: "# Same\n" }
  const documentB = { document_id: fixtureDocumentId("document-b"), text: "# Same\n" }
  await openStoredDocuments(page, [documentB, documentA])
  const documents = page.getByRole("complementary", { name: "Documents" })
  const selected = documents.getByRole("button", { name: "Same (2 of 2)", exact: true })
  await selected.click()
  await expect(selected).toHaveAttribute("data-state", "active")
  await expect.poll(() => readStoredDocumentRaw(page, EDITING_DOCUMENT_KEY))
    .toBe(documentB.document_id)

  await openDeleteConfirmation(page, "Same (1 of 2)")
  await page.getByRole("alertdialog").getByRole("button", { name: "Delete document" }).click()
  await expect.poll(() => readStoredDocuments(page)).toEqual([documentB])
  await expect(documents.getByRole("button", { name: "Same", exact: true }))
    .toHaveAttribute("data-state", "active")
  await expect(documents.getByRole("button", { name: /^Same \(/ })).toHaveCount(0)
})

test("page-local recency reorders edits but reload restores lexical order", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const documentA = { document_id: fixtureDocumentId("document-a"), text: "# A\n" }
  const documentB = { document_id: fixtureDocumentId("document-b"), text: "# B\n" }
  const documentC = { document_id: fixtureDocumentId("document-c"), text: "# C\n" }
  await replaceStoreRecords(page, [
    { key: sourceKey(documentA.document_id), value: encodeStoredDocument(documentA) },
    { key: sourceKey(documentB.document_id), value: encodeStoredDocument(documentB) },
    { key: sourceKey(documentC.document_id), value: encodeStoredDocument(documentC) },
  ])
  await page.reload()
  const documents = page.getByRole("complementary", { name: "Documents" })
  const order = async () => documents
    .locator('[data-slot="sidebar-menu-button"][aria-label]')
    .evaluateAll(buttons => (
      buttons.map(button => button.getAttribute("aria-label"))
        .filter((label): label is string => label !== null && !label.startsWith("Delete ")
          && label !== "Documents" && label !== "New document"
    )))
  await expect.poll(order).toEqual(["A", "B", "C"])

  const text = page.getByRole("textbox", { name: "Text" })
  await documents.getByRole("button", { name: "C", exact: true }).click()
  await expect(text).toHaveValue(documentC.text)
  await expect.poll(order).toEqual(["A", "B", "C"])
  await text.fill("# C changed\n")
  await expect.poll(order).toEqual(["C changed", "A", "B"])
  await expectStoredDocument(page, { ...documentC, text: "# C changed\n" })
  await documents.getByRole("button", { name: "B", exact: true }).click()
  await expect.poll(order).toEqual(["C changed", "A", "B"])

  await page.reload()
  await expect.poll(order).toEqual(["A", "B", "C changed"])

  await page.getByLabel("Import Markdown")
    .setInputFiles("tests/fixtures/import-bom-crlf.bin")
  await expect.poll(order).toHaveLength(4)
  await expect.poll(async () => (await order())[0]).toBe("Imported\ntext")
  await page.getByRole("button", { name: "B", exact: true }).click()
  await expect.poll(async () => (await order())[0]).toBe("Imported\ntext")

  await page.locator("#loomark-editor").getByRole("button", { name: "New document" }).click()
  await expect(text).toHaveValue("")
  await text.fill("# New promotion\n")
  await expect.poll(async () => (await order())[0]).toBe("New promotion")
})

test("startup is read-only and restores an accepted Editing Document", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const documentA = { document_id: fixtureDocumentId("document-a"), text: "# A\n" }
  const documentB = { document_id: fixtureDocumentId("document-b"), text: "# B\n" }
  await replaceStoreRecords(page, [
    { key: sourceKey(documentA.document_id), value: encodeStoredDocument(documentA) },
    { key: sourceKey(documentB.document_id), value: encodeStoredDocument(documentB) },
    { key: EDITING_DOCUMENT_KEY, value: documentB.document_id },
  ])

  await page.addInitScript(installStoreMutationLog)
  await page.reload()
  const documents = page.getByRole("complementary", { name: "Documents" })
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue(documentB.text)
  await expect(documents.getByRole("button", { name: "B", exact: true }))
    .toHaveAttribute("data-state", "active")
  expect(await readStoreMutationLog(page)).toEqual([])
})

test("a non-string Editing Document is equivalent to no Editing Document", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const documentA = { document_id: fixtureDocumentId("document-a"), text: "# A\n" }
  await replaceStoreRecords(page, [
    { key: sourceKey(documentA.document_id), value: encodeStoredDocument(documentA) },
    { key: EDITING_DOCUMENT_KEY, value: { unsupported: true } },
  ])

  await page.reload()
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue(documentA.text)
  await expect(page.getByRole("heading", { name: "Document recovery" })).toHaveCount(0)
})

test("Document Sidebar switches saved Sources A to B to A without cross-document undo", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const documentA = { document_id: fixtureDocumentId("document-a"), text: "# A\n" }
  const documentB = { document_id: fixtureDocumentId("document-b"), text: "# B\n" }
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
  await expectStoredDocument(page, { ...documentA, text: "# A edited\n" })
  await page.getByRole("tab", { name: "Split" }).click()
  await expect(page.getByRole("heading", { name: "A edited" })).toBeVisible()

  await documents.getByRole("button", { name: "B", exact: true }).click()
  await expect(text).toHaveValue(documentB.text)
  await expect.poll(() => readStoredDocumentRaw(page, EDITING_DOCUMENT_KEY))
    .toBe(documentB.document_id)
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
  await expect.poll(() => readStoredDocumentRaw(page, EDITING_DOCUMENT_KEY))
    .toBe(documentA.document_id)
  await expect(page.getByRole("heading", { name: "A edited" })).toBeVisible()
  expect(await readStoredDocumentRaw(page, sourceKey(documentB.document_id)))
    .toBe(encodeStoredDocument(documentB))
  await page.reload()
  await expect(text).toHaveValue("# A edited\n")
})

test("Editing Document writes are last-invocation-wins", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const documentA = { document_id: fixtureDocumentId("document-a"), text: "# A\n" }
  const documentB = { document_id: fixtureDocumentId("document-b"), text: "# B\n" }
  await replaceStoreRecords(page, [
    { key: sourceKey(documentA.document_id), value: encodeStoredDocument(documentA) },
    { key: sourceKey(documentB.document_id), value: encodeStoredDocument(documentB) },
  ])

  await page.reload()
  await page.evaluate(installDelayedDocumentCommit, EDITING_DOCUMENT_KEY)
  const documents = page.getByRole("complementary", { name: "Documents" })
  const text = page.getByRole("textbox", { name: "Text" })
  await documents.getByRole("button", { name: "B", exact: true }).click()
  await documents.getByRole("button", { name: "A", exact: true }).click()
  await expect(text).toHaveValue(documentA.text)
  await expect.poll(() => page.evaluate(() => (
    (globalThis as typeof globalThis & {
      __loomarkDelayedCommitCompletions?: number
    }).__loomarkDelayedCommitCompletions ?? 0
  ))).toBe(2)
  await expect.poll(() => readStoredDocumentRaw(page, EDITING_DOCUMENT_KEY))
    .toBe(documentA.document_id)

  await page.reload()
  await expect(text).toHaveValue(documentA.text)
})

test("remember failure cannot affect editing or Source recovery", async ({ page }) => {
  await page.addInitScript(installDocumentPutFailure, EDITING_DOCUMENT_KEY)
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const documentA = { document_id: fixtureDocumentId("document-a"), text: "# A\n" }
  const documentB = { document_id: fixtureDocumentId("document-b"), text: "# B\n" }
  await replaceStoreRecords(page, [
    { key: sourceKey(documentA.document_id), value: encodeStoredDocument(documentA) },
    { key: sourceKey(documentB.document_id), value: encodeStoredDocument(documentB) },
  ])

  await page.reload()
  const documents = page.getByRole("complementary", { name: "Documents" })
  const text = page.getByRole("textbox", { name: "Text" })
  await documents.getByRole("button", { name: "B", exact: true }).click()
  await expect(text).toHaveValue(documentB.text)
  await expect(page.getByRole("heading", { name: "Document recovery" })).toHaveCount(0)
  expect(await readStoredDocumentRaw(page, EDITING_DOCUMENT_KEY)).toBeUndefined()

  await page.reload()
  await expect(text).toHaveValue(documentA.text)
  await expect(page.getByRole("heading", { name: "Document recovery" })).toHaveCount(0)
})

test("New stays ephemeral and its first Source save is not remembered", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const before = await readStoredDocuments(page)
  expect(before).toHaveLength(1)

  const documents = page.getByRole("complementary", { name: "Documents" })
  await page.evaluate(installStoreMutationLog)
  await page.locator("#loomark-editor").getByRole("button", { name: "New document" }).click()
  await expect.poll(() => readStoredDocuments(page).then(documents => documents.length)).toBe(1)
  expect(await readStoreMutationLog(page)).toEqual([])
  const after = await readStoredDocuments(page)
  expect(after).toEqual(before)
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue("")
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Project notes\n")
  await expect.poll(() => readStoredDocuments(page).then(documents => documents.find(
    document => !before.some(previous => previous.document_id === document.document_id),
  ) ?? null)).not.toBeNull()
  const created = (await readStoredDocuments(page)).find(
    document => !before.some(previous => previous.document_id === document.document_id),
  )
  if (!created) throw new Error("created Source missing")
  await expectStoredDocument(page, { ...created, text: "# Project notes\n" })
  await expect(documents.locator('[data-state="active"]')).toContainText("Project notes")
  const mutations = await readStoreMutationLog(page)
  expect(mutations.some(mutation => mutation.key === sourceKey(created.document_id)))
    .toBe(true)
  expect(mutations.some(mutation => mutation.key === EDITING_DOCUMENT_KEY))
    .toBe(false)
  expect(await readStoredDocumentRaw(page, EDITING_DOCUMENT_KEY)).toBeUndefined()
  const renamed = await readStoredDocuments(page)

  await page.reload()
  const firstLexical = [...renamed].sort((left, right) => (
    left.document_id.localeCompare(right.document_id)
  ))[0]
  const firstName = firstLexical.text === "# Project notes\n"
    ? "Project notes"
    : "Untitled"
  await expect(documents.getByRole("button", { name: firstName, exact: true }))
    .toHaveAttribute("data-state", "active")
  await expect(text).toHaveValue(firstLexical.text)
  expect(await readStoredDocumentRaw(page, EDITING_DOCUMENT_KEY)).toBeUndefined()
  expect(await readStoredDocuments(page)).toEqual(renamed)
})

test("Delete document removes a non-active Source without moving the editor", async ({ page }) => {
  const documentA = { document_id: fixtureDocumentId("document-a"), text: "# A\n" }
  const documentB = { document_id: fixtureDocumentId("document-b"), text: "# B\n" }
  await openStoredDocuments(page, [documentA, documentB])

  const text = page.getByRole("textbox", { name: "Text" })
  await expect(text).toHaveValue(documentA.text)
  await openDeleteConfirmation(page, "B")
  const dialog = page.getByRole("alertdialog")
  await expect(dialog).toContainText('Delete "B"?')
  await dialog.getByRole("button", { name: "Delete document" }).click()

  await expect.poll(() => readStoredDocuments(page)).toEqual([documentA])
  await expect(text).toHaveValue(documentA.text)
  await page.reload()
  await expect(text).toHaveValue(documentA.text)
  await expect(page.getByRole("button", { name: "B", exact: true })).toHaveCount(0)
})

test("Delete icon is disabled while deletion is pending", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const documentA = { document_id: fixtureDocumentId("document-a"), text: "# A\n" }
  const documentB = { document_id: fixtureDocumentId("document-b"), text: "# B\n" }
  await replaceStoreRecords(page, [
    { key: sourceKey(documentA.document_id), value: encodeStoredDocument(documentA) },
    { key: sourceKey(documentB.document_id), value: encodeStoredDocument(documentB) },
  ])
  await page.addInitScript(() => {
    const prototype = IDBObjectStore.prototype as any
    const originalDelete = prototype.delete
    prototype.delete = function(this: IDBObjectStore, key: IDBValidKey) {
      const request = originalDelete.call(this, key)
      if (typeof key === "string" && key.startsWith("source/v1/")) {
        const store = this
        let released = false
        ;(window as any).releasePendingDelete = () => { released = true }
        const keepAlive = () => {
          if (released) return
          const request = store.get("__loomark_delete_keepalive__")
          request.addEventListener("success", keepAlive, { once: true })
          request.addEventListener("error", keepAlive, { once: true })
        }
        keepAlive()
      }
      return request
    }
  })
  await page.reload()

  const documents = page.getByRole("complementary", { name: "Documents" })
  await documents.getByRole("button", { name: "B", exact: true }).click()
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue("# B\n")
  await openDeleteConfirmation(page, "B")
  await page.getByRole("alertdialog").getByRole("button", { name: "Delete document" }).click()
  await expect(documents.getByRole("button", { name: 'Delete "B"', exact: true }))
    .toBeDisabled()
  await page.evaluate(() => (window as any).releasePendingDelete())
  await expect.poll(() => readStoredDocumentRaw(page, sourceKey(documentB.document_id)))
    .toBeUndefined()
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue("# A\n")
})

test("Delete document activates and remembers the newest fallback", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const documentA = { document_id: fixtureDocumentId("document-a"), text: "# A\n" }
  const documentB = { document_id: fixtureDocumentId("document-b"), text: "# B\n" }
  const documentC = { document_id: fixtureDocumentId("document-c"), text: "# C\n" }
  await replaceStoreRecords(page, [
    { key: sourceKey(documentA.document_id), value: encodeStoredDocument(documentA) },
    { key: sourceKey(documentB.document_id), value: encodeStoredDocument(documentB) },
    { key: sourceKey(documentC.document_id), value: encodeStoredDocument(documentC) },
    { key: EDITING_DOCUMENT_KEY, value: documentA.document_id },
  ])
  await page.reload()

  const text = page.getByRole("textbox", { name: "Text" })
  const documents = page.getByRole("complementary", { name: "Documents" })
  await documents.getByRole("button", { name: "C", exact: true }).click()
  await expect(text).toHaveValue(documentC.text)
  const newestC = { ...documentC, text: "# C newest\n" }
  await text.fill(newestC.text)
  await expectStoredDocument(page, newestC)
  await documents.getByRole("button", { name: "A", exact: true }).click()
  await openDeleteConfirmation(page, "A")
  const dialog = page.getByRole("alertdialog")
  await dialog.getByRole("button", { name: "Delete document" }).click()

  await expect(text).toHaveValue(newestC.text)
  await expect.poll(() => readStoredDocumentRaw(page, EDITING_DOCUMENT_KEY))
    .toBe(documentC.document_id)
  await expect.poll(() => readStoredDocumentRaw(page, sourceKey(documentA.document_id)))
    .toBeUndefined()
  await page.reload()
  await expect(text).toHaveValue(newestC.text)
})

test("Delete document cancellation preserves the Source and editor", async ({ page }) => {
  const documentA = { document_id: fixtureDocumentId("document-a"), text: "# A\n" }
  const documentB = { document_id: fixtureDocumentId("document-b"), text: "# B\n" }
  await openStoredDocuments(page, [documentA, documentB])

  await openDeleteConfirmation(page, "B")
  const dialog = page.getByRole("alertdialog")
  await dialog.getByRole("button", { name: "Cancel" }).click()

  await expect(dialog).toHaveCount(0)
  await expect.poll(() => readStoredDocuments(page)).toEqual([documentA, documentB])
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Still editable\n")
  await expect(text).toHaveValue("# Still editable\n")
})

test("queued full-value input cannot commit a rejected range edit to Documents", async ({ page }) => {
  const documentA = { document_id: fixtureDocumentId("document-a"), text: "# A\n" }
  const documentB = { document_id: fixtureDocumentId("document-b"), text: "# B\n" }
  await openStoredDocuments(page, [documentA, documentB])
  await page.getByRole("tab", { name: "Split" }).click()
  const text = page.getByRole("textbox", { name: "Text" })
  const preview = page.getByRole("region", { name: "Markdown preview" })
  await expect(text).toHaveValue(documentA.text)
  await expect(preview.getByRole("heading", { name: "A" })).toBeVisible()
  await page.evaluate(installDocumentPutLog, sourceKey(documentA.document_id))

  // A divergent native value gives valid before/after range facts whose start
  // is past the accepted Document text. Loomark rejects that ReplaceRange and
  // restores the Document; the subsequent ReplaceAll was queued before that
  // rejection and must not commit the divergent native value.
  const beforeDrain = await text.evaluate(element => {
    const area = element as HTMLTextAreaElement
    area.value = "# A\nLONG"
    area.setSelectionRange(area.value.length, area.value.length)
    area.dispatchEvent(new InputEvent("beforeinput", {
      bubbles: true, composed: true, cancelable: true, inputType: "insertText", data: "!",
    }))
    area.value += "!"
    area.setSelectionRange(area.value.length, area.value.length)
    area.dispatchEvent(new InputEvent("input", {
      bubbles: true, composed: true, inputType: "insertText", data: "!",
    }))
    area.value += "X"
    area.dispatchEvent(new InputEvent("input", {
      bubbles: true, composed: true, inputType: "insertText", data: "X",
    }))
    return area.value
  })
  expect(beforeDrain).toBe("# A\nLONG!X")
  await expect(text).toHaveValue(documentA.text)
  await expect(preview.getByRole("heading", { name: "A" })).toBeVisible()
  await expect(preview).not.toContainText("LONG")
  await page.waitForTimeout(350) // Let an incorrectly accepted edit reach quiet Autosave.
  expect(await readDocumentPutLog(page)).toEqual([])
  expect(await readStoredDocuments(page)).toEqual([documentA, documentB])

  await text.evaluate(element => (element as HTMLTextAreaElement).setSelectionRange(3, 3))
  await text.press("B")
  await expect(text).toHaveValue("# AB\n")
  await expect(preview.getByRole("heading", { name: "AB" })).toBeVisible()
  await expectStoredDocument(page, { ...documentA, text: "# AB\n" })
})

test("final Delete leaves an empty New with a live Split Preview", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const split = page.getByRole("tab", { name: "Split" })
  await split.click()
  await page.getByRole("button", { name: /^Delete "/ }).first().click()
  await page.getByRole("alertdialog").getByRole("button", { name: "Delete document" }).click()
  const text = page.getByRole("textbox", { name: "Text" })
  await expect(text).toHaveValue("")
  await expect(split).toHaveAttribute("aria-selected", "true")
  await expect.poll(() => readStoredDocuments(page)).toEqual([])
  await text.fill("# Recreated\n")
  await expect(page.getByRole("heading", { name: "Recreated" })).toBeVisible()
  await expect.poll(() => readStoredDocuments(page)).toHaveLength(1)
})

// The browser's crypto.randomUUID property is non-configurable in the supported
// Playwright runtime, so the obsolete identity-retry browser case is covered by
// the pure repository tests instead of attempting to patch the platform API.
test("Document delete icon is directly accessible and keyboard operable", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Icon test\n")

  const deleteButton = page.getByRole("button", { name: 'Delete "Icon test"', exact: true })
  await expect(deleteButton).toHaveAttribute("title", 'Delete "Icon test"')
  await deleteButton.focus()
  await page.keyboard.press("Enter")
  const dialog = page.getByRole("alertdialog")
  await expect(dialog).toContainText('Delete "Icon test"?')
  await dialog.getByRole("button", { name: "Cancel" }).click()
  await expect(dialog).toHaveCount(0)
  await expect(text).toHaveValue("# Icon test\n")
})

test("Document controls remain accessible without horizontal overflow at 390 px", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const toggle = page.getByRole("button", { name: "Toggle documents" })
  await expect(toggle)
    .toHaveAttribute("aria-expanded", "false")
  const togglePosition = await toggle.evaluate(element => ({
    x: element.getBoundingClientRect().x,
    y: element.getBoundingClientRect().y,
  }))
  expect(togglePosition).toEqual({ x: 8, y: 5 })
  const sidebar = page.locator("#loomark-document-sidebar")
  const editor = page.locator("#loomark-editor")
  await expect(sidebar)
    .toHaveAttribute("aria-hidden", "true")
  const topBar = page.locator("header")
  expect(await topBar.evaluate(element => ({
    height: element.getBoundingClientRect().height,
    scrollHeight: element.scrollHeight,
  }))).toEqual({ height: 52, scrollHeight: 52 })
  await expect(page.getByRole("tab", { name: "Text" })).toBeVisible()
  await expect(page.getByRole("tab", { name: "Preview" })).toBeVisible()
  await expect(page.getByRole("tab", { name: "Split" })).toBeVisible()
  await toggle.focus()
  await page.keyboard.press("Enter")
  await expect(sidebar).toBeVisible()
  expect(await toggle.evaluate(element => ({
    x: element.getBoundingClientRect().x,
    y: element.getBoundingClientRect().y,
  }))).toEqual(togglePosition)
  await expect(sidebar).toHaveCSS("opacity", "1")
  expect(await editor.evaluate(element => (element as HTMLElement).inert)).toBe(true)
  await expect.poll(() => sidebar.evaluate(element => (
    element.contains(document.activeElement)
  ))).toBe(true)
  expect(await sidebar.evaluate(element => element.getBoundingClientRect().width))
    .toBe(390)
  const newDocument = sidebar.getByRole("button", { name: "New document" })
  await expect(newDocument).toBeVisible()
  await expect(newDocument.locator(".i-lucide-square-pen")).toBeVisible()
  const sidebarFooter = sidebar.locator('[data-slot="sidebar-footer"]')
  await expect(sidebarFooter.getByRole("toolbar", { name: "Example documents" }))
    .toBeVisible()
  await expect(sidebarFooter.locator("label[title=\"Import Markdown\"] .i-lucide-upload"))
    .toBeVisible()
  await expect(sidebarFooter.getByText("Import", { exact: true })).toBeVisible()
  const importControl = sidebarFooter.locator("label[title=\"Import Markdown\"]")
  await expect(importControl).toHaveCSS("cursor", "pointer")
  const importInput = page.getByLabel("Import Markdown")
  const exportControl = sidebarFooter.getByRole("button", { name: "Export Markdown" })
  await exportControl.focus()
  await page.keyboard.press("Shift+Tab")
  await expect(importInput).toBeFocused()
  expect(await importInput.evaluate(input => input.matches(":focus-visible"))).toBe(true)
  await expect(importControl).toHaveCSS("outline-style", "solid")
  await expect(importControl).toHaveCSS("outline-width", "2px")
  expect(await importControl.evaluate(label => {
    const bounds = label.getBoundingClientRect()
    const target = document.elementFromPoint(
      bounds.x + bounds.width / 2,
      bounds.y + bounds.height / 2,
    )
    return target !== null && label.contains(target)
  })).toBe(true)
  await expect(exportControl.locator(".i-lucide-download")).toBeVisible()
  await expect(sidebarFooter.getByText("Export", { exact: true })).toBeVisible()
  expect(await page.evaluate(() => ({
    viewport: window.innerWidth,
    scrollWidth: document.documentElement.scrollWidth,
  }))).toEqual({ viewport: 390, scrollWidth: 390 })
})

test("Square-pen New control creates a document", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const text = page.getByRole("textbox", { name: "Text" })
  const newDocument = page.locator("#loomark-editor").getByRole("button", { name: "New document" })
  await text.fill("# Existing\n")
  await expect(newDocument).toBeEnabled()

  await newDocument.click()
  await expect(text).toHaveValue("")
})

test("Document sidebar spans the viewport and slides the editor while its toggle stays fixed", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const toggle = page.getByRole("button", { name: "Toggle documents" })
  const sidebar = page.locator("#loomark-document-sidebar")
  const text = page.getByRole("textbox", { name: "Text" })
  const closedPosition = await toggle.evaluate(element => ({
    x: element.getBoundingClientRect().x,
    y: element.getBoundingClientRect().y,
  }))
  expect(closedPosition).toEqual({ x: 12, y: 5 })
  await expect(toggle).toHaveAttribute("aria-expanded", "true")
  await expect(sidebar).toBeVisible()
  expect(await sidebar.evaluate(element => ({
    top: element.getBoundingClientRect().top,
    bottom: element.getBoundingClientRect().bottom,
  }))).toEqual({ top: 0, bottom: 900 })
  const openTextX = await text.evaluate(element => element.getBoundingClientRect().x)
  expect(openTextX).toBeGreaterThan(0)
  await toggle.click()
  await expect(sidebar).toHaveAttribute("aria-hidden", "true")
  expect(await toggle.evaluate(element => ({
    x: element.getBoundingClientRect().x,
    y: element.getBoundingClientRect().y,
  }))).toEqual(closedPosition)
  await expect.poll(() => text.evaluate(element => element.getBoundingClientRect().x)).toBe(0)
  await toggle.click()
  await expect(sidebar).toBeVisible()
  expect(await toggle.evaluate(element => ({
    x: element.getBoundingClientRect().x,
    y: element.getBoundingClientRect().y,
  }))).toEqual(closedPosition)
  await expect.poll(() => text.evaluate(element => element.getBoundingClientRect().x)).toBe(openTextX)
})

test("Document sidebar respects reduced motion", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" })
  await page.setViewportSize({ width: 1280, height: 900 })
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const sidebar = page.locator("#loomark-document-sidebar")
  const shell = page.locator('[data-slot="sidebar-shell"][data-collapsible="offcanvas"]')

  await expect(sidebar).toHaveCSS("transition-duration", "0s")
  await expect(shell).toHaveCSS("transition-duration", "0s")
  await page.getByRole("button", { name: "Toggle documents" }).click()
  await expect(sidebar).toHaveAttribute("aria-hidden", "true")
})

test("Sidebar visibility survives breakpoints but resets on reload", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const toggle = page.getByRole("button", { name: "Toggle documents" })
  const sidebar = page.locator("#loomark-document-sidebar")
  const editor = page.locator("#loomark-editor")
  const text = page.getByRole("textbox", { name: "Text" })
  await expect(toggle).toHaveAttribute("aria-expanded", "true")
  await text.focus()
  await expect(text).toBeFocused()
  await page.setViewportSize({ width: 390, height: 844 })
  await expect(toggle).toHaveAttribute("aria-expanded", "true")
  expect(await editor.evaluate(element => (element as HTMLElement).inert)).toBe(true)
  await expect.poll(() => sidebar.evaluate(element => (
    element.contains(document.activeElement)
  ))).toBe(true)
  await toggle.click()
  await expect(toggle).toHaveAttribute("aria-expanded", "false")
  expect(await editor.evaluate(element => (element as HTMLElement).inert)).toBe(false)
  await page.setViewportSize({ width: 1280, height: 900 })
  await expect(toggle).toHaveAttribute("aria-expanded", "false")
  await page.reload()
  await expect(toggle).toHaveAttribute("aria-expanded", "true")
})

test("Document switch does not wait for the active Source to save", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const documentA = { document_id: fixtureDocumentId("document-a"), text: "# A\n" }
  const documentB = { document_id: fixtureDocumentId("document-b"), text: "# B\n" }
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
  await expect(text).toHaveValue("# A\nx")
  await expect(page.getByText("Wait for saving to finish.")).toHaveCount(0)
  await documentBButton.click()
  await expect(text).toHaveValue(documentB.text)
  await expectStoredDocument(page, { ...documentA, text: "# A\nx" })
})

test("active remains unknown and does not hide valid Documents", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const valid = { document_id: fixtureDocumentId("valid-document"), text: "# Valid\n" }
  const legacy = JSON.stringify({ document_id: "legacy-document", text: "# Legacy\n", change_order: 1 })
  await replaceStoreRecords(page, [
    { key: LEGACY_ACTIVE_KEY, value: legacy },
    { key: sourceKey(valid.document_id), value: encodeStoredDocument(valid) },
  ])

  await page.reload()
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue(valid.text)
  expect(await readStoredDocumentRaw(page, LEGACY_ACTIVE_KEY)).toBe(legacy)
})

test("old three-field Source records remain preserved and unreadable", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const valid = { document_id: fixtureDocumentId("valid-document"), text: "# Valid\n" }
  const legacyKey = sourceKey("legacy-document")
  const legacy = JSON.stringify({ document_id: "legacy-document", text: "# Legacy\n", change_order: 7 })
  await replaceStoreRecords(page, [
    { key: legacyKey, value: legacy },
    { key: sourceKey(valid.document_id), value: encodeStoredDocument(valid) },
  ])

  await page.reload()
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue(valid.text)
  await expect(page.getByRole("button", { name: "Legacy", exact: true })).toHaveCount(0)
  expect(await readStoredDocumentRaw(page, legacyKey)).toBe(legacy)
})


test("unknown metadata is preserved and cannot override a Source", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const document = { document_id: fixtureDocumentId("document-a"), text: "# Current\n" }
  const metadata = JSON.stringify({
    entries: [{ document_id: document.document_id, name: "Stale" }],
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
        document_id: fixtureDocumentId(`scan-${index}`),
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
    const document = { document_id: fixtureDocumentId(`put-${name}`), text }
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
  await page.getByRole("button", { name: "Toggle documents" }).click()
  await expect.poll(() => page.getByRole("textbox", { name: "Text" })
    .evaluate(element => element.getBoundingClientRect().left)).toBe(0)

  const styles = await page.evaluate(() => {
    const modeBar = document.querySelector(".loomark-topbar") as HTMLElement
    const selectedTab = document.querySelector('[role="tab"][aria-selected="true"]') as HTMLElement
    const text = document.getElementById("loomark-text") as HTMLTextAreaElement
    return {
      bodyMargin: getComputedStyle(document.body).margin,
      boxSizing: getComputedStyle(document.documentElement).boxSizing,
      modeBarDisplay: getComputedStyle(modeBar).display,
      modeBarHeight: getComputedStyle(modeBar).height,
      selectedBackground: getComputedStyle(selectedTab).backgroundColor,
      textFont: getComputedStyle(text).fontFamily,
      textPaddingLeft: Number.parseFloat(getComputedStyle(text).paddingLeft),
    }
  })
  expect(styles.bodyMargin).toBe("0px")
  expect(styles.boxSizing).toBe("border-box")
  expect(styles.modeBarDisplay).toBe("flex")
  expect(styles.modeBarHeight).toBe("48px")
  expect(styles.selectedBackground).not.toBe("rgba(0, 0, 0, 0)")
  expect(styles.textFont).toContain("ui-monospace")
  expect(styles.textPaddingLeft).toBe(70)

  await page.setViewportSize({ width: 640, height: 700 })
  await expect.poll(() => page.locator("#loomark-text").evaluate(element => (
    getComputedStyle(element).paddingLeft
  ))).toBe("32px")

  await page.getByRole("button", { name: "Toggle documents" }).click()
  await page.getByRole("button", {
    name: "Create Markdown feature tour example document",
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
    .evaluate(element => getComputedStyle(element).lineHeight))).toBeCloseTo(19.6, 1)
  expect(await preview.locator("p code").first().evaluate(element => ({
    before: getComputedStyle(element, "::before").content,
    after: getComputedStyle(element, "::after").content,
  }))).toEqual({ before: "none", after: "none" })
  await expect.poll(() => preview.locator("p").first().evaluate(element => (
    getComputedStyle(element).fontSize
  ))).toBe("16px")
  expect(await preview.locator("p").first().evaluate(element => (
    getComputedStyle(element).marginTop
  ))).toBe("18px")
  expect(await preview.locator("h2").first().evaluate(element => (
    getComputedStyle(element).marginTop
  ))).toBe("28px")

  await page.setViewportSize({ width: 1280, height: 700 })
  await expect.poll(() => preview.locator("p").first().evaluate(element => (
    getComputedStyle(element).fontSize
  ))).toBe("16px")
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
  await expect(splitTab).toBeFocused()
  await expect(splitTab).toHaveAttribute("aria-selected", "true")
  await expect(editorPanel).toHaveAttribute(
    "aria-labelledby",
    "loomark-mode-split",
  )
  await expect(preview).toBeVisible()

  await page.keyboard.press("ArrowRight")
  await expect(previewTab).toBeFocused()
  await expect(previewTab).toHaveAttribute("aria-selected", "true")
  await expect(editorPanel).toHaveAttribute("aria-labelledby", "loomark-mode-preview")
  await expect(page.getByRole("textbox", { name: "Text" })).toBeHidden()
  await expect(preview).toBeVisible()

  await page.keyboard.press("ArrowLeft")
  await expect(splitTab).toBeFocused()
  await expect(splitTab).toHaveAttribute("aria-selected", "true")
})

test("Split uses RUI keyboard resizing and preserves textarea across orientation", async ({ page }) => {
  await page.setViewportSize({ width: 900, height: 700 })
  await page.goto("/")
  await page.getByRole("button", { name: "Toggle documents" }).click()
  await expect.poll(() => page.getByRole("textbox", { name: "Text" })
    .evaluate(element => element.getBoundingClientRect().left)).toBe(0)

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
  if (!groupBox || !gripBox) {
    throw new Error("Split resize geometry missing")
  }
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

test("Examples create and open new Documents, preserve existing Documents, and close the sidebar", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto("/")

  const text = page.getByRole("textbox", { name: "Text" })
  const toggle = page.getByRole("button", { name: "Toggle documents" })
  const sidebar = page.locator("#loomark-document-sidebar")
  await text.fill("# Work in progress\n")
  await expect.poll(() => readStoredDocuments(page)).toHaveLength(1)
  const [existing] = await readStoredDocuments(page)
  const examples = page.getByRole("toolbar", { name: "Example documents" })
  const cases = [
    ["Create Markdown feature tour example document", "# Markdown Feature Tour\n"],
    ["Create Hello example document", "# Hello World\n"],
    ["Create Blog example document", "# Getting Started\n"],
    ["Create List example document", "# Shopping List\n"],
    ["Create Code example document", "# README\n"],
  ] as const

  for (const [index, [name, firstLine]] of cases.entries()) {
    await toggle.click()
    await examples.getByRole("button", { name }).click()
    await expect(sidebar).toHaveAttribute("aria-hidden", "true")
    await expect.poll(async () => (await text.inputValue()).startsWith(firstLine))
      .toBe(true)
    await expect.poll(() => readStoredDocuments(page)).toHaveLength(index + 2)
  }

  const documents = await readStoredDocuments(page)
  expect(documents).toContainEqual(existing)
  expect(new Set(documents.map(document => document.document_id)).size).toBe(6)
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

test("production keyed lead subscriptions reconcile timer lifecycles", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const seed = (await readStoredDocument(page))!
  const imported = { document_id: fixtureDocumentId("imported-document"), text: "# Imported\n" }
  await replaceStoreRecords(page, [
    { key: sourceKey(seed.document_id), value: encodeStoredDocument(seed) },
    { key: sourceKey(imported.document_id), value: encodeStoredDocument(imported) },
    { key: EDITING_DOCUMENT_KEY, value: seed.document_id },
  ])
  await page.reload()
  const text = page.getByRole("textbox", { name: "Text" })
  await expect(text).toHaveValue(seed.text)
  await page.clock.install()
  await page.clock.pauseAt(new Date())
  await page.evaluate(installPendingTimerProbe)
  await resetPendingTimerObservation(page)

  await text.fill("# First\n")
  await expect.poll(() => pendingTimerObservation(page)).toEqual({ scheduled: 1, canceled: 0, fired: 0 })

  // A same-key root update must refresh the tagger without restarting its timer.
  await page.setViewportSize({ width: 900, height: 700 })
  await expect.poll(() => pendingTimerObservation(page)).toEqual({ scheduled: 1, canceled: 0, fired: 0 })

  // A changed revision replaces the keyed subscription and cancels its old timer.
  await text.fill("# Replaced\n")
  await expect.poll(() => pendingTimerObservation(page)).toEqual({ scheduled: 2, canceled: 1, fired: 0 })

  // Composition starts while the replacement timer is pending and cancels it.
  await text.evaluate(element => {
    const textarea = element as HTMLTextAreaElement
    textarea.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true }))
    textarea.value = "# Composing\n"
    textarea.dispatchEvent(new InputEvent("input", {
      bubbles: true, composed: true, data: "# Composing\n", inputType: "insertCompositionText",
    }))
  })
  await expect.poll(() => pendingTimerObservation(page)).toEqual({ scheduled: 2, canceled: 2, fired: 0 })

  // Edits during composition do not schedule a timer; composition end schedules exactly one.
  await text.evaluate(element => {
    const textarea = element as HTMLTextAreaElement
    textarea.value = "# Composing again\n"
    textarea.dispatchEvent(new InputEvent("input", {
      bubbles: true, composed: true, data: "# Composing again\n", inputType: "insertCompositionText",
    }))
  })
  await expect.poll(() => pendingTimerObservation(page)).toEqual({ scheduled: 2, canceled: 2, fired: 0 })
  await text.evaluate(element => {
    const textarea = element as HTMLTextAreaElement
    textarea.dispatchEvent(new CompositionEvent("compositionend", { bubbles: true, data: textarea.value }))
    textarea.dispatchEvent(new InputEvent("input", {
      bubbles: true, composed: true, data: textarea.value, inputType: "insertText",
    }))
  })
  await expect.poll(() => pendingTimerObservation(page)).toEqual({ scheduled: 3, canceled: 2, fired: 0 })
  await page.clock.runFor(250)
  await expect.poll(() => pendingTimerObservation(page)).toEqual({ scheduled: 3, canceled: 2, fired: 1 })
  const documentId = seed.document_id
  await expectStoredDocument(page, { document_id: documentId, text: "# Composing again\n" })

  // Deleting with a pending timer cancels it; advancing beyond the delay cannot resurrect a save.
  await text.fill("# Removed\n")
  await expect.poll(() => pendingTimerObservation(page)).toEqual({ scheduled: 4, canceled: 2, fired: 1 })
  await page.clock.runFor(1)
  await page.getByRole("button", { name: /^Delete "/ }).first().click()
  await page.keyboard.press("Escape")
  await page.clock.runFor(249)
  await expect.poll(() => pendingTimerObservation(page)).toEqual({ scheduled: 4, canceled: 2, fired: 2 })
})

test("quiet Autosave restores exact Saved text after reload", async ({ page }) => {
  const savedText = "# Saved locally\n\nExact text.\n"
  await page.goto("/")
  await waitForRepositoryOpen(page)

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

test("exact acknowledged revert avoids a redundant Source write", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
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

  await expect(page.locator("#loomark-editor").getByRole("button", { name: "New document" })).toBeEnabled()
  await page.waitForTimeout(2_250)
  expect(await readDocumentPutLog(page)).toEqual([])
  expect((await readStoredDocument(page))?.text).toBe("# Untitled\n")
  await expectStoredDocument(page, baseline)
})

test("equal-text ABA still saves the latest exact text", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
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

test("large input during an active save coalesces to the latest text", async ({ page }) => {
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

  const finalText = await text.evaluate(async element => {
    const textarea = element as HTMLTextAreaElement
    const state = globalThis as typeof globalThis & {
      __loomarkDelayedCommitActive?: boolean
    }
    const append = (value: string) => {
      textarea.value += value
      textarea.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        composed: true,
        data: value,
        inputType: "insertText",
      }))
    }

    append("a")
    const deadline = performance.now() + 2_000
    while (!state.__loomarkDelayedCommitActive) {
      if (performance.now() >= deadline) throw new Error("save did not start")
      await new Promise(resolve => setTimeout(resolve, 10))
    }
    append("b")
    return textarea.value
  })

  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe(finalText)
  const overlap = await page.evaluate(() => {
    const state = globalThis as typeof globalThis & {
      __loomarkDelayedCommitInputs?: number
      __loomarkDelayedCommitPuts?: PutObservation[]
    }
    return {
      inputs: state.__loomarkDelayedCommitInputs ?? 0,
      puts: state.__loomarkDelayedCommitPuts ?? [],
    }
  })
  expect(overlap.inputs).toBe(1)
  expect(overlap.puts.map(put => (JSON.parse(put.value) as StoredDocument).text))
    .toEqual([`${largeText}a`, finalText])
})

test("hidden visibility saves an inactive document while save timers are held", async ({ page }) => {
  const documentA = { document_id: fixtureDocumentId("document-a"), text: "# A\n" }
  const documentB = { document_id: fixtureDocumentId("document-b"), text: "# B\n" }
  await openStoredDocuments(page, [documentA, documentB])
  const text = page.getByRole("textbox", { name: "Text" })
  await expect(text).toHaveValue(documentA.text)
  // Hold only autosave deadlines; freezing all browser timers also freezes activation.
  await page.evaluate(() => {
    const schedule = window.setTimeout.bind(window)
    window.setTimeout = ((handler: TimerHandler, timeout?: number, ...args: any[]) => (
      schedule(handler, timeout === 250 || timeout === 2_000 ? 60_000 : timeout, ...args)
    )) as typeof window.setTimeout
  })
  await text.pressSequentially("x")
  await expect(text).toHaveValue("# A\nx")
  await page.getByRole("button", { name: "B", exact: true }).click()
  await expect(text).toHaveValue(documentB.text)
  await page.evaluate(() => {
    Object.defineProperty(document, "hidden", { configurable: true, get: () => true })
    document.dispatchEvent(new Event("visibilitychange"))
  })
  await expectStoredDocument(page, { ...documentA, text: "# A\nx" })
  await expect(text).toHaveValue(documentB.text)
  await expectStoredDocument(page, documentB)
})

test("hidden visibility makes pending text eligible before quiet", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
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
  await waitForRepositoryOpen(page)
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
  await waitForRepositoryOpen(page)
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
  await waitForRepositoryOpen(page)
  await expect.poll(() => readStoredDocument(page)).toEqual({
    document_id: expect.any(String),
    text: "# Untitled\n",
  })
  const baseline = await readStoredDocument(page)
  if (!baseline) throw new Error("baseline Source missing")
  await page.evaluate(installDocumentPutFailure, sourceKey(baseline.document_id))

  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Not saved\n")
  await expect(page.locator(".loomark-save-status")).toHaveAttribute("title", "Not saved")
  await expect(page.getByRole("alert")).toBeVisible()
  await expect(page.getByRole("button", { name: "Retry saving" })).toBeEnabled()
  await text.fill("# Latest text\n")
  await expect(text).toHaveValue("# Latest text\n")
  await page.waitForTimeout(300)
  expect((await readStoredDocument(page))?.text).toBe("# Untitled\n")

  await page.evaluate(removeDocumentPutFailure)
  const retry = page.getByRole("button", { name: "Retry saving" })
  await retry.focus()
  await retry.press("Enter")
  await expect(page.getByRole("alert")).toHaveCount(0)
  await expect(text).toBeFocused()
  await expect(page.locator(".loomark-save-status")).toHaveAttribute("title", "Saved on this device")
  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe("# Latest text\n")
  await page.reload()
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue("# Latest text\n")
})

test("failed attempt exact acknowledged revert restores truthful Saved", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe("# Untitled\n")
  const baseline = await readStoredDocument(page)
  if (!baseline) throw new Error("baseline Source missing")
  await page.evaluate(installDocumentPutFailure, sourceKey(baseline.document_id))

  const text = page.getByRole("textbox", { name: "Text" })
  await text.fill("# Not saved\n")
  await expect(page.getByRole("alert")).toBeVisible()
  await expect(page.getByRole("button", { name: "Retry saving" })).toBeEnabled()
  const failedCalls = await page.evaluate(() => (
    (globalThis as typeof globalThis & {
      __loomarkDocumentPutFailureCalls?: number
    }).__loomarkDocumentPutFailureCalls ?? 0
  ))
  expect(failedCalls).toBe(1)

  await text.fill("# Untitled\n")
  await expect(page.getByRole("alert")).toHaveCount(0)
  await expect(page.locator(".loomark-save-status")).toHaveAttribute("title", "Saved on this device")
  await expect(page.locator("#loomark-editor").getByRole("button", { name: "New document" })).toBeEnabled()
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
  await waitForRepositoryOpen(page)
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
  await expect(page.locator("#loomark-editor").getByRole("button", { name: "New document" })).toBeEnabled()
  await expect.poll(() => readStoredDocument(page).then(document => document?.text))
    .toBe("# Untitled\n")
})

test("saving one Source preserves unrelated Sources and unknown metadata", async ({ page }) => {
  await page.goto("/")
  await waitForRepositoryOpen(page)
  const documentA = { document_id: fixtureDocumentId("document-a"), text: "# A\n" }
  const documentB = { document_id: fixtureDocumentId("document-b"), text: "# B\n" }
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
  await expectStoredDocument(page, { ...documentA, text: "# Updated A\n" })
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
  await waitForRepositoryOpen(page)
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
  await expect(page.locator("#loomark-editor").getByRole("button", { name: "New document" })).toBeEnabled()
  await page.waitForTimeout(350)
  expect(await readDocumentPutLog(page)).toEqual([])
})
