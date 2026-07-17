#!/usr/bin/env node

import { lstat, mkdir, readdir, writeFile } from 'node:fs/promises';
import { isAbsolute, join } from 'node:path';

import { canonicalJson, sha256Hex } from '../src/genui-feasibility-provider.js';

const STEP_DEFINITIONS = Object.freeze([
  Object.freeze({ id: 'environment_and_model', changedDimension: null, operation: 'inspect' }),
  Object.freeze({ id: 'load_without_generation', changedDimension: 'generation', operation: 'load' }),
  Object.freeze({ id: 'minimal_text', changedDimension: 'prompt', operation: 'generate', prompt: 'Reply with the word ok.', format: null }),
  Object.freeze({ id: 'json_object', changedDimension: 'format', operation: 'generate', prompt: 'Return one JSON object.', format: 'json' }),
  Object.freeze({
    id: 'unrelated_json_schema',
    changedDimension: 'schema',
    operation: 'generate',
    prompt: 'Return an object with one integer field named value.',
    format: Object.freeze({ type: 'object', properties: Object.freeze({ value: Object.freeze({ type: 'integer' }) }), required: Object.freeze(['value']) }),
  }),
]);
const PUBLIC_HEADER_ALLOWLIST = new Set(['content-type', 'content-length', 'date', 'etag']);
const SAFETY_FIELDS = Object.freeze(['credentialsSafe', 'budgetSafe', 'isolationSafe', 'evidenceIntegrity']);
const BEFORE_CANOPY_PROMPT = new Set(['load_without_generation', 'minimal_text', 'json_object', 'unrelated_json_schema']);

export function buildOllamaDiagnosticPlan({ frozenIdentity, fixtures, candidateSchema, syntheticPrompt }) {
  validateIdentity(frozenIdentity);
  validateFixtures(fixtures);
  requireObject(candidateSchema, 'candidate schema');
  requireNonEmptyString(syntheticPrompt, 'synthetic prompt');

  return deepFreeze([
    ...STEP_DEFINITIONS.map((definition) => ({ ...definition })),
    {
      id: 'candidate_schema_synthetic',
      changedDimension: 'schema',
      operation: 'generate',
      prompt: syntheticPrompt,
      format: copyJson(candidateSchema),
    },
    {
      id: 'trusted_fixtures',
      changedDimension: 'prompt',
      operation: 'generate',
      format: copyJson(candidateSchema),
      fixtureIds: fixtures.map((fixture) => fixture.id),
    },
  ]);
}

