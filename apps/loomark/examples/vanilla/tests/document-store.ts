import type { Page } from "@playwright/test"

// Loomark's IndexedDB document store, as tests seed and read it.

export const DOCUMENT_DATABASE_NAME = "loomark"
export const DOCUMENT_DATABASE_VERSION = 2
export const DOCUMENT_STORE_NAME = "documents"
export const SOURCE_KEY_PREFIX = "source/v1/"

export type StoredDocument = {
  document_id: string
  text: string
}

export type StoreRecord = {
  key: string | number
  value: unknown
}

export function sourceKey(documentId: string): string {
  return `${SOURCE_KEY_PREFIX}${documentId}`
}

export async function scanStoreRecords(page: Page): Promise<StoreRecord[]> {
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

export async function readStoredDocumentRaw(page: Page, key: string | number): Promise<unknown> {
  return (await scanStoreRecords(page)).find(record => record.key === key)?.value
}

export async function replaceStoreRecords(page: Page, records: StoreRecord[]): Promise<void> {
  await page.evaluate(({ databaseName, databaseVersion, storeName, records }) => (
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

/**
 * A stored Source document. Fixtures are changed at the epoch unless given a
 * Change time, so by default they list in Document ID order.
 */
export function encodeStoredDocument(document: StoredDocument, changedAt = 0): string {
  return JSON.stringify({ ...document, changed_at: changedAt })
}
