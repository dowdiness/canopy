import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { chmod, mkdir, mkdtemp, readFile, stat, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import {
  buildComparisonSchedule,
  evaluateStage1Eligibility,
  finalizeComparisonEvidence,
  normalizeProviderTranscript,
  qualifyProvider,
  validateComparisonJournal,
} from './genui-provider-comparison.mjs';
import {
  buildComparisonManifest,
  writeComparisonManifest,
} from './build-genui-provider-comparison-manifest.mjs';
import { buildManifest as buildFeasibilityManifest } from './build-genui-feasibility-manifest.mjs';
import { canonicalJson } from '../src/genui-feasibility-provider.js';
import {
  executeComparisonStudy,
  prepareComparisonRunRoot,
} from './run-genui-provider-comparison-study.mjs';
import {
  executeCodexSmoke,
  SMOKE_FIXTURE,
} from './smoke-genui-codex-provider.mjs';

const FIXTURES = Object.freeze([
  Object.freeze({ id: 'ast', digest: 'a'.repeat(64) }),
  Object.freeze({ id: 'json', digest: 'b'.repeat(64) }),
  Object.freeze({ id: 'markdown', digest: 'c'.repeat(64) }),
]);
const OLLAMA_SEEDS = Object.freeze([1701, 1702, 1703, 1704, 1705, 1706, 1707, 1708, 1709, 1710]);
const DIGEST = 'd'.repeat(64);
const DIAGNOSTIC_STEPS = Object.freeze([
  'environment_and_model',
  'load_without_generation',
  'minimal_text',
  'json_object',
  'unrelated_json_schema',
  'candidate_schema_synthetic',
  'trusted_fixtures',
]);

function manifestBuilderInput(branch = 'paired') {
  const activeRequests = branch === 'paired' ? 60 : 30;
  const diagnosticSummary = {
    version: 1,
    terminal: true,
    complete: true,
    safe: true,
    selectedBranch: branch,
    probeOrder: branch === 'paired' ? [...DIAGNOSTIC_STEPS] : DIAGNOSTIC_STEPS.slice(0, 4),
    firstFailure: branch === 'paired' ? null : {
      step: 'json_object',
      classification: 'provider_http_error',
    },
    qualifiedForComparison: branch === 'paired',
    fixtureIds: branch === 'paired' ? FIXTURES.map((fixture) => fixture.id) : [],
    identityPreserved: true,
    evidenceIntegrity: true,
    credentialsSafe: true,
    budgetSafe: true,
    isolationSafe: true,
    requestSettingsFrozen: true,
    requestDigest: 'e'.repeat(64),
  };
  return {
    branch,
    diagnosticSummary,
    diagnosticSummarySha256: createHash('sha256').update(canonicalJson(diagnosticSummary)).digest('hex'),
    fixtures: FIXTURES,
    repeats: 10,
    randomizationSeed: 730_513,
    ollamaSeeds: OLLAMA_SEEDS,
    inputDigests: {
      candidateSchemaSha256: '1'.repeat(64),
      fixturesSha256: '2'.repeat(64),
      capabilitiesSha256: '3'.repeat(64),
      promptSha256: '4'.repeat(64),
      rubricSourceSha256: '5'.repeat(64),
      preparationCoreSourceSha256: '6'.repeat(64),
      validationCommandsSha256: '7'.repeat(64),
    },
    providerIdentities: {
      ollama: {
        lookupTag: 'gemma4:e2b',
        ollamaVersion: '0.11.4',
        modelManifestSha256: '8'.repeat(64),
        showDetailsSha256: 'd'.repeat(64),
        templateSha256: '9'.repeat(64),
        parametersSha256: 'a'.repeat(64),
      },
      codex: {
        cliVersion: 'codex-cli 0.144.4',
        catalogEntrySha256: 'b'.repeat(64),
        modelSlug: 'gpt-5.6-luna',
        reasoningEffort: 'medium',
        authMode: 'chatgpt',
      },
    },
    providerContracts: {
      ollama: {
        stream: false,
        temperature: 0.2,
        numCtx: 4096,
        numPredict: 512,
        keepAlive: '5m',
      },
      codex: {
        transport: 'stdio-jsonl',
        experimentalApi: true,
        allowProviderModelFallback: false,
      },
      sandbox: {
        bubblewrapVersion: '0.9.0',
        configSha256: 'c'.repeat(64),
        repositoryMounted: false,
        hostHomeMounted: false,
      },
    },
    limits: {
      slotPositions: 60,
      activeRequests,
      maxCandidateBytes: 65_536,
      slotWallTimeMs: 120_000,
      perRequestTokenCeiling: 16_000,
      runTokenCeiling: activeRequests * 16_000,
      runWallTimeMs: activeRequests * 120_000 + 300_000,
    },
    validationCommands: [
      { id: 'node', command: 'node', args: ['--test'], cwd: 'examples/web' },
      { id: 'moon', command: 'moon', args: ['test', 'ffi/jsx'], cwd: '.' },
    ],
    artifactContract: {
      privateRunRoot: '$XDG_STATE_HOME/canopy/genui-provider-benchmark/<run-id>/',
      rawArtifacts: {
        appServerJsonl: 'raw/app-server.jsonl',
        appServerStderr: 'raw/app-server.stderr',
        ollamaBodies: 'raw/ollama/',
        ollamaServerLogs: 'raw/ollama-server/',
      },
      normalizedTranscript: 'docs/evidence/genui-provider-comparison-transcript.json',
      aggregateEvidence: 'docs/evidence/genui-provider-comparison.json',
    },
  };
}

function schedule(branch = 'paired', randomizationSeed = 730_513) {
  return buildComparisonSchedule({
    fixtures: FIXTURES,
    repeats: 10,
    randomizationSeed,
    ollamaSeeds: OLLAMA_SEEDS,
    branch,
  });
}

function passingSlotRecord(slot, overrides = {}) {
  return {
    slotId: slot.slotId,
    fixtureId: slot.fixtureId,
    providerId: slot.providerId,
    terminal: true,
    active: slot.active,
    classification: slot.active ? 'candidate_pass' : 'ollama_not_operational',
    preparationPassed: slot.active,
    passedRubric: slot.active,
    safetyViolations: 0,
    toolUseViolations: 0,
    stateMutationViolations: 0,
    credentialLeakageViolations: 0,
    identityDrift: false,
    replayMismatch: false,
    ...overrides,
  };
}

function stage1Records(manifest) {
  return manifest.schedule
    .filter((slot) => slot.stage === 1)
    .map((slot) => passingSlotRecord(slot));
}

function passingAudit(overrides = {}) {
  return {
    manifest: true,
    schedule: true,
    evidence: true,
    retention: true,
    ...overrides,
  };
}

function journalFor(manifest, terminalFor = () => 'candidate_pass') {
  return manifest.schedule.flatMap((slot) => slot.active
    ? [
        { type: 'start', slotId: slot.slotId },
        { type: 'terminal', slotId: slot.slotId, classification: terminalFor(slot) },
      ]
    : [{ type: 'terminal', slotId: slot.slotId, classification: 'ollama_not_operational' }]);
}

function manifestFor(branch = 'paired') {
  return { branch, schedule: schedule(branch) };
}

function finalizerInput(overrides = {}) {
  const manifest = manifestFor('paired');
  return {
    manifest,
    manifestSha256: '1'.repeat(64),
    frozenCommit: '2'.repeat(40),
    preflight: { isolation: true, identity: true, credentials: true, budget: true },
    journal: journalFor(manifest),
    rawArtifacts: [
      { id: 'app-server-jsonl', digest: '3'.repeat(64), available: true },
      { id: 'stderr', digest: '4'.repeat(64), available: true },
    ],
    ...overrides,
  };
}

test('freezes 60 canonical adjacent slots with exact seeded 15/15 pair balancing', () => {
  const paired = schedule('paired');
  assert.equal(paired.length, 60);
  assert.equal(new Set(paired.map((slot) => slot.slotId)).size, 60);
  assert.equal(paired.filter((slot) => slot.providerId === 'ollama').length, 30);
  assert.equal(paired.filter((slot) => slot.providerId === 'codex').length, 30);
  assert.equal(paired.filter((slot) => slot.stage === 1).length, 18);
  assert.equal(paired.filter((slot) => slot.stage === 2).length, 42);

  const ollamaFirst = [];
  for (let index = 0; index < paired.length; index += 2) {
    const pair = paired.slice(index, index + 2);
    assert.equal(pair[0].pairId, pair[1].pairId);
    assert.equal(pair[0].fixtureId, pair[1].fixtureId);
    assert.equal(pair[0].repeatIndex, pair[1].repeatIndex);
    assert.deepEqual(new Set(pair.map((slot) => slot.providerId)), new Set(['ollama', 'codex']));
    ollamaFirst.push(pair[0].providerId === 'ollama');
  }
  assert.equal(ollamaFirst.filter(Boolean).length, 15);
  assert.equal(ollamaFirst.filter((value) => !value).length, 15);
  assert.deepEqual(schedule('paired'), paired);
  assert.notDeepEqual(
    schedule('paired', 730_514).map((slot) => slot.providerId),
    paired.map((slot) => slot.providerId),
  );
});

test('codex_only changes only Ollama activation while preserving canonical slot identity and order', () => {
  const paired = schedule('paired');
  const codexOnly = schedule('codex_only');
  assert.deepEqual(codexOnly.map((slot) => slot.slotId), paired.map((slot) => slot.slotId));
  assert.deepEqual(codexOnly.map((slot) => slot.pairId), paired.map((slot) => slot.pairId));
  assert.equal(codexOnly.filter((slot) => slot.active).length, 30);
  for (let index = 0; index < codexOnly.length; index += 1) {
    const slot = codexOnly[index];
    const expectedId = `${slot.fixtureId}/${String(slot.repeatIndex + 1).padStart(2, '0')}/${slot.providerId}`;
    assert.equal(slot.slotId, expectedId);
    if (slot.providerId === 'ollama') {
      assert.equal(slot.active, false);
      assert.equal(slot.classification, 'ollama_not_operational');
      assert.equal(slot.seed, OLLAMA_SEEDS[slot.repeatIndex]);
    } else {
      assert.equal(slot.active, true);
      assert.equal('seed' in slot, false);
    }
  }
});

test('Stage 1 eligibility requires exact terminal coverage and every active-provider predicate', () => {
  for (const branch of ['paired', 'codex_only']) {
    const manifest = manifestFor(branch);
    const records = stage1Records(manifest);
    const result = evaluateStage1Eligibility({ manifest, slots: records, audit: passingAudit() });
    assert.equal(records.length, 18);
    assert.equal(records.filter((slot) => slot.active).length, branch === 'paired' ? 18 : 9);
    assert.equal(result.eligible, true);
    assert.equal(result.providers.ollama.status, branch === 'paired' ? 'eligible' : 'unavailable');
    assert.equal(result.providers.codex.status, 'eligible');

    assert.equal(evaluateStage1Eligibility({ manifest, slots: records.slice(1), audit: passingAudit() }).eligible, false);
    assert.equal(evaluateStage1Eligibility({ manifest, slots: [...records, records[0]], audit: passingAudit() }).eligible, false);
    const onePreparationFailure = records.map((record, index) =>
      index === records.findIndex((candidate) => candidate.active)
        ? { ...record, preparationPassed: false }
        : record
    );
    assert.equal(
      evaluateStage1Eligibility({ manifest, slots: onePreparationFailure, audit: passingAudit() }).eligible,
      true,
    );
  }
});

test('Stage 1 independently fails preparation, safety, mutation, credential, identity, replay, and audit predicates', () => {
  const manifest = manifestFor('paired');
  const base = stage1Records(manifest);
  const activeIndex = base.findIndex((slot) => slot.providerId === 'codex' && slot.fixtureId === FIXTURES[0].id);
  const replace = (patch) => base.map((slot, index) => index === activeIndex ? { ...slot, ...patch } : slot);
  const cases = [
    replace({ safetyViolations: 1 }),
    replace({ toolUseViolations: 1 }),
    replace({ stateMutationViolations: 1 }),
    replace({ credentialLeakageViolations: 1 }),
    replace({ identityDrift: true }),
    replace({ replayMismatch: true }),
  ];
  for (const slots of cases) {
    assert.equal(evaluateStage1Eligibility({ manifest, slots, audit: passingAudit() }).eligible, false);
  }

  const noPreparation = base.map((slot) => slot.providerId === 'codex' && slot.fixtureId === FIXTURES[0].id
    ? { ...slot, preparationPassed: false }
    : slot);
  assert.equal(evaluateStage1Eligibility({ manifest, slots: noPreparation, audit: passingAudit() }).eligible, false);
  for (const key of ['manifest', 'schedule', 'evidence', 'retention']) {
    assert.equal(evaluateStage1Eligibility({ manifest, slots: base, audit: passingAudit({ [key]: false }) }).eligible, false, key);
  }
});

test('qualification pins 23/24 overall, 6/7 per fixture, and zero-tolerance boundaries', () => {
  const providerSlots = (fixturePasses) => FIXTURES.flatMap((fixture) => Array.from({ length: 10 }, (_, index) => ({
    providerId: 'codex',
    fixtureId: fixture.id,
    active: true,
    terminal: true,
    passedRubric: index < fixturePasses[fixture.id],
    safetyViolations: 0,
    replayMismatch: false,
    identityDrift: false,
  })));

  assert.equal(qualifyProvider({ providerId: 'codex', slots: providerSlots({ ast: 8, json: 8, markdown: 7 }) }).qualifies, false);
  assert.equal(qualifyProvider({ providerId: 'codex', slots: providerSlots({ ast: 8, json: 8, markdown: 8 }) }).qualifies, true);
  assert.equal(qualifyProvider({ providerId: 'codex', slots: providerSlots({ ast: 9, json: 9, markdown: 6 }) }).qualifies, false);
  assert.equal(qualifyProvider({ providerId: 'codex', slots: providerSlots({ ast: 10, json: 7, markdown: 7 }) }).qualifies, true);

  for (const patch of [{ safetyViolations: 1 }, { replayMismatch: true }, { identityDrift: true }]) {
    const slots = providerSlots({ ast: 10, json: 10, markdown: 10 });
    slots[0] = { ...slots[0], ...patch };
    assert.equal(qualifyProvider({ providerId: 'codex', slots }).qualifies, false);
  }

  const unavailable = qualifyProvider({
    providerId: 'ollama',
    slots: schedule('codex_only').filter((slot) => slot.providerId === 'ollama').map((slot) => passingSlotRecord(slot)),
  });
  assert.equal(unavailable.status, 'unavailable');
  assert.equal(unavailable.qualifies, false);
});

test('journal enforces frozen order, one start and terminal, and no retry or replacement', () => {
  const manifest = manifestFor('paired');
  const journal = journalFor(manifest);
  assert.equal(validateComparisonJournal({ manifest, journal }).complete, true);

  const wrongOrder = [...journal];
  [wrongOrder[0], wrongOrder[2]] = [wrongOrder[2], wrongOrder[0]];
  assert.throws(() => validateComparisonJournal({ manifest, journal: wrongOrder }), /order/u);
  assert.throws(() => validateComparisonJournal({ manifest, journal: [...journal, journal[1]] }), /duplicate|extra/u);
  assert.throws(() => validateComparisonJournal({ manifest, journal: journal.slice(1) }), /start/u);
  assert.throws(() => validateComparisonJournal({
    manifest,
    journal: journal.map((event, index) => index === 0 ? { ...event, slotId: 'replacement-slot' } : event),
  }), /slot|order/u);
});

test('journal continues ordinary failures and accepts only fail-closed terminal fills', () => {
  const paired = manifestFor('paired');
  const ordinary = journalFor(paired, (slot) => slot.repeatIndex === 0 ? 'provider_timeout' : 'candidate_pass');
  assert.equal(validateComparisonJournal({ manifest: paired, journal: ordinary }).terminalCount, 60);

  const firstTerminalIndex = ordinary.findIndex((event) => event.type === 'terminal');
  const globalStop = [
    ...ordinary.slice(0, firstTerminalIndex + 1),
    ...paired.schedule.slice(1).map((slot) => ({ type: 'terminal', slotId: slot.slotId, classification: 'global_stop' })),
  ];
  assert.equal(validateComparisonJournal({ manifest: paired, journal: globalStop }).globalStop, true);

  const stage1 = paired.schedule.filter((slot) => slot.stage === 1);
  const ineligible = [
    ...journalFor({ ...paired, schedule: stage1 }),
    ...paired.schedule.filter((slot) => slot.stage === 2).map((slot) => ({
      type: 'terminal', slotId: slot.slotId, classification: 'stage1_ineligible',
    })),
  ];
  assert.equal(validateComparisonJournal({ manifest: paired, journal: ineligible }).stage2Executed, false);

  const codexOnly = manifestFor('codex_only');
  assert.equal(validateComparisonJournal({ manifest: codexOnly, journal: journalFor(codexOnly) }).terminalCount, 60);
  const codexStage1 = codexOnly.schedule.filter((slot) => slot.stage === 1);
  const codexIneligible = [
    ...journalFor({ ...codexOnly, schedule: codexStage1 }),
    ...codexOnly.schedule.filter((slot) => slot.stage === 2).map((slot) => ({
      type: 'terminal',
      slotId: slot.slotId,
      classification: slot.active ? 'stage1_ineligible' : 'ollama_not_operational',
    })),
  ];
  const codexIneligibleSummary = validateComparisonJournal({ manifest: codexOnly, journal: codexIneligible });
  assert.equal(codexIneligibleSummary.activeAttempts, 9);
  assert.equal(codexIneligibleSummary.stage2Executed, false);
  for (const classification of ['process_crash', 'signal_interruption']) {
    const events = journalFor(paired, (slot) => slot.repeatIndex === 0 ? classification : 'candidate_pass');
    assert.equal(validateComparisonJournal({ manifest: paired, journal: events }).complete, true);
  }
});

test('normalizes stable type-specific opaque IDs and preserves only reviewable fields', () => {
  const rawEvents = [
    {
      requestId: 'same-private-id',
      threadId: 'same-private-id',
      turnId: 'turn-secret',
      method: 'turn/start',
      itemType: 'agentMessage',
      status: 'completed',
      model: 'gpt-5.6-codex',
      usage: { inputTokens: 12, outputTokens: 4, totalTokens: 16 },
      timing: { elapsedMs: 250 },
      candidateDigest: DIGEST,
      candidateByteLength: 42,
      rawArtifactDigest: 'e'.repeat(64),
      cwd: '/private/host/worktree',
      account: { email: 'private@example.com' },
      prompt: 'private prompt bytes',
      candidate: 'private candidate bytes',
    },
    {
      requestId: 'request-two',
      threadId: 'same-private-id',
      turnId: 'turn-secret',
      method: 'turn/completed',
      status: 'completed',
    },
  ];
  const normalized = normalizeProviderTranscript({ providerId: 'codex', rawEvents, canaries: { hostPaths: [], secretValues: [] } });
  assert.deepEqual(normalized.events.map((event) => event.requestId), ['request-0001', 'request-0002']);
  assert.deepEqual(normalized.events.map((event) => event.threadId), ['thread-0001', 'thread-0001']);
  assert.deepEqual(normalized.events.map((event) => event.turnId), ['turn-0001', 'turn-0001']);
  assert.equal(normalized.events[0].model, 'gpt-5.6-codex');
  assert.deepEqual(normalized.events[0].usage, { inputTokens: 12, outputTokens: 4, totalTokens: 16 });
  assert.equal(normalized.events[0].candidateDigest, DIGEST);
  const text = JSON.stringify(normalized);
  for (const forbidden of ['/private/host/worktree', 'private@example.com', 'private prompt bytes', 'private candidate bytes', 'same-private-id', 'turn-secret']) {
    assert.equal(text.includes(forbidden), false, forbidden);
  }
  assert.deepEqual(normalized.redactions.map((entry) => entry.field).sort(), [
    'account', 'candidate', 'cwd', 'prompt', 'requestId', 'requestId', 'threadId', 'threadId', 'turnId', 'turnId',
  ].sort());
  assert.deepEqual(normalizeProviderTranscript({ providerId: 'codex', rawEvents, canaries: { hostPaths: [], secretValues: [] } }), normalized);
});

test('transcript rejects injected canaries and malformed reviewable fields', () => {
  const base = { requestId: 'r', threadId: 't', turnId: 'u', method: 'turn/start', status: 'completed' };
  for (const event of [
    { ...base, detail: 'SECRET-CANARY' },
    { ...base, detail: '/private/PATH-CANARY' },
  ]) {
    assert.throws(() => normalizeProviderTranscript({
      providerId: 'codex',
      rawEvents: [event],
      canaries: { hostPaths: ['/private/PATH-CANARY'], secretValues: ['SECRET-CANARY'] },
    }), /canary|forbidden/u);
  }
  assert.throws(() => normalizeProviderTranscript({
    providerId: 'codex', rawEvents: [{ ...base, usage: { totalTokens: -1 } }], canaries: { hostPaths: [], secretValues: [] },
  }), /usage|token/u);
});

test('final evidence verifies schedule and raw digests and downgrades missing raw auditability', () => {
  const complete = finalizeComparisonEvidence(finalizerInput());
  assert.equal(complete.schedule.complete, true);
  assert.equal(complete.journal.terminalCount, 60);
  assert.equal(complete.auditability, 'full');
  assert.equal(JSON.stringify(complete).includes('private candidate bytes'), false);

  const missingInput = finalizerInput();
  missingInput.rawArtifacts[1] = { ...missingInput.rawArtifacts[1], available: false };
  const missing = finalizeComparisonEvidence(missingInput);
  assert.equal(missing.auditability, 'unavailable');
  assert.match(missing.conclusionLimit, /raw artifact/u);
  assert.throws(() => finalizeComparisonEvidence(finalizerInput({ rawArtifacts: [{ id: 'raw', available: true }] })), /digest/u);
  assert.throws(() => finalizeComparisonEvidence(finalizerInput({ manifest: { branch: 'paired', schedule: schedule('paired').slice(1) } })), /60|schedule/u);
});

test('CLI writes final evidence exclusively and refuses replacement', async () => {
  const root = await mkdtemp(join(tmpdir(), 'canopy-genui-policy-'));
  const inputPath = join(root, 'input.json');
  const outputPath = join(root, 'evidence.json');
  await writeFile(inputPath, `${JSON.stringify(finalizerInput())}\n`, { flag: 'wx' });
  const cli = join(import.meta.dirname, 'genui-provider-comparison.mjs');
  const first = spawnSync(process.execPath, [cli, 'finalize', '--input', inputPath, '--output', outputPath], { encoding: 'utf8' });
  assert.equal(first.status, 0, first.stderr);
  const written = JSON.parse(await readFile(outputPath, 'utf8'));
  assert.equal(written.auditability, 'full');
  const second = spawnSync(process.execPath, [cli, 'finalize', '--input', inputPath, '--output', outputPath], { encoding: 'utf8' });
  assert.notEqual(second.status, 0);
});

test('CLI writes normalized transcript exclusively and refuses replacement', async () => {
  const root = await mkdtemp(join(tmpdir(), 'canopy-genui-transcript-'));
  const inputPath = join(root, 'input.json');
  const outputPath = join(root, 'transcript.json');
  const input = {
    providerId: 'codex',
    rawEvents: [{ requestId: 'private-request', method: 'turn/completed', status: 'completed' }],
    canaries: { hostPaths: [], secretValues: [] },
  };
  await writeFile(inputPath, `${JSON.stringify(input)}\n`, { flag: 'wx' });
  const cli = join(import.meta.dirname, 'genui-provider-comparison.mjs');
  const first = spawnSync(process.execPath, [cli, 'normalize', '--input', inputPath, '--output', outputPath], { encoding: 'utf8' });
  assert.equal(first.status, 0, first.stderr);
  const written = JSON.parse(await readFile(outputPath, 'utf8'));
  assert.equal(written.events[0].requestId, 'request-0001');
  assert.equal(JSON.stringify(written).includes('private-request'), false);
  const second = spawnSync(process.execPath, [cli, 'normalize', '--input', inputPath, '--output', outputPath], { encoding: 'utf8' });
  assert.notEqual(second.status, 0);
});

test('manifest builder freezes both branches, identities, schedule, contracts, limits, commands, and logical artifacts', () => {
  for (const branch of ['paired', 'codex_only']) {
    const input = manifestBuilderInput(branch);
    const manifest = buildComparisonManifest(input, {
      verifyRepository: () => '0'.repeat(40),
    });
    assert.equal(manifest.manifestVersion, 1);
    assert.equal(manifest.studyId, 'genui-provider-comparison-v1');
    assert.match(manifest.claimScope, /engineering provider benchmark/u);
    assert.match(manifest.claimScope, /no user-value|does not establish user value/u);
    assert.equal(manifest.sourceCommit, '0'.repeat(40));
    assert.equal(manifest.diagnosticSummarySha256, input.diagnosticSummarySha256);
    assert.equal(manifest.branch, branch);
    assert.equal(manifest.schedule.length, 60);
    assert.deepEqual(manifest.providerOrder, ['ollama', 'codex']);
    assert.deepEqual(manifest.ollamaSeeds, OLLAMA_SEEDS);
    assert.deepEqual(manifest.inputDigests, input.inputDigests);
    assert.deepEqual(manifest.providerIdentities, input.providerIdentities);
    assert.deepEqual(manifest.providerContracts, input.providerContracts);
    assert.deepEqual(manifest.limits, input.limits);
    assert.deepEqual(manifest.validationCommands, input.validationCommands);
    assert.deepEqual(manifest.artifacts, input.artifactContract);
    assert.equal(manifest.decisionRule.noRetry, true);
    assert.equal(manifest.decisionRule.replayRequiredForEveryCandidate, true);
    assert.equal(manifest.decisionRule.stage1Slots, 18);
    assert.equal(manifest.decisionRule.stage2RequiresEligibleStage1, true);
    assert.equal(manifest.schedule.filter((slot) => slot.active).length, branch === 'paired' ? 60 : 30);
    assert.equal(
      manifest.schedule.filter((slot) => !slot.active).every((slot) =>
        slot.providerId === 'ollama' && slot.classification === 'ollama_not_operational'
      ),
      true,
    );
    for (const slot of manifest.schedule) {
      assert.equal(slot.ollamaSeed, slot.providerId === 'ollama' ? OLLAMA_SEEDS[slot.repeatIndex] : null);
    }
    const serialized = JSON.stringify(manifest);
    assert.equal(serialized.includes('/home/'), false);
    assert.equal(serialized.includes('/tmp/'), false);
    assert.equal(
      manifest.artifacts.privateRunRoot,
      '$XDG_STATE_HOME/canopy/genui-provider-benchmark/<run-id>/',
    );
  }
});

test('manifest builder rejects dirty state, unsafe or incomplete diagnostics, branch mismatch, paths, and invalid limits', () => {
  assert.throws(
    () => buildComparisonManifest(manifestBuilderInput(), {
      verifyRepository: () => {
        throw new Error('repository must be clean');
      },
    }),
    /clean/u,
  );

  const mismatch = manifestBuilderInput('paired');
  mismatch.diagnosticSummary = { ...mismatch.diagnosticSummary, selectedBranch: 'codex_only' };
  assert.throws(() => buildComparisonManifest(mismatch, { verifyRepository: () => '0'.repeat(40) }), /branch/u);

  const staleDigest = manifestBuilderInput('paired');
  staleDigest.diagnosticSummary = { ...staleDigest.diagnosticSummary, requestDigest: '0'.repeat(64) };
  assert.throws(
    () => buildComparisonManifest(staleDigest, { verifyRepository: () => '0'.repeat(40) }),
    /diagnostic.*digest|digest.*diagnostic|mismatch/u,
  );

  const incomplete = manifestBuilderInput('paired');
  incomplete.diagnosticSummary = {
    ...incomplete.diagnosticSummary,
    probeOrder: DIAGNOSTIC_STEPS.slice(0, 6),
  };
  assert.throws(() => buildComparisonManifest(incomplete, { verifyRepository: () => '0'.repeat(40) }), /diagnostic|seven|probe/u);

  for (const patch of [
    { safe: false },
    { evidenceIntegrity: false },
    { credentialsSafe: false },
    { budgetSafe: false },
    { isolationSafe: false },
  ]) {
    const unsafe = manifestBuilderInput();
    unsafe.diagnosticSummary = { ...unsafe.diagnosticSummary, ...patch };
    assert.throws(
      () => buildComparisonManifest(unsafe, { verifyRepository: () => '0'.repeat(40) }),
      /safe|integrity|credential|budget|isolation/u,
    );
  }

  const localRaw = manifestBuilderInput();
  localRaw.artifactContract = {
    ...localRaw.artifactContract,
    privateRunRoot: 'examples/web/test-results/provider-benchmark/',
  };
  assert.throws(() => buildComparisonManifest(localRaw, { verifyRepository: () => '0'.repeat(40) }), /raw|XDG|artifact/u);

  const absolutePublic = manifestBuilderInput();
  absolutePublic.artifactContract = {
    ...absolutePublic.artifactContract,
    rawArtifacts: { ...absolutePublic.artifactContract.rawArtifacts, appServerJsonl: '/tmp/raw.jsonl' },
  };
  assert.throws(() => buildComparisonManifest(absolutePublic, { verifyRepository: () => '0'.repeat(40) }), /absolute|artifact|path/u);

  for (const invalid of ['4 * smokeTotalTokens', 0, -1, 16_000.5, 32_001]) {
    const invalidLimit = manifestBuilderInput();
    invalidLimit.limits = { ...invalidLimit.limits, perRequestTokenCeiling: invalid };
    assert.throws(
      () => buildComparisonManifest(invalidLimit, { verifyRepository: () => '0'.repeat(40) }),
      /limit|token|integer|range/u,
    );
  }

  const missingShowIdentity = manifestBuilderInput();
  delete missingShowIdentity.providerIdentities.ollama.showDetailsSha256;
  assert.throws(
    () => buildComparisonManifest(missingShowIdentity, { verifyRepository: () => '0'.repeat(40) }),
    /Ollama.*show.*digest|showDetailsSha256/u,
  );
});

test('manifest writer creates output exclusively', async () => {
  const root = await mkdtemp(join(tmpdir(), 'canopy-genui-manifest-'));
  const outputPath = join(root, 'manifest.json');
  const deps = { verifyRepository: () => '0'.repeat(40) };
  const first = await writeComparisonManifest({
    outputPath,
    input: manifestBuilderInput('codex_only'),
  }, deps);
  assert.equal(first.branch, 'codex_only');
  assert.equal(JSON.parse(await readFile(outputPath, 'utf8')).sourceCommit, '0'.repeat(40));
  await assert.rejects(
    () => writeComparisonManifest({ outputPath, input: manifestBuilderInput('codex_only') }, deps),
    /exist|overwrite/u,
  );
});

test('exporting legacy manifest helpers leaves the v2 manifest bytes unchanged', async () => {
  const identity = {
    lookupTag: 'gemma4:4b',
    modelManifestSha256: 'a'.repeat(64),
    showDetailsSha256: 'b'.repeat(64),
    ollamaVersion: '0.1.2',
    templateSha256: 'c'.repeat(64),
    parametersSha256: 'd'.repeat(64),
  };
  const manifest = await buildFeasibilityManifest({
    model: identity.lookupTag,
    verifyRepository: () => 'frozen-commit',
    readIdentity: async () => identity,
  });
  const bytes = `${JSON.stringify(manifest, null, 2)}\n`;
  assert.equal(Buffer.byteLength(bytes), 4_884);
  assert.equal(
    createHash('sha256').update(bytes).digest('hex'),
    'ae8c89814b9a42e7fbeb36f00f6aec8a4a9ecb23a1caa323e968da87ae1558d7',
  );
});

const CANDIDATE_JSON = '{"type":"component","component":"DataTable"}';
const CANDIDATE_DIGEST = createHash('sha256').update(CANDIDATE_JSON).digest('hex');
const RUN_CANARIES = Object.freeze({
  hostPaths: Object.freeze(['/private/host/worktree']),
  secretValues: Object.freeze(['private-secret-value']),
});

function successfulProviderAttempt(slot) {
  return {
    classification: 'candidate_pass',
    candidateJson: CANDIDATE_JSON,
    rawEvents: [
      {
        type: 'agentMessage',
        requestId: `request-${slot.slotId}`,
        threadId: `thread-${slot.slotId}`,
        turnId: `turn-${slot.slotId}`,
        model: slot.providerId,
        timing: { elapsedMs: 5 },
        candidateDigest: CANDIDATE_DIGEST,
        candidateByteLength: Buffer.byteLength(CANDIDATE_JSON),
        usage: { inputTokens: 3, cachedInputTokens: 0, outputTokens: 2, totalTokens: 5 },
      },
    ],
  };
}

function passingCandidateGate() {
  return {
    classification: 'candidate_pass',
    preparationPassed: true,
    safetyViolations: 0,
    mutationViolations: 0,
    credentialLeakageViolations: 0,
    identityDrift: false,
    replayMismatch: false,
    validations: {
      decoding: true,
      semantic: true,
      materialization: true,
      rubric: true,
      replay: true,
      sessionCommit: true,
    },
  };
}

function passingStage1Audit() {
  return {
    manifest: true,
    schedule: true,
    evidence: true,
    retention: true,
    identityPreserved: true,
    evidenceIntegrity: true,
    credentialsSafe: true,
    budgetSafe: true,
    isolationSafe: true,
    requestSettingsFrozen: true,
  };
}

async function runnerFixture(manifest, slot) {
  const frozen = manifest.fixtures.find((fixture) => fixture.id === slot.fixtureId);
  return {
    fixture: {
      caseId: slot.fixtureId,
      question: `Question for ${slot.fixtureId}`,
      sourceFormat: 'json-array',
      binding: 'records',
      selectionKey: 'id',
      fields: ['id', 'value'],
      numericFields: ['value'],
      taskValue: 1,
      source: [{ id: slot.fixtureId, value: 1 }],
    },
    capabilitiesJson: '{"bindings":[{"name":"records"}]}',
    datasetJson: '[{"id":"record-1","value":1}]',
    digest: frozen.digest,
  };
}

async function makeRunPaths(label) {
  const root = await mkdtemp(join(tmpdir(), `canopy-provider-${label}-`));
  const xdgStateHome = join(root, 'state');
  const runRoot = join(xdgStateHome, 'canopy', 'genui-provider-benchmark', 'run-001');
  const repositoryRoot = join(root, 'repository');
  await mkdir(repositoryRoot, { mode: 0o700 });
  return { root, xdgStateHome, runRoot, repositoryRoot };
}

function runnerDeps(manifest, calls, overrides = {}) {
  return {
    verifyRepository: () => manifest.sourceCommit,
    preflight: async () => {
      calls.push('preflight');
      return {
        isolation: true,
        identity: true,
        credentials: true,
        budget: true,
      };
    },
    loadFixture: (slot) => runnerFixture(manifest, slot),
    createSandbox: async ({ slot }) => {
      calls.push(`sandbox:${slot.slotId}`);
      return {
        contract: { runRoot: `/private/${slot.slotId}` },
        cleanup: async () => calls.push(`cleanup:${slot.slotId}`),
      };
    },
    requestGate: async ({ slot }) => calls.push(`gate:${slot.slotId}`),
    attempts: {
      codex: async ({ slot, sandbox }) => {
        assert.equal(sandbox.contract.runRoot, `/private/${slot.slotId}`);
        calls.push(`codex:${slot.slotId}`);
        return successfulProviderAttempt(slot);
      },
      ollama: async ({ slot, seed }) => {
        calls.push(`ollama:${slot.slotId}:${seed}`);
        return successfulProviderAttempt(slot);
      },
    },
    evaluateCandidate: async ({ slot, candidateJson, input }) => {
      assert.equal(candidateJson, CANDIDATE_JSON);
      assert.equal(input.fixture.caseId, slot.fixtureId);
      calls.push(`moonbit:${slot.slotId}`);
      return passingCandidateGate();
    },
    auditStage1: async () => passingStage1Audit(),
    canaries: RUN_CANARIES,
    now: () => '2026-07-17T00:00:00.000Z',
    ...overrides,
  };
}

function testComparisonManifest(branch) {
  return buildComparisonManifest(manifestBuilderInput(branch), {
    verifyRepository: () => '0'.repeat(40),
  });
}

test('runner executes the paired frozen schedule sequentially with exact Ollama seeds', async () => {
  const manifest = testComparisonManifest('paired');
  const paths = await makeRunPaths('paired');
  const calls = [];
  let inFlight = 0;
  let maxInFlight = 0;
  const deps = runnerDeps(manifest, calls);
  for (const providerId of ['codex', 'ollama']) {
    const attempt = deps.attempts[providerId];
    deps.attempts[providerId] = async (input) => {
      inFlight += 1;
      maxInFlight = Math.max(maxInFlight, inFlight);
      await new Promise((resolvePromise) => setImmediate(resolvePromise));
      const result = await attempt(input);
      inFlight -= 1;
      return result;
    };
  }

  const result = await executeComparisonStudy({
    manifest,
    runRoot: paths.runRoot,
    xdgStateHome: paths.xdgStateHome,
    repositoryRoot: paths.repositoryRoot,
  }, deps);

  assert.equal(calls[0], 'preflight');
  assert.equal(maxInFlight, 1);
  assert.equal(calls.filter((entry) => entry.startsWith('codex:')).length, 30);
  const ollamaCalls = calls.filter((entry) => entry.startsWith('ollama:'));
  assert.equal(ollamaCalls.length, 30);
  assert.deepEqual(
    ollamaCalls.map((entry) => Number(entry.split(':').at(-1))).sort((left, right) => left - right),
    OLLAMA_SEEDS.flatMap((seed) => [seed, seed, seed]).sort((left, right) => left - right),
  );
  assert.equal(calls.filter((entry) => entry.startsWith('cleanup:')).length, 30);
  assert.equal(result.journal.terminalCount, 60);
  assert.equal(result.journal.activeAttempts, 60);
  assert.equal(result.journal.stage2Executed, true);
  assert.match(result.evidence.manifestSha256, /^[0-9a-f]{64}$/u);
});

test('runner rejects a reviewed Ollama seed assigned to the wrong repeat before provider access', async () => {
  const base = testComparisonManifest('paired');
  const firstOllamaSlotId = base.schedule.find((slot) => slot.providerId === 'ollama').slotId;
  const manifest = {
    ...base,
    schedule: base.schedule.map((slot) =>
      slot.slotId === firstOllamaSlotId
        ? { ...slot, ollamaSeed: base.ollamaSeeds[(slot.repeatIndex + 1) % base.ollamaSeeds.length] }
        : slot),
  };
  const paths = await makeRunPaths('invalid-ollama-seed');
  let ollamaProviderCalls = 0;
  const deps = runnerDeps(manifest, [], {
    attempts: {
      codex: async ({ slot }) => successfulProviderAttempt(slot),
      ollama: async () => {
        ollamaProviderCalls += 1;
        return { classification: 'candidate_pass' };
      },
    },
  });
  await assert.rejects(
    executeComparisonStudy({
      manifest,
      runRoot: paths.runRoot,
      xdgStateHome: paths.xdgStateHome,
      repositoryRoot: paths.repositoryRoot,
    }, deps),
    /reviewed manifest seed vector/u,
  );
  assert.equal(ollamaProviderCalls, 0);
});

test('runner codex-only branch preserves all canonical slots and never invokes Ollama', async () => {
  const manifest = testComparisonManifest('codex_only');
  const paths = await makeRunPaths('codex-only');
  const calls = [];
  const deps = runnerDeps(manifest, calls, {
    attempts: {
      codex: async ({ slot }) => {
        calls.push(`codex:${slot.slotId}`);
        return successfulProviderAttempt(slot);
      },
      ollama: async () => assert.fail('Ollama must not run in codex_only'),
    },
  });

  const result = await executeComparisonStudy({
    manifest,
    runRoot: paths.runRoot,
    xdgStateHome: paths.xdgStateHome,
    repositoryRoot: paths.repositoryRoot,
  }, deps);

  assert.equal(result.journal.terminalCount, 60);
  assert.equal(result.journal.activeAttempts, 30);
  assert.equal(result.journal.stage2Executed, true);
  assert.equal(result.slots.filter((slot) => slot.classification === 'ollama_not_operational').length, 30);
  assert.equal(calls.filter((entry) => entry.startsWith('codex:')).length, 30);
});

test('runner never retries ordinary failures and global stop fills every remaining slot', async () => {
  const manifest = testComparisonManifest('paired');
  const ordinaryPaths = await makeRunPaths('ordinary-failure');
  const ordinaryCalls = [];
  let failedSlotId = null;
  const ordinaryDeps = runnerDeps(manifest, ordinaryCalls);
  const firstProvider = manifest.schedule.find((slot) => slot.active).providerId;
  const successful = ordinaryDeps.attempts[firstProvider];
  ordinaryDeps.attempts[firstProvider] = async (input) => {
    ordinaryCalls.push(`${firstProvider}:${input.slot.slotId}`);
    if (failedSlotId === null) {
      failedSlotId = input.slot.slotId;
      return { classification: 'process_crash', rawEvents: [] };
    }
    return successful(input);
  };

  const ordinary = await executeComparisonStudy({
    manifest,
    runRoot: ordinaryPaths.runRoot,
    xdgStateHome: ordinaryPaths.xdgStateHome,
    repositoryRoot: ordinaryPaths.repositoryRoot,
  }, ordinaryDeps);
  assert.equal(
    ordinaryCalls.filter((entry) => entry === `${firstProvider}:${failedSlotId}`).length,
    1,
  );
  assert.equal(ordinary.slots.find((slot) => slot.slotId === failedSlotId).classification, 'process_crash');
  assert.equal(ordinary.journal.activeAttempts, 60);
  assert.equal(ordinary.journal.stage2Executed, true);

  const stopPaths = await makeRunPaths('global-stop');
  const stopCalls = [];
  const stopDeps = runnerDeps(manifest, stopCalls);
  for (const providerId of ['codex', 'ollama']) {
    stopDeps.attempts[providerId] = async ({ slot }) => {
      stopCalls.push(`${providerId}:${slot.slotId}`);
      return { classification: 'global_stop', rawEvents: [] };
    };
  }
  const stopped = await executeComparisonStudy({
    manifest,
    runRoot: stopPaths.runRoot,
    xdgStateHome: stopPaths.xdgStateHome,
    repositoryRoot: stopPaths.repositoryRoot,
  }, stopDeps);
  assert.equal(stopCalls.filter((entry) => /^(codex|ollama):/u.test(entry)).length, 1);
  assert.equal(stopped.journal.terminalCount, 60);
  assert.equal(stopped.journal.globalStop, true);
  assert.equal(stopped.slots.filter((slot) => slot.classification === 'global_stop').length, 60);
});

test('run root enforces XDG ancestry, symlink safety, permissions, and exclusive outputs', async () => {
  const paths = await makeRunPaths('root-policy');
  await assert.rejects(
    () => prepareComparisonRunRoot({ runRoot: 'relative', xdgStateHome: paths.xdgStateHome, repositoryRoot: paths.repositoryRoot }),
    /absolute/u,
  );
  await assert.rejects(
    () => prepareComparisonRunRoot({ runRoot: paths.runRoot, xdgStateHome: '', repositoryRoot: paths.repositoryRoot }),
    /XDG_STATE_HOME/u,
  );
  await assert.rejects(
    () => prepareComparisonRunRoot({
      runRoot: join(paths.repositoryRoot, 'state', 'canopy', 'genui-provider-benchmark', 'run'),
      xdgStateHome: join(paths.repositoryRoot, 'state'),
      repositoryRoot: paths.repositoryRoot,
    }),
    /repository/u,
  );

  const outside = join(paths.root, 'outside');
  await mkdir(outside);
  const stateParent = join(paths.xdgStateHome, 'canopy');
  await mkdir(stateParent, { recursive: true });
  await symlink(outside, join(stateParent, 'genui-provider-benchmark'));
  await assert.rejects(
    () => prepareComparisonRunRoot({ runRoot: paths.runRoot, xdgStateHome: paths.xdgStateHome, repositoryRoot: paths.repositoryRoot }),
    /symbolic link|symlink/u,
  );

  const clean = await makeRunPaths('root-modes');
  const prepared = await prepareComparisonRunRoot(clean);
  assert.equal((await stat(prepared.runRoot)).mode & 0o777, 0o700);
  assert.equal((await stat(prepared.journalPath)).mode & 0o777, 0o600);
  await assert.rejects(() => prepareComparisonRunRoot(clean), /exist|exclusive/u);
  await chmod(prepared.runRoot, 0o755);
  await assert.rejects(
    () => prepareComparisonRunRoot({ ...clean, runRoot: prepared.runRoot }),
    /exist|exclusive|mode/u,
  );
});

test('credentialed smoke uses one distinct synthetic fixture and rejects a second request path', async () => {
  const manifest = testComparisonManifest('codex_only');
  assert.equal(manifest.fixtures.some((fixture) => fixture.id === SMOKE_FIXTURE.caseId), false);
  const paths = await makeRunPaths('smoke');
  let requests = 0;
  let cleanupCalls = 0;
  const result = await executeCodexSmoke({
    manifest,
    runRoot: paths.runRoot,
    xdgStateHome: paths.xdgStateHome,
    repositoryRoot: paths.repositoryRoot,
  }, {
    verifyRepository: () => manifest.sourceCommit,
    preflight: async () => ({
      isolation: true,
      identity: true,
      credentials: true,
      budget: true,
    }),
    createSandbox: async () => ({
      contract: { runRoot: '/private/smoke' },
      cleanup: async () => { cleanupCalls += 1; },
    }),
    requestGate: async () => undefined,
    codexAttempt: async ({ fixture, sandbox }) => {
      requests += 1;
      assert.equal(fixture.caseId, SMOKE_FIXTURE.caseId);
      assert.equal(sandbox.contract.runRoot, '/private/smoke');
      return successfulProviderAttempt({ slotId: 'smoke', providerId: 'codex' });
    },
    evaluateCandidate: async ({ candidateJson, input }) => {
      assert.equal(candidateJson, CANDIDATE_JSON);
      assert.equal(input.fixture.caseId, SMOKE_FIXTURE.caseId);
      return passingCandidateGate();
    },
    canaries: RUN_CANARIES,
    now: () => '2026-07-17T00:00:00.000Z',
  });
  assert.equal(requests, 1);
  assert.equal(cleanupCalls, 1);
  assert.equal(result.classification, 'candidate_pass');
  assert.equal(result.usage.totalTokens, 5);
  assert.equal(resolve(result.rawArtifactPath).startsWith(resolve(paths.runRoot, 'smoke')), true);
  assert.equal(resolve(result.summaryPath).startsWith(resolve(paths.runRoot, 'smoke')), true);
  assert.equal((await stat(result.rawArtifactPath)).mode & 0o777, 0o600);
  assert.equal((await stat(result.summaryPath)).mode & 0o777, 0o600);
});

test('credentialed smoke fails closed on provider and canary errors without retry', async () => {
  const manifest = testComparisonManifest('codex_only');
  for (const scenario of ['provider', 'canary']) {
    const paths = await makeRunPaths(`smoke-${scenario}`);
    let requests = 0;
    await assert.rejects(
      () => executeCodexSmoke({
        manifest,
        runRoot: paths.runRoot,
        xdgStateHome: paths.xdgStateHome,
        repositoryRoot: paths.repositoryRoot,
      }, {
        verifyRepository: () => manifest.sourceCommit,
        preflight: async () => ({
          isolation: true,
          identity: true,
          credentials: true,
          budget: true,
        }),
        createSandbox: async () => ({ contract: {}, cleanup: async () => undefined }),
        requestGate: async () => undefined,
        codexAttempt: async ({ slot }) => {
          requests += 1;
          if (scenario === 'provider') throw new Error('provider failed');
          const attempt = successfulProviderAttempt(slot);
          attempt.rawEvents[0].itemText = RUN_CANARIES.secretValues[0];
          return attempt;
        },
        evaluateCandidate: async () => passingCandidateGate(),
        canaries: RUN_CANARIES,
        now: () => '2026-07-17T00:00:00.000Z',
      }),
      scenario === 'provider' ? /provider failed/u : /canary|secret/u,
    );
    assert.equal(requests, 1);
  }
});
