import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { expect, test } from '@playwright/test';

test('minimal provider candidate reaches unchanged commit path', async ({ page }) => {
  const runRoot = process.env.GENUI_MINIMAL_PROVIDER_RUN_DIR;
  if (!runRoot) throw new Error('GENUI_MINIMAL_PROVIDER_RUN_DIR is required');
  const request = JSON.parse(await readFile(join(runRoot, 'request.json'), 'utf8'));
  const candidateJson = await readFile(join(runRoot, 'candidate.json'), 'utf8');

  await page.goto('/genui.html');
  const result = await page.evaluate(
    ({ caseId, candidateJson }) => window.__canopyGenUiFeasibilityTest.commitSavedCandidate({ caseId, candidateJson }),
    { caseId: request.fixtureId, candidateJson },
  );

  await writeFile(join(runRoot, 'browser-result.json'), `${JSON.stringify(result, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
  expect(typeof result.classification).toBe('string');
});
