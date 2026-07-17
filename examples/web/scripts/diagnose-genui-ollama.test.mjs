import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtemp, mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

import {
  buildOllamaDiagnosticPlan,
  executeOllamaDiagnostic,
} from './diagnose-genui-ollama.mjs';

const SHA = (character) => character.repeat(64);
const FROZEN_IDENTITY = Object.freeze({
  lookupTag: 'gemma4:e2b',
  ollamaVersion: '0.12.2',
  modelManifestSha256: SHA('1'),
  showDetailsSha256: SHA('2'),
  templateSha256: SHA('3'),
  parametersSha256: SHA('4'),
});
const FIXTURES = Object.freeze([
  Object.freeze({ id: 'orders-pending-attention', digest: SHA('5'), prompt: 'orders prompt' }),
  Object.freeze({ id: 'inventory-low-stock', digest: SHA('6'), prompt: 'inventory prompt' }),
  Object.freeze({ id: 'incidents-critical-resolution', digest: SHA('7'), prompt: 'incidents prompt' }),
]);
const SETTINGS = Object.freeze({ stream: false, temperature: 0.2, num_ctx: 4096 });
const CANDIDATE = JSON.stringify({ type: 'component', component: 'DataTable', props: {} });

async function makeRunRoot(label) {
  const parent = await mkdtemp(join(tmpdir(), `canopy-ollama-diagnostic-${label}-`));
  const runRoot = join(parent, 'run');
  await mkdir(runRoot, { mode: 0o700 });
  return runRoot;
}

function successfulDependencies(calls = [], overrides = {}) {
  return {
    inspectEnvironment: async () => {
      calls.push('environment_and_model');
      return observation({ step: 'environment_and_model' });
    },
    executeProbe: async ({ probe, fixture, model }) => {
      calls.push(`${probe.id}:${fixture?.id ?? model}`);
      return observation({
        step: probe.id,
        request: {
          method: 'POST',
          url: 'http://127.0.0.1:11434/api/generate',
          headers: { 'content-type': 'application/json', authorization: 'must-not-be-public' },
          body: JSON.stringify({ model, prompt: fixture?.prompt ?? probe.prompt, format: probe.format }),
        },
        response: {
          status: 200,
          headers: { 'content-type': 'application/json', 'x-private': 'must-not-be-public' },
          body: JSON.stringify({ response: CANDIDATE }),
        },
        serverLog: `private server log for ${probe.id}`,
        candidateJson: probe.id === 'candidate_schema_synthetic' || probe.id === 'trusted_fixtures'
          ? CANDIDATE
          : null,
      });
    },
    prepareCandidate: async ({ fixture, candidateJson }) => {
      calls.push(`prepare:${fixture.id}`);
      assert.equal(candidateJson, CANDIDATE);
      return { passed: true, classification: 'candidate_pass' };
    },
    ...overrides,
  };
}

function observation({
  step,
  success = true,
  classification = success ? 'pass' : 'provider_http_error',
  request = null,
  response = null,
  serverLog = '',
  candidateJson = null,
  identityBefore = FROZEN_IDENTITY,
  identityAfter = FROZEN_IDENTITY,
  requestSettings = SETTINGS,
  safety = {},
} = {}) {
  return {
    step,
    success,
    classification,
    request,
    response,
    serverLog,
    candidateJson,
    identityBefore,
    identityAfter,
    requestSettings,
    safety: {
      credentialsSafe: true,
      budgetSafe: true,
      isolationSafe: true,
      evidenceIntegrity: true,
      ...safety,
    },
  };
}

function diagnosticInput(runRoot, overrides = {}) {
  return {
    runRoot,
    frozenIdentity: FROZEN_IDENTITY,
    fixtures: FIXTURES,
    candidateSchema: { type: 'object', required: ['type', 'component', 'props'] },
    syntheticPrompt: 'Return a minimal candidate.',
    knownWorkingModel: 'qwen3:4b',
    protectedInputs: {
      v1: JSON.stringify({ manifestVersion: 1, studyId: 'v1' }),
      v2: JSON.stringify({ manifestVersion: 2, studyId: 'v2' }),
    },
    ...overrides,
  };
}

