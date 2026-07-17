#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { canonicalJson } from '../src/genui-feasibility-provider.js';

const PROVIDERS = Object.freeze(['ollama', 'codex']);
const BRANCHES = new Set(['paired', 'codex_only']);
const TERMINAL_CLASSIFICATIONS = new Set([
  'candidate_pass',
  'candidate_invalid_utf8',
  'candidate_oversize',
  'capability_decode_failure',
  'credential_leakage',
  'global_stop',
  'identity_drift',
  'materialization_failure',
  'ollama_not_operational',
  'process_crash',
  'provider_decode_failure',
  'provider_http_error',
  'provider_protocol_error',
  'provider_timeout',
  'replay_mismatch',
  'rubric_failure',
  'semantic_validation_failure',
  'session_commit_failure',
  'signal_interruption',
  'stage1_ineligible',
  'state_mutation',
  'tool_use',
]);
const TRANSCRIPT_STRING_FIELDS = Object.freeze(['method', 'itemType', 'status', 'model']);
const TRANSCRIPT_DIGEST_FIELDS = Object.freeze(['candidateDigest', 'rawArtifactDigest']);
const USAGE_FIELDS = Object.freeze([
  'cachedInputTokens',
  'inputTokens',
  'outputTokens',
  'reasoningOutputTokens',
  'totalTokens',
]);
const PRIVATE_TRANSCRIPT_FIELDS = new Set([
  'account',
  'accountEmail',
  'candidate',
  'candidateBytes',
  'cwd',
  'path',
  'prompt',
  'promptBytes',
]);
const HEX_SHA256 = /^[0-9a-f]{64}$/u;
const HEX_COMMIT = /^[0-9a-f]{40}$/u;

export function buildComparisonSchedule({
  fixtures,
  repeats,
  randomizationSeed,
  ollamaSeeds,
  branch,
}) {
  requireBranch(branch);
  if (!Array.isArray(fixtures) || fixtures.length !== 3) {
    throw comparisonError('schedule_invalid', 'The comparison requires exactly three fixtures.');
  }
  if (repeats !== 10) {
    throw comparisonError('schedule_invalid', 'The comparison requires exactly ten repeats per fixture.');
  }
  requireNonNegativeInteger(randomizationSeed, 'randomizationSeed');
  if (!Array.isArray(ollamaSeeds) || ollamaSeeds.length !== repeats) {
    throw comparisonError('schedule_invalid', 'Ollama requires one seed per repeated slot.');
  }
  const fixtureIds = new Set();
  for (const fixture of fixtures) {
    if (!fixture || typeof fixture.id !== 'string' || fixture.id.length === 0 || fixtureIds.has(fixture.id)) {
      throw comparisonError('schedule_invalid', 'Fixture IDs must be non-empty and unique.');
    }
    requireDigest(fixture.digest, `fixture ${fixture.id} digest`);
    fixtureIds.add(fixture.id);
  }
  for (const seed of ollamaSeeds) requireNonNegativeInteger(seed, 'Ollama seed');

  const providerOrders = balancedProviderOrders(fixtures.length * repeats, randomizationSeed);
  const slots = [];
  let pairIndex = 0;
  for (const [stage, start, end] of [[1, 0, 3], [2, 3, repeats]]) {
    for (const fixture of fixtures) {
      for (let repeatIndex = start; repeatIndex < end; repeatIndex += 1) {
        const pairId = `${fixture.id}/${String(repeatIndex + 1).padStart(2, '0')}`;
        for (const providerId of providerOrders[pairIndex]) {
          const active = branch === 'paired' || providerId === 'codex';
          const slot = {
            slotId: `${pairId}/${providerId}`,
            pairId,
            fixtureId: fixture.id,
            fixtureDigest: fixture.digest,
            repeatIndex,
            providerId,
            stage,
            active,
          };
          if (providerId === 'ollama') slot.seed = ollamaSeeds[repeatIndex];
          if (!active) slot.classification = 'ollama_not_operational';
          slots.push(Object.freeze(slot));
        }
        pairIndex += 1;
      }
    }
  }
  return Object.freeze(slots);
}

