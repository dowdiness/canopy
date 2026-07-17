#!/usr/bin/env node

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, isAbsolute } from 'node:path';
import { pathToFileURL } from 'node:url';
import { verifyBuilderRepository } from './build-genui-feasibility-manifest.mjs';
import { buildComparisonSchedule } from './genui-provider-comparison.mjs';
import { canonicalJson } from '../src/genui-feasibility-provider.js';
import { createHash } from 'node:crypto';

const STUDY_ID = 'genui-provider-comparison-v1';
const MANIFEST_VERSION = 1;
const PROVIDER_ORDER = Object.freeze(['ollama', 'codex']);
const DIAGNOSTIC_STEPS = Object.freeze([
  'environment_and_model',
  'load_without_generation',
  'minimal_text',
  'json_object',
  'unrelated_json_schema',
  'candidate_schema_synthetic',
  'trusted_fixtures',
]);
const INPUT_DIGEST_FIELDS = Object.freeze([
  'candidateSchemaSha256',
  'fixturesSha256',
  'capabilitiesSha256',
  'promptSha256',
  'rubricSourceSha256',
  'preparationCoreSourceSha256',
  'validationCommandsSha256',
]);
const HEX_SHA256 = /^[0-9a-f]{64}$/u;
const HEX_COMMIT = /^[0-9a-f]{40}$/u;
const PRIVATE_RUN_ROOT = '$XDG_STATE_HOME/canopy/genui-provider-benchmark/<run-id>/';

export function buildComparisonManifest(input, deps = {}) {
  const verifyRepository = deps.verifyRepository ?? verifyBuilderRepository;
  const sourceCommit = verifyRepository();
  requireCommit(sourceCommit);
  requireObject(input, 'manifest input');
  requireBranch(input.branch);
  validateDiagnostic(input);
  validateFixtures(input.fixtures);
  validateInputDigests(input.inputDigests);
  validateProviderIdentities(input.providerIdentities);
  validateProviderContracts(input.providerContracts);
  validateLimits(input.branch, input.limits);
  validateCommands(input.validationCommands);
  validateArtifacts(input.artifactContract);

  const schedule = buildComparisonSchedule({
    fixtures: input.fixtures,
    repeats: input.repeats,
    randomizationSeed: input.randomizationSeed,
    ollamaSeeds: input.ollamaSeeds,
    branch: input.branch,
  }).map(({ seed, ...slot }) => ({
    ...slot,
    ollamaSeed: seed ?? null,
  }));

  if (input.limits.slotPositions !== schedule.length) {
    throw manifestError('limit_invalid', 'The slot-position limit must equal the frozen schedule length.');
  }

  const manifest = {
    manifestVersion: MANIFEST_VERSION,
    studyId: STUDY_ID,
    claimScope: 'engineering provider benchmark only; it does not establish user value or model superiority.',
    sourceCommit,
    diagnosticSummarySha256: input.diagnosticSummarySha256,
    branch: input.branch,
    providerOrder: [...PROVIDER_ORDER],
    fixtures: input.fixtures,
    repeats: input.repeats,
    randomizationSeed: input.randomizationSeed,
    ollamaSeeds: input.ollamaSeeds,
    schedule,
    decisionRule: {
      noRetry: true,
      replayRequiredForEveryCandidate: true,
      stage1Slots: 18,
      stage2RequiresEligibleStage1: true,
      pairedStage1ActiveAttempts: 18,
      codexOnlyStage1ActiveAttempts: 9,
      qualificationOverallMinimum: 23,
      qualificationPerFixtureMinimum: 6,
      zeroToleranceFailures: true,
    },
    inputDigests: input.inputDigests,
    providerIdentities: input.providerIdentities,
    providerContracts: input.providerContracts,
    limits: input.limits,
    validationCommands: input.validationCommands,
    artifacts: input.artifactContract,
  };
  const frozen = deepFreeze(copyJson(manifest));
  rejectHostPaths(JSON.stringify(frozen));
  return frozen;
}