export async function executeOllamaDiagnostic(input, deps) {
  requireDependencies(deps);
  const {
    runRoot,
    frozenIdentity,
    fixtures,
    candidateSchema,
    syntheticPrompt,
    knownWorkingModel = null,
    protectedInputs = {},
  } = input ?? {};
  const plan = buildOllamaDiagnosticPlan({ frozenIdentity, fixtures, candidateSchema, syntheticPrompt });
  const protectedDigest = sha256Hex(canonicalJson(protectedInputs));
  const paths = await prepareOutputPaths(runRoot);
  const state = createState();

  for (let stepIndex = 0; stepIndex < plan.length; stepIndex += 1) {
    const probe = plan[stepIndex];
    state.probeOrder.push(probe.id);
    if (probe.id === 'environment_and_model') {
      const result = await deps.inspectEnvironment({ probe, frozenIdentity, runRoot });
      const accepted = await acceptObservation({ result, probe, stepIndex, frozenIdentity, paths, state });
      if (!accepted) break;
      continue;
    }

    if (probe.id === 'trusted_fixtures') {
      let failed = false;
      for (let fixtureIndex = 0; fixtureIndex < fixtures.length; fixtureIndex += 1) {
        const fixture = fixtures[fixtureIndex];
        const result = await deps.executeProbe({
          probe,
          fixture,
          model: frozenIdentity.lookupTag,
          frozenIdentity,
          runRoot,
        });
        const accepted = await acceptObservation({
          result,
          probe,
          stepIndex,
          fixture,
          fixtureIndex,
          frozenIdentity,
          paths,
          state,
        });
        if (!accepted) {
          failed = true;
          break;
        }
        if (typeof result?.candidateJson !== 'string' || result.candidateJson.length === 0) {
          recordFailure(state, probe.id, 'candidate_absent');
          failed = true;
          break;
        }
        const preparation = await deps.prepareCandidate({
          fixture,
          candidateJson: result.candidateJson,
          runRoot,
        });
        recordPreparation(state, preparation?.classification ?? 'preparation_failure');
        if (preparation?.passed !== true) {
          recordFailure(state, probe.id, preparation?.classification ?? 'preparation_failure');
          failed = true;
          break;
        }
        state.fixtureIds.push(fixture.id);
      }
      if (failed) break;
      continue;
    }

    const result = await deps.executeProbe({
      probe,
      fixture: null,
      model: frozenIdentity.lookupTag,
      frozenIdentity,
      runRoot,
    });
    const accepted = await acceptObservation({ result, probe, stepIndex, frozenIdentity, paths, state });
    if (!accepted) {
      if (knownWorkingModel && BEFORE_CANOPY_PROMPT.has(probe.id)) {
        state.runtimeControl = await runRuntimeControl({
          probe,
          stepIndex,
          model: knownWorkingModel,
          frozenIdentity,
          runRoot,
          paths,
          deps,
        });
      }
      break;
    }
    if (probe.id === 'candidate_schema_synthetic' && (typeof result?.candidateJson !== 'string' || result.candidateJson.length === 0)) {
      recordFailure(state, probe.id, 'candidate_absent');
      break;
    }
  }

  if (sha256Hex(canonicalJson(protectedInputs)) !== protectedDigest) {
    throw new Error('A protected diagnostic input was mutated.');
  }

  const summary = finalizeSummary(state, plan);
  await writeExclusiveJson(paths.summaryPath, summary, 0o600);
  return deepFreeze(summary);
}

async function acceptObservation({
  result,
  probe,
  stepIndex,
  fixture = null,
  fixtureIndex = null,
  frozenIdentity,
  paths,
  state,
}) {
  const normalized = normalizeObservation(result, probe, frozenIdentity);
  accumulateSafety(state, normalized.safety);
  const rawPath = join(paths.rawRoot, rawFileName(stepIndex, probe.id, fixtureIndex, fixture?.id));
  await writeExclusiveJson(rawPath, {
    step: probe.id,
    fixtureId: fixture?.id ?? null,
    changedDimension: probe.changedDimension,
    ...copyJson(result),
  }, 0o600);
  state.observations.push(publicObservation(normalized, probe, fixture));

  if (probe.operation === 'generate') {
    const settingsDigest = normalized.requestSettingsSha256;
    if (settingsDigest === null) {
      state.requestDigestMismatch = true;
      if (normalized.success) recordFailure(state, probe.id, 'request_digest_mismatch');
    } else if (state.requestDigest === null) {
      state.requestDigest = settingsDigest;
    } else if (state.requestDigest !== settingsDigest) {
      state.requestDigestMismatch = true;
      if (normalized.success) recordFailure(state, probe.id, 'request_digest_mismatch');
    }
  }

  if (!normalized.success) {
    recordFailure(state, probe.id, normalized.classification);
    return false;
  }
  if (state.requestDigestMismatch) return false;
  return true;
}

async function runRuntimeControl({ probe, stepIndex, model, frozenIdentity, runRoot, paths, deps }) {
  const result = await deps.executeProbe({ probe, fixture: null, model, frozenIdentity, runRoot, runtimeControl: true });
  const normalized = normalizeObservation(result, probe, null);
  const rawPath = join(paths.rawRoot, `control-${rawFileName(stepIndex, probe.id)}`);
  await writeExclusiveJson(rawPath, { step: probe.id, model, runtimeControl: true, ...copyJson(result) }, 0o600);
  return Object.freeze({
    model,
    classification: normalized.success ? 'pass' : normalized.classification,
    requestSha256: normalized.requestSha256,
    responseSha256: normalized.responseSha256,
    serverLogSha256: normalized.serverLogSha256,
  });
}