export function evaluateStage1Eligibility({ manifest, slots, audit }) {
  const schedule = requireManifestSchedule(manifest);
  const expected = schedule.filter((slot) => slot.stage === 1);
  const failures = [];
  if (!Array.isArray(slots) || slots.length !== expected.length) {
    failures.push('stage1_terminal_coverage');
  }
  const records = Array.isArray(slots) ? slots : [];
  const bySlotId = new Map();
  for (const record of records) {
    if (!record || typeof record.slotId !== 'string' || bySlotId.has(record.slotId)) {
      failures.push('stage1_terminal_coverage');
      continue;
    }
    bySlotId.set(record.slotId, record);
  }
  for (const expectedSlot of expected) {
    const record = bySlotId.get(expectedSlot.slotId);
    if (!record || record.terminal !== true || record.providerId !== expectedSlot.providerId ||
        record.fixtureId !== expectedSlot.fixtureId || record.active !== expectedSlot.active) {
      failures.push('stage1_terminal_coverage');
    }
  }
  if (bySlotId.size !== expected.length || [...bySlotId.keys()].some((id) => !expected.some((slot) => slot.slotId === id))) {
    failures.push('stage1_terminal_coverage');
  }
  if (!audit || ['manifest', 'schedule', 'evidence', 'retention'].some((key) => audit[key] !== true)) {
    failures.push('audit_failure');
  }

  const providers = {};
  for (const providerId of PROVIDERS) {
    const expectedProvider = expected.filter((slot) => slot.providerId === providerId);
    const activeExpected = expectedProvider.filter((slot) => slot.active);
    if (activeExpected.length === 0) {
      providers[providerId] = Object.freeze({ status: 'unavailable', eligible: false });
      continue;
    }
    const activeRecords = activeExpected.map((slot) => bySlotId.get(slot.slotId)).filter(Boolean);
    const providerFailures = [];
    if (activeRecords.length !== activeExpected.length) {
      providerFailures.push('preparation_coverage');
    }
    for (const fixtureId of new Set(activeExpected.map((slot) => slot.fixtureId))) {
      if (!activeRecords.some((record) => record.fixtureId === fixtureId && record.preparationPassed === true)) {
        providerFailures.push(`preparation_coverage:${fixtureId}`);
      }
    }
    if (activeRecords.some(hasSafetyFailure)) providerFailures.push('safety_violation');
    if (activeRecords.some((record) => record.identityDrift === true)) providerFailures.push('identity_drift');
    if (activeRecords.some((record) => record.replayMismatch === true)) providerFailures.push('replay_mismatch');
    if (providerFailures.length > 0) failures.push(...providerFailures.map((failure) => `${providerId}:${failure}`));
    providers[providerId] = Object.freeze({
      status: providerFailures.length === 0 ? 'eligible' : 'ineligible',
      eligible: providerFailures.length === 0,
      failures: Object.freeze(providerFailures),
    });
  }

  return Object.freeze({
    eligible: failures.length === 0,
    providers: Object.freeze(providers),
    failures: Object.freeze([...new Set(failures)]),
  });
}

export function qualifyProvider({ providerId, slots }) {
  requireProvider(providerId);
  if (!Array.isArray(slots)) throw comparisonError('qualification_invalid', 'Provider slots must be an array.');
  const providerSlots = slots.filter((slot) => slot?.providerId === providerId);
  if (providerSlots.length > 0 && providerSlots.every((slot) => slot.active === false)) {
    return Object.freeze({ providerId, status: 'unavailable', qualifies: false });
  }
  const active = providerSlots.filter((slot) => slot.active !== false);
  if (active.length !== 30 || active.some((slot) => slot.terminal !== true)) {
    return Object.freeze({ providerId, status: 'ineligible', qualifies: false, failures: Object.freeze(['terminal_coverage']) });
  }
  const fixtures = new Map();
  for (const slot of active) {
    const counts = fixtures.get(slot.fixtureId) ?? { total: 0, passed: 0 };
    counts.total += 1;
    if (slot.passedRubric === true) counts.passed += 1;
    fixtures.set(slot.fixtureId, counts);
  }
  const totalPassed = active.filter((slot) => slot.passedRubric === true).length;
  const failures = [];
  if (fixtures.size !== 3 || [...fixtures.values()].some((counts) => counts.total !== 10)) failures.push('fixture_coverage');
  if (totalPassed < 24) failures.push('overall_threshold');
  if ([...fixtures.values()].some((counts) => counts.passed < 7)) failures.push('fixture_threshold');
  if (active.some(hasSafetyFailure)) failures.push('safety_violation');
  if (active.some((slot) => slot.replayMismatch === true)) failures.push('replay_mismatch');
  if (active.some((slot) => slot.identityDrift === true)) failures.push('identity_drift');
  return Object.freeze({
    providerId,
    status: failures.length === 0 ? 'qualified' : 'ineligible',
    qualifies: failures.length === 0,
    passed: totalPassed,
    total: active.length,
    byFixture: Object.freeze(Object.fromEntries(fixtures)),
    failures: Object.freeze(failures),
  });
}

