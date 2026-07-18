import assert from 'node:assert/strict';
import test from 'node:test';

import { GENUI_CANDIDATE_SCHEMA } from './genui-candidate-schema.js';
import {
  GENUI_PROVIDER_SETTINGS,
  buildFeasibilityPrompt,
  callOllamaSlot,
  canonicalJson,
  readOllamaIdentity,
  sha256Hex,
} from './genui-feasibility-provider.js';
import { GENUI_FEASIBILITY_FIXTURES } from './genui-feasibility-fixtures.js';
import { getRecordedFeasibilityCandidate } from './genui-recorded-candidates.js';
import { callFakeFeasibilitySlot, createFeasibilityRequestGate } from '../vite-plugin-genui-feasibility.ts';

const MODEL_TAG = 'gemma4:4b';
const SHOW_BODY = Object.freeze({
  license: 'test-license',
  modelfile: 'FROM sha256:test',
  parameters: 'temperature 0.2\nnum_ctx 4096',
  template: '{{ .Prompt }}',
  details: { family: 'gemma3', parameter_size: '4.3B', quantization_level: 'Q4_K_M' },
  model_info: { 'general.architecture': 'gemma3' },
  capabilities: ['completion'],
});
const CANONICAL_PARAMETERS = 'num_ctx 4096\ntemperature 0.2';
const FROZEN_IDENTITY = Object.freeze({
  lookupTag: MODEL_TAG,
  modelManifestSha256: 'sha256:model-manifest',
  showDetailsSha256: sha256Hex(canonicalJson({ ...SHOW_BODY, parameters: CANONICAL_PARAMETERS })),
  ollamaVersion: '0.11.4',
  templateSha256: sha256Hex(SHOW_BODY.template),
  parametersSha256: sha256Hex(CANONICAL_PARAMETERS),
});
const RAW_CANDIDATE = '{"not":"parsed by provider"}';

function jsonResponse(body, { ok = true, status = 200 } = {}) {
  return { ok, status, async json() { return body; } };
}

function identityFetch({ showBody = SHOW_BODY, version = '0.11.4', digest = 'sha256:model-manifest' } = {}) {
  return async (url, options) => {
    if (url.endsWith('/api/version')) return jsonResponse({ version });
    if (url.endsWith('/api/tags')) {
      return jsonResponse({ models: [{ name: MODEL_TAG, model: MODEL_TAG, digest }] });
    }
    if (url.endsWith('/api/show')) {
      assert.deepEqual(JSON.parse(options.body), { model: MODEL_TAG });
      return jsonResponse(showBody);
    }
    throw new Error(`Unexpected URL: ${url}`);
  };
}

function createGenerateFetch(providerBody = {
  model: MODEL_TAG,
  response: RAW_CANDIDATE,
  done: true,
  total_duration: 12_300_000,
  prompt_eval_count: 17,
  eval_count: 23,
}) {
  const calls = [];
  return {
    calls,
    fetch: async (url, options) => {
      calls.push({ url, options });
      return jsonResponse(providerBody);
    },
  };
}

function validateSchema(value, schema, root = schema) {
  if ('$ref' in schema) {
    const target = schema.$ref.split('/').slice(1).reduce((current, part) => current[part], root);
    return validateSchema(value, target, root);
  }
  if ('const' in schema && value !== schema.const) return false;
  if (schema.enum && !schema.enum.includes(value)) return false;
  if (schema.type === 'string') {
    if (typeof value !== 'string') return false;
    if (schema.minLength !== undefined && value.length < schema.minLength) return false;
    if (schema.maxLength !== undefined && value.length > schema.maxLength) return false;
  }
  if (schema.type === 'object') {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
    if (schema.required?.some((key) => !(key in value))) return false;
    if (schema.additionalProperties === false && Object.keys(value).some((key) => !(key in schema.properties))) return false;
    for (const [key, childSchema] of Object.entries(schema.properties ?? {})) {
      if (key in value && !validateSchema(value[key], childSchema, root)) return false;
    }
  }
  if (schema.type === 'array') {
    if (!Array.isArray(value)) return false;
    if (schema.maxItems !== undefined && value.length > schema.maxItems) return false;
    if (schema.items === false && value.length !== (schema.prefixItems?.length ?? 0)) return false;
    for (let index = 0; index < (schema.prefixItems?.length ?? 0); index += 1) {
      if (!validateSchema(value[index], schema.prefixItems[index], root)) return false;
    }
  }
  if (schema.oneOf) {
    return schema.oneOf.filter((branch) => validateSchema(value, branch, root)).length === 1;
  }
  return true;
}

