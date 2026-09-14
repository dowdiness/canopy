import { expect, test, type Page } from "@playwright/test"

type Document = { document_id: string; text: string }
const docs: Document[] = [
  { document_id: "a", text: "# A\n" },
  { document_id: "b", text: "# B\n" },
  { document_id: "c", text: "# C\n" },
]

async function seed(page: Page, documents: Document[]) {
  await page.evaluate(async documents => {
    const request = indexedDB.open("loomark", 1)
    await new Promise<void>((resolve, reject) => {
      request.onupgradeneeded = () => {
        if (!request.result.objectStoreNames.contains("documents")) request.result.createObjectStore("documents")
      }
      request.onsuccess = () => resolve()
      request.onerror = () => reject(request.error)
    })
    const db = request.result
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction("documents", "readwrite")
      tx.objectStore("documents").clear()
      for (const document of documents) {
        tx.objectStore("documents").put(JSON.stringify(document), `source/v1/${document.document_id}`)
      }
      tx.oncomplete = () => resolve()
      tx.onerror = () => reject(tx.error)
    })
    db.close()
  }, documents)
  await page.reload()
}

async function count(page: Page): Promise<number> {
  return page.evaluate(() => Number((globalThis as { __loomarkDocumentLeadExtractCount?: number }).__loomarkDocumentLeadExtractCount ?? 0))
}

async function waitForSavedText(page: Page, documentId: string, text: string): Promise<void> {
  await expect.poll(() => page.evaluate(async ({ documentId }) => {
    const request = indexedDB.open("loomark", 1)
    return await new Promise<string | null>(resolve => {
      request.onsuccess = () => {
        const db = request.result
        const get = db.transaction("documents", "readonly").objectStore("documents")
          .get(`source/v1/${documentId}`)
        get.onsuccess = () => {
          db.close()
          const value = typeof get.result === "string" ? JSON.parse(get.result) : null
          resolve(value?.text ?? null)
        }
        get.onerror = () => resolve(null)
      }
      request.onerror = () => resolve(null)
    })
  }, { documentId })).toBe(text)
}

async function readStoredDocument(page: Page, documentId: string): Promise<unknown> {
  return page.evaluate(async documentId => {
    const request = indexedDB.open("loomark", 1)
    return await new Promise<unknown>((resolve, reject) => {
      request.onsuccess = () => {
        const db = request.result
        const transaction = db.transaction("documents", "readonly")
        const get = transaction.objectStore("documents").get(`source/v1/${documentId}`)
        let value: unknown
        get.onsuccess = () => { value = get.result }
        transaction.oncomplete = () => {
          db.close()
          resolve(value)
        }
        transaction.onabort = () => {
          db.close()
          reject(transaction.error)
        }
      }
      request.onerror = () => reject(request.error)
    })
  }, documentId)
}

async function closeAndReopen(page: Page): Promise<void> {
  const toggle = page.getByRole("button", { name: "Toggle documents" })
  await toggle.click()
  await expect(toggle).toHaveAttribute("aria-expanded", "false")
  await toggle.click()
  await expect(toggle).toHaveAttribute("aria-expanded", "true")
}

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    ;(globalThis as { __loomarkDocumentLeadExtractCount?: number }).__loomarkDocumentLeadExtractCount = 0
  })
})

test("visible rows retain exactly three leads across repeated close/open", async ({ page }) => {
  await page.goto("/")
  await seed(page, docs)
  await expect.poll(() => count(page)).toBe(3)
  await closeAndReopen(page)
  await closeAndReopen(page)
  await expect.poll(() => count(page)).toBe(3)
})

test("hidden accepted edit retains leads and only extracts the changed row on reopen", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto("/")
  await seed(page, docs)
  await expect.poll(() => count(page)).toBe(0)
  await page.getByRole("button", { name: "Documents", exact: true }).click()
  await expect.poll(() => count(page)).toBe(3)
  await page.getByRole("button", { name: "Documents", exact: true }).click()
  await page.getByRole("textbox", { name: "Text" }).fill("# A changed\n")
  await waitForSavedText(page, "a", "# A changed\n")
  await page.waitForTimeout(300)
  await expect.poll(() => count(page)).toBe(3)
  await page.getByRole("button", { name: "Documents", exact: true }).click()
  await expect.poll(() => count(page)).toBe(4)
})

test("status-only unsaved transition before 250ms does not re-extract", async ({ page }) => {
  await page.goto("/")
  await seed(page, docs)
  await expect.poll(() => count(page)).toBe(3)
  await page.getByRole("textbox", { name: "Text" }).fill("# A changed\n")
  await page.waitForTimeout(100)
  await expect.poll(() => count(page)).toBe(3)
})

test("visible accepted edit extracts A once and reorder does not reparse B or C", async ({ page }) => {
  await page.goto("/")
  await seed(page, docs)
  await expect.poll(() => count(page)).toBe(3)
  await page.getByRole("textbox", { name: "Text" }).fill("# A changed\n")
  await waitForSavedText(page, "a", "# A changed\n")
  await page.waitForTimeout(300)
  await expect.poll(() => count(page)).toBe(4)
  await page.getByRole("button", { name: "B", exact: true }).click()
  await page.getByRole("button", { name: "C", exact: true }).click()
  await expect.poll(() => count(page)).toBe(4)
})