export function validateComparisonJournal({ manifest, journal }) {
  const schedule = requireManifestSchedule(manifest);
  if (!Array.isArray(journal)) throw comparisonError('journal_invalid', 'Journal must be an array.');
  let eventIndex = 0;
  let globalStop = false;
  let stage1Ineligible = false;
  let stage2Executed = false;
  let activeAttempts = 0;
  const seenStarts = new Set();
  const seenTerminals = new Set();

  for (const slot of schedule) {
    const first = journal[eventIndex];
    if (!first) throw comparisonError('journal_incomplete', `Missing terminal state for slot ${slot.slotId}.`);
    if (first.slotId !== slot.slotId) {
      throw comparisonError('journal_order', `Journal slot order differs at ${slot.slotId}.`);
    }

    if (!slot.active || globalStop || stage1Ineligible) {
      if (first.type !== 'terminal') throw comparisonError('journal_start', `Non-running slot ${slot.slotId} cannot start.`);
      const expectedClassification = !slot.active
        ? slot.classification
        : globalStop
          ? 'global_stop'
          : 'stage1_ineligible';
      if (first.classification !== expectedClassification) {
        throw comparisonError('journal_terminal', `Slot ${slot.slotId} has the wrong terminal classification.`);
      }
      requireTerminalIdentity(slot, first);
      recordTerminal(first, seenTerminals);
      eventIndex += 1;
      continue;
    }

    if (first.type === 'terminal' && first.classification === 'global_stop') {
      globalStop = true;
      requireTerminalIdentity(slot, first);
      recordTerminal(first, seenTerminals);
      eventIndex += 1;
      continue;
    }
    if (slot.stage === 2 && first.type === 'terminal' && first.classification === 'stage1_ineligible') {
      stage1Ineligible = true;
      requireTerminalIdentity(slot, first);
      recordTerminal(first, seenTerminals);
      eventIndex += 1;
      continue;
    }
    if (first.type !== 'start') throw comparisonError('journal_start', `Active slot ${slot.slotId} must start once.`);
    if (seenStarts.has(slot.slotId)) throw comparisonError('journal_duplicate', `Duplicate start for ${slot.slotId}.`);
    seenStarts.add(slot.slotId);
    activeAttempts += 1;
    if (slot.stage === 2) stage2Executed = true;
    eventIndex += 1;

    const terminal = journal[eventIndex];
    if (!terminal || terminal.slotId !== slot.slotId || terminal.type !== 'terminal') {
      throw comparisonError('journal_terminal', `Active slot ${slot.slotId} must terminate before the next slot.`);
    }
    if (!TERMINAL_CLASSIFICATIONS.has(terminal.classification) ||
        ['stage1_ineligible', 'ollama_not_operational'].includes(terminal.classification)) {
      throw comparisonError('journal_terminal', `Slot ${slot.slotId} has an invalid active terminal classification.`);
    }
    if (terminal.classification === 'global_stop') globalStop = true;
    requireTerminalIdentity(slot, terminal);
    recordTerminal(terminal, seenTerminals);
    eventIndex += 1;
  }

  if (eventIndex !== journal.length) throw comparisonError('journal_extra', 'Journal contains duplicate or extra events.');
  return Object.freeze({
    complete: seenTerminals.size === schedule.length,
    terminalCount: seenTerminals.size,
    activeAttempts,
    globalStop,
    stage2Executed,
  });
}

