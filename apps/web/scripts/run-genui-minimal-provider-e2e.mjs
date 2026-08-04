import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { chmod, mkdir, open, readFile, realpath, rm, stat } from 'node:fs/promises';
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';

import { GENUI_CANDIDATE_SCHEMA } from '../src/features/genui/core/genui-candidate-schema.js';
import { getFeasibilityFixture } from '../src/features/genui/core/genui-feasibility-fixtures.js';
import { buildFeasibilityPrompt, GENUI_PROVIDER_SETTINGS } from '../server/genui/feasibility-provider.js';
import { runProviderProcess, waitForProcess } from './genui-minimal-provider-process.mjs';

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
    browserResult: join(canonicalOutput, 'browser-result.json'),
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

export async function runProviderAttempt(run, options, deps = {}) {
  await writeExclusive(run.paths.schema, `${JSON.stringify(GENUI_CANDIDATE_SCHEMA)}\n`);
  await mkdir(run.paths.work, { mode: 0o700 });
  const eventsHandle = await open(run.paths.providerEvents, 'a', 0o600);
  const eventsStream = eventsHandle.createWriteStream();
  const observed = await runProviderProcess(run, options, { ...deps, eventsStream });
  if (observed.timedOut) return { ...observed, classification: 'provider_timeout', safeMessage: 'Provider deadline exceeded.' };
  if (observed.interrupted) return { ...observed, classification: 'provider_failed', safeMessage: 'Provider interrupted.' };
  if (observed.error || observed.exitCode !== 0) return { ...observed, classification: 'provider_failed', safeMessage: 'Provider process failed.' };
  return { ...observed, classification: 'success', safeMessage: null };
}

export async function classifyCandidate(candidatePath, maxBytes) {
  let candidateStat;
  try { candidateStat = await stat(candidatePath); }
  catch { return { classification: 'provider_failed', safeMessage: 'Provider produced no final message.' }; }
  if (candidateStat.size === 0) {
    return { classification: 'provider_failed', safeMessage: 'Provider produced no final message.' };
  }
  if (candidateStat.size > maxBytes) {
    return { classification: 'candidate_oversize', safeMessage: 'Provider final output exceeded the size limit.' };
  }
  let bytes;
  try { bytes = await readFile(candidatePath); }
  catch { return { classification: 'provider_failed', safeMessage: 'Provider produced no final message.' }; }
  let candidateJson;
  try {
    candidateJson = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    JSON.parse(candidateJson);
  } catch {
    return { classification: 'candidate_invalid', safeMessage: 'Provider final output was not valid JSON.' };
  }
  await chmod(candidatePath, 0o600);
  return { candidateJson, bytes };
}

export async function evaluateInBrowser(run, options, deps = {}) {
  const spawnProcess = deps.spawnBrowserProcess ?? spawn;
  const child = spawnProcess(
    'npx',
    ['playwright', 'test', '--config=playwright.minimal-provider.config.ts', '--project=chromium'],
    {
      cwd: resolve(import.meta.dirname, '..'),
      env: { ...process.env, GENUI_MINIMAL_PROVIDER_RUN_DIR: run.paths.root },
      detached: process.platform !== 'win32',
      stdio: ['ignore', 'ignore', 'ignore'],
    },
  );
  const terminateWindowsTree = deps.terminateWindowsTree ?? ((pid, force) => {
    const killer = spawn('taskkill', ['/PID', String(pid), '/T', ...(force ? ['/F'] : [])], { stdio: 'ignore' });
    killer.unref();
  });
  const observed = await waitForProcess(child, {
    timeoutMs: options.timeoutMs,
    kill: deps.kill ?? process.kill,
    platform: deps.platform ?? process.platform,
    terminateWindowsTree,
  });
  if (observed.exitCode !== 0) return { classification: 'browser_failed', safeMessage: 'Browser validation failed.' };
  try {
    return JSON.parse(await readFile(run.paths.browserResult, 'utf8'));
  } catch {
    return { classification: 'browser_failed', safeMessage: 'Browser result was unavailable.' };
  }
}

export async function runMinimalProviderE2E(options, deps = {}) {
  let run;
  try {
    run = await createPrivateRun(options, deps);
    const provider = await runProviderAttempt(run, options, deps);
    if (provider.classification !== 'success') {
      const result = { ...provider, invocationCount: provider.invocationCount };
      await writeTerminalResult(run, result);
      return { exitCode: 1, result };
    }
    const candidate = await classifyCandidate(run.paths.candidate, GENUI_PROVIDER_SETTINGS.maxCandidateBytes);
    if (candidate.classification) {
      const result = { ...candidate, invocationCount: provider.invocationCount };
      await writeTerminalResult(run, result);
      return { exitCode: 1, result };
    }
    const browser = await (deps.runBrowser?.(run) ?? evaluateInBrowser(run, options, deps));
    const result = { ...browser, invocationCount: provider.invocationCount };
    await writeTerminalResult(run, result);
    const passed = result.classification === 'success' && result.rubric?.passed === true && result.session?.success === true;
    return { exitCode: passed ? 0 : 1, result };
  } finally {
    if (run) {
      for (const path of [run.paths.schema, run.paths.work, run.paths.playwright, run.paths.browserResult]) {
        await rm(path, { recursive: true, force: true });
      }
    }
  }
}

async function main() {
  try {
    const options = parseMinimalProviderArgs(process.argv.slice(2), {
      repositoryRoot: resolve(import.meta.dirname, '../../..'),
    });
    const { exitCode } = await runMinimalProviderE2E(options);
    process.exitCode = exitCode;
  } catch (error) {
    console.error(error.code === CONFIGURATION_ERROR ? error.message : 'Minimal provider E2E failed.');
    process.exitCode = 1;
  }
}

if (import.meta.url === new URL(process.argv[1], 'file:').href) await main();