function normalizeObservation(result, probe, expectedIdentity) {
  requireObject(result, `diagnostic observation ${probe.id}`);
  const safety = {};
  for (const field of SAFETY_FIELDS) safety[field] = result.safety?.[field] === true;
  let success = result.success === true;
  let classification = typeof result.classification === 'string'
    ? result.classification
    : success ? 'pass' : 'provider_protocol_error';
  if (expectedIdentity && (!identityMatches(expectedIdentity, result.identityBefore) || !identityMatches(expectedIdentity, result.identityAfter))) {
    success = false;
    classification = 'identity_drift';
  }
  if (!SAFETY_FIELDS.every((field) => safety[field])) success = false;
  return {
    success,
    classification,
    safety,
    requestSettings: result.requestSettings ?? null,
    requestSettingsSha256: digestNullable(result.requestSettings),
    requestSha256: digestNullable(result.request),
    responseSha256: digestNullable(result.response),
    serverLogSha256: digestNullable(result.serverLog),
    responseStatus: Number.isInteger(result.response?.status) ? result.response.status : null,
    responseHeaders: allowlistedHeaders(result.response?.headers),
    requestBytes: byteLength(result.request),
    responseBytes: byteLength(result.response?.body),
    serverLogBytes: byteLength(result.serverLog),
  };
}

function publicObservation(normalized, probe, fixture) {
  return Object.freeze({
    step: probe.id,
    fixtureId: fixture?.id ?? null,
    changedDimension: probe.changedDimension,
    classification: normalized.success ? 'pass' : normalized.classification,
    requestSettingsSha256: normalized.requestSettingsSha256,
    requestSha256: normalized.requestSha256,
    responseSha256: normalized.responseSha256,
    serverLogSha256: normalized.serverLogSha256,
    responseStatus: normalized.responseStatus,
    responseHeaders: normalized.responseHeaders,
    requestBytes: normalized.requestBytes,
    responseBytes: normalized.responseBytes,
    serverLogBytes: normalized.serverLogBytes,
  });
}

function recordPreparation(state, classification) {
  const index = state.observations.length - 1;
  state.observations[index] = Object.freeze({
    ...state.observations[index],
    preparationClassification: classification,
  });
}

function finalizeSummary(state, plan) {
  const passed = state.firstFailure === null && state.probeOrder.length === plan.length && state.fixtureIds.length === 3;
  const safe = SAFETY_FIELDS.every((field) => state[field]);
  return {
    terminal: true,
    complete: true,
    safe,
    identityPreserved: state.identityPreserved,
    evidenceIntegrity: state.evidenceIntegrity,
    credentialsSafe: state.credentialsSafe,
    budgetSafe: state.budgetSafe,
    isolationSafe: state.isolationSafe,
    requestSettingsFrozen: state.requestDigest !== null && !state.requestDigestMismatch,
    probeOrder: [...state.probeOrder],
    observations: [...state.observations],
    firstFailure: state.firstFailure,
    runtimeControl: state.runtimeControl,
    fixtureIds: passed ? [...state.fixtureIds] : [],
    requestDigest: state.requestDigest ?? sha256Hex(canonicalJson(null)),
    qualifiedForComparison: safe && passed,
    selectedBranch: safe ? passed ? 'paired' : 'codex_only' : null,
  };
}

function createState() {
  return {
    probeOrder: [],
    observations: [],
    fixtureIds: [],
    firstFailure: null,
    runtimeControl: null,
    requestDigest: null,
    requestDigestMismatch: false,
    identityPreserved: true,
    credentialsSafe: true,
    budgetSafe: true,
    isolationSafe: true,
    evidenceIntegrity: true,
  };
}

function recordFailure(state, step, classification) {
  if (state.firstFailure === null) state.firstFailure = Object.freeze({ step, classification });
  if (classification === 'identity_drift') state.identityPreserved = false;
  if (classification === 'request_digest_mismatch') state.requestDigestMismatch = true;
}

function accumulateSafety(state, safety) {
  for (const field of SAFETY_FIELDS) state[field] = state[field] && safety[field];
}