export function normalizeProviderTranscript({ providerId, rawEvents, canaries }) {
  requireProvider(providerId);
  if (!Array.isArray(rawEvents)) throw comparisonError('transcript_invalid', 'Raw transcript must be an array.');
  const hostPaths = canaries?.hostPaths ?? [];
  const secretValues = canaries?.secretValues ?? [];
  const rawText = JSON.stringify(rawEvents);
  for (const canary of [...hostPaths, ...secretValues]) {
    if (typeof canary === 'string' && canary.length > 0 && rawText.includes(canary)) {
      throw comparisonError('transcript_canary', 'Raw transcript contains a forbidden canary.');
    }
  }

  const idMaps = {
    requestId: new Map(),
    threadId: new Map(),
    turnId: new Map(),
  };
  const idPrefixes = { requestId: 'request', threadId: 'thread', turnId: 'turn' };
  const redactions = [];
  const events = rawEvents.map((rawEvent, eventIndex) => {
    if (!rawEvent || typeof rawEvent !== 'object' || Array.isArray(rawEvent)) {
      throw comparisonError('transcript_invalid', `Transcript event ${eventIndex} is malformed.`);
    }
    const event = {};
    for (const field of Object.keys(idMaps)) {
      if (field in rawEvent) {
        if (typeof rawEvent[field] !== 'string' || rawEvent[field].length === 0) {
          throw comparisonError('transcript_invalid', `${field} is malformed.`);
        }
        event[field] = opaqueId(idMaps[field], idPrefixes[field], rawEvent[field]);
        redactions.push(Object.freeze({ eventIndex, field, action: 'opaque_id' }));
      }
    }
    for (const field of TRANSCRIPT_STRING_FIELDS) {
      if (field in rawEvent) {
        if (typeof rawEvent[field] !== 'string') throw comparisonError('transcript_invalid', `${field} must be a string.`);
        event[field] = rawEvent[field];
      }
    }
    if ('usage' in rawEvent) event.usage = normalizeUsage(rawEvent.usage);
    if ('timing' in rawEvent) event.timing = normalizeTiming(rawEvent.timing);
    for (const field of TRANSCRIPT_DIGEST_FIELDS) {
      if (field in rawEvent) {
        requireDigest(rawEvent[field], field);
        event[field] = rawEvent[field];
      }
    }
    if ('candidateByteLength' in rawEvent) {
      requireNonNegativeInteger(rawEvent.candidateByteLength, 'candidateByteLength');
      event.candidateByteLength = rawEvent.candidateByteLength;
    }
    for (const field of Object.keys(rawEvent)) {
      if (PRIVATE_TRANSCRIPT_FIELDS.has(field)) {
        redactions.push(Object.freeze({ eventIndex, field, action: 'removed' }));
      }
    }
    return Object.freeze(event);
  });

  return Object.freeze({
    providerId,
    events: Object.freeze(events),
    redactions: Object.freeze(redactions),
  });
}

export function finalizeComparisonEvidence({
  manifest,
  manifestSha256,
  frozenCommit,
  preflight,
  journal,
  rawArtifacts,
}) {
  const schedule = requireManifestSchedule(manifest);
  requireDigest(manifestSha256, 'manifestSha256');
  requireManifestEvidenceMetadata(manifest);
  const actualManifestSha256 = createHash('sha256')
    .update(`${JSON.stringify(manifest, null, 2)}\n`)
    .digest('hex');
  if (manifestSha256 !== actualManifestSha256) {
    throw comparisonError('evidence_manifest', 'Manifest digest does not match the reviewed manifest bytes.');
  }
  if (typeof frozenCommit !== 'string' || !HEX_COMMIT.test(frozenCommit)) {
    throw comparisonError('evidence_invalid', 'Frozen commit must be a full hexadecimal commit SHA.');
  }
  if (frozenCommit !== manifest.sourceCommit) {
    throw comparisonError('evidence_manifest', 'Frozen commit does not match the manifest source commit.');
  }
  if (!preflight || ['isolation', 'identity', 'credentials', 'budget'].some((key) => preflight[key] !== true)) {
    throw comparisonError('evidence_preflight', 'All evidence preflight gates must pass.');
  }
  const journalSummary = validateComparisonJournal({ manifest, journal });
  if (!Array.isArray(rawArtifacts) || rawArtifacts.length === 0) {
    throw comparisonError('evidence_invalid', 'Raw artifact inventory is required.');
  }
  const expectedArtifactIds = new Set(
    journal.filter((event) => event.type === 'start').map((event) => event.slotId),
  );
  const seenArtifactIds = new Set();
  let auditability = 'full';
  const artifactInventory = rawArtifacts.map((artifact) => {
    if (!artifact || typeof artifact.id !== 'string' || artifact.id.length === 0 || typeof artifact.available !== 'boolean') {
      throw comparisonError('evidence_invalid', 'Raw artifact inventory entry is malformed.');
    }
    if (artifact.available) requireDigest(artifact.digest, `raw artifact ${artifact.id} digest`);
    if (seenArtifactIds.has(artifact.id)) {
      throw comparisonError('evidence_invalid', `Raw artifact ID ${artifact.id} is duplicated.`);
    }
    if (!expectedArtifactIds.has(artifact.id)) {
      throw comparisonError('evidence_invalid', `Raw artifact ID ${artifact.id} has no matching started slot.`);
    }
    seenArtifactIds.add(artifact.id);
    if (!artifact.available) auditability = 'unavailable';
    return Object.freeze({
      id: artifact.id,
      available: artifact.available,
      ...(artifact.available ? { digest: artifact.digest } : {}),
    });
  });
  if (seenArtifactIds.size !== expectedArtifactIds.size) {
    throw comparisonError('evidence_invalid', 'Raw artifact inventory does not cover every started slot.');
  }
  return Object.freeze({
    studyId: manifest.studyId,
    manifestVersion: manifest.manifestVersion,
    randomizationSeed: manifest.randomizationSeed,
    sourceCommit: manifest.sourceCommit,
    providerIdentities: frozenJsonSnapshot(manifest.providerIdentities),
    diagnosticSummarySha256: manifest.diagnosticSummarySha256,
    manifestSha256,
    frozenCommit,
    branch: manifest.branch,
    schedule: Object.freeze({
      complete: true,
      slots: schedule.length,
      sha256: createHash('sha256').update(canonicalJson(schedule)).digest('hex'),
    }),
    journal: journalSummary,
    rawArtifacts: Object.freeze(artifactInventory),
    auditability,
    conclusionLimit: auditability === 'full'
      ? null
      : 'raw artifact loss makes the affected evidence unavailable for provider conclusions.',
  });
}

