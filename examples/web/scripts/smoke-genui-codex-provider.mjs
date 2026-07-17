#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { chmod, mkdir, readFile, writeFile } from 'node:fs/promises';
import { isAbsolute, join, relative, resolve, sep } from 'node:path';
import { pathToFileURL } from 'node:url';
import { normalizeProviderTranscript } from './genui-provider-comparison.mjs';
import { validateComparisonRunRoot } from './run-genui-provider-comparison-study.mjs';
import {
  capabilitiesJsonForFixture,
  normalizedDatasetJsonForFixture,
} from '../src/genui-feasibility-fixtures.js';

export const SMOKE_FIXTURE = Object.freeze({
  caseId: 'provider-smoke-synthetic',
  question: 'Which synthetic records are below the frozen threshold, and what is their total value?',
  sourceFormat: 'json-array',
  binding: 'smoke_records',
  selectionKey: 'id',
  fields: Object.freeze(['id', 'label', 'value']),
  numericFields: Object.freeze(['value']),
  taskValue: 10,
  source: Object.freeze([
    Object.freeze({ id: 'smoke-1', label: 'below', value: 4 }),
    Object.freeze({ id: 'smoke-2', label: 'above', value: 16 }),
  ]),
});

const REQUIRED_PREFLIGHT = Object.freeze(['isolation', 'identity', 'credentials', 'budget']);
const REQUIRED_VALIDATIONS = Object.freeze(['decoding', 'semantic', 'materialization', 'rubric', 'replay', 'sessionCommit']);

export async function executeCodexSmoke({
  manifest,
  runRoot,
  xdgStateHome,
  repositoryRoot,
  rawOutput = join(runRoot, 'smoke', 'raw.json'),
  summaryOutput = join(runRoot, 'smoke', 'summary.json'),
}, deps) {
  requireDependencies(deps);
  const frozenCommit = await deps.verifyRepository();
  if (frozenCommit !== manifest?.sourceCommit) {
    throw new Error('The checked-out commit does not match the reviewed smoke manifest.');
  }
  const preflight = await deps.preflight({ manifest, repositoryRoot, runRoot });
  requireTrueFields(preflight, REQUIRED_PREFLIGHT, 'smoke preflight');
  const resolvedRunRoot = await validateComparisonRunRoot({
    runRoot,
    xdgStateHome,
    repositoryRoot,
    createIfMissing: true,
  });
  const smokeRoot = join(resolvedRunRoot, 'smoke');
  await ensurePrivateDirectory(smokeRoot);
  const rawArtifactPath = requireSmokeOutput(rawOutput, smokeRoot, 'rawOutput');
  const summaryPath = requireSmokeOutput(summaryOutput, smokeRoot, 'summaryOutput');
  if (rawArtifactPath === summaryPath) throw new Error('Smoke output paths must be distinct.');

  const input = Object.freeze({
    fixture: SMOKE_FIXTURE,
    capabilitiesJson: capabilitiesJsonForFixture(SMOKE_FIXTURE),
    datasetJson: normalizedDatasetJsonForFixture(SMOKE_FIXTURE),
  });
  const slot = Object.freeze({
    slotId: 'provider-smoke-synthetic/codex',
    fixtureId: SMOKE_FIXTURE.caseId,
    providerId: 'codex',
    stage: 0,
    active: true,
  });
  const gate = await deps.requestGate({ manifest, slot, input, runRoot: resolvedRunRoot });
  if (gate?.classification === 'global_stop') throw new Error('Smoke request gate stopped provider access.');

  const sandbox = await deps.createSandbox({ manifest, slot, runRoot: resolvedRunRoot });
  let attempt;
  try {
    attempt = await deps.codexAttempt({
      manifest,
      slot,
      fixture: SMOKE_FIXTURE,
      input,
      sandbox,
    });
  } finally {
    await sandbox.cleanup();
  }

  if (!attempt || attempt.classification !== 'candidate_pass' || typeof attempt.candidateJson !== 'string') {
    throw new Error(`Credentialed Codex smoke failed: ${attempt?.classification ?? 'missing_result'}.`);
  }
  const transcript = normalizeProviderTranscript({
    providerId: 'codex',
    rawEvents: attempt.rawEvents,
    canaries: deps.canaries,
  });
  const finalMessages = attempt.rawEvents.filter((event) => event?.type === 'agentMessage');
  if (finalMessages.length !== 1) throw new Error('Smoke requires exactly one final agent message.');
  const usage = requireTokenUsage(attempt);
  const evaluated = await deps.evaluateCandidate({
    manifest,
    slot,
    candidateJson: attempt.candidateJson,
    input,
  });
  if (evaluated?.classification !== 'candidate_pass' || evaluated.preparationPassed !== true ||
      REQUIRED_VALIDATIONS.some((field) => evaluated.validations?.[field] !== true) ||
      evaluated.replayMismatch === true) {
    throw new Error('Smoke candidate failed the unchanged MoonBit preparation, replay, or commit path.');
  }

  await writeExclusiveJson(rawArtifactPath, { attempt, transcript });
  const summary = Object.freeze({
    classification: 'candidate_pass',
    caseId: SMOKE_FIXTURE.caseId,
    providerId: 'codex',
    frozenCommit,
    candidateSha256: createHash('sha256').update(attempt.candidateJson).digest('hex'),
    usage,
    preparationPassed: true,
    replayEqual: true,
    completedAt: deps.now?.() ?? new Date().toISOString(),
  });
  await writeExclusiveJson(summaryPath, summary);
  return Object.freeze({ ...summary, rawArtifactPath, summaryPath });
}