test('diagnostic plan freezes the exact seven-step order and one changed dimension per transition', () => {
  const plan = buildOllamaDiagnosticPlan({
    frozenIdentity: FROZEN_IDENTITY,
    fixtures: FIXTURES,
    candidateSchema: { type: 'object' },
    syntheticPrompt: 'synthetic',
  });
  assert.deepEqual(plan.map((probe) => probe.id), [
    'environment_and_model',
    'load_without_generation',
    'minimal_text',
    'json_object',
    'unrelated_json_schema',
    'candidate_schema_synthetic',
    'trusted_fixtures',
  ]);
  assert.deepEqual(plan.map((probe) => probe.changedDimension), [
    null,
    'generation',
    'prompt',
    'format',
    'schema',
    'schema',
    'prompt',
  ]);
  assert.deepEqual(plan.at(-1).fixtureIds, FIXTURES.map((fixture) => fixture.id));
  assert.equal(Object.isFrozen(plan), true);
  assert.equal(Object.isFrozen(plan[0]), true);
});

test('passing diagnostic records all fixtures, preparation, digests, and only safe public metadata', async () => {
  const runRoot = await makeRunRoot('pass');
  const calls = [];
  const before = JSON.stringify(diagnosticInput(runRoot));
  const summary = await executeOllamaDiagnostic(diagnosticInput(runRoot), successfulDependencies(calls));

  assert.equal(summary.terminal, true);
  assert.equal(summary.complete, true);
  assert.equal(summary.safe, true);
  assert.equal(summary.selectedBranch, 'paired');
  assert.equal(summary.qualifiedForComparison, true);
  assert.equal(summary.firstFailure, null);
  assert.deepEqual(summary.probeOrder, buildOllamaDiagnosticPlan(diagnosticInput(runRoot)).map((probe) => probe.id));
  assert.deepEqual(summary.fixtureIds, FIXTURES.map((fixture) => fixture.id));
  assert.equal(summary.identityPreserved, true);
  assert.equal(summary.requestSettingsFrozen, true);
  assert.match(summary.requestDigest, /^[0-9a-f]{64}$/u);
  assert.equal(summary.observations.length, 9);
  assert.equal(summary.observations.every((entry) => !('body' in entry) && !('serverLog' in entry)), true);
  assert.equal(JSON.stringify(summary).includes('authorization'), false);
  assert.equal(JSON.stringify(summary).includes('x-private'), false);
  assert.equal(JSON.stringify(summary).includes('private server log'), false);
  assert.deepEqual(summary.observations[2].responseHeaders, { 'content-type': 'application/json' });
  assert.deepEqual(
    summary.observations.filter((entry) => entry.step === 'trusted_fixtures').map((entry) => entry.preparationClassification),
    ['candidate_pass', 'candidate_pass', 'candidate_pass'],
  );
  assert.equal(
    summary.observations.filter((entry) => ['candidate_schema_synthetic', 'trusted_fixtures'].includes(entry.step))
      .every((entry) => entry.requestSettingsSha256 === summary.requestDigest),
    true,
  );
  assert.equal(JSON.stringify(diagnosticInput(runRoot)), before);

  const raw = JSON.parse(await readFile(join(runRoot, 'raw', 'diagnostic', '02-minimal-text.json'), 'utf8'));
  assert.equal(JSON.parse(raw.response.body).response, CANDIDATE);
  assert.equal(raw.serverLog.includes('private server log'), true);
  assert.equal((await stat(join(runRoot, 'raw', 'diagnostic'))).mode & 0o777, 0o700);
  assert.equal((await stat(join(runRoot, 'diagnostic-summary.json'))).mode & 0o777, 0o600);
  assert.deepEqual(calls.filter((call) => call.startsWith('prepare:')), FIXTURES.map((fixture) => `prepare:${fixture.id}`));
});