function frozenJsonSnapshot(value) {
  return deepFreezeJson(JSON.parse(canonicalJson(value)));
}

function deepFreezeJson(value) {
  if (Array.isArray(value)) {
    for (const entry of value) deepFreezeJson(entry);
    return Object.freeze(value);
  }
  if (value !== null && typeof value === 'object') {
    for (const entry of Object.values(value)) deepFreezeJson(entry);
    return Object.freeze(value);
  }
  return value;
}

function balancedProviderOrders(pairCount, seed) {
  const firstProviders = Array.from({ length: pairCount }, (_, index) => index < pairCount / 2 ? 'ollama' : 'codex');
  const random = mulberry32(seed);
  for (let index = firstProviders.length - 1; index > 0; index -= 1) {
    const replacement = Math.floor(random() * (index + 1));
    [firstProviders[index], firstProviders[replacement]] = [firstProviders[replacement], firstProviders[index]];
  }
  return firstProviders.map((first) => Object.freeze(first === 'ollama' ? ['ollama', 'codex'] : ['codex', 'ollama']));
}

function mulberry32(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6D2B79F5) >>> 0;
    let value = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4_294_967_296;
  };
}

function requireManifestSchedule(manifest) {
  requireBranch(manifest?.branch);
  if (!Array.isArray(manifest.schedule) || manifest.schedule.length !== 60) {
    throw comparisonError('schedule_invalid', 'Manifest schedule must contain exactly 60 slots.');
  }
  const seen = new Set();
  for (const slot of manifest.schedule) {
    if (!slot || typeof slot.slotId !== 'string' || seen.has(slot.slotId)) {
      throw comparisonError('schedule_invalid', 'Manifest schedule slot IDs must be unique.');
    }
    requireProvider(slot.providerId);
    if (!Number.isInteger(slot.stage) || ![1, 2].includes(slot.stage) || typeof slot.active !== 'boolean') {
      throw comparisonError('schedule_invalid', `Manifest slot ${slot.slotId} is malformed.`);
    }
    seen.add(slot.slotId);
  }
  return manifest.schedule;
}

function requireManifestEvidenceMetadata(manifest) {
  if (typeof manifest.studyId !== 'string' || manifest.studyId.length === 0) {
    throw comparisonError('evidence_manifest', 'Manifest study ID is required.');
  }
  if (!Number.isInteger(manifest.manifestVersion) || manifest.manifestVersion <= 0) {
    throw comparisonError('evidence_manifest', 'Manifest version must be a positive integer.');
  }
  if (!Number.isInteger(manifest.randomizationSeed) || manifest.randomizationSeed < 0) {
    throw comparisonError('evidence_manifest', 'Manifest randomization seed must be a non-negative integer.');
  }
  requireDigest(manifest.diagnosticSummarySha256, 'manifest diagnosticSummarySha256');
  if (typeof manifest.sourceCommit !== 'string' || !HEX_COMMIT.test(manifest.sourceCommit)) {
    throw comparisonError('evidence_manifest', 'Manifest source commit must be a full hexadecimal commit SHA.');
  }
}

