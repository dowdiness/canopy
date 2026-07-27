import assert from 'node:assert/strict';
import test from 'node:test';
import {
  evaluateWakuReleaseCandidate,
  REQUIRED_WAKU_JOBS,
} from './waku-release-gate-core.mjs';

const headSha = '0123456789abcdef0123456789abcdef01234567';
const artifactSha256 = 'a'.repeat(64);
const configSha256 = 'b'.repeat(64);

function greenFacts() {
  return {
    run: {
      workflowName: 'CI',
      workflowPath: '.github/workflows/ci.yml',
      event: 'push',
      branch: 'main',
      status: 'completed',
      conclusion: 'success',
      repository: 'dowdiness/canopy',
      headSha,
      runId: '123456',
      runAttempt: '2',
      createdAt: '2026-07-27T00:00:00.000Z',
    },
    jobs: REQUIRED_WAKU_JOBS.map((name) => ({
      name,
      runId: '123456',
      runAttempt: '2',
      headSha,
      status: 'completed',
      conclusion: 'success',
    })),
    artifacts: [
      {
        name: 'waku-web-build-2',
        runId: '123456',
        runAttempt: '2',
        headSha,
        expired: false,
      },
      {
        name: 'waku-web-release-manifest-2',
        runId: '123456',
        runAttempt: '2',
        headSha,
        expired: false,
      },
    ],
    manifest: {
      schema: 'canopy.waku-release.v1',
      repository: 'dowdiness/canopy',
      headSha,
      runId: '123456',
      runAttempt: '2',
      tools: { waku: '1.0.0-beta.8', wrangler: '4.114.0' },
      artifact: { root: 'dist', sha256: artifactSha256 },
      config: { path: 'wrangler.waku.jsonc', sha256: configSha256 },
    },
    verifiedArtifactSha256: artifactSha256,
    verifiedConfigSha256: configSha256,
    checkedOutSha: headSha,
    mainTipSha: headSha,
    protectedEnvironment: true,
    evaluatedAt: '2026-07-28T00:00:00.000Z',
  };
}

test('accepts only one exact-green, same-commit, protected release candidate', () => {
  assert.deepEqual(evaluateWakuReleaseCandidate(greenFacts()), {
    ok: true,
    failures: [],
  });
});

test('rejects workflow identity and every non-success Waku job conclusion', () => {
  const wrongWorkflow = greenFacts();
  wrongWorkflow.run.event = 'workflow_dispatch';
  wrongWorkflow.run.branch = 'release';
  wrongWorkflow.run.conclusion = 'failure';
  const workflowResult = evaluateWakuReleaseCandidate(wrongWorkflow);
  assert.equal(workflowResult.ok, false);
  assert.deepEqual(workflowResult.failures.slice(0, 3), [
    'workflow.event',
    'workflow.branch',
    'workflow.conclusion',
  ]);

  const wrongFixedIdentity = greenFacts();
  wrongFixedIdentity.run.workflowPath = '.github/workflows/release.yml';
  wrongFixedIdentity.run.repository = 'fork/canopy';
  wrongFixedIdentity.manifest.repository = 'fork/canopy';
  const fixedIdentityResult = evaluateWakuReleaseCandidate(wrongFixedIdentity);
  for (const expected of [
    'workflow.path',
    'workflow.repository',
    'manifest.repository',
  ]) {
    assert.ok(fixedIdentityResult.failures.includes(expected), expected);
  }

  for (const conclusion of ['skipped', 'failure', 'cancelled', 'neutral', 'timed_out']) {
    const facts = greenFacts();
    facts.jobs[1].conclusion = conclusion;
    const result = evaluateWakuReleaseCandidate(facts);
    assert.equal(result.ok, false, conclusion);
    assert.ok(result.failures.includes(`job.not_success:${REQUIRED_WAKU_JOBS[1]}`));
  }

  const duplicate = greenFacts();
  duplicate.jobs.push({ ...duplicate.jobs[0] });
  assert.ok(evaluateWakuReleaseCandidate(duplicate).failures.includes(
    `job.missing_or_duplicate:${REQUIRED_WAKU_JOBS[0]}`,
  ));

  const crossAttemptJob = greenFacts();
  crossAttemptJob.jobs[2].runAttempt = '1';
  assert.ok(evaluateWakuReleaseCandidate(crossAttemptJob).failures.includes(
    `job.identity:${REQUIRED_WAKU_JOBS[2]}`,
  ));
});

test('rejects ambiguous, expired, or cross-attempt artifacts', () => {
  const duplicate = greenFacts();
  duplicate.artifacts.push({ ...duplicate.artifacts[0] });
  assert.ok(evaluateWakuReleaseCandidate(duplicate).failures.includes(
    'artifact.missing_or_duplicate:waku-web-build-2',
  ));

  const expired = greenFacts();
  expired.artifacts[0].expired = true;
  assert.ok(evaluateWakuReleaseCandidate(expired).failures.includes(
    'artifact.expired:waku-web-build-2',
  ));

  const wrongAttempt = greenFacts();
  wrongAttempt.artifacts[1].runAttempt = '1';
  assert.ok(evaluateWakuReleaseCandidate(wrongAttempt).failures.includes(
    'artifact.identity:waku-web-release-manifest-2',
  ));
});

test('rejects manifest, checkout, main tip, environment, and age drift', () => {
  const facts = greenFacts();
  facts.manifest.headSha = 'f'.repeat(40);
  facts.manifest.tools.wrangler = '4.113.0';
  facts.manifest.artifact.root = 'other';
  facts.manifest.config.path = 'other.jsonc';
  facts.verifiedArtifactSha256 = 'c'.repeat(64);
  facts.verifiedConfigSha256 = 'd'.repeat(64);
  facts.checkedOutSha = 'e'.repeat(40);
  facts.mainTipSha = 'd'.repeat(40);
  facts.protectedEnvironment = false;
  facts.evaluatedAt = '2026-09-01T00:00:00.000Z';

  const result = evaluateWakuReleaseCandidate(facts);
  for (const expected of [
    'manifest.head_sha',
    'manifest.tools',
    'manifest.artifact_digest',
    'manifest.config_digest',
    'checkout.sha',
    'main.sha',
    'environment.unprotected',
    'candidate.age',
  ]) {
    assert.ok(result.failures.includes(expected), expected);
  }
});