test('first failing prerequisite is retained, later probes stop, and one runtime control runs before Canopy prompt', async () => {
  const runRoot = await makeRunRoot('failure-control');
  const calls = [];
  const deps = successfulDependencies(calls, {
    executeProbe: async ({ probe, model }) => {
      calls.push(`${probe.id}:${model}`);
      if (probe.id === 'minimal_text' && model === FROZEN_IDENTITY.lookupTag) {
        return observation({
          step: probe.id,
          success: false,
          classification: 'provider_http_error',
          response: { status: 500, headers: { 'content-type': 'text/plain' }, body: 'llama.cpp assertion details' },
          serverLog: 'private backtrace',
        });
      }
      return observation({ step: probe.id });
    },
  });
  const summary = await executeOllamaDiagnostic(diagnosticInput(runRoot), deps);

  assert.deepEqual(summary.probeOrder, ['environment_and_model', 'load_without_generation', 'minimal_text']);
  assert.deepEqual(summary.firstFailure, { step: 'minimal_text', classification: 'provider_http_error' });
  assert.equal(summary.selectedBranch, 'codex_only');
  assert.equal(summary.qualifiedForComparison, false);
  assert.deepEqual(summary.fixtureIds, []);
  assert.equal(summary.requestSettingsFrozen, true);
  assert.equal(summary.observations.at(-1).requestSettingsSha256, summary.requestDigest);
  assert.equal(summary.runtimeControl.model, 'qwen3:4b');
  assert.equal(summary.runtimeControl.classification, 'pass');
  assert.equal(calls.filter((call) => call === 'minimal_text:qwen3:4b').length, 1);
  assert.equal(calls.some((call) => call.startsWith('json_object:')), false);
  assert.equal(JSON.stringify(summary).includes('llama.cpp assertion'), false);
  const raw = await readFile(join(runRoot, 'raw', 'diagnostic', '02-minimal-text.json'), 'utf8');
  assert.equal(raw.includes('llama.cpp assertion details'), true);
  assert.equal(raw.includes('private backtrace'), true);
});

test('runtime control never substitutes for selected-model qualification and does not run after Canopy prompt', async () => {
  for (const failingStep of ['candidate_schema_synthetic', 'trusted_fixtures']) {
    const runRoot = await makeRunRoot(`no-control-${failingStep}`);
    const calls = [];
    const deps = successfulDependencies(calls, {
      executeProbe: async ({ probe, fixture, model }) => {
        calls.push(`${probe.id}:${model}`);
        if (probe.id === failingStep) {
          return observation({ step: probe.id, success: false, classification: 'provider_decode_failure' });
        }
        return observation({
          step: probe.id,
          candidateJson: probe.id === 'candidate_schema_synthetic' || probe.id === 'trusted_fixtures'
            ? CANDIDATE
            : null,
        });
      },
    });
    const summary = await executeOllamaDiagnostic(diagnosticInput(runRoot), deps);
    assert.equal(summary.selectedBranch, 'codex_only');
    assert.equal(summary.qualifiedForComparison, false);
    assert.equal(summary.runtimeControl, null);
    assert.equal(summary.requestSettingsFrozen, true);
    assert.equal(summary.observations.at(-1).requestSettingsSha256, summary.requestDigest);
    assert.equal(calls.some((call) => call.endsWith(':qwen3:4b')), false);
  }
});

test('HTTP JSON/text errors, timeout, identity drift, and preparation failure remain distinct terminal outcomes', async () => {
  const scenarios = [
    ['http-json', observation({ success: false, classification: 'provider_http_error', response: { status: 500, headers: { 'content-type': 'application/json' }, body: '{"error":"model crash"}' } }), 'provider_http_error'],
    ['http-text', observation({ success: false, classification: 'provider_http_error', response: { status: 500, headers: { 'content-type': 'text/plain' }, body: 'model crash' } }), 'provider_http_error'],
    ['timeout', observation({ success: false, classification: 'timeout' }), 'timeout'],
    ['identity', observation({ identityAfter: { ...FROZEN_IDENTITY, parametersSha256: SHA('9') } }), 'identity_drift'],
  ];
  for (const [label, failed, classification] of scenarios) {
    const runRoot = await makeRunRoot(label);
    const deps = successfulDependencies([], {
      executeProbe: async ({ probe }) => probe.id === 'minimal_text' ? { ...failed, step: probe.id } : observation({ step: probe.id }),
    });
    const summary = await executeOllamaDiagnostic(diagnosticInput(runRoot), deps);
    assert.equal(summary.firstFailure.classification, classification);
    assert.equal(summary.selectedBranch, 'codex_only');
  }

  const runRoot = await makeRunRoot('preparation');
  const deps = successfulDependencies([], {
    prepareCandidate: async () => ({ passed: false, classification: 'preparation_failure' }),
  });
  const summary = await executeOllamaDiagnostic(diagnosticInput(runRoot), deps);
  assert.equal(summary.firstFailure.classification, 'preparation_failure');
  assert.equal(summary.selectedBranch, 'codex_only');
});