export async function writeComparisonManifest({ outputPath, input }, deps = {}) {
  if (typeof outputPath !== 'string' || outputPath.length === 0) {
    throw manifestError('output_invalid', 'A manifest output path is required.');
  }
  const manifest = buildComparisonManifest(input, deps);
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(manifest, null, 2)}\n`, {
    encoding: 'utf8',
    flag: 'wx',
    mode: 0o644,
  });
  return manifest;
}

function validateDiagnostic(input) {
  requireObject(input.diagnosticSummary, 'diagnostic summary');
  requireDigest(input.diagnosticSummarySha256, 'diagnostic summary digest');
  const summary = input.diagnosticSummary;
  for (const field of ['terminal', 'complete', 'safe', 'identityPreserved', 'evidenceIntegrity', 'credentialsSafe', 'budgetSafe', 'isolationSafe', 'requestSettingsFrozen']) {
    if (summary[field] !== true) {
      throw manifestError('diagnostic_unsafe', `Diagnostic safety, integrity, credential, budget, or isolation gate ${field} must be true before manifest creation.`);
    }
  }
  if (summary.selectedBranch !== input.branch) {
    throw manifestError('branch_mismatch', 'The requested branch does not match the diagnostic decision.');
  }
  if (!Array.isArray(summary.probeOrder) || summary.probeOrder.length === 0) {
    throw manifestError('diagnostic_incomplete', 'The diagnostic probe order is missing.');
  }
  const expectedPrefix = DIAGNOSTIC_STEPS.slice(0, summary.probeOrder.length);
  if (JSON.stringify(summary.probeOrder) !== JSON.stringify(expectedPrefix)) {
    throw manifestError('diagnostic_order', 'The diagnostic probes are not the frozen ordered prefix.');
  }
  requireDigest(summary.requestDigest, 'diagnostic request digest');

  if (input.branch === 'paired') {
    if (summary.probeOrder.length !== DIAGNOSTIC_STEPS.length || summary.qualifiedForComparison !== true || summary.firstFailure !== null) {
      throw manifestError('diagnostic_incomplete', 'The paired branch requires all seven diagnostic probes and passing qualification.');
    }
    const expectedFixtureIds = input.fixtures?.map((fixture) => fixture.id);
    if (JSON.stringify(summary.fixtureIds) !== JSON.stringify(expectedFixtureIds)) {
      throw manifestError('diagnostic_fixture_mismatch', 'The diagnostic fixture identities do not match the manifest fixtures.');
    }
  } else {
    if (summary.qualifiedForComparison !== false) {
      throw manifestError('diagnostic_branch', 'The codex_only branch requires a terminal Ollama qualification failure.');
    }
    requireObject(summary.firstFailure, 'diagnostic first failure');
    if (summary.firstFailure.step !== summary.probeOrder.at(-1) || typeof summary.firstFailure.classification !== 'string') {
      throw manifestError('diagnostic_failure', 'The diagnostic first failure must identify the terminal probe and classification.');
    }
    if (!Array.isArray(summary.fixtureIds) || summary.fixtureIds.length !== 0) {
      throw manifestError('diagnostic_fixture_mismatch', 'A pre-qualification Ollama failure cannot claim fixture qualification.');
    }
  }
  validateDiagnosticObservations(summary, input);
  const actualDigest = sha256(canonicalJson(summary));
  if (actualDigest !== input.diagnosticSummarySha256) {
    throw manifestError('diagnostic_digest_mismatch', 'The diagnostic summary digest does not match its content.');
  }
}

function validateDiagnosticObservations(summary, input) {
  if (!Array.isArray(summary.observations)) {
    throw manifestError('diagnostic_observations', 'The diagnostic observations are missing.');
  }
  const fixtureIds = input.fixtures?.map((fixture) => fixture.id) ?? [];
  const expected = [];
  for (const step of summary.probeOrder) {
    if (step !== 'trusted_fixtures') {
      expected.push({ step, fixtureId: null });
      continue;
    }
    const trustedCount = input.branch === 'paired'
      ? fixtureIds.length
      : summary.observations.length - expected.length;
    if (trustedCount < 1 || trustedCount > fixtureIds.length) {
      throw manifestError('diagnostic_observations', 'The trusted-fixture diagnostic observations are incomplete.');
    }
    for (const fixtureId of fixtureIds.slice(0, trustedCount)) {
      expected.push({ step, fixtureId });
    }
  }
  if (summary.observations.length !== expected.length) {
    throw manifestError('diagnostic_observations', 'The diagnostic observations do not cover the frozen probe sequence exactly once.');
  }
  for (let index = 0; index < expected.length; index += 1) {
    const observation = summary.observations[index];
    requireObject(observation, `diagnostic observation ${index}`);
    if (observation.step !== expected[index].step || observation.fixtureId !== expected[index].fixtureId) {
      throw manifestError('diagnostic_observations', 'The diagnostic observation order or fixture identity does not match the frozen sequence.');
    }
    if (typeof observation.classification !== 'string' || observation.classification.length === 0) {
      throw manifestError('diagnostic_observations', 'Every diagnostic observation requires a terminal classification.');
    }
    for (const field of ['requestSettingsSha256', 'requestSha256', 'responseSha256', 'serverLogSha256']) {
      requireDigest(observation[field], `diagnostic observation ${field}`);
    }
    for (const field of ['requestBytes', 'responseBytes', 'serverLogBytes']) {
      if (!Number.isInteger(observation[field]) || observation[field] < 0) {
        throw manifestError('diagnostic_observations', `Diagnostic observation ${field} must be a non-negative integer.`);
      }
    }
    const isRetainedTerminalFailure = input.branch === 'codex_only'
      && index === expected.length - 1
      && (observation.classification === summary.firstFailure.classification
        || observation.preparationClassification === summary.firstFailure.classification);
    if (['candidate_schema_synthetic', 'trusted_fixtures'].includes(observation.step)
      && observation.requestSettingsSha256 !== summary.requestDigest
      && !isRetainedTerminalFailure) {
      throw manifestError('diagnostic_request_mismatch', 'The diagnostic request settings do not match the frozen request digest.');
    }
    if (input.branch === 'paired' && observation.classification !== 'pass') {
      throw manifestError('diagnostic_observations', 'Paired qualification requires every diagnostic observation to pass.');
    }
    if (observation.step === 'trusted_fixtures'
      && observation.preparationClassification !== 'candidate_pass'
      && !isRetainedTerminalFailure) {
      throw manifestError('diagnostic_preparation', 'Every trusted fixture must pass the unchanged preparation pipeline.');
    }
  }
  if (input.branch === 'codex_only') {
    const last = summary.observations.at(-1);
    const retainedFailure = last?.classification === summary.firstFailure.classification
      || last?.preparationClassification === summary.firstFailure.classification;
    if (!retainedFailure) {
      throw manifestError('diagnostic_failure', 'The final diagnostic observation does not retain the first failure classification.');
    }
  }
  if (summary.runtimeControl !== null) {
    requireObject(summary.runtimeControl, 'diagnostic runtime control');
    if (typeof summary.runtimeControl.model !== 'string' || summary.runtimeControl.model.length === 0
      || typeof summary.runtimeControl.classification !== 'string' || summary.runtimeControl.classification.length === 0) {
      throw manifestError('diagnostic_runtime_control', 'The runtime control requires model identity and classification.');
    }
    for (const field of ['requestSha256', 'responseSha256', 'serverLogSha256']) {
      requireDigest(summary.runtimeControl[field], `diagnostic runtime control ${field}`);
    }
  }
}

function validateFixtures(fixtures) {
  if (!Array.isArray(fixtures) || fixtures.length !== 3) {
    throw manifestError('fixture_invalid', 'Exactly three frozen fixtures are required.');
  }
  const ids = new Set();
  for (const fixture of fixtures) {
    requireObject(fixture, 'fixture');
    if (typeof fixture.id !== 'string' || fixture.id.length === 0 || ids.has(fixture.id)) {
      throw manifestError('fixture_invalid', 'Fixture IDs must be non-empty and unique.');
    }
    requireDigest(fixture.digest, `fixture ${fixture.id} digest`);
    ids.add(fixture.id);
  }
}

function validateInputDigests(digests) {
  requireObject(digests, 'input digests');
  for (const field of INPUT_DIGEST_FIELDS) requireDigest(digests[field], field);
  if (Object.keys(digests).length !== INPUT_DIGEST_FIELDS.length) {
    throw manifestError('digest_invalid', 'The input digest set must contain only the frozen fields.');
  }
}

function validateProviderIdentities(identities) {
  requireObject(identities, 'provider identities');
  requireObject(identities.ollama, 'Ollama identity');
  requireString(identities.ollama.lookupTag, 'Ollama lookup tag');
  requireString(identities.ollama.ollamaVersion, 'Ollama version');
  for (const field of ['modelManifestSha256', 'showDetailsSha256', 'templateSha256', 'parametersSha256']) {
    requireDigest(identities.ollama[field], `Ollama ${field}`);
  }
  requireObject(identities.codex, 'Codex identity');
  for (const field of ['cliVersion', 'modelSlug', 'reasoningEffort', 'authMode']) {
    requireString(identities.codex[field], `Codex ${field}`);
  }
  requireDigest(identities.codex.catalogEntrySha256, 'Codex catalog entry digest');
  if (identities.codex.reasoningEffort !== 'medium') {
    throw manifestError('identity_invalid', 'The frozen Codex reasoning effort must be medium.');
  }
}

function validateProviderContracts(contracts) {
  requireObject(contracts, 'provider contracts');
  requireObject(contracts.ollama, 'Ollama contract');
  if (contracts.ollama.stream !== false || contracts.ollama.temperature !== 0.2 ||
      contracts.ollama.numCtx !== 4096 || contracts.ollama.numPredict !== 512 || contracts.ollama.keepAlive !== '5m') {
    throw manifestError('contract_invalid', 'The Ollama request contract differs from the frozen settings.');
  }
  requireObject(contracts.codex, 'Codex contract');
  if (contracts.codex.transport !== 'stdio-jsonl' || contracts.codex.experimentalApi !== true ||
      contracts.codex.allowProviderModelFallback !== false) {
    throw manifestError('contract_invalid', 'The Codex protocol contract differs from the reviewed settings.');
  }
  requireObject(contracts.sandbox, 'sandbox contract');
  requireString(contracts.sandbox.bubblewrapVersion, 'bubblewrap version');
  requireDigest(contracts.sandbox.configSha256, 'sandbox config digest');
  if (contracts.sandbox.repositoryMounted !== false || contracts.sandbox.hostHomeMounted !== false) {
    throw manifestError('isolation_invalid', 'The sandbox must not mount the repository or host home.');
  }
}

function validateLimits(branch, limits) {
  requireObject(limits, 'limits');
  const activeRequests = branch === 'paired' ? 60 : 30;
  for (const field of ['slotPositions', 'activeRequests', 'maxCandidateBytes', 'slotWallTimeMs', 'perRequestTokenCeiling', 'runTokenCeiling', 'runWallTimeMs']) {
    requirePositiveInteger(limits[field], `limit ${field}`);
  }
  if (limits.activeRequests !== activeRequests || limits.slotPositions !== 60 || limits.maxCandidateBytes !== 65_536) {
    throw manifestError('limit_invalid', 'Branch request, slot, or candidate-byte limits are inconsistent.');
  }
  if (limits.perRequestTokenCeiling > 32_000) {
    throw manifestError('token_limit_invalid', 'The per-request token limit must not exceed 32,000.');
  }
  if (limits.runTokenCeiling !== activeRequests * limits.perRequestTokenCeiling) {
    throw manifestError('token_limit_invalid', 'The run token limit must equal the per-request limit times active requests.');
  }
  if (limits.runWallTimeMs !== activeRequests * limits.slotWallTimeMs + 300_000) {
    throw manifestError('limit_invalid', 'The run wall-time limit is inconsistent with the frozen slot budget.');
  }
}

function validateCommands(commands) {
  if (!Array.isArray(commands) || commands.length === 0) {
    throw manifestError('command_invalid', 'At least one validation command is required.');
  }
  const ids = new Set();
  for (const command of commands) {
    requireObject(command, 'validation command');
    for (const field of ['id', 'command', 'cwd']) requireString(command[field], `validation command ${field}`);
    if (ids.has(command.id) || isHostAbsolute(command.cwd) || hasTraversal(command.cwd)) {
      throw manifestError('command_invalid', 'Validation command IDs must be unique and working directories repository-relative.');
    }
    if (!Array.isArray(command.args) || command.args.some((arg) => typeof arg !== 'string')) {
      throw manifestError('command_invalid', 'Validation command arguments must be strings.');
    }
    ids.add(command.id);
  }
}

function validateArtifacts(artifacts) {
  requireObject(artifacts, 'artifact contract');
  if (artifacts.privateRunRoot !== PRIVATE_RUN_ROOT) {
    throw manifestError('raw_artifact_invalid', 'Private raw artifacts must use the logical XDG state run root.');
  }
  requireObject(artifacts.rawArtifacts, 'raw artifact paths');
  for (const path of Object.values(artifacts.rawArtifacts)) {
    requireLogicalRelativePath(path, 'raw artifact path');
    if (!path.startsWith('raw/')) {
      throw manifestError('raw_artifact_invalid', 'Raw artifact paths must remain below the private raw directory.');
    }
  }
  for (const field of ['normalizedTranscript', 'aggregateEvidence']) {
    requireLogicalRelativePath(artifacts[field], `${field} path`);
    if (!artifacts[field].startsWith('docs/evidence/')) {
      throw manifestError('artifact_invalid', 'Reviewable evidence paths must remain below docs/evidence.');
    }
  }
}

function requireLogicalRelativePath(path, field) {
  requireString(path, field);
  if (isHostAbsolute(path) || hasTraversal(path) || path.includes('\\')) {
    throw manifestError('artifact_path_invalid', `${field} must be a portable relative path.`);
  }
}

function isHostAbsolute(path) {
  return isAbsolute(path) || /^[A-Za-z]:[\\/]/u.test(path);
}

function hasTraversal(path) {
  return path.split('/').includes('..');
}

function rejectHostPaths(serialized) {
  if (serialized.includes('/home/') || serialized.includes('/tmp/') || /[A-Za-z]:[\\/]/u.test(serialized)) {
    throw manifestError('artifact_path_invalid', 'The public manifest contains a host-specific absolute path.');
  }
}

function requireBranch(branch) {
  if (!['paired', 'codex_only'].includes(branch)) {
    throw manifestError('branch_invalid', 'Comparison branch must be paired or codex_only.');
  }
}

function requireCommit(value) {
  if (typeof value !== 'string' || !HEX_COMMIT.test(value)) {
    throw manifestError('repository_invalid', 'The source commit must be a full lowercase Git commit SHA.');
  }
}

function requireDigest(value, field) {
  if (typeof value !== 'string' || !HEX_SHA256.test(value)) {
    throw manifestError('digest_invalid', `${field} must be a lowercase SHA-256 digest.`);
  }
}

function requirePositiveInteger(value, field) {
  if (!Number.isInteger(value) || value <= 0) {
    throw manifestError('limit_invalid', `${field} must be a positive integer.`);
  }
}

function requireString(value, field) {
  if (typeof value !== 'string' || value.length === 0) {
    throw manifestError('field_invalid', `${field} must be a non-empty string.`);
  }
}

function requireObject(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw manifestError('field_invalid', `${field} must be an object.`);
  }
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function copyJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function deepFreeze(value) {
  if (!value || typeof value !== 'object' || Object.isFrozen(value)) return value;
  for (const child of Object.values(value)) deepFreeze(child);
  return Object.freeze(value);
}

function manifestError(classification, message) {
  const error = new Error(message);
  error.name = 'ComparisonManifestError';
  error.classification = classification;
  return error;
}

function parseArguments(argv) {
  const args = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith('--') || value === undefined) {
      throw new Error('Usage: build-genui-provider-comparison-manifest.mjs --input INPUT --output OUTPUT');
    }
    args.set(key.slice(2), value);
  }
  if (args.size !== 2 || !args.has('input') || !args.has('output')) {
    throw new Error('Usage: build-genui-provider-comparison-manifest.mjs --input INPUT --output OUTPUT');
  }
  return args;
}

async function runCli(argv) {
  const args = parseArguments(argv);
  const input = JSON.parse(await readFile(args.get('input'), 'utf8'));
  await writeComparisonManifest({ outputPath: args.get('output'), input });
  process.stdout.write(`${args.get('output')}\n`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  runCli(process.argv.slice(2)).catch((error) => {
    process.stderr.write(`${error.name ?? 'Error'}: ${error.message}\n`);
    process.exitCode = 1;
  });
}