test('provider schema accepts recorded controls and embeds no case authority', () => {
  for (const fixture of GENUI_FEASIBILITY_FIXTURES) {
    assert.equal(validateSchema(getRecordedFeasibilityCandidate(fixture.caseId), GENUI_CANDIDATE_SCHEMA), true);
  }
  const schemaText = JSON.stringify(GENUI_CANDIDATE_SCHEMA);
  assert.equal(schemaText.includes('"prefixItems":[]'), false, 'provider schema cannot contain empty prefixItems');
  for (const forbidden of [
    'orders', 'inventory', 'incidents', 'status', 'amount', 'on_hand', 'severity',
    'resolution_minutes', 'pending', 'critical', 'ord-1002', 'sku-001', 'inc-001',
  ]) {
    assert.equal(schemaText.includes(JSON.stringify(forbidden)), false, `schema leaked ${forbidden}`);
  }
});

test('prompt contains task inputs and capabilities but no rubric or expected outcome', () => {
  const fixture = GENUI_FEASIBILITY_FIXTURES[0];
  const prompt = buildFeasibilityPrompt(fixture);
  assert.match(prompt, new RegExp(fixture.question.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.match(prompt, /pending/);
  assert.match(prompt, /orders/);
  assert.match(prompt, /filter_operators/);
  assert.doesNotMatch(prompt, /rubric|expected|matched_stable_keys|summary_value/i);
});

test('canonical JSON and identity discovery freeze all provider identity surfaces', async () => {
  assert.equal(canonicalJson({ z: 1, a: { y: 2, x: 3 } }), '{"a":{"x":3,"y":2},"z":1}');
  const identity = await readOllamaIdentity(MODEL_TAG, { fetch: identityFetch() });
  assert.deepEqual(identity, FROZEN_IDENTITY);
});

test('parameter identity ignores provider line order', async () => {
  const first = await readOllamaIdentity(MODEL_TAG, {
    fetch: identityFetch({
      showBody: {
        ...SHOW_BODY,
        parameters: 'temperature 0.2\nnum_ctx 4096',
      },
    }),
  });
  const reordered = await readOllamaIdentity(MODEL_TAG, {
    fetch: identityFetch({
      showBody: {
        ...SHOW_BODY,
        parameters: 'num_ctx 4096\ntemperature 0.2',
      },
    }),
  });

  assert.equal(first.parametersSha256, reordered.parametersSha256);
  assert.equal(first.showDetailsSha256, reordered.showDetailsSha256);
});

test('parameter identity detects value changes', async () => {
  const original = await readOllamaIdentity(MODEL_TAG, {
    fetch: identityFetch(),
  });
  const changed = await readOllamaIdentity(MODEL_TAG, {
    fetch: identityFetch({
      showBody: {
        ...SHOW_BODY,
        parameters: 'temperature 0.3\nnum_ctx 4096',
      },
    }),
  });

  assert.notEqual(original.parametersSha256, changed.parametersSha256);
  assert.notEqual(original.showDetailsSha256, changed.showDetailsSha256);
});

test('show identity ignores only Modelfile parameter order', async () => {
  const first = await readOllamaIdentity(MODEL_TAG, {
    fetch: identityFetch({
      showBody: {
        ...SHOW_BODY,
        modelfile:
          'FROM sha256:test\nPARAMETER temperature 0.2\nPARAMETER num_ctx 4096\nTEMPLATE {{ .Prompt }}',
      },
    }),
  });
  const reordered = await readOllamaIdentity(MODEL_TAG, {
    fetch: identityFetch({
      showBody: {
        ...SHOW_BODY,
        modelfile:
          'FROM sha256:test\nPARAMETER num_ctx 4096\nPARAMETER temperature 0.2\nTEMPLATE {{ .Prompt }}',
      },
    }),
  });
  const changed = await readOllamaIdentity(MODEL_TAG, {
    fetch: identityFetch({
      showBody: {
        ...SHOW_BODY,
        modelfile:
          'FROM sha256:other\nPARAMETER num_ctx 4096\nPARAMETER temperature 0.2\nTEMPLATE {{ .Prompt }}',
      },
    }),
  });

  assert.equal(first.showDetailsSha256, reordered.showDetailsSha256);
  assert.notEqual(first.showDetailsSha256, changed.showDetailsSha256);
});

test('one provider attempt preserves opaque candidate bytes and frozen telemetry', async () => {
  const generated = createGenerateFetch();
  const identityReads = [];
  const result = await callOllamaSlot(
    { fixture: GENUI_FEASIBILITY_FIXTURES[0], slotId: 1, frozenIdentity: FROZEN_IDENTITY },
    {
      fetch: generated.fetch,
      readIdentity: async (tag) => { identityReads.push(tag); return FROZEN_IDENTITY; },
      now: (() => { const values = [100, 141]; return () => values.shift(); })(),
      timeoutSignal: () => new AbortController().signal,
    },
  );

  assert.equal(result.classification, 'success');
  assert.equal(result.candidateJson, RAW_CANDIDATE);
  assert.equal(result.candidateSha256, sha256Hex(RAW_CANDIDATE));
  assert.equal(result.seed, 1702);
  assert.equal(result.elapsedMs, 41);
  assert.equal(result.providerDurationMs, 12);
  assert.equal(result.promptTokens, 17);
  assert.equal(result.outputTokens, 23);
  assert.deepEqual(identityReads, [MODEL_TAG, MODEL_TAG]);
  assert.equal(generated.calls.length, 1);
  const request = JSON.parse(generated.calls[0].options.body);
  assert.equal(request.stream, false);
  assert.deepEqual(request.format, GENUI_CANDIDATE_SCHEMA);
  assert.deepEqual(request.options, { temperature: 0.2, num_ctx: 4096, num_predict: 512, seed: 1702 });
  assert.equal(request.keep_alive, '5m');
});

test('provider leaves invalid candidate syntax opaque for MoonBit preparation', async () => {
  const generated = createGenerateFetch({ model: MODEL_TAG, response: 'not json', done: true });
  const result = await callOllamaSlot(
    { fixture: GENUI_FEASIBILITY_FIXTURES[0], slotId: 0, frozenIdentity: FROZEN_IDENTITY },
    { fetch: generated.fetch, readIdentity: async () => FROZEN_IDENTITY, timeoutSignal: () => new AbortController().signal },
  );
  assert.equal(result.classification, 'success');
  assert.equal(result.candidateJson, 'not json');
});

test('every frozen identity drift fails before generation', async () => {
  for (const field of [
    'modelManifestSha256', 'showDetailsSha256', 'ollamaVersion', 'templateSha256', 'parametersSha256',
  ]) {
    let generateCalls = 0;
    const result = await callOllamaSlot(
      { fixture: GENUI_FEASIBILITY_FIXTURES[0], slotId: 0, frozenIdentity: FROZEN_IDENTITY },
      {
        readIdentity: async () => ({ ...FROZEN_IDENTITY, [field]: `${FROZEN_IDENTITY[field]}-drift` }),
        fetch: async () => { generateCalls += 1; return jsonResponse({}); },
      },
    );
    assert.equal(result.classification, 'model_identity_mismatch', field);
    assert.equal(generateCalls, 0, field);
  }
});

test('identity remap after generation rejects returned candidate without retry', async () => {
  const generated = createGenerateFetch();
  let reads = 0;
  const result = await callOllamaSlot(
    { fixture: GENUI_FEASIBILITY_FIXTURES[0], slotId: 0, frozenIdentity: FROZEN_IDENTITY },
    {
      fetch: generated.fetch,
      readIdentity: async () => {
        reads += 1;
        return reads === 1 ? FROZEN_IDENTITY : { ...FROZEN_IDENTITY, modelManifestSha256: 'remapped' };
      },
      timeoutSignal: () => new AbortController().signal,
    },
  );
  assert.equal(result.classification, 'model_identity_mismatch');
  assert.equal(generated.calls.length, 1);
  assert.equal('candidateJson' in result, false);
});

test('provider failures are terminal, distinct, and never retried', async () => {
  const failures = [
    {
      expected: 'provider_http_error',
      fetch: async () => jsonResponse({}, { ok: false, status: 503 }),
    },
    {
      expected: 'provider_timeout',
      fetch: async () => { const error = new Error('late'); error.name = 'TimeoutError'; throw error; },
    },
    {
      expected: 'provider_envelope_error',
      fetch: async () => ({ ok: true, status: 200, async json() { throw new SyntaxError('bad'); } }),
    },
    {
      expected: 'provider_envelope_error',
      fetch: async () => jsonResponse({ model: MODEL_TAG, done: true }),
    },
    {
      expected: 'candidate_oversize',
      fetch: async () => jsonResponse({ model: MODEL_TAG, response: 'x'.repeat(GENUI_PROVIDER_SETTINGS.maxCandidateBytes + 1), done: true }),
    },
  ];

  for (const failure of failures) {
    let calls = 0;
    const result = await callOllamaSlot(
      { fixture: GENUI_FEASIBILITY_FIXTURES[0], slotId: 0, frozenIdentity: FROZEN_IDENTITY },
      {
        readIdentity: async () => FROZEN_IDENTITY,
        fetch: async (...args) => { calls += 1; return failure.fetch(...args); },
        timeoutSignal: () => new AbortController().signal,
      },
    );
    assert.equal(result.classification, failure.expected);
    assert.equal(calls, 1);
  }
});

test('request gate rejects malformed or replayed slots before provider access', async () => {
  let providerCalls = 0;
  const manifest = {
    studyId: 'genui-local-v1',
    modelIdentity: FROZEN_IDENTITY,
    schedule: GENUI_FEASIBILITY_FIXTURES.flatMap((fixture) => [0, 1, 2].map((slotId) => ({ caseId: fixture.caseId, slotId }))),
  };
  const gate = createFeasibilityRequestGate({
    manifest,
    runCapability: 'a'.repeat(64),
    fixtures: GENUI_FEASIBILITY_FIXTURES,
    callSlot: async (input) => { providerCalls += 1; return { classification: 'success', caseId: input.fixture.caseId, slotId: input.slotId }; },
  });
  const valid = { studyId: manifest.studyId, runCapability: 'a'.repeat(64), caseId: manifest.schedule[0].caseId, slotId: 0 };

  for (const body of [
    { ...valid, extra: true },
    { ...valid, studyId: 'wrong' },
    { ...valid, runCapability: 'b'.repeat(64) },
    { ...valid, caseId: 'unknown' },
    { ...valid, slotId: 9 },
  ]) {
    const result = await gate.execute(body);
    assert.equal(result.classification, 'request_rejected');
  }
  assert.equal(providerCalls, 0);
  assert.equal((await gate.execute(valid)).classification, 'success');
  assert.equal((await gate.execute(valid)).classification, 'duplicate_slot');
  assert.equal(providerCalls, 1);
});

test('fake study provider returns one recorded candidate, one rejection candidate, and one failure per case', async () => {
  for (const fixture of GENUI_FEASIBILITY_FIXTURES) {
    const success = await callFakeFeasibilitySlot({ fixture, slotId: 0, frozenIdentity: FROZEN_IDENTITY });
    assert.equal(success.classification, 'success');
    assert.equal(success.candidateJson, JSON.stringify(getRecordedFeasibilityCandidate(fixture.caseId)));

    const rejected = await callFakeFeasibilitySlot({ fixture, slotId: 1, frozenIdentity: FROZEN_IDENTITY });
    assert.equal(rejected.classification, 'success');
    assert.equal(rejected.candidateJson, '{}');

    const failure = await callFakeFeasibilitySlot({ fixture, slotId: 2, frozenIdentity: FROZEN_IDENTITY });
    assert.equal(failure.classification, 'provider_failure');
  }
});
