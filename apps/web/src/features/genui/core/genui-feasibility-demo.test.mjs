import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildLiveStudyRequest,
  recordedDemoInput,
} from './genui-feasibility-demo.js';
import { GENUI_FEASIBILITY_FIXTURES } from './genui-feasibility-fixtures.js';

const RUN_CAPABILITY = 'a'.repeat(64);

test('recorded demo inputs freeze candidate, capabilities, and normalized dataset per case', () => {
  for (const fixture of GENUI_FEASIBILITY_FIXTURES) {
    const input = recordedDemoInput(fixture.caseId);
    assert.equal(input.fixture, fixture);
    assert.equal(JSON.parse(input.candidateJson).type, 'component');
    assert.equal(JSON.parse(input.capabilitiesJson).bindings[0].name, fixture.binding);
    assert.equal(JSON.parse(input.datasetJson).case_id, fixture.caseId);
    assert.equal(Object.isFrozen(input), true);
  }
});

test('recorded demo rejects unknown cases before MoonBit evaluation', () => {
  assert.throws(() => recordedDemoInput('missing-case'), /Unknown feasibility case/);
});

test('live study request has the exact provider gate shape', () => {
  const request = buildLiveStudyRequest({
    studyId: 'genui-local-v1',
    runCapability: RUN_CAPABILITY,
    caseId: 'orders-pending-attention',
    slotId: 2,
  });
  assert.deepEqual(Object.keys(request).sort(), ['caseId', 'runCapability', 'slotId', 'studyId']);
  assert.deepEqual(request, {
    studyId: 'genui-local-v1',
    runCapability: RUN_CAPABILITY,
    caseId: 'orders-pending-attention',
    slotId: 2,
  });
  assert.equal(Object.isFrozen(request), true);
});

test('live study request rejects invalid authority and slots', () => {
  assert.throws(
    () => buildLiveStudyRequest({ studyId: '', runCapability: RUN_CAPABILITY, caseId: 'orders-pending-attention', slotId: 0 }),
    /studyId/,
  );
  assert.throws(
    () => buildLiveStudyRequest({ studyId: 'genui-local-v1', runCapability: 'bad', caseId: 'orders-pending-attention', slotId: 0 }),
    /runCapability/,
  );
  assert.throws(
    () => buildLiveStudyRequest({ studyId: 'genui-local-v1', runCapability: RUN_CAPABILITY, caseId: 'orders-pending-attention', slotId: 3 }),
    /slotId/,
  );
});
