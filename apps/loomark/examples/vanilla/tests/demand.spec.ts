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
  await row.getByRole("button", { name: "Actions for document" }).click()
  await page.getByRole("menuitem", { name: "Delete", exact: true }).click()
  await page.getByRole("alertdialog").getByRole("button", { name: "Delete document" }).click()
  await expect(page.getByRole("button", { name: "B", exact: true })).toHaveCount(0)
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
