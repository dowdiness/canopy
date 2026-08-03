import assert from 'node:assert/strict'
import test from 'node:test'

import { runFeasibilityCandidate } from './genui-feasibility-flow.js'

const fixture = Object.freeze({
  capabilitiesJson: '{"bindings":[]}',
  datasetJson: '{"rows":[]}',
})

const terminalClassifications = [
  'candidate_decode_error',
  'capability_decode_error',
  'candidate_validation_error',
  'dataset_decode_error',
  'materialization_error',
  'rubric_failure',
  'commit_failure',
  'replay_mismatch',
  'success',
]

test('evaluate mode invokes only evaluate once with opaque candidate bytes', async () => {
  const calls = []
  const expected = {
    classification: 'candidate_decode_error',
    evidence: { matched_stable_keys: ['opaque'] },
    rubric: { passed: false, reasons: ['decode'] },
    safe_output_sha256: 'digest',
    session: null,
  }
  const result = await runFeasibilityCandidate({
    mode: 'evaluate',
    candidateJson: 'not candidate json',
    fixture,
    evaluateCandidate(candidateJson, capabilitiesJson, datasetJson) {
      calls.push({ candidateJson, capabilitiesJson, datasetJson })
      return JSON.stringify(expected)
    },
    commitCandidate() {
      assert.fail('commit callback must not run in evaluate mode')
    },
  })

  assert.deepEqual(calls, [{
    candidateJson: 'not candidate json',
    capabilitiesJson: fixture.capabilitiesJson,
    datasetJson: fixture.datasetJson,
  }])
  assert.deepEqual(result, expected)
})

test('commit mode invokes only commit once with opaque candidate bytes', async () => {
  const calls = []
  const expected = {
    classification: 'success',
    evidence: { matched_stable_keys: ['ord-1002', 'ord-1006'] },
    rubric: { passed: true, reasons: [] },
    safe_output_sha256: 'digest',
    session: { success: true, revision: 2 },
  }
  const result = await runFeasibilityCandidate({
    mode: 'commit',
    candidateJson: '{opaque candidate bytes',
    fixture,
    evaluateCandidate() {
      assert.fail('evaluate callback must not run in commit mode')
    },
    commitCandidate(candidateJson, capabilitiesJson, datasetJson) {
      calls.push({ candidateJson, capabilitiesJson, datasetJson })
      return JSON.stringify(expected)
    },
  })

  assert.deepEqual(calls, [{
    candidateJson: '{opaque candidate bytes',
    capabilitiesJson: fixture.capabilitiesJson,
    datasetJson: fixture.datasetJson,
  }])
  assert.deepEqual(result, expected)
})

test('all MoonBit terminal envelopes remain unchanged', async () => {
  for (const classification of terminalClassifications) {
    const expected = {
      classification,
      message: `message:${classification}`,
      evidence: { matched_stable_keys: ['stable'], summary: { field: 'amount', aggregation: 'sum', value: 7 } },
      rubric: { passed: classification === 'success', reasons: [`reason:${classification}`] },
      safe_output_sha256: `sha:${classification}`,
      session: { success: classification === 'success', revision: 7, error: { code: classification } },
    }
    const actual = await runFeasibilityCandidate({
      mode: 'evaluate',
      candidateJson: classification,
      fixture,
      evaluateCandidate: () => JSON.stringify(expected),
      commitCandidate: () => assert.fail('commit callback must not run'),
    })
    assert.deepEqual(actual, expected)
  }
})

test('invalid modes fail before either callback runs', async () => {
  let calls = 0
  await assert.rejects(
    runFeasibilityCandidate({
      mode: 'unknown',
      candidateJson: '{}',
      fixture,
      evaluateCandidate: () => { calls += 1 },
      commitCandidate: () => { calls += 1 },
    }),
    /mode must be "evaluate" or "commit"/,
  )
  assert.equal(calls, 0)
})
