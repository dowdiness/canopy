import assert from 'node:assert/strict';
import test from 'node:test';

import {
  assertUnusedOutputs,
  buildValidationEnv,
  createRunCapability,
  runDeterministicPreflight,
} from './run-genui-feasibility-study.mjs';
import { finalizeEvidence } from './finalize-genui-feasibility-study.mjs';
import { buildManifest } from './build-genui-feasibility-manifest.mjs';

const SCHEDULE = [
  { caseId: 'orders-pending-attention', slotId: 0, seed: 1701 },
  { caseId: 'orders-pending-attention', slotId: 1, seed: 1702 },
  { caseId: 'orders-pending-attention', slotId: 2, seed: 1703 },
  { caseId: 'inventory-low-stock', slotId: 0, seed: 1701 },
  { caseId: 'inventory-low-stock', slotId: 1, seed: 1702 },
  { caseId: 'inventory-low-stock', slotId: 2, seed: 1703 },
  { caseId: 'incidents-critical-resolution', slotId: 0, seed: 1701 },
  { caseId: 'incidents-critical-resolution', slotId: 1, seed: 1702 },
  { caseId: 'incidents-critical-resolution', slotId: 2, seed: 1703 },
];

const MANIFEST = {
  manifestVersion: 1,
  studyId: 'genui-local-v1',
  schedule: SCHEDULE,
  decisionRule: {
    positive: 'all_checks_pass_and_each_fixture_has_success',
  },
};

const PREFLIGHT = {
  passed: true,
  checks: [{ command: 'deterministic-check', exitCode: 0 }],
};

test('provider-disabled finalization classifies interruption and every later slot', () => {
  let providerCalls = 0;
  const evidence = finalizeEvidence({
    manifest: MANIFEST,
    manifestSha256: 'a'.repeat(64),
    frozenCommit: 'b'.repeat(40),
    preflight: PREFLIGHT,
    journal: [
      { kind: 'started', caseId: SCHEDULE[0].caseId, slotId: 0 },
      {
        kind: 'terminal',
        caseId: SCHEDULE[0].caseId,
        slotId: 0,
        result: {
          classification: 'success',
          candidateSha256: 'c'.repeat(64),
          provider: {
            showDetailsSha256: 'e'.repeat(64),
          },
          replayEqual: true,
        },
      },
      { kind: 'started', caseId: SCHEDULE[1].caseId, slotId: 1 },
    ],
    onProviderAccess: () => { providerCalls += 1; },
  });

  assert.equal(providerCalls, 0);
  assert.equal(evidence.decision, 'NOT_YET_FEASIBLE');
  assert.equal(evidence.slots.length, 9);
  assert.equal(evidence.slots[0].classification, 'success');
  assert.equal(evidence.slots[1].classification, 'interrupted');
  assert.equal(evidence.slots[0].provider.showDetailsSha256, 'e'.repeat(64));
  assert.deepEqual(
    evidence.slots.slice(2).map((slot) => slot.classification),
    Array(7).fill('not_run_interrupted'),
  );
});

test('positive decision requires replay equality and one success per fixture', () => {
  const journal = SCHEDULE.flatMap((slot) => [
    { kind: 'started', caseId: slot.caseId, slotId: slot.slotId },
    {
      kind: 'terminal',
      caseId: slot.caseId,
      slotId: slot.slotId,
      result: {
        classification: slot.slotId === 0 ? 'success' : 'provider_failure',
        candidateSha256: slot.slotId === 0 ? 'd'.repeat(64) : null,
        replayEqual: slot.slotId === 0 ? true : null,
      },
    },
  ]);
  journal.push({ kind: 'harness', exitCode: 0, signal: null });
  const evidence = finalizeEvidence({
    manifest: MANIFEST,
    manifestSha256: 'a'.repeat(64),
    frozenCommit: 'b'.repeat(40),
    preflight: PREFLIGHT,
    journal,
  });

  assert.equal(evidence.decision, 'TECHNICALLY_FEASIBLE');
  const replayMismatch = structuredClone(journal);
  replayMismatch[1].result.replayEqual = false;
  assert.equal(finalizeEvidence({
    manifest: MANIFEST,
    manifestSha256: 'a'.repeat(64),
    frozenCommit: 'b'.repeat(40),
    preflight: PREFLIGHT,
    journal: replayMismatch,
  }).decision, 'NOT_YET_FEASIBLE');
  const missingReplay = structuredClone(journal);
  missingReplay[1].result.candidateSha256 = null;
  missingReplay[1].result.replayEqual = null;
  assert.equal(finalizeEvidence({
    manifest: MANIFEST,
    manifestSha256: 'a'.repeat(64),
    frozenCommit: 'b'.repeat(40),
    preflight: PREFLIGHT,
    journal: missingReplay,
  }).decision, 'NOT_YET_FEASIBLE');
  const failedHarness = structuredClone(journal);
  failedHarness.at(-1).exitCode = 1;
  assert.equal(finalizeEvidence({
    manifest: MANIFEST,
    manifestSha256: 'a'.repeat(64),
    frozenCommit: 'b'.repeat(40),
    preflight: PREFLIGHT,
    journal: failedHarness,
  }).decision, 'NOT_YET_FEASIBLE');
  const missingStart = journal.slice(1);
  assert.equal(finalizeEvidence({
    manifest: MANIFEST,
    manifestSha256: 'a'.repeat(64),
    frozenCommit: 'b'.repeat(40),
    preflight: PREFLIGHT,
    journal: missingStart,
  }).decision, 'NOT_YET_FEASIBLE');
  const terminalBeforeStart = structuredClone(journal);
  [terminalBeforeStart[0], terminalBeforeStart[1]] =
    [terminalBeforeStart[1], terminalBeforeStart[0]];
  assert.equal(finalizeEvidence({
    manifest: MANIFEST,
    manifestSha256: 'a'.repeat(64),
    frozenCommit: 'b'.repeat(40),
    preflight: PREFLIGHT,
    journal: terminalBeforeStart,
  }).decision, 'NOT_YET_FEASIBLE');
});

