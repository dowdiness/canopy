import { execFile } from "node:child_process"
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { promisify } from "node:util"
import { canonicalBrowserFixtureIds, sha256 } from "./r0-browser-fixtures.mjs"

const execFileAsync = promisify(execFile)
const repositoryRoot = fileURLToPath(new URL("../../../../", import.meta.url))
const egwRoot = resolve(repositoryRoot, "deps/event-graph-walker")
const outputRoot = resolve(
  process.env.LOOMARK_R0_BROWSER_FIXTURE_OUTPUT ??
    fileURLToPath(new URL("./fixtures/r0-browser-v1/", import.meta.url)),
)
const temporaryRoot = await mkdtemp(joinPath(tmpdir(), "loomark-r0-browser-generator-"))
const canonicalCatalog = JSON.parse(await readFile(joinPath(
  egwRoot,
  "internal/restore_feasibility_probe/fixtures/fixture-catalog-v1.json",
)))
const canonicalById = new Map(
  canonicalCatalog.fixtures.map(fixture => [fixture.fixture_id, fixture]),
)

function joinPath(...parts) {
  return resolve(...parts)
}

async function runMoon(cwd, args) {
  const result = await execFileAsync("moon", args, {
    cwd,
    env: { ...process.env, NEW_MOON_MOD: "0" },
    maxBuffer: 32 * 1024 * 1024,
  })
  if (result.stderr.trim() !== "") process.stderr.write(result.stderr)
}

try {
  await mkdir(outputRoot, { recursive: true })
  const fixtures = []
  for (const fixtureId of canonicalBrowserFixtureIds) {
    const historyPath = joinPath(temporaryRoot, `${fixtureId}.history.json`)
    const archivePath = `${fixtureId}.v1.json`
    const archiveOutputPath = joinPath(outputRoot, archivePath)
    const documentId = `loomark-r0-fixture-${fixtureId}`
    const canonicalFixture = canonicalById.get(fixtureId)
    if (canonicalFixture === undefined) {
      throw new Error(`${fixtureId}: missing from the canonical EGW fixture catalog`)
    }

    await runMoon(egwRoot, [
      "run",
      "--quiet",
      "--release",
      "--target",
      "native",
      "internal/restore_feasibility_probe",
      "--",
      "legacy-history",
      "--case-id",
      fixtureId,
      "--output",
      historyPath,
    ])
    await runMoon(repositoryRoot, [
      "run",
      "--quiet",
      "--release",
      "--target",
      "native",
      "apps/loomark/restore_feasibility_oracle",
      "--",
      "browser-fixture",
      historyPath,
      documentId,
      archiveOutputPath,
    ])

    const archiveBytes = await readFile(archiveOutputPath)
    const archive = JSON.parse(archiveBytes)
    const history = JSON.parse(archive.history)
    if (
      archive.schema_version !== "1" ||
      archive.document_id !== documentId ||
      canonicalFixture.document_id !== documentId ||
      canonicalFixture.event_count !== 1000 ||
      archive.portable_markdown !== canonicalFixture.final_text ||
      history.operations.length !== 1000
    ) {
      throw new Error(`${fixtureId}: generated archive differs from the fixed v1 contract`)
    }
    const expectedTextAfterEdit = `${archive.portable_markdown}Z`
    fixtures.push({
      fixture_id: fixtureId,
      archive_path: archivePath,
      archive_sha256: sha256(archiveBytes),
      archive_bytes: archiveBytes.length,
      expected_text: archive.portable_markdown,
      expected_text_sha256: sha256(archive.portable_markdown),
      expected_text_bytes: Buffer.byteLength(archive.portable_markdown),
      expected_text_scalars: [...archive.portable_markdown].length,
      expected_text_utf16_units: archive.portable_markdown.length,
      history_sha256: sha256(archive.history),
      history_bytes: Buffer.byteLength(archive.history),
      event_count: history.operations.length,
      canonical_fixture_sha256: canonicalFixture.canonical_sha256,
      disposition: "valid",
      consumer: "full_history_v1",
      first_edit: {
        kind: "append_unicode_scalar",
        scalar: "U+005A",
        utf16_position: archive.portable_markdown.length,
      },
      expected_text_after_edit: expectedTextAfterEdit,
      expected_text_after_edit_sha256: sha256(expectedTextAfterEdit),
    })
  }

  const catalog = {
    schema_version: 1,
    generator: "r0_fixture_generator_v1",
    oracle_adapter: "LegacyOracleEventV1",
    fixture_seed: "none",
    fixtures,
  }
  await writeFile(
    joinPath(outputRoot, "browser-fixture-catalog-v1.json"),
    `${JSON.stringify(catalog, null, 2)}\n`,
  )
  process.stdout.write(`${JSON.stringify({ output_root: outputRoot, fixture_count: fixtures.length })}\n`)
} finally {
  await rm(temporaryRoot, { recursive: true, force: true })
}
