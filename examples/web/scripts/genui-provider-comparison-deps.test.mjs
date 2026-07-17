import assert from 'node:assert/strict';
import test from 'node:test';
import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { canonicalJson } from '../src/genui-feasibility-provider.js';
import {
  getFeasibilityFixture,
  normalizeTrustedFixture,
} from '../src/genui-feasibility-fixtures.js';
import { createComparisonDependencies } from './genui-provider-comparison-deps.mjs';

const COMMIT = 'a'.repeat(40);
const fixture = getFeasibilityFixture('orders-pending-attention');
const fixtureDigest = createHash('sha256')
  .update(canonicalJson(normalizeTrustedFixture(fixture)))
  .digest('hex');

function manifest() {
  return {
    sourceCommit: COMMIT,
    branch: 'codex_only',
    fixtures: [{ id: fixture.caseId, digest: fixtureDigest }],
    schedule: [],
    providerIdentities: {
      codex: {
        cliVersion: 'codex-cli 0.144.4',
        modelSlug: 'gpt-5.6-luna',
        reasoningEffort: 'medium',
        authMode: 'chatgpt',
        catalogEntrySha256: 'b'.repeat(64),
      },
      ollama: {
        lookupTag: 'gemma4:e2b',
        ollamaVersion: '0.11.4',
        modelManifestSha256: 'c'.repeat(64),
        showDetailsSha256: 'd'.repeat(64),
        templateSha256: 'e'.repeat(64),
        parametersSha256: 'f'.repeat(64),
      },
    },
    limits: {
      activeRequests: 1,
      perRequestTokenCeiling: 100,
      runTokenCeiling: 100,
      runWallTimeMs: 1_000,
    },
  };
}

function passingCandidateEvaluation() {
  return {
    classification: 'success',
    rubric: { passed: true, reasons: [] },
    evidence: { matched_stable_keys: ['ord-1002'] },
    session: { success: true, revision: 1 },
  };
}

test('production dependencies load frozen fixture bytes and commit through the browser evaluator', async () => {
  const calls = [];
  const browserEvaluator = {
    evaluate: async (input) => {
      calls.push(input);
      return passingCandidateEvaluation();
    },
    close: async () => calls.push('closed'),
  };
  const deps = await createComparisonDependencies({ manifest: manifest() }, {
    browserEvaluatorFactory: async () => browserEvaluator,
  });

  const input = await deps.loadFixture({ fixtureId: fixture.caseId, fixtureDigest });
  assert.equal(input.digest, fixtureDigest);
  assert.equal(input.fixture.caseId, fixture.caseId);
  assert.deepEqual(JSON.parse(input.datasetJson), normalizeTrustedFixture(fixture));

  const result = await deps.evaluateCandidate({
    slot: { fixtureId: fixture.caseId },
    candidateJson: '{"type":"text","value":"ok"}',
    input,
  });
  assert.equal(result.classification, 'candidate_pass');
  assert.equal(result.preparationPassed, true);
  assert.deepEqual(result.validations, {
    decoding: true,
    semantic: true,
    materialization: true,
    rubric: true,
    replay: true,
    sessionCommit: true,
  });
  assert.equal(calls[0].caseId, fixture.caseId);
  assert.deepEqual(calls[0].input, input);
  await deps.close();
  assert.equal(calls.at(-1), 'closed');
});

test('production dependencies preserve failure taxonomy from the MoonBit browser path', async () => {
  const classifications = [
    ['candidate_decode_error', 'provider_decode_failure'],
    ['capability_decode_error', 'capability_decode_failure'],
    ['candidate_validation_error', 'semantic_validation_failure'],
    ['materialization_error', 'materialization_failure'],
    ['rubric_failure', 'rubric_failure'],
    ['replay_mismatch', 'replay_mismatch'],
    ['commit_failure', 'session_commit_failure'],
  ];
  for (const [browserClassification, terminalClassification] of classifications) {
    const deps = await createComparisonDependencies({ manifest: manifest() }, {
      browserEvaluatorFactory: async () => ({
        evaluate: async () => ({ classification: browserClassification, rubric: null, session: null }),
        close: async () => undefined,
      }),
    });
    const result = await deps.evaluateCandidate({
      slot: { fixtureId: fixture.caseId },
      candidateJson: '{}',
      input: { fixture },
    });
    assert.equal(result.classification, terminalClassification);
    await deps.close();
  }
});

test('production provider attempts close Codex sessions, normalize Ollama success, and stop at frozen budgets', async () => {
  let codexClosed = 0;
  let receivedCodexIdentity = null;
  const deps = await createComparisonDependencies({ manifest: manifest() }, {
    createCodexSession: async ({ frozenIdentity }) => {
      receivedCodexIdentity = frozenIdentity;
      return {
      runSlot: async () => ({
        classification: 'success',
        candidateJson: '{}',
        transcript: [
        { direction: 'server', method: 'item/completed', itemType: 'agentMessage', terminalStatus: null },
        ],
        tokenUsage: { inputTokens: 10, cachedInputTokens: 0, outputTokens: 5, reasoningOutputTokens: 0, totalTokens: 15 },
      }),
        close: async () => { codexClosed += 1; },
      };
    },
    callOllama: async () => ({
      classification: 'success',
      candidateJson: '{}',
      lookupTag: 'gemma4:e2b',
      candidateSha256: '1'.repeat(64),
      promptTokens: 5,
      outputTokens: 4,
    }),
  });
  const sandbox = { spawnProcess: async () => undefined };
  const slot = { slotId: 'slot-1', fixtureId: fixture.caseId, providerId: 'codex' };
  const codex = await deps.attempts.codex({ slot, fixture, sandbox });
  assert.equal(codex.classification, 'candidate_pass');
  assert.equal(codex.rawEvents.filter((event) => event.type === 'agentMessage').length, 1);
  assert.equal(codex.usage.totalTokens, 15);
  assert.equal(codexClosed, 1);
  assert.deepEqual(receivedCodexIdentity, {
    cliVersion: 'codex-cli 0.144.4',
    slug: 'gpt-5.6-luna',
    effort: 'medium',
    authMode: 'chatgpt',
    catalogEntrySha256: 'b'.repeat(64),
  });
  assert.deepEqual(await deps.requestGate({ slot }), { classification: 'global_stop' });

  const ollama = await deps.attempts.ollama({
    slot: { ...slot, providerId: 'ollama' },
    fixture,
    seed: 1701,
  });
  assert.equal(ollama.classification, 'global_stop');
});

