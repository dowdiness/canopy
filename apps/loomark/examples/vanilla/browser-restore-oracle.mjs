import { spawn } from "node:child_process"
import { once } from "node:events"
import { dirname } from "node:path"
import { fileURLToPath } from "node:url"
import { chromium } from "playwright"

const [archivePath, caseId, expectedCountRaw, distRoot] = process.argv.slice(2)
if (archivePath == null || caseId == null || expectedCountRaw == null) {
  throw new Error("usage: browser-restore-oracle.mjs ARCHIVE CASE EXPECTED_COUNT [DIST_ROOT]")
}
const expectedCount = Number.parseInt(expectedCountRaw, 10)
if (!Number.isSafeInteger(expectedCount) || expectedCount !== 1000) {
  throw new Error("expected operation count must be exactly 1000")
}

const fixtureRoot = dirname(archivePath)
const port = 0
let origin = ""
const archiveDatabase = "loomark.local-repository"
const archiveStore = "archives"
const archiveKey = "loomark.active-document-archive"
const serverPath = fileURLToPath(new URL("./serve-standalone-dist.mjs", import.meta.url))
const server = spawn(process.execPath, [serverPath], {
  env: {
    ...process.env,
    LOOMARK_STANDALONE_PORT: String(port),
    LOOMARK_R0_BROWSER_FIXTURE_ROOT: fixtureRoot,
    ...(distRoot == null ? {} : { LOOMARK_STANDALONE_DIST: distRoot }),
  },
  stdio: ["ignore", "pipe", "inherit"],
})
let readyBuffer = ""
const ready = new Promise((resolve, reject) => {
  const timeout = setTimeout(() => reject(new Error("standalone server timeout")), 5000)
  server.stdout.setEncoding("utf8")
  server.stdout.on("data", chunk => {
    readyBuffer += chunk
    const match = readyBuffer.match(/http:\/\/127\.0\.0\.1:(\d+)/)
    if (match !== null) {
      origin = match[0]
      clearTimeout(timeout)
      resolve()
    }
  })
  server.once("error", reject)
  server.once("close", code => reject(new Error(`standalone server exited: ${code}`)))
})

function browserText(source) {
  return source.replace(/\r\n?/g, "\n")
}

