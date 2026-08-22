import { createHash } from "node:crypto"
import { readFile } from "node:fs/promises"
import { basename, join } from "node:path"

export const canonicalBrowserFixtureIds = Object.freeze([
  "S-linear-1000",
  "S-distributed-1000",
  "S-tombstone-1000",
  "S-replacement-1000",
  "S-unicode-1000",
])

export class BrowserFixtureFailure extends Error {
  constructor(code, detail) {
    super(`${code}: ${detail}`)
    this.name = "BrowserFixtureFailure"
    this.code = code
  }
}

function fail(code, detail) {
  throw new BrowserFixtureFailure(code, detail)
}

export function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex")
}

function byteLength(text) {
  return Buffer.byteLength(text, "utf8")
}

function scalarLength(text) {
  return [...text].length
}

function assertRecord(condition, code, fixtureId, detail) {
  if (!condition) fail(code, `${fixtureId}: ${detail}`)
}

function validateArchiveEnvelope(fixture, encoded) {
  let archive
  try {
    archive = JSON.parse(encoded)
  } catch {
    fail("malformed_v1_archive", `${fixture.fixture_id}: invalid JSON`)
  }
  const fields = archive !== null && typeof archive === "object" && !Array.isArray(archive)
    ? Object.keys(archive).sort()
    : []
  const expectedFields = [
    "document_id",
    "extensions",
    "history",
    "portable_markdown",
    "schema_version",
  ]
  assertRecord(
    JSON.stringify(fields) === JSON.stringify(expectedFields),
    "malformed_v1_archive",
    fixture.fixture_id,
    "archive is not a complete v1 envelope",
  )
  assertRecord(
    archive.schema_version === "1",
    "unsupported_archive_version",
    fixture.fixture_id,
    `expected version 1, got ${String(archive.schema_version)}`,
  )
  assertRecord(
    archive.document_id === `loomark-r0-fixture-${fixture.fixture_id}`,
    "malformed_v1_archive",
    fixture.fixture_id,
    "document identity differs from the fixed fixture identity",
  )
  assertRecord(
    typeof archive.portable_markdown === "string" && typeof archive.history === "string",
    "malformed_v1_archive",
    fixture.fixture_id,
    "portable text and history must be strings",
  )
  assertRecord(
    archive.extensions !== null && typeof archive.extensions === "object" &&
      !Array.isArray(archive.extensions) && Object.keys(archive.extensions).length === 0,
    "malformed_v1_archive",
    fixture.fixture_id,
    "extensions must be an empty object",
  )
  return archive
}

function validateHistory(fixture, history) {
  let decoded
  try {
    decoded = JSON.parse(history)
  } catch {
    fail("malformed_v1_archive", `${fixture.fixture_id}: history is not JSON`)
  }
  assertRecord(
    decoded !== null && typeof decoded === "object" && Array.isArray(decoded.operations),
    "malformed_v1_archive",
    fixture.fixture_id,
    "history has no operation array",
  )
  assertRecord(
    decoded.operations.length === fixture.event_count,
    "expected_portable_history_mismatch",
    fixture.fixture_id,
    `expected ${fixture.event_count} events, got ${decoded.operations.length}`,
  )
}

function validateCatalogRow(fixture) {
  const fixtureId = fixture?.fixture_id ?? "unknown"
  assertRecord(fixture !== null && typeof fixture === "object", "catalog_invalid", fixtureId, "row must be an object")
  assertRecord(fixture.disposition === "valid", "catalog_invalid", fixtureId, "disposition must be valid")
  assertRecord(fixture.consumer === "full_history_v1", "candidate_consumer_selected", fixtureId, "only the v1 full-history consumer is permitted")
  assertRecord(fixture.event_count === 1000, "catalog_invalid", fixtureId, "event count must be 1000")
  assertRecord(typeof fixture.archive_path === "string" && basename(fixture.archive_path) === fixture.archive_path, "catalog_invalid", fixtureId, "archive path must be one relative filename")
  assertRecord(typeof fixture.archive_sha256 === "string" && /^[0-9a-f]{64}$/.test(fixture.archive_sha256), "catalog_invalid", fixtureId, "archive hash must be lowercase SHA-256")
  assertRecord(typeof fixture.history_sha256 === "string" && /^[0-9a-f]{64}$/.test(fixture.history_sha256), "catalog_invalid", fixtureId, "history hash must be lowercase SHA-256")
  assertRecord(typeof fixture.canonical_fixture_sha256 === "string" && /^[0-9a-f]{64}$/.test(fixture.canonical_fixture_sha256), "catalog_invalid", fixtureId, "canonical fixture hash must be lowercase SHA-256")
  assertRecord(typeof fixture.expected_text === "string", "catalog_invalid", fixtureId, "expected text must be a string")
  assertRecord(fixture.first_edit?.kind === "append_unicode_scalar" && fixture.first_edit.scalar === "U+005A", "catalog_invalid", fixtureId, "first edit must append U+005A")
}

