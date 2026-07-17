import { createHash } from 'node:crypto';
import { mkdir, open, realpath, rm, stat } from 'node:fs/promises';
import { basename, isAbsolute, join, relative, resolve, sep } from 'node:path';

import { GENUI_CANDIDATE_SCHEMA } from '../src/genui-candidate-schema.js';
import { getFeasibilityFixture } from '../src/genui-feasibility-fixtures.js';
import { buildFeasibilityPrompt, GENUI_PROVIDER_SETTINGS } from '../src/genui-feasibility-provider.js';

const CONFIGURATION_ERROR = 'configuration_error';

function configurationError(message) {
  return Object.assign(new Error(message), { code: CONFIGURATION_ERROR });
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

async function writeExclusive(path, value) {
  const handle = await open(path, 'wx', 0o600);
  try { await handle.writeFile(value); } finally { await handle.close(); }
}

export function parseMinimalProviderArgs(argv, { repositoryRoot }) {
  if (argv.length % 2 !== 0) throw configurationError('Every flag requires one value.');
  const allowed = new Set(['--fixture', '--model', '--output-dir', '--timeout-ms']);
  const values = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (!allowed.has(flag) || values.has(flag)) throw configurationError('Unknown or duplicate CLI flag.');
    values.set(flag, value);
  }
  for (const flag of ['--fixture', '--model', '--output-dir']) {
    if (!values.has(flag) || values.get(flag) === '') throw configurationError(`Missing ${flag}.`);
  }
  const timeoutText = values.get('--timeout-ms');
  const timeoutMs = timeoutText === undefined ? GENUI_PROVIDER_SETTINGS.timeoutMs : Number(timeoutText);
  if (!Number.isInteger(timeoutMs) || timeoutMs <= 0) throw configurationError('Timeout must be a positive integer.');
  let fixture;
  try { fixture = getFeasibilityFixture(values.get('--fixture')); }
  catch { throw configurationError('Unknown fixture.'); }
  return {
    fixtureId: values.get('--fixture'), fixture, model: values.get('--model'),
    outputDir: values.get('--output-dir'), timeoutMs, repositoryRoot: resolve(repositoryRoot),
  };
}

export async function createPrivateRun(options, deps = {}) {
  const repositoryRoot = await realpath(deps.repositoryRoot ?? options.repositoryRoot);
  const outputDir = options.outputDir;
  if (!isAbsolute(outputDir)) throw configurationError('Output path must be absolute.');
  const parent = resolve(outputDir, '..');
  let canonicalParent;
  try {
    canonicalParent = await realpath(parent);
    await stat(canonicalParent);
  } catch { throw configurationError('Output parent must exist.'); }
  const canonicalOutput = join(canonicalParent, basename(outputDir));
  if (canonicalOutput !== outputDir) throw configurationError('Output path must be canonical.');
  const rel = relative(repositoryRoot, canonicalOutput);
  if (rel === '' || (!isAbsolute(rel) && rel !== '..' && !rel.startsWith(`..${sep}`))) {
    throw configurationError('Output path must be outside the repository.');
  }
  try { await stat(canonicalOutput); throw configurationError('Output path must not exist.'); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  await mkdir(canonicalOutput, { recursive: false, mode: 0o700 });
  const paths = {
    root: canonicalOutput,
    request: join(canonicalOutput, 'request.json'),
    providerEvents: join(canonicalOutput, 'provider-events.jsonl'),
    candidate: join(canonicalOutput, 'candidate.json'),
    result: join(canonicalOutput, 'result.json'),
    schema: join(canonicalOutput, '.candidate-schema.json'),
    work: join(canonicalOutput, '.codex-work'),
    playwright: join(canonicalOutput, '.playwright'),
    browserResult: join(canonicalOutput, '.browser-result.json'),
  };
  const prompt = buildFeasibilityPrompt(options.fixture);
  const schemaJson = JSON.stringify(GENUI_CANDIDATE_SCHEMA);
  const request = {
    schemaVersion: 1,
    fixtureId: options.fixtureId,
    model: options.model,
    timeoutMs: options.timeoutMs,
    invocationTimestamp: (deps.now?.() ?? new Date().toISOString()),
    expectedProviderInvocationCount: 1,
    prompt,
    promptSha256: sha256(prompt),
    schemaSha256: sha256(schemaJson),
  };
  await writeExclusive(paths.request, `${JSON.stringify(request, null, 2)}\n`);
  await writeExclusive(paths.providerEvents, '');
  return { paths, request, options };
}

export async function writeTerminalResult(run, terminal) {
  for (const path of [run.paths.schema, run.paths.work, run.paths.playwright, run.paths.browserResult]) {
    await rm(path, { recursive: true, force: true });
  }
  await writeExclusive(run.paths.result, `${JSON.stringify(terminal, null, 2)}\n`);
}