async function seedFromBrowserAsset(page) {
  const catalogUrl = `${origin}/fixtures/r0-browser-v1/browser-fixture-catalog-v1.json`
  await page.goto(catalogUrl, { waitUntil: "commit" })
  return page.evaluate(async ({ caseId, archiveDatabase, archiveStore, archiveKey }) => {
    const hash = async text => {
      const bytes = new TextEncoder().encode(text)
      const digest = await crypto.subtle.digest("SHA-256", bytes)
      return {
        bytes: bytes.length,
        sha256: [...new Uint8Array(digest)]
          .map(value => value.toString(16).padStart(2, "0"))
          .join(""),
      }
    }
    const catalogResponse = await fetch(location.href, { cache: "no-store" })
    if (!catalogResponse.ok) throw new Error("catalog_missing")
    const catalogText = await catalogResponse.text()
    const catalog = JSON.parse(catalogText)
    const fixture = catalog.fixtures?.find(row => row.fixture_id === caseId)
    if (fixture === undefined) throw new Error("catalog_entry_missing")
    if (fixture.consumer !== "full_history_v1") {
      throw new Error("candidate_consumer_selected")
    }
    const archiveResponse = await fetch(new URL(fixture.archive_path, location.href), {
      cache: "no-store",
    })
    if (!archiveResponse.ok) throw new Error("archive_asset_missing")
    const encoded = await archiveResponse.text()
    const archiveDigest = await hash(encoded)
    if (
      archiveDigest.bytes !== fixture.archive_bytes ||
      archiveDigest.sha256 !== fixture.archive_sha256
    ) {
      throw new Error("archive_digest_mismatch")
    }
    let archive
    try {
      archive = JSON.parse(encoded)
    } catch {
      throw new Error("malformed_v1_archive")
    }
    if (archive.schema_version !== "1") throw new Error("unsupported_archive_version")
    const textDigest = await hash(archive.portable_markdown)
    const historyDigest = await hash(archive.history)
    if (
      archive.portable_markdown !== fixture.expected_text ||
      textDigest.sha256 !== fixture.expected_text_sha256
    ) {
      throw new Error("expected_portable_text_mismatch")
    }
    if (historyDigest.sha256 !== fixture.history_sha256) {
      throw new Error("expected_portable_history_mismatch")
    }
    const history = JSON.parse(archive.history)
    if (history.operations.length !== fixture.event_count) {
      throw new Error("expected_portable_history_mismatch")
    }
    await new Promise((resolve, reject) => {
      const request = indexedDB.open(archiveDatabase, 1)
      request.onupgradeneeded = () => {
        const database = request.result
        if (!database.objectStoreNames.contains(archiveStore)) {
          database.createObjectStore(archiveStore)
        }
      }
      request.onerror = () => reject(request.error ?? new Error("archive database open failed"))
      request.onsuccess = () => {
        const database = request.result
        const transaction = database.transaction(archiveStore, "readwrite")
        transaction.objectStore(archiveStore).put(encoded, archiveKey)
        transaction.oncomplete = () => {
          database.close()
          resolve()
        }
        transaction.onerror = () => reject(transaction.error ?? new Error("archive seed failed"))
        transaction.onabort = () => reject(transaction.error ?? new Error("archive seed aborted"))
      }
    })
    return {
      fixture,
      archiveTransportBytes: archiveDigest.bytes,
      catalogTransportBytes: new TextEncoder().encode(catalogText).length,
      archiveSha256: archiveDigest.sha256,
      textSha256: textDigest.sha256,
      historySha256: historyDigest.sha256,
    }
  }, { caseId, archiveDatabase, archiveStore, archiveKey })
}

async function readArchive(page) {
  return page.evaluate(async ({ databaseName, storeName, key }) => await new Promise((resolve, reject) => {
    const request = indexedDB.open(databaseName, 1)
    request.onerror = () => reject(request.error ?? new Error("archive database open failed"))
    request.onsuccess = () => {
      const database = request.result
      const transaction = database.transaction(storeName, "readonly")
      const read = transaction.objectStore(storeName).get(key)
      read.onsuccess = () => {
        database.close()
        resolve(read.result ?? null)
      }
      read.onerror = () => reject(read.error ?? new Error("archive read failed"))
    }
  }), { databaseName: archiveDatabase, storeName: archiveStore, key: archiveKey })
}

async function waitForArchive(page, matches, timeout = 30000) {
  const deadline = Date.now() + timeout
  while (Date.now() < deadline) {
    const encoded = await readArchive(page)
    if (encoded != null) {
      const parsed = JSON.parse(encoded)
      if (matches(parsed, encoded)) return encoded
    }
    await page.waitForTimeout(100)
  }
  throw new Error("timed out waiting for IndexedDB archive")
}