async function readRequired(path, code) {
  try {
    return await readFile(path)
  } catch (error) {
    fail(code, `${path}: ${error.code ?? error.message}`)
  }
}

export async function loadBrowserFixtureCatalog(
  fixtureRoot,
  { requiredFixtureIds = canonicalBrowserFixtureIds } = {},
) {
  const catalogPath = join(fixtureRoot, "browser-fixture-catalog-v1.json")
  const catalogBytes = await readRequired(catalogPath, "catalog_missing")
  let catalog
  try {
    catalog = JSON.parse(catalogBytes)
  } catch {
    fail("catalog_invalid", `${catalogPath}: invalid JSON`)
  }
  if (catalog?.schema_version !== 1 || catalog.fixture_seed !== "none" || !Array.isArray(catalog.fixtures)) {
    fail("catalog_invalid", `${catalogPath}: expected schema 1, fixture_seed none, and fixtures array`)
  }
  const byId = new Map(catalog.fixtures.map(fixture => [fixture.fixture_id, fixture]))
  for (const fixtureId of requiredFixtureIds) {
    if (!byId.has(fixtureId)) fail("catalog_entry_missing", fixtureId)
  }
  if (
    requiredFixtureIds === canonicalBrowserFixtureIds &&
    JSON.stringify(catalog.fixtures.map(fixture => fixture.fixture_id)) !== JSON.stringify(canonicalBrowserFixtureIds)
  ) {
    fail("catalog_invalid", "canonical fixture order differs")
  }

  const validated = []
  for (const fixture of catalog.fixtures) {
    validateCatalogRow(fixture)
    const archiveBytes = await readRequired(
      join(fixtureRoot, fixture.archive_path),
      "archive_asset_missing",
    )
    assertRecord(archiveBytes.length === fixture.archive_bytes, "archive_digest_mismatch", fixture.fixture_id, "archive byte length differs")
    assertRecord(sha256(archiveBytes) === fixture.archive_sha256, "archive_digest_mismatch", fixture.fixture_id, "archive SHA-256 differs")
    const encoded = archiveBytes.toString("utf8")
    const archive = validateArchiveEnvelope(fixture, encoded)
    assertRecord(archive.portable_markdown === fixture.expected_text, "expected_portable_text_mismatch", fixture.fixture_id, "portable text differs")
    assertRecord(sha256(archive.portable_markdown) === fixture.expected_text_sha256, "expected_portable_text_mismatch", fixture.fixture_id, "portable text SHA-256 differs")
    assertRecord(byteLength(archive.portable_markdown) === fixture.expected_text_bytes, "expected_portable_text_mismatch", fixture.fixture_id, "portable text byte length differs")
    assertRecord(scalarLength(archive.portable_markdown) === fixture.expected_text_scalars, "expected_portable_text_mismatch", fixture.fixture_id, "portable text scalar length differs")
    assertRecord(archive.portable_markdown.length === fixture.expected_text_utf16_units, "expected_portable_text_mismatch", fixture.fixture_id, "portable text UTF-16 length differs")
    assertRecord(sha256(archive.history) === fixture.history_sha256, "expected_portable_history_mismatch", fixture.fixture_id, "history SHA-256 differs")
    assertRecord(byteLength(archive.history) === fixture.history_bytes, "expected_portable_history_mismatch", fixture.fixture_id, "history byte length differs")
    validateHistory(fixture, archive.history)
    assertRecord(fixture.first_edit.utf16_position === archive.portable_markdown.length, "catalog_invalid", fixture.fixture_id, "first edit is not at UTF-16 end")
    assertRecord(fixture.expected_text_after_edit === `${archive.portable_markdown}Z`, "expected_portable_text_mismatch", fixture.fixture_id, "post-edit text differs")
    assertRecord(sha256(fixture.expected_text_after_edit) === fixture.expected_text_after_edit_sha256, "expected_portable_text_mismatch", fixture.fixture_id, "post-edit text SHA-256 differs")
    validated.push({ ...fixture, encoded, archive })
  }
  return {
    ...catalog,
    catalog_path: catalogPath,
    catalog_sha256: sha256(catalogBytes),
    fixtures: validated,
  }
}