test('unsafe observations fail closed and cannot claim a comparison branch', async () => {
  const runRoot = await makeRunRoot('unsafe');
  const deps = successfulDependencies([], {
    executeProbe: async ({ probe }) => probe.id === 'minimal_text'
      ? observation({ step: probe.id, success: false, classification: 'credential_leak', safety: { credentialsSafe: false } })
      : observation({ step: probe.id }),
  });
  const summary = await executeOllamaDiagnostic(diagnosticInput(runRoot), deps);
  assert.equal(summary.safe, false);
  assert.equal(summary.credentialsSafe, false);
  assert.equal(summary.selectedBranch, null);
  assert.equal(summary.qualifiedForComparison, false);
});

test('raw and summary outputs are exclusive and a rerun performs no provider request', async () => {
  const runRoot = await makeRunRoot('exclusive');
  const calls = [];
  const deps = successfulDependencies(calls);
  await executeOllamaDiagnostic(diagnosticInput(runRoot), deps);
  const firstCalls = calls.length;
  await assert.rejects(executeOllamaDiagnostic(diagnosticInput(runRoot), deps), /already exists/u);
  assert.equal(calls.length, firstCalls);

  const occupiedRoot = await makeRunRoot('occupied-raw');
  await mkdir(join(occupiedRoot, 'raw', 'diagnostic'), { recursive: true, mode: 0o700 });
  await writeFile(join(occupiedRoot, 'raw', 'diagnostic', '00-environment-and-model.json'), '{}', { flag: 'wx' });
  let providerCalls = 0;
  await assert.rejects(
    executeOllamaDiagnostic(diagnosticInput(occupiedRoot), successfulDependencies([], {
      inspectEnvironment: async () => { providerCalls += 1; return observation({ step: 'environment_and_model' }); },
    })),
    /already exists/u,
  );
  assert.equal(providerCalls, 0);
});

test('missing fixtures, candidate bytes, request-setting consistency, and protected-input mutation fail qualification', async () => {
  assert.throws(
    () => buildOllamaDiagnosticPlan({ frozenIdentity: FROZEN_IDENTITY, fixtures: FIXTURES.slice(0, 2), candidateSchema: {}, syntheticPrompt: 'x' }),
    /Exactly three/u,
  );

  const missingCandidateRoot = await makeRunRoot('missing-candidate');
  const missingCandidate = successfulDependencies([], {
    executeProbe: async ({ probe }) => observation({ step: probe.id, candidateJson: null }),
  });
  const missingSummary = await executeOllamaDiagnostic(diagnosticInput(missingCandidateRoot), missingCandidate);
  assert.equal(missingSummary.firstFailure.classification, 'candidate_absent');

  const digestRoot = await makeRunRoot('settings-drift');
  let requestCount = 0;
  const settingsDrift = successfulDependencies([], {
    executeProbe: async ({ probe }) => {
      requestCount += 1;
      return observation({
        step: probe.id,
        candidateJson: probe.id === 'candidate_schema_synthetic' || probe.id === 'trusted_fixtures' ? CANDIDATE : null,
        requestSettings: probe.id === 'trusted_fixtures' && requestCount > 7 ? { ...SETTINGS, temperature: 0.3 } : SETTINGS,
      });
    },
  });
  const driftSummary = await executeOllamaDiagnostic(diagnosticInput(digestRoot), settingsDrift);
  assert.equal(driftSummary.firstFailure.classification, 'request_digest_mismatch');

  const mutationRoot = await makeRunRoot('protected-mutation');
  const input = diagnosticInput(mutationRoot);
  const mutationDeps = successfulDependencies([], {
    inspectEnvironment: async () => {
      input.protectedInputs.v1 = 'mutated';
      return observation({ step: 'environment_and_model' });
    },
  });
  await assert.rejects(executeOllamaDiagnostic(input, mutationDeps), /protected diagnostic input was mutated/u);
});