let browser
let context
let page
try {
  await ready
  browser = await chromium.launch({ headless: true })
  const browserVersion = browser.version()
  context = await browser.newContext()
  await context.addInitScript(({ storeName, key }) => {
    const originalGet = IDBObjectStore.prototype.get
    const originalOpenCursor = IDBObjectStore.prototype.openCursor
    globalThis.__loomarkR0ReadAccounting = {
      applicationArchiveReads: 0,
      observationArchiveReads: 0,
    }
    IDBObjectStore.prototype.get = function(nextKey) {
      if (this.name === storeName && nextKey === key) {
        globalThis.__loomarkR0ReadAccounting.observationArchiveReads += 1
      }
      return originalGet.call(this, nextKey)
    }
    IDBObjectStore.prototype.openCursor = function(query, direction) {
      if (this.name === storeName && query === key) {
        globalThis.__loomarkR0ReadAccounting.applicationArchiveReads += 1
      }
      return originalOpenCursor.call(this, query, direction)
    }
  }, { storeName: archiveStore, key: archiveKey })
  page = await context.newPage()
  const seeded = await seedFromBrowserAsset(page)
  if (seeded.fixture.event_count !== expectedCount) {
    throw new Error("catalog event count differs from runner input")
  }

  await page.goto(`${origin}/`, { waitUntil: "commit" })
  const input = page.locator("#loomark-input")
  await input.waitFor({ state: "visible", timeout: 30000 })
  const expectedBrowserText = browserText(seeded.fixture.expected_text)
  await page.waitForFunction(expected => (
    document.querySelector("#loomark-input")?.value === expected
  ), expectedBrowserText, { timeout: 30000 })

  const beforeEditArchive = await readArchive(page)
  if (beforeEditArchive === null) throw new Error("archive disappeared before first edit")
  const beforeEdit = await page.evaluate(async ({ encoded, candidateMarkers }) => {
    const archive = JSON.parse(encoded)
    const history = JSON.parse(archive.history)
    const historyDigest = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(archive.history),
    )
    const historySha256 = [...new Uint8Array(historyDigest)]
      .map(value => value.toString(16).padStart(2, "0"))
      .join("")
    const indexResource = performance.getEntriesByType("resource")
      .find(resource => resource.name.endsWith("/index.js"))
    const indexResponse = await fetch(indexResource?.name ?? "/index.js", {
      cache: "no-store",
    })
    const indexSource = await indexResponse.text()
    const candidateBundleMarkerDetected = candidateMarkers.some(marker => (
      indexSource.includes(marker)
    ))
    return {
      portableText: archive.portable_markdown,
      historySha256,
      historyEvents: history.operations.length,
      applicationArchiveReads: globalThis.__loomarkR0ReadAccounting.applicationArchiveReads,
      observationArchiveReads: globalThis.__loomarkR0ReadAccounting.observationArchiveReads,
      candidateBundleMarkerDetected,
      candidateConsumerStarts: candidateBundleMarkerDetected ? 1 : 0,
      candidateEventReads: candidateBundleMarkerDetected ? 1 : 0,
      browserUtf16End: document.querySelector("#loomark-input")?.value.length ?? null,
    }
  }, {
    encoded: beforeEditArchive,
    candidateMarkers: ["restore_feasibility_probe", "paper_branch_candidate"],
  })
  if (
    beforeEdit.portableText !== seeded.fixture.expected_text ||
    beforeEdit.historySha256 !== seeded.historySha256
  ) {
    throw new Error("browser portable text/history mismatch")
  }
  const applicationArchiveReads = beforeEdit.applicationArchiveReads
  if (applicationArchiveReads !== 1 || beforeEdit.observationArchiveReads !== 1) {
    throw new Error(`unexpected archive storage read count: ${JSON.stringify({
      application: applicationArchiveReads,
      observation: beforeEdit.observationArchiveReads,
    })}`)
  }
  if (beforeEdit.candidateConsumerStarts !== 0 || beforeEdit.candidateEventReads !== 0) {
    throw new Error("candidate_consumer_selected")
  }

  await input.focus()
  await input.evaluate(element => {
    const length = element.value.length
    element.setSelectionRange(length, length, "forward")
  })
  await page.keyboard.type("Z")
  const afterEditArchive = await waitForArchive(
    page,
    archive => archive.portable_markdown === seeded.fixture.expected_text_after_edit,
  )
  const parsedAfterEditArchive = JSON.parse(afterEditArchive)
  const afterEdit = {
    portableText: parsedAfterEditArchive.portable_markdown,
    historyEvents: JSON.parse(parsedAfterEditArchive.history).operations.length,
  }
  const firstEditResultEqual = (
    afterEdit.portableText === seeded.fixture.expected_text_after_edit &&
    afterEdit.historyEvents === expectedCount + 1
  )
  if (!firstEditResultEqual) throw new Error("exact first edit differs")
  const firstEditLocalOperations = afterEdit.historyEvents - beforeEdit.historyEvents
  const browserControlPositionValid = (
    beforeEdit.browserUtf16End === expectedBrowserText.length
  )
  const coordinatePositionsEqual = (
    seeded.fixture.first_edit.utf16_position === beforeEdit.browserUtf16End
  )
  const adapterMappingProved = firstEditResultEqual && browserControlPositionValid

  await page.reload({ waitUntil: "commit" })
  await page.locator("#loomark-input").waitFor({ state: "visible", timeout: 30000 })
  await page.waitForFunction(expected => (
    document.querySelector("#loomark-input")?.value === expected
  ), browserText(seeded.fixture.expected_text_after_edit), { timeout: 30000 })

  process.stdout.write(`${JSON.stringify({
    schema_version: 1,
    run_id: "gate-r0-v1",
    case_id: caseId,
    producer: "loomark_fresh_browser_oracle",
    status: "pass",
    payload: {
      record: "browser_oracle_result",
      browser_version: browserVersion,
      operation_count: expectedCount,
      post_edit_operation_count: afterEdit.historyEvents,
      archive_sha256: seeded.archiveSha256,
      restored_text_sha256: seeded.textSha256,
      restored_history_sha256: seeded.historySha256,
      browser_portable_text_equal: true,
      browser_portable_history_equal: true,
      selected_consumer: seeded.fixture.consumer,
      candidate_detection: {
        basis: "catalog selection plus release-bundle exclusion canary",
        release_bundle_marker_detected: beforeEdit.candidateBundleMarkerDetected,
      },
      candidate_consumer_starts: beforeEdit.candidateConsumerStarts,
      full_history_consumer_starts: applicationArchiveReads,
      edit_persisted_after_fresh_page: true,
      fresh_page: true,
      first_edit: {
        scalar: "U+005A",
        canonical_utf16_position: seeded.fixture.first_edit.utf16_position,
        browser_control_utf16_position: beforeEdit.browserUtf16End,
        coordinate_positions_equal: coordinatePositionsEqual,
        browser_control_position_valid: browserControlPositionValid,
        adapter_mapping_proved: adapterMappingProved,
        result_equal: firstEditResultEqual,
      },
      read_accounting: {
        archive_transport_bytes: seeded.archiveTransportBytes,
        catalog_transport_bytes: seeded.catalogTransportBytes,
        archive_decode_read_operations: applicationArchiveReads,
        oracle_full_history_event_reads: beforeEdit.historyEvents,
        candidate_event_reads: beforeEdit.candidateEventReads,
        first_edit_local_operations: firstEditLocalOperations,
        observation_storage_read_operations: beforeEdit.observationArchiveReads,
        observation_storage_reads_excluded: true,
      },
    },
  })}\n`)
  await context.close()
} catch (error) {
  if (page != null) {
    const observed = await page.locator("#loomark-input").inputValue().catch(() => "")
    process.stderr.write(`browser input: ${JSON.stringify({ length: observed.length, prefix: observed.slice(0, 16), suffix: observed.slice(-16) })}\n`)
    const stored = await readArchive(page).catch(() => null)
    process.stderr.write(`browser archive bytes: ${stored == null ? 0 : Buffer.byteLength(stored)}\n`)
  }
  throw error
} finally {
  if (browser != null) await browser.close()
  if (server.exitCode == null) {
    server.kill("SIGTERM")
    await Promise.race([once(server, "close"), new Promise(resolve => setTimeout(resolve, 1000))])
    if (server.exitCode == null) server.kill("SIGKILL")
  }
}
