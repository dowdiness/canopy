import {
  capabilitiesJsonForFixture,
  getFeasibilityFixture,
  normalizedDatasetJsonForFixture,
} from './genui-feasibility-fixtures.js';
import { recordedFeasibilityCandidateJson } from './genui-recorded-candidates.js';

export function recordedDemoInput(caseId) {
  const fixture = getFeasibilityFixture(caseId);
  return Object.freeze({
    fixture,
    candidateJson: recordedFeasibilityCandidateJson(caseId),
    capabilitiesJson: capabilitiesJsonForFixture(fixture),
    datasetJson: normalizedDatasetJsonForFixture(fixture),
  });
}

export function buildLiveStudyRequest({ studyId, runCapability, caseId, slotId }) {
  if (typeof studyId !== 'string' || studyId.length === 0) {
    throw new Error('studyId must be a non-empty string');
  }
  if (typeof runCapability !== 'string' || !/^[0-9a-f]{64}$/.test(runCapability)) {
    throw new Error('runCapability must be a 256-bit lowercase hexadecimal value');
  }
  getFeasibilityFixture(caseId);
  if (!Number.isInteger(slotId) || slotId < 0 || slotId > 2) {
    throw new Error('slotId must be 0, 1, or 2');
  }
  return Object.freeze({ studyId, runCapability, caseId, slotId });
}