test('production Codex usage contributes exact tokens to the frozen run budget', async () => {
  const budgetManifest = manifest();
  budgetManifest.limits = {
    activeRequests: 10,
    perRequestTokenCeiling: 100,
    runTokenCeiling: 30,
    runWallTimeMs: 1_000_000,
  };
  const deps = await createComparisonDependencies({ manifest: budgetManifest }, {
    createCodexSession: async () => ({
      runSlot: async () => ({
        classification: 'success',
        candidateJson: '{}',
        transcript: [
          { direction: 'server', method: 'item/completed', itemType: 'agentMessage', terminalStatus: null },
        ],
        tokenUsage: {
          inputTokens: 10,
          cachedInputTokens: 0,
          outputTokens: 5,
          reasoningOutputTokens: 0,
          totalTokens: 15,
        },
      }),
      close: async () => undefined,
    }),
  });
  const sandbox = { spawnProcess: async () => undefined };
  const slot = { slotId: 'slot-1', fixtureId: fixture.caseId, providerId: 'codex' };

  const first = await deps.attempts.codex({ slot, fixture, sandbox });
  assert.equal(first.usage.totalTokens, 15);
  assert.deepEqual(await deps.requestGate({ slot }), { classification: 'pass' });
  const second = await deps.attempts.codex({
    slot: { ...slot, slotId: 'slot-2' },
    fixture,
    sandbox,
  });
  assert.equal(second.usage.totalTokens, 15);
  assert.deepEqual(await deps.requestGate({ slot }), { classification: 'global_stop' });
  await deps.close();
});

test('production dependencies accept an explicit reviewed Codex binary path', async () => {
  const runRoot = await mkdtemp(join(tmpdir(), 'canopy-provider-codex-binary-'));
  const previous = process.env.GENUI_PROVIDER_CODEX_BINARY;
  process.env.GENUI_PROVIDER_CODEX_BINARY = '/opt/reviewed/codex';
  let receivedBinary = null;
  try {
    const deps = await createComparisonDependencies({ manifest: manifest() }, {
      prepareSandbox: async ({ codexBinary }) => {
        receivedBinary = codexBinary;
        return {
          contract: {},
          spawnProcess: async () => undefined,
          cleanup: async () => undefined,
        };
      },
    });
    await deps.createSandbox({ runRoot });
    assert.equal(receivedBinary, '/opt/reviewed/codex');
  } finally {
    if (previous === undefined) delete process.env.GENUI_PROVIDER_CODEX_BINARY;
    else process.env.GENUI_PROVIDER_CODEX_BINARY = previous;
    await rm(runRoot, { recursive: true, force: true });
  }
});

test('production preflight maps manifest identity and rejects discovered drift', async () => {
  const root = await mkdtemp(join(tmpdir(), 'canopy-provider-preflight-'));
  const stateHome = join(root, 'state');
  const namespace = join(stateHome, 'canopy', 'genui-provider-benchmark');
  const authSource = join(root, 'auth.json');
  const previousStateHome = process.env.XDG_STATE_HOME;
  const expectedIdentity = {
    cliVersion: 'codex-cli 0.144.4',
    slug: 'gpt-5.6-luna',
    effort: 'medium',
    authMode: 'chatgpt',
    catalogEntrySha256: 'b'.repeat(64),
  };
  const discoveryInputs = [];
  let drift = false;
  try {
    await mkdir(namespace, { recursive: true });
    await writeFile(authSource, '{}');
    process.env.XDG_STATE_HOME = stateHome;
    const deps = await createComparisonDependencies({ manifest: manifest() }, {
      authSource,
      verifyRepository: async () => COMMIT,
      prepareSandbox: async () => ({
        contract: { codexVersion: expectedIdentity.cliVersion },
        spawnProcess: async () => undefined,
        cleanup: async () => undefined,
      }),
      discoverCodexIdentity: async ({ cliVersion, slug, effort }) => {
        discoveryInputs.push({ cliVersion, slug, effort });
        return {
          ...expectedIdentity,
          ...(drift ? { catalogEntrySha256: 'c'.repeat(64) } : {}),
        };
      },
    });

    assert.deepEqual(await deps.preflight(), {
      isolation: true,
      identity: true,
      credentials: true,
      budget: true,
    });
    assert.deepEqual(discoveryInputs, [{
      cliVersion: expectedIdentity.cliVersion,
      slug: expectedIdentity.slug,
      effort: expectedIdentity.effort,
    }]);

    drift = true;
    await assert.rejects(() => deps.preflight(), /identity differs/u);
  } finally {
    if (previousStateHome === undefined) delete process.env.XDG_STATE_HOME;
    else process.env.XDG_STATE_HOME = previousStateHome;
    await rm(root, { recursive: true, force: true });
  }
});
