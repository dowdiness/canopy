export async function runFeasibilityCandidate({
  mode,
  candidateJson,
  fixture,
  evaluateCandidate,
  commitCandidate,
}) {
  if (mode !== 'evaluate' && mode !== 'commit') {
    throw new Error('mode must be "evaluate" or "commit"')
  }

  const invoke = mode === 'evaluate' ? evaluateCandidate : commitCandidate
  const response = await invoke(
    candidateJson,
    fixture.capabilitiesJson,
    fixture.datasetJson,
  )
  return typeof response === 'string' ? JSON.parse(response) : response
}