function requireTokenUsage(attempt) {
  const usage = attempt.usage ?? attempt.rawEvents.findLast((event) => event?.usage)?.usage;
  if (!usage || !Number.isInteger(usage.totalTokens) || usage.totalTokens <= 0) {
    throw new Error('Smoke token telemetry requires a positive integer totalTokens.');
  }
  for (const field of ['inputTokens', 'cachedInputTokens', 'outputTokens']) {
    if (!Number.isInteger(usage[field]) || usage[field] < 0) {
      throw new Error(`Smoke token telemetry requires a non-negative integer ${field}.`);
    }
  }
  return Object.freeze({
    inputTokens: usage.inputTokens,
    cachedInputTokens: usage.cachedInputTokens,
    outputTokens: usage.outputTokens,
    totalTokens: usage.totalTokens,
  });
}

function requireSmokeOutput(path, smokeRoot, field) {
  if (typeof path !== 'string' || !isAbsolute(path)) throw new Error(`${field} must be absolute.`);
  const absolute = resolve(path);
  const rel = relative(smokeRoot, absolute);
  if (rel.length === 0 || rel === '..' || rel.startsWith(`..${sep}`) || isAbsolute(rel)) {
    throw new Error(`${field} must be an absolute descendant of the smoke directory.`);
  }
  return absolute;
}

async function ensurePrivateDirectory(path) {
  try {
    await mkdir(path, { mode: 0o700 });
  } catch (error) {
    if (error?.code !== 'EEXIST') throw error;
  }
  await chmod(path, 0o700);
}

async function writeExclusiveJson(path, value) {
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`, { encoding: 'utf8', flag: 'wx', mode: 0o600 });
  await chmod(path, 0o600);
}

function requireDependencies(deps) {
  for (const name of ['verifyRepository', 'preflight', 'createSandbox', 'requestGate', 'codexAttempt', 'evaluateCandidate']) {
    if (typeof deps?.[name] !== 'function') throw new Error(`Smoke dependency ${name} is required.`);
  }
}

function requireTrueFields(value, fields, label) {
  if (!value || fields.some((field) => value[field] !== true)) throw new Error(`${label} failed closed.`);
}

function parseCli(argv) {
  const values = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    if (!argv[index]?.startsWith('--') || !argv[index + 1]) throw new Error('Smoke arguments must be --name value pairs.');
    values.set(argv[index], argv[index + 1]);
  }
  for (const key of ['--manifest', '--run-root', '--raw-output', '--summary-output']) {
    if (!values.has(key)) throw new Error(`Missing required smoke argument ${key}.`);
  }
  return values;
}

async function runCli(argv) {
  const values = parseCli(argv);
  const manifest = JSON.parse(await readFile(resolve(values.get('--manifest')), 'utf8'));
  const dependencyModule = process.env.GENUI_PROVIDER_COMPARISON_DEPS;
  if (!dependencyModule) {
    throw new Error('GENUI_PROVIDER_COMPARISON_DEPS must name the reviewed production dependency module.');
  }
  const imported = await import(pathToFileURL(resolve(dependencyModule)).href);
  const deps = await imported.createComparisonDependencies({ manifest });
  const result = await executeCodexSmoke({
    manifest,
    runRoot: resolve(values.get('--run-root')),
    rawOutput: resolve(values.get('--raw-output')),
    summaryOutput: resolve(values.get('--summary-output')),
    xdgStateHome: process.env.XDG_STATE_HOME,
    repositoryRoot: resolve(import.meta.dirname, '../../..'),
  }, deps);
  process.stdout.write(`${JSON.stringify({
    classification: result.classification,
    usage: result.usage,
    rawArtifactPath: result.rawArtifactPath,
    summaryPath: result.summaryPath,
  }, null, 2)}\n`);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  runCli(process.argv.slice(2)).catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.stack : String(error)}\n`);
    process.exitCode = 1;
  });
}