test("removing one row does not reparse the remaining rows", async ({ page }) => {
  await page.goto("/")
  await seed(page, docs)
  await expect.poll(() => count(page)).toBe(3)
  const row = page.getByRole("button", { name: "B", exact: true }).locator("..")
  await row.getByRole("button", { name: 'Delete "B"', exact: true }).click()
  await page.getByRole("alertdialog").getByRole("button", { name: "Delete document" }).click()
  await expect(page.getByRole("button", { name: "B", exact: true })).toHaveCount(0)
  await expect.poll(() => count(page)).toBe(3)
})

test("pending deletion survives hiding Recent documents and does not resurrect B", async ({ page }) => {
  await page.goto("/")
  await seed(page, docs)
  await expect.poll(() => count(page)).toBe(3)

  await page.addInitScript(() => {
    const prototype = IDBObjectStore.prototype as any
    const originalDelete = prototype.delete
    prototype.delete = function(this: IDBObjectStore, key: IDBValidKey) {
      const request = originalDelete.call(this, key)
      if (typeof key === "string" && key === "source/v1/b") {
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

  const row = page.getByRole("button", { name: "B", exact: true }).locator("..")
  await row.getByRole("button", { name: 'Delete "B"', exact: true }).click()
  await page.getByRole("alertdialog").getByRole("button", { name: "Delete document" }).click()
  await expect(page.getByRole("alertdialog")).toHaveCount(0)
  await expect(row.getByRole("button", { name: 'Delete "B"', exact: true })).toBeDisabled()
  await expect.poll(() => page.evaluate(() => typeof (window as any).releasePendingDelete)).toBe("function")
  await expect.poll(() => count(page)).toBe(3)

  const toggle = page.getByRole("button", { name: "Toggle documents" })
  await toggle.click()
  await expect(toggle).toHaveAttribute("aria-expanded", "false")
  await expect(page.locator(".loomark-document-row")).toHaveCount(0)

  await page.evaluate(() => (window as any).releasePendingDelete())
  await expect.poll(() => readStoredDocument(page, "b")).toBeUndefined()
  await expect(page.locator(".loomark-document-row")).toHaveCount(0)
  await expect.poll(() => count(page)).toBe(3)

  // Observe additions, not just the eventual list: B must never render on reopen.
  const renderedDeletedRow = await page.evaluateHandle(() => {
    const evidence = { rendered: false }
    const selector = '.loomark-document-row[aria-label="B"]'
    new MutationObserver(records => {
      for (const record of records) {
        for (const node of record.addedNodes) {
          if (node instanceof Element && (node.matches(selector) || node.querySelector(selector))) {
            evidence.rendered = true
          }
        }
      }
    }).observe(document.body, { childList: true, subtree: true })
    return evidence
  })
  await toggle.click()
  await expect(toggle).toHaveAttribute("aria-expanded", "true")
  await expect(page.locator(".loomark-document-row")).toHaveCount(2)
  await expect(page.getByRole("button", { name: "B", exact: true })).toHaveCount(0)
  await expect(page.getByRole("button", { name: "A", exact: true })).toHaveCount(1)
  await expect(page.getByRole("button", { name: "C", exact: true })).toHaveCount(1)
  expect(await renderedDeletedRow.evaluate(evidence => evidence.rendered)).toBe(false)
  await expect.poll(() => count(page)).toBe(3)
})

test("hiding Recent documents removes row DOM and reopening creates fresh rows", async ({ page }) => {
  await page.goto("/")
  await seed(page, docs)
  await expect.poll(() => count(page)).toBe(3)
  const row = page.getByRole("button", { name: "B", exact: true })
  const rowHandle = await row.elementHandle()
  expect(rowHandle).not.toBeNull()

  const toggle = page.getByRole("button", { name: "Toggle documents" })
  await toggle.click()
  await expect(toggle).toHaveAttribute("aria-expanded", "false")
  await expect(page.locator(".loomark-document-row")).toHaveCount(0)
  await expect.poll(() => rowHandle!.evaluate(element => element.isConnected)).toBe(false)

  await toggle.click()
  await expect(toggle).toHaveAttribute("aria-expanded", "true")
  await expect(page.locator(".loomark-document-row")).toHaveCount(3)
  await expect(page.getByRole("button", { name: "A", exact: true })).toHaveCount(1)
  await expect(page.getByRole("button", { name: "B", exact: true })).toHaveCount(1)
  await expect(page.getByRole("button", { name: "C", exact: true })).toHaveCount(1)
  const reopenedRowHandle = await page.getByRole("button", { name: "B", exact: true }).elementHandle()
  expect(reopenedRowHandle).not.toBeNull()
  expect(await reopenedRowHandle!.evaluate((element, previous) => element === previous, rowHandle)).toBe(false)
  expect(await rowHandle!.evaluate(element => element.isConnected)).toBe(false)
  await expect.poll(() => count(page)).toBe(3)
})

test("hidden startup performs no extraction until Recent documents is shown", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto("/")
  await seed(page, docs)
  await expect.poll(() => count(page)).toBe(0)
  await page.getByRole("button", { name: "Documents", exact: true }).click()
  await expect.poll(() => count(page)).toBe(3)
})

test("hidden dialog demand renders duplicate-safe target without navigation rows", async ({ page }) => {
  // This cold fixture isolates the dialog consumer; it is not a user-flow claim.
  await page.goto("/?recent-dialog-demand")
  await expect(page.locator(".loomark-document-row")).toHaveCount(0)
  const dialog = page.getByRole("alertdialog")
  await expect(dialog).toBeVisible()
  await expect(dialog.getByRole("heading")).toHaveText('Delete "Shared (2 of 2)"?')
  await expect.poll(() => count(page)).toBe(3)
})
