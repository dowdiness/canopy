import { createHash } from 'node:crypto';

import { GENUI_CANDIDATE_SCHEMA } from '../../src/features/genui/core/genui-candidate-schema.js';
import { capabilitiesJsonForFixture } from '../../src/features/genui/core/genui-feasibility-fixtures.js';

export const GENUI_PROVIDER_SETTINGS = deepFreeze({
  stream: false,
  temperature: 0.2,
  numCtx: 4096,
  numPredict: 512,
  keepAlive: '5m',
  timeoutMs: 120_000,
  slotSeeds: [1701, 1702, 1703],
  maxCandidateBytes: 64 * 1024,
});

export function buildFeasibilityPrompt(fixture) {
  return [
    'You design one focused read-only view for the supplied data task.',
    'Return only one JSON value matching the supplied schema and raw component wire format.',
    'The output is untrusted. The host will reject any invalid, unsupported, or task-incomplete candidate.',
    'Do not emit HTML, JavaScript, Markdown, explanations, or properties outside the schema.',
    `Question: ${fixture.question}`,
    `Source format: ${fixture.sourceFormat}`,
    `Binding: ${fixture.binding}`,
    `Selection key: ${fixture.selectionKey}`,
    `Task filter value: ${JSON.stringify(fixture.taskValue)}`,
    `Capabilities: ${capabilitiesJsonForFixture(fixture)}`,
    `Source: ${JSON.stringify(fixture.source)}`,
  ].join('\n');
}

function sortSelectedLineSlots(text, isSelected) {
  const lines = text.split('\n');
  const sortedLines = lines.filter(isSelected).sort();
  let sortedIndex = 0;
  return lines
    .map((line) => isSelected(line) ? sortedLines[sortedIndex++] : line)
    .join('\n');
}

export async function readOllamaIdentity(modelTag, deps = {}) {
  const fetchImpl = deps.fetch ?? fetch;
  const digest = deps.digest ?? sha256Hex;
  const baseUrl = deps.ollamaUrl ?? 'http://127.0.0.1:11434';

  const versionBody = await fetchJson(fetchImpl, `${baseUrl}/api/version`);
  if (!isRecord(versionBody) || typeof versionBody.version !== 'string') {
    throw new ProviderReadError('provider_identity_error', 'Ollama returned an invalid version response.');
  }

  const tagsBody = await fetchJson(fetchImpl, `${baseUrl}/api/tags`);
  if (!isRecord(tagsBody) || !Array.isArray(tagsBody.models)) {
    throw new ProviderReadError('provider_identity_error', 'Ollama returned an invalid model list.');
  }
  const model = tagsBody.models.find((entry) =>
    isRecord(entry) && (entry.name === modelTag || entry.model === modelTag),
  );
  if (!isRecord(model) || typeof model.digest !== 'string') {
    throw new ProviderReadError('model_not_installed', `Ollama model is not installed: ${modelTag}`);
  }

  const showBody = await fetchJson(fetchImpl, `${baseUrl}/api/show`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ model: modelTag }),
  });
  if (!isRecord(showBody)) {
    throw new ProviderReadError('provider_identity_error', 'Ollama returned an invalid model details response.');
  }
  const template = typeof showBody.template === 'string' ? showBody.template : '';
  const parameters = sortSelectedLineSlots(
    typeof showBody.parameters === 'string' ? showBody.parameters : '',
    (line) => line !== '',
  );
  const normalizedShowBody = { ...showBody, parameters };
  if (typeof normalizedShowBody.modelfile === 'string') {
    normalizedShowBody.modelfile = sortSelectedLineSlots(
      normalizedShowBody.modelfile,
      (line) => line.startsWith('PARAMETER '),
    );
  }

  return deepFreeze({
    lookupTag: modelTag,
    modelManifestSha256: model.digest,
    showDetailsSha256: digest(canonicalJson(normalizedShowBody)),
    ollamaVersion: versionBody.version,
    templateSha256: digest(template),
    parametersSha256: digest(parameters),
  });
}