function requireTerminalIdentity(slot, terminal) {
  for (const field of ['pairId', 'fixtureId', 'providerId', 'stage']) {
    if (terminal[field] !== slot[field]) {
      throw comparisonError('journal_identity', `Terminal identity mismatch for ${slot.slotId}: ${field}.`);
    }
  }
}

function recordTerminal(event, seenTerminals) {
  if (seenTerminals.has(event.slotId)) throw comparisonError('journal_duplicate', `Duplicate terminal for ${event.slotId}.`);
  if (!TERMINAL_CLASSIFICATIONS.has(event.classification)) {
    throw comparisonError('journal_terminal', `Unknown terminal classification for ${event.slotId}.`);
  }
  seenTerminals.add(event.slotId);
}

function hasSafetyFailure(record) {
  return ['safetyViolations', 'toolUseViolations', 'stateMutationViolations', 'credentialLeakageViolations']
    .some((field) => record[field] !== undefined && (!Number.isInteger(record[field]) || record[field] !== 0));
}

function normalizeUsage(usage) {
  if (!usage || typeof usage !== 'object' || Array.isArray(usage)) {
    throw comparisonError('transcript_usage', 'Usage must be an object.');
  }
  const normalized = {};
  for (const field of USAGE_FIELDS) {
    if (field in usage) {
      requireNonNegativeInteger(usage[field], `usage.${field}`);
      normalized[field] = usage[field];
    }
  }
  if (Object.keys(normalized).length === 0) throw comparisonError('transcript_usage', 'Usage has no reviewable token fields.');
  return Object.freeze(normalized);
}

function normalizeTiming(timing) {
  if (!timing || typeof timing !== 'object' || Array.isArray(timing)) {
    throw comparisonError('transcript_timing', 'Timing must be an object.');
  }
  requireNonNegativeInteger(timing.elapsedMs, 'timing.elapsedMs');
  return Object.freeze({ elapsedMs: timing.elapsedMs });
}

function opaqueId(map, prefix, privateId) {
  if (!map.has(privateId)) map.set(privateId, `${prefix}-${String(map.size + 1).padStart(4, '0')}`);
  return map.get(privateId);
}

function requireBranch(branch) {
  if (!BRANCHES.has(branch)) throw comparisonError('branch_invalid', 'Comparison branch must be paired or codex_only.');
}

function requireProvider(providerId) {
  if (!PROVIDERS.includes(providerId)) throw comparisonError('provider_invalid', `Unknown provider ${String(providerId)}.`);
}

function requireNonNegativeInteger(value, field) {
  if (!Number.isInteger(value) || value < 0) throw comparisonError('number_invalid', `${field} must be a non-negative integer.`);
}

function requireDigest(value, field) {
  if (typeof value !== 'string' || !HEX_SHA256.test(value)) {
    throw comparisonError('digest_invalid', `${field} must be a lowercase SHA-256 digest.`);
  }
}

function comparisonError(classification, message) {
  const error = new Error(message);
  error.name = 'ComparisonPolicyError';
  error.classification = classification;
  return error;
}

async function runCli(argv) {
  const operation = argv[0];
  if (!['finalize', 'normalize'].includes(operation)) {
    throw comparisonError('cli_usage', 'Usage: <finalize|normalize> --input INPUT --output OUTPUT');
  }
  const inputIndex = argv.indexOf('--input');
  const outputIndex = argv.indexOf('--output');
  if (inputIndex < 0 || outputIndex < 0 || !argv[inputIndex + 1] || !argv[outputIndex + 1]) {
    throw comparisonError('cli_usage', 'Usage: <finalize|normalize> --input INPUT --output OUTPUT');
  }
  const input = JSON.parse(await readFile(argv[inputIndex + 1], 'utf8'));
  const output = operation === 'finalize'
    ? finalizeComparisonEvidence(input)
    : normalizeProviderTranscript(input);
  await writeFile(argv[outputIndex + 1], `${JSON.stringify(output, null, 2)}\n`, { flag: 'wx', mode: 0o600 });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  runCli(process.argv.slice(2)).catch((error) => {
    process.stderr.write(`${error.name ?? 'Error'}: ${error.message}\n`);
    process.exitCode = 1;
  });
}