async function prepareOutputPaths(runRoot) {
  requireNonEmptyString(runRoot, 'runRoot');
  if (!isAbsolute(runRoot)) throw new Error('runRoot must be absolute.');
  const info = await lstat(runRoot);
  if (!info.isDirectory() || info.isSymbolicLink() || (info.mode & 0o777) !== 0o700) {
    throw new Error('runRoot must be a private non-symbolic directory with mode 0700.');
  }
  const summaryPath = join(runRoot, 'diagnostic-summary.json');
  await assertMissing(summaryPath);
  const rawParent = join(runRoot, 'raw');
  const rawRoot = join(rawParent, 'diagnostic');
  await mkdir(rawParent, { mode: 0o700 });
  await mkdir(rawRoot, { mode: 0o700 });
  const existing = await readdir(rawRoot);
  if (existing.length !== 0) throw new Error('Diagnostic raw output already exists.');
  return { summaryPath, rawRoot };
}

async function assertMissing(path) {
  try {
    await lstat(path);
  } catch (error) {
    if (error?.code === 'ENOENT') return;
    throw error;
  }
  throw new Error(`Diagnostic output already exists: ${path}`);
}

async function writeExclusiveJson(path, value, mode) {
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`, { encoding: 'utf8', flag: 'wx', mode });
}

function rawFileName(stepIndex, stepId, fixtureIndex = null, fixtureId = null) {
  const prefix = String(stepIndex).padStart(2, '0');
  const slug = stepId.replaceAll('_', '-');
  if (fixtureIndex === null) return `${prefix}-${slug}.json`;
  return `${prefix}-${slug}-${String(fixtureIndex).padStart(2, '0')}-${fixtureId}.json`;
}

function allowlistedHeaders(headers) {
  if (!headers || typeof headers !== 'object' || Array.isArray(headers)) return Object.freeze({});
  return Object.freeze(Object.fromEntries(
    Object.entries(headers)
      .map(([name, value]) => [name.toLowerCase(), String(value)])
      .filter(([name]) => PUBLIC_HEADER_ALLOWLIST.has(name))
      .sort(([left], [right]) => left.localeCompare(right)),
  ));
}

function digestNullable(value) {
  return value === null || value === undefined ? null : sha256Hex(typeof value === 'string' ? value : canonicalJson(value));
}

function byteLength(value) {
  if (value === null || value === undefined) return 0;
  return Buffer.byteLength(typeof value === 'string' ? value : canonicalJson(value), 'utf8');
}

function identityMatches(expected, actual) {
  return expected !== null && actual !== null && canonicalJson(expected) === canonicalJson(actual);
}

function validateIdentity(identity) {
  requireObject(identity, 'frozen identity');
  for (const field of ['lookupTag', 'ollamaVersion', 'modelManifestSha256', 'showDetailsSha256', 'templateSha256', 'parametersSha256']) {
    requireNonEmptyString(identity[field], `frozen identity ${field}`);
  }
}

function validateFixtures(fixtures) {
  if (!Array.isArray(fixtures) || fixtures.length !== 3) throw new Error('Exactly three trusted fixtures are required.');
  const ids = new Set();
  for (const fixture of fixtures) {
    requireObject(fixture, 'fixture');
    requireNonEmptyString(fixture.id, 'fixture id');
    requireNonEmptyString(fixture.digest, 'fixture digest');
    requireNonEmptyString(fixture.prompt, 'fixture prompt');
    if (ids.has(fixture.id)) throw new Error('Fixture IDs must be unique.');
    ids.add(fixture.id);
  }
}

function requireDependencies(deps) {
  for (const name of ['inspectEnvironment', 'executeProbe', 'prepareCandidate']) {
    if (typeof deps?.[name] !== 'function') throw new Error(`Diagnostic dependency ${name} is required.`);
  }
}

function requireObject(value, name) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error(`${name} must be an object.`);
}

function requireNonEmptyString(value, name) {
  if (typeof value !== 'string' || value.length === 0) throw new Error(`${name} must be a non-empty string.`);
}

function copyJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function deepFreeze(value) {
  if (!value || typeof value !== 'object' || Object.isFrozen(value)) return value;
  Object.freeze(value);
  for (const child of Object.values(value)) deepFreeze(child);
  return value;
}