export async function callOllamaSlot({ fixture, slotId, frozenIdentity }, deps = {}) {
  if (!Number.isInteger(slotId) || slotId < 0 || slotId >= GENUI_PROVIDER_SETTINGS.slotSeeds.length) {
    return failure('request_rejected', `Unknown feasibility slot: ${slotId}`);
  }

  const digest = deps.digest ?? sha256Hex;
  const readIdentity = deps.readIdentity ?? ((modelTag) => readOllamaIdentity(modelTag, deps));
  let identityBefore;
  try {
    identityBefore = await readIdentity(frozenIdentity.lookupTag);
  } catch (error) {
    return providerReadFailure(error);
  }
  if (!identitiesEqual(identityBefore, frozenIdentity)) {
    return failure('model_identity_mismatch', 'Ollama model identity differs from the frozen study manifest.');
  }

  const seed = GENUI_PROVIDER_SETTINGS.slotSeeds[slotId];
  const prompt = buildFeasibilityPrompt(fixture);
  const requestBody = {
    model: frozenIdentity.lookupTag,
    prompt,
    stream: GENUI_PROVIDER_SETTINGS.stream,
    format: GENUI_CANDIDATE_SCHEMA,
    options: {
      temperature: GENUI_PROVIDER_SETTINGS.temperature,
      num_ctx: GENUI_PROVIDER_SETTINGS.numCtx,
      num_predict: GENUI_PROVIDER_SETTINGS.numPredict,
      seed,
    },
    keep_alive: GENUI_PROVIDER_SETTINGS.keepAlive,
  };
  const fetchImpl = deps.fetch ?? fetch;
  const baseUrl = deps.ollamaUrl ?? 'http://127.0.0.1:11434';
  const now = deps.now ?? (() => performance.now());
  const timeoutSignal = deps.timeoutSignal ?? ((milliseconds) => AbortSignal.timeout(milliseconds));
  const startedAt = now();

  let response;
  try {
    response = await fetchImpl(`${baseUrl}/api/generate`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(requestBody),
      signal: timeoutSignal(GENUI_PROVIDER_SETTINGS.timeoutMs),
    });
  } catch (error) {
    if (isTimeoutError(error)) {
      return failure('provider_timeout', 'Ollama generation timed out.');
    }
    return failure('provider_transport_error', errorMessage(error));
  }
  if (!response.ok) {
    return failure('provider_http_error', `Ollama returned HTTP ${response.status}.`);
  }

  let providerBody;
  try {
    providerBody = await response.json();
  } catch {
    return failure('provider_envelope_error', 'Ollama returned a non-JSON response envelope.');
  }

  let identityAfter;
  try {
    identityAfter = await readIdentity(frozenIdentity.lookupTag);
  } catch (error) {
    return providerReadFailure(error);
  }
  if (!identitiesEqual(identityAfter, frozenIdentity)) {
    return failure('model_identity_mismatch', 'Ollama model identity changed during generation.');
  }

  if (
    !isRecord(providerBody) ||
    typeof providerBody.response !== 'string' ||
    (typeof providerBody.model === 'string' && providerBody.model !== frozenIdentity.lookupTag)
  ) {
    return failure('provider_envelope_error', 'Ollama returned an invalid response envelope.');
  }
  const candidateJson = providerBody.response;
  if (Buffer.byteLength(candidateJson, 'utf8') > GENUI_PROVIDER_SETTINGS.maxCandidateBytes) {
    return failure('candidate_oversize', 'Ollama candidate exceeds the frozen byte limit.');
  }

  return {
    classification: 'success',
    candidateJson,
    caseId: fixture.caseId,
    slotId,
    lookupTag: frozenIdentity.lookupTag,
    modelManifestSha256: frozenIdentity.modelManifestSha256,
    showDetailsSha256: frozenIdentity.showDetailsSha256,
    ollamaVersion: frozenIdentity.ollamaVersion,
    templateSha256: frozenIdentity.templateSha256,
    parametersSha256: frozenIdentity.parametersSha256,
    seed,
    settings: {
      stream: GENUI_PROVIDER_SETTINGS.stream,
      temperature: GENUI_PROVIDER_SETTINGS.temperature,
      numCtx: GENUI_PROVIDER_SETTINGS.numCtx,
      numPredict: GENUI_PROVIDER_SETTINGS.numPredict,
      keepAlive: GENUI_PROVIDER_SETTINGS.keepAlive,
      timeoutMs: GENUI_PROVIDER_SETTINGS.timeoutMs,
    },
    promptSha256: digest(prompt),
    candidateSha256: digest(candidateJson),
    elapsedMs: Math.round(now() - startedAt),
    providerDurationMs: nanosecondsToMilliseconds(readMetric(providerBody.total_duration)),
    promptTokens: readMetric(providerBody.prompt_eval_count),
    outputTokens: readMetric(providerBody.eval_count),
  };
}

export function canonicalJson(value) {
  if (value === null || typeof value === 'boolean' || typeof value === 'string') {
    return JSON.stringify(value);
  }
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new TypeError('Canonical JSON cannot encode non-finite numbers.');
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((entry) => canonicalJson(entry)).join(',')}]`;
  }
  if (isRecord(value)) {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`)
      .join(',')}}`;
  }
  throw new TypeError('Canonical JSON accepts only JSON values.');
}

export function sha256Hex(value) {
  return createHash('sha256').update(value).digest('hex');
}

function identitiesEqual(actual, expected) {
  return (
    actual.lookupTag === expected.lookupTag &&
    actual.modelManifestSha256 === expected.modelManifestSha256 &&
    actual.showDetailsSha256 === expected.showDetailsSha256 &&
    actual.ollamaVersion === expected.ollamaVersion &&
    actual.templateSha256 === expected.templateSha256 &&
    actual.parametersSha256 === expected.parametersSha256
  );
}

async function fetchJson(fetchImpl, url, options) {
  let response;
  try {
    response = await fetchImpl(url, options);
  } catch (error) {
    throw new ProviderReadError('provider_identity_error', errorMessage(error));
  }
  if (!response.ok) {
    throw new ProviderReadError('provider_identity_error', `Ollama identity endpoint returned HTTP ${response.status}.`);
  }
  try {
    return await response.json();
  } catch {
    throw new ProviderReadError('provider_identity_error', 'Ollama identity endpoint returned invalid JSON.');
  }
}

class ProviderReadError extends Error {
  constructor(classification, message) {
    super(message);
    this.classification = classification;
  }
}

function providerReadFailure(error) {
  if (error instanceof ProviderReadError) return failure(error.classification, error.message);
  return failure('provider_identity_error', errorMessage(error));
}

function failure(classification, message) {
  return { classification, message };
}

function readMetric(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function nanosecondsToMilliseconds(value) {
  return value === null ? null : Math.round(value / 1_000_000);
}

function isTimeoutError(error) {
  return error instanceof Error && (error.name === 'TimeoutError' || error.name === 'AbortError');
}

function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

function isRecord(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function deepFreeze(value) {
  if (value !== null && typeof value === 'object' && !Object.isFrozen(value)) {
    for (const child of Object.values(value)) deepFreeze(child);
    Object.freeze(value);
  }
  return value;
}
