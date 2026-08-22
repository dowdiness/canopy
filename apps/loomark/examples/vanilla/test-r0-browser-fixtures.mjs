import assert from "node:assert/strict"
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { fileURLToPath } from "node:url"
import {
  BrowserFixtureFailure,
  loadBrowserFixtureCatalog,
} from "./r0-browser-fixtures.mjs"

const fixtureRoot = fileURLToPath(new URL("./fixtures/r0-browser-v1/", import.meta.url))
const expectedFixtureIds = [
  "S-linear-1000",
  "S-distributed-1000",
  "S-tombstone-1000",
  "S-replacement-1000",
  "S-unicode-1000",
]

async function expectFailure(code, action) {
  await assert.rejects(action, error => {
    assert.ok(error instanceof BrowserFixtureFailure)
    assert.equal(error.code, code)
    return true
  })
}

async function copyFixtureRoot(destination) {
  const catalogBytes = await readFile(join(fixtureRoot, "browser-fixture-catalog-v1.json"))
  await mkdir(destination, { recursive: true })
  await writeFile(join(destination, "browser-fixture-catalog-v1.json"), catalogBytes)
  const catalog = JSON.parse(catalogBytes)
  for (const fixture of catalog.fixtures) {
    await writeFile(
      join(destination, fixture.archive_path),
      await readFile(join(fixtureRoot, fixture.archive_path)),
    )
  }
}

const catalog = await loadBrowserFixtureCatalog(fixtureRoot)
assert.equal(catalog.schema_version, 1)
assert.equal(catalog.fixture_seed, "none")
assert.deepEqual(catalog.fixtures.map(fixture => fixture.fixture_id), expectedFixtureIds)

for (const fixture of catalog.fixtures) {
  assert.equal(fixture.disposition, "valid")
  assert.equal(fixture.consumer, "full_history_v1")
  assert.equal(fixture.event_count, 1000)
  assert.equal(fixture.first_edit.kind, "append_unicode_scalar")
  assert.equal(fixture.first_edit.scalar, "U+005A")
  assert.equal(fixture.first_edit.utf16_position, fixture.expected_text_utf16_units)
  assert.equal(fixture.expected_text_after_edit, `${fixture.expected_text}Z`)
  assert.ok(fixture.fixture_id !== "S-unicode-1000" || (
    fixture.expected_text_utf16_units > fixture.expected_text_scalars
  ))
}

await expectFailure("catalog_entry_missing", async () => {
  await loadBrowserFixtureCatalog(fixtureRoot, { requiredFixtureIds: ["absent"] })
})

const temporaryRoot = await mkdtemp(join(tmpdir(), "loomark-r0-browser-fixtures-"))
try {
  await expectFailure("catalog_missing", async () => {
    await loadBrowserFixtureCatalog(join(temporaryRoot, "missing"))
  })

  const copyRoot = join(temporaryRoot, "copy")
  await copyFixtureRoot(copyRoot)
  const copiedCatalogPath = join(copyRoot, "browser-fixture-catalog-v1.json")
  const copiedCatalog = JSON.parse(await readFile(copiedCatalogPath, "utf8"))
  const first = copiedCatalog.fixtures[0]

  await rm(join(copyRoot, first.archive_path))
  await expectFailure("archive_asset_missing", async () => {
    await loadBrowserFixtureCatalog(copyRoot)
  })

  await copyFixtureRoot(copyRoot)
  await writeFile(join(copyRoot, first.archive_path), "{}")
  await expectFailure("archive_digest_mismatch", async () => {
    await loadBrowserFixtureCatalog(copyRoot)
  })

  await copyFixtureRoot(copyRoot)
  copiedCatalog.fixtures[0].archive_sha256 = await import("node:crypto").then(({ createHash }) => (
    createHash("sha256").update("not-json").digest("hex")
  ))
  copiedCatalog.fixtures[0].archive_bytes = Buffer.byteLength("not-json")
  await writeFile(copiedCatalogPath, JSON.stringify(copiedCatalog))
  await writeFile(join(copyRoot, first.archive_path), "not-json")
  await expectFailure("malformed_v1_archive", async () => {
    await loadBrowserFixtureCatalog(copyRoot)
  })

  await copyFixtureRoot(copyRoot)
  const unsupportedCatalog = JSON.parse(await readFile(copiedCatalogPath, "utf8"))
  const unsupportedPath = join(copyRoot, unsupportedCatalog.fixtures[0].archive_path)
  const unsupportedArchive = JSON.parse(await readFile(unsupportedPath, "utf8"))
  unsupportedArchive.schema_version = "2"
  const unsupportedBytes = JSON.stringify(unsupportedArchive)
  const { createHash } = await import("node:crypto")
  unsupportedCatalog.fixtures[0].archive_sha256 = createHash("sha256").update(unsupportedBytes).digest("hex")
  unsupportedCatalog.fixtures[0].archive_bytes = Buffer.byteLength(unsupportedBytes)
  await writeFile(copiedCatalogPath, JSON.stringify(unsupportedCatalog))
  await writeFile(unsupportedPath, unsupportedBytes)
  await expectFailure("unsupported_archive_version", async () => {
    await loadBrowserFixtureCatalog(copyRoot)
  })

  await copyFixtureRoot(copyRoot)
  const mismatchCatalog = JSON.parse(await readFile(copiedCatalogPath, "utf8"))
  mismatchCatalog.fixtures[0].expected_text = "wrong"
  await writeFile(copiedCatalogPath, JSON.stringify(mismatchCatalog))
  await expectFailure("expected_portable_text_mismatch", async () => {
    await loadBrowserFixtureCatalog(copyRoot)
  })

  await copyFixtureRoot(copyRoot)
  const historyMismatchCatalog = JSON.parse(await readFile(copiedCatalogPath, "utf8"))
  historyMismatchCatalog.fixtures[0].history_sha256 = "0".repeat(64)
  await writeFile(copiedCatalogPath, JSON.stringify(historyMismatchCatalog))
  await expectFailure("expected_portable_history_mismatch", async () => {
    await loadBrowserFixtureCatalog(copyRoot)
  })

  await copyFixtureRoot(copyRoot)
  const candidateCatalog = JSON.parse(await readFile(copiedCatalogPath, "utf8"))
  candidateCatalog.fixtures[0].consumer = "paper_branch_candidate"
  await writeFile(copiedCatalogPath, JSON.stringify(candidateCatalog))
  await expectFailure("candidate_consumer_selected", async () => {
    await loadBrowserFixtureCatalog(copyRoot)
  })
} finally {
  await rm(temporaryRoot, { recursive: true, force: true })
}

process.stdout.write("PASS Gate R0 browser fixture catalog contract\n")