test('execute mode refuses either existing journal or evidence', () => {
  assert.throws(
    () => assertUnusedOutputs({ journalExists: true, evidenceExists: false }),
    /journal already exists/,
  );
  assert.throws(
    () => assertUnusedOutputs({ journalExists: false, evidenceExists: true }),
    /evidence already exists/,
  );
  assert.doesNotThrow(
    () => assertUnusedOutputs({ journalExists: false, evidenceExists: false }),
  );
});

test('run capability is exactly 256 bits from the injected CSPRNG', () => {
  let requestedBytes = null;
  const capability = createRunCapability((size) => {
    requestedBytes = size;
    return Buffer.alloc(size, 0xab);
  });
  assert.equal(requestedBytes, 32);
  assert.equal(capability, 'ab'.repeat(32));
});

test('validation environment removes inherited study state and preserves unrelated keys', () => {
  assert.deepEqual(
    buildValidationEnv(
      {
        PATH: '/bin',
        GENUI_FEASIBILITY_LIVE: '1',
        GENUI_FEASIBILITY_RUN_CAPABILITY: 'ambient-secret',
      },
      {},
    ),
    { PATH: '/bin' },
  );
});

test('validation environment applies explicit manifest study state after isolation', () => {
  assert.deepEqual(
    buildValidationEnv(
      {
        PATH: '/bin',
        GENUI_FEASIBILITY_LIVE: '1',
        CONTROL: 'ambient',
      },
      {
        GENUI_FEASIBILITY_LIVE: '0',
        CONTROL: 'manifest',
      },
    ),
    {
      PATH: '/bin',
      GENUI_FEASIBILITY_LIVE: '0',
      CONTROL: 'manifest',
    },
  );
});

test('deterministic preflight isolates ambient study state at the child process', () => {
  const assertionScript = `
    const assert = require('node:assert/strict');
    assert.equal(process.env.GENUI_FEASIBILITY_LIVE, '0');
    assert.equal(process.env.GENUI_FEASIBILITY_RUN_CAPABILITY, undefined);
    assert.equal(process.env.UNRELATED_PARENT_KEY, 'preserved');
  `;
  const preflight = runDeterministicPreflight(
    [{
      id: 'environment-boundary',
      command: process.execPath,
      args: ['-e', assertionScript],
      cwd: '.',
      env: { GENUI_FEASIBILITY_LIVE: '0' },
    }],
    {
      GENUI_FEASIBILITY_LIVE: '1',
      GENUI_FEASIBILITY_RUN_CAPABILITY: 'ambient-secret',
      UNRELATED_PARENT_KEY: 'preserved',
    },
  );

  assert.equal(preflight.passed, true);
  assert.equal(preflight.checks[0].exitCode, 0);
});

test('manifest builder freezes nine slots, provider identity, inputs, and validation commands without generation', async () => {
  let identityReads = 0;
  const identity = {
    lookupTag: 'gemma4:4b',
    modelManifestSha256: 'a'.repeat(64),
    showDetailsSha256: 'b'.repeat(64),
    ollamaVersion: '0.1.2',
    templateSha256: 'c'.repeat(64),
    parametersSha256: 'd'.repeat(64),
  };
  const manifest = await buildManifest({
    model: identity.lookupTag,
    verifyRepository: () => 'frozen-commit',
    readIdentity: async (model) => {
      identityReads += 1;
      assert.equal(model, identity.lookupTag);
      return identity;
    },
  });

  assert.equal(identityReads, 1);
  assert.equal(manifest.sourceCommit, 'frozen-commit');
  assert.deepEqual(manifest.modelIdentity, identity);
  assert.deepEqual(manifest.schedule, SCHEDULE);
  assert.equal(manifest.validationCommands.length, 7);
  assert.equal(Object.keys(manifest.inputDigests).length, 7);
  for (const digest of Object.values(manifest.inputDigests)) {
    assert.match(digest, /^[0-9a-f]{64}$/);
  }
});
