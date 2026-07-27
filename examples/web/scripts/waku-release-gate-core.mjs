export const REQUIRED_WAKU_JOBS = Object.freeze([
  'All Checks Passed',
  'Build Waku Web Foundation',
  'Waku Web Foundation E2E',
  'Waku Worker Foundation Smoke',
]);

const MAX_CANDIDATE_AGE_MS = 30 * 24 * 60 * 60 * 1_000;
const EXPECTED_REPOSITORY = 'dowdiness/canopy';
const EXPECTED_WORKFLOW_PATH = '.github/workflows/ci.yml';
const EXPECTED_WAKU_VERSION = '1.0.0-beta.8';
const EXPECTED_WRANGLER_VERSION = '4.114.0';

export function evaluateWakuReleaseCandidate(facts) {
  const failures = [];
  const run = facts.run ?? {};
  const jobs = Array.isArray(facts.jobs) ? facts.jobs : [];
  const artifacts = Array.isArray(facts.artifacts) ? facts.artifacts : [];
  const manifest = facts.manifest ?? {};

  const requireFact = (condition, code) => {
    if (!condition) failures.push(code);
  };

  requireFact(run.workflowName === 'CI', 'workflow.name');
  requireFact(run.workflowPath === EXPECTED_WORKFLOW_PATH, 'workflow.path');
  requireFact(run.repository === EXPECTED_REPOSITORY, 'workflow.repository');
  requireFact(run.event === 'push', 'workflow.event');
  requireFact(run.branch === 'main', 'workflow.branch');
  requireFact(run.status === 'completed', 'workflow.status');
  requireFact(run.conclusion === 'success', 'workflow.conclusion');
  requireFact(/^[0-9a-f]{40}$/.test(run.headSha ?? ''), 'identity.head_sha');
  requireFact(/^\d+$/.test(run.runId ?? '') && run.runId !== '0', 'identity.run_id');
  requireFact(
    /^\d+$/.test(run.runAttempt ?? '') && run.runAttempt !== '0',
    'identity.run_attempt',
  );

  for (const requiredJob of REQUIRED_WAKU_JOBS) {
    const matches = jobs.filter((job) => job.name === requiredJob);
    requireFact(matches.length === 1, `job.missing_or_duplicate:${requiredJob}`);
    if (matches.length === 1) {
      requireFact(
        matches[0].runId === run.runId &&
        matches[0].runAttempt === run.runAttempt &&
        matches[0].headSha === run.headSha,
        `job.identity:${requiredJob}`,
      );
      requireFact(
        matches[0].status === 'completed' && matches[0].conclusion === 'success',
        `job.not_success:${requiredJob}`,
      );
    }
  }

  for (const artifactName of [
    `waku-web-build-${run.runAttempt}`,
    `waku-web-release-manifest-${run.runAttempt}`,
  ]) {
    const matches = artifacts.filter((artifact) => artifact.name === artifactName);
    requireFact(matches.length === 1, `artifact.missing_or_duplicate:${artifactName}`);
    if (matches.length === 1) {
      const artifact = matches[0];
      requireFact(artifact.expired === false, `artifact.expired:${artifactName}`);
      requireFact(
        artifact.runId === run.runId &&
        artifact.runAttempt === run.runAttempt &&
        artifact.headSha === run.headSha,
        `artifact.identity:${artifactName}`,
      );
    }
  }

  requireFact(manifest.schema === 'canopy.waku-release.v1', 'manifest.schema');
  requireFact(
    manifest.repository === EXPECTED_REPOSITORY &&
    manifest.repository === run.repository,
    'manifest.repository',
  );
  requireFact(manifest.headSha === run.headSha, 'manifest.head_sha');
  requireFact(manifest.runId === run.runId, 'manifest.run_id');
  requireFact(manifest.runAttempt === run.runAttempt, 'manifest.run_attempt');
  requireFact(
    manifest.tools?.waku === EXPECTED_WAKU_VERSION &&
    manifest.tools?.wrangler === EXPECTED_WRANGLER_VERSION,
    'manifest.tools',
  );
  requireFact(
    manifest.artifact?.root === 'dist' &&
    /^[0-9a-f]{64}$/.test(manifest.artifact?.sha256 ?? '') &&
    facts.verifiedArtifactSha256 === manifest.artifact?.sha256,
    'manifest.artifact_digest',
  );
  requireFact(
    manifest.config?.path === 'wrangler.waku.jsonc' &&
    /^[0-9a-f]{64}$/.test(manifest.config?.sha256 ?? '') &&
    facts.verifiedConfigSha256 === manifest.config?.sha256,
    'manifest.config_digest',
  );

  requireFact(facts.checkedOutSha === run.headSha, 'checkout.sha');
  requireFact(facts.mainTipSha === run.headSha, 'main.sha');
  requireFact(facts.protectedEnvironment === true, 'environment.unprotected');

  const createdAt = Date.parse(run.createdAt ?? '');
  const evaluatedAt = Date.parse(facts.evaluatedAt ?? '');
  requireFact(
    Number.isFinite(createdAt) &&
    Number.isFinite(evaluatedAt) &&
    evaluatedAt >= createdAt &&
    evaluatedAt - createdAt <= MAX_CANDIDATE_AGE_MS,
    'candidate.age',
  );

  return Object.freeze({
    ok: failures.length === 0,
    failures: Object.freeze(failures),
  });
}
