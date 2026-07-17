import { createHash, randomBytes } from 'node:crypto';
import { execFile as nodeExecFile, spawn as nodeSpawn } from 'node:child_process';
import {
  access,
  chmod,
  mkdtemp,
  readFile,
  rm,
  stat,
  writeFile,
} from 'node:fs/promises';
import { homedir } from 'node:os';
import { basename, join, resolve } from 'node:path';
import { promisify } from 'node:util';
import { chromium } from '@playwright/test';
import {
  createCodexAppServerSession,
  discoverCodexAppServerIdentity,
} from '../src/genui-codex-app-server.js';
import {
  buildFeasibilityPrompt,
  callOllamaAttempt,
  canonicalJson,
  readOllamaIdentity,
} from '../src/genui-feasibility-provider.js';
import {
  capabilitiesJsonForFixture,
  getFeasibilityFixture,
  normalizeTrustedFixture,
  normalizedDatasetJsonForFixture,
} from '../src/genui-feasibility-fixtures.js';
import { prepareCodexSandbox } from './genui-codex-sandbox.mjs';

const execFile = promisify(nodeExecFile);
const DEFAULT_CODEX_BINARY = '/usr/bin/codex';
const DEFAULT_BWRAP_BINARY = '/usr/bin/bwrap';
const DEFAULT_BROWSER_HOST = '127.0.0.1';
const DEFAULT_BROWSER_PORT = 5187;
const TERMINAL_MAP = Object.freeze({
  candidate_decode_error: 'provider_decode_failure',
  capability_decode_error: 'capability_decode_failure',
  candidate_validation_error: 'semantic_validation_failure',
  materialization_error: 'materialization_failure',
  rubric_failure: 'rubric_failure',
  replay_mismatch: 'replay_mismatch',
  commit_failure: 'session_commit_failure',
});

const CODEX_TERMINAL_MAP = Object.freeze({
  model_not_available: 'identity_drift',
  provider_identity_mismatch: 'identity_drift',
  forbidden_provider_tool: 'tool_use',
  provider_failed: 'provider_protocol_error',
  provider_interrupted: 'signal_interruption',
  request_rejected: 'provider_protocol_error',
});
export async function createComparisonDependencies({ manifest }, overrides = {}) {
  if (!manifest || typeof manifest !== 'object') throw new TypeError('A frozen comparison manifest is required.');
  const repositoryRoot = overrides.repositoryRoot ?? resolve(import.meta.dirname, '../../..');
  const webRoot = resolve(import.meta.dirname, '..');
  const codexBinary = overrides.codexBinary ?? process.env.GENUI_PROVIDER_CODEX_BINARY ?? DEFAULT_CODEX_BINARY;
  const bwrapBinary = overrides.bwrapBinary ?? DEFAULT_BWRAP_BINARY;
  const authSource = overrides.authSource ?? join(homedir(), '.codex', 'auth.json');
  const startedAt = (overrides.now ?? Date.now)();
  const budget = { requests: 0, totalTokens: 0, globalStop: false };
  const canaries = {
    hostPaths: [],
    secretValues: [`CANOPY-PRIVATE-${randomBytes(16).toString('hex')}`],
  };
  const codexIdentity = Object.freeze({
    cliVersion: manifest.providerIdentities.codex.cliVersion,
    slug: manifest.providerIdentities.codex.modelSlug,
    effort: manifest.providerIdentities.codex.reasoningEffort,
    authMode: manifest.providerIdentities.codex.authMode,
    catalogEntrySha256: manifest.providerIdentities.codex.catalogEntrySha256,
  });
  let browserEvaluatorPromise = null;

  const createSandbox = async ({ runRoot }) => {
    const hostCanary = join(runRoot, '.host-path-canary');
    if (!canaries.hostPaths.includes(hostCanary)) {
      await writeFile(hostCanary, `${canaries.secretValues[0]}\n`, { flag: 'wx', mode: 0o600 });
      await chmod(hostCanary, 0o600);
      canaries.hostPaths.push(hostCanary);
    }
    return (overrides.prepareSandbox ?? prepareCodexSandbox)({
      runRoot,
      codexBinary,
      bwrapBinary,
      authSource,
      canaries,
    });
  };

  const codexAttempt = async ({ fixture, slot, sandbox }) => {
    if (budget.globalStop) return globalStopAttempt();
    const factory = overrides.createCodexSession ?? createCodexAppServerSession;
    const session = await factory({
      frozenIdentity: codexIdentity,
      spawnProcess: sandbox.spawnProcess,
    });
    try {
      const result = await session.runSlot({ fixture, slotId: slot.slotId });
      const usage = result.tokenUsage ?? result.usage;
      const rawEvents = normalizeCodexEvents(result.transcript ?? [], usage);
      const attempt = {
        ...result,
        classification: result.classification === 'success'
          ? 'candidate_pass'
          : CODEX_TERMINAL_MAP[result.classification] ?? result.classification,
        rawEvents,
        ...(usage === undefined ? {} : { usage }),
      };
      return accountForAttempt(attempt, manifest.limits, budget);
    } finally {
      await session.close();
    }
  };

  const ollamaAttempt = async ({ fixture, seed }) => {
    if (budget.globalStop) return globalStopAttempt();
    const invoke = overrides.callOllama ?? callOllamaAttempt;
    const result = await invoke({
      fixture,
      seed,
      frozenIdentity: manifest.providerIdentities.ollama,
    });
    const attempt = result.classification === 'success'
      ? {
          ...result,
          classification: 'candidate_pass',
          rawEvents: [{
            type: 'providerResponse',
            status: 'success',
            model: result.lookupTag,
            candidateBytes: result.candidateJson,
            candidateDigest: result.candidateSha256,
            usage: {
              inputTokens: result.promptTokens ?? 0,
              cachedInputTokens: 0,
              outputTokens: result.outputTokens ?? 0,
              totalTokens: (result.promptTokens ?? 0) + (result.outputTokens ?? 0),
            },
          }],
          usage: {
            inputTokens: result.promptTokens ?? 0,
            cachedInputTokens: 0,
            outputTokens: result.outputTokens ?? 0,
            totalTokens: (result.promptTokens ?? 0) + (result.outputTokens ?? 0),
          },
        }
      : { ...result, rawEvents: [{ type: 'providerResponse', status: result.classification }] };
    return accountForAttempt(attempt, manifest.limits, budget);
  };

  const getBrowserEvaluator = async () => {
    browserEvaluatorPromise ??= (overrides.browserEvaluatorFactory ?? createBrowserCandidateEvaluator)({
      webRoot,
      host: overrides.browserHost ?? DEFAULT_BROWSER_HOST,
      port: overrides.browserPort ?? DEFAULT_BROWSER_PORT,
      spawn: overrides.spawn ?? nodeSpawn,
    });
    return browserEvaluatorPromise;
  };

  return Object.freeze({
    canaries,
    verifyRepository: overrides.verifyRepository ?? (() => verifyCleanRepository(repositoryRoot)),
    preflight: overrides.runPreflight ?? (async () => runProductionPreflight({
      manifest,
      frozenCodexIdentity: codexIdentity,
      repositoryRoot,
      codexBinary,
      bwrapBinary,
      authSource,
      canaries,
      overrides,
    })),
    loadFixture(slot) {
      const fixture = getFeasibilityFixture(slot.fixtureId);
      const dataset = normalizeTrustedFixture(fixture);
      const digest = sha256(canonicalJson(dataset));
      if (digest !== slot.fixtureDigest) throw new Error(`Frozen fixture digest mismatch for ${slot.fixtureId}.`);
      return Object.freeze({
        digest,
        fixture,
        prompt: buildFeasibilityPrompt(fixture),
        datasetJson: normalizedDatasetJsonForFixture(fixture),
        capabilitiesJson: capabilitiesJsonForFixture(fixture),
      });
    },
    createSandbox,
    async requestGate() {
      if (
        budget.globalStop ||
        budget.requests >= manifest.limits.activeRequests ||
        budget.totalTokens >= manifest.limits.runTokenCeiling ||
        (overrides.now ?? Date.now)() - startedAt >= manifest.limits.runWallTimeMs
      ) {
        budget.globalStop = true;
        return Object.freeze({ classification: 'global_stop' });
      }
      return Object.freeze({ classification: 'pass' });
    },
    async evaluateCandidate({ slot, candidateJson, input }) {
      const evaluator = await getBrowserEvaluator();
      const result = await evaluator.evaluate({
        caseId: slot.fixtureId ?? input.fixture.caseId,
        candidateJson,
        input,
      });
      return mapBrowserEvaluation(result);
    },
    auditStage1: overrides.auditStage1 ?? auditStage1Artifacts,
    attempts: Object.freeze({ codex: codexAttempt, ollama: ollamaAttempt }),
    codexAttempt,
    async close() {
      const evaluator = await browserEvaluatorPromise;
      await evaluator?.close();
    },
  });
}

function normalizeCodexEvents(transcript, usage) {
  const events = transcript.map((raw) => {
    const event = {};
    if (typeof raw.method === 'string') event.method = raw.method;
    if (typeof raw.itemType === 'string') event.itemType = raw.itemType;
    if (typeof raw.terminalStatus === 'string') event.status = raw.terminalStatus;
    for (const field of ['requestId', 'threadId', 'turnId']) {
      if (typeof raw[field] === 'string' || typeof raw[field] === 'number') {
        event[field] = String(raw[field]);
      }
    }
    event.type = raw.method === 'item/completed' && raw.itemType === 'agentMessage'
      ? 'agentMessage'
      : 'protocol';
    return Object.freeze(event);
  });
  if (usage !== undefined) events.push(Object.freeze({ type: 'usage', usage }));
  return Object.freeze(events);
}

function accountForAttempt(attempt, limits, budget) {
  budget.requests += 1;
  const totalTokens = attempt?.usage?.totalTokens;
  const requiresUsage = attempt?.classification === 'candidate_pass';
  if (Number.isInteger(totalTokens) && totalTokens >= 0) budget.totalTokens += totalTokens;
  if (
    (requiresUsage && (!Number.isInteger(totalTokens) || totalTokens <= 0)) ||
    (Number.isInteger(totalTokens) && totalTokens > limits.perRequestTokenCeiling) ||
    budget.totalTokens > limits.runTokenCeiling ||
    budget.requests > limits.activeRequests
  ) {
    budget.globalStop = true;
    return globalStopAttempt();
  }
  return attempt;
}

function globalStopAttempt() {
  return Object.freeze({ classification: 'global_stop', rawEvents: [] });
}

function mapBrowserEvaluation(result) {
  const classification = result?.classification === 'success'
    ? 'candidate_pass'
    : TERMINAL_MAP[result?.classification] ?? 'session_commit_failure';
  const preparationPassed = ['success', 'rubric_failure', 'replay_mismatch', 'commit_failure'].includes(result?.classification);
  const validations = {
    decoding: preparationPassed || !['candidate_decode_error'].includes(result?.classification),
    semantic: preparationPassed || !['candidate_decode_error', 'candidate_validation_error'].includes(result?.classification),
    materialization: preparationPassed || !['candidate_decode_error', 'candidate_validation_error', 'materialization_error'].includes(result?.classification),
    rubric: result?.rubric?.passed === true,
    replay: classification === 'candidate_pass',
    sessionCommit: classification === 'candidate_pass',
  };
  return Object.freeze({
    classification,
    preparationPassed,
    validations: Object.freeze(validations),
    replayMismatch: classification === 'replay_mismatch',
    safetyViolations: 0,
    toolUseViolations: 0,
    stateMutationViolations: 0,
    credentialLeakageViolations: 0,
  });
}

async function createBrowserCandidateEvaluator({ webRoot, host, port, spawn }) {
  const vite = resolve(webRoot, 'node_modules/vite/bin/vite.js');
  await access(vite);
  const child = spawn(process.execPath, [vite, '--host', host, '--port', String(port), '--strictPort'], {
    cwd: webRoot,
    detached: true,
    env: { ...process.env },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const logs = [];
  for (const stream of [child.stdout, child.stderr]) {
    stream?.on('data', (chunk) => {
      logs.push(chunk.toString('utf8'));
      if (logs.length > 100) logs.shift();
    });
  }
  let browser;
  let page;
  try {
    await waitForUrl(`http://${host}:${port}/genui.html`, child, logs);
    browser = await chromium.launch();
    page = await browser.newPage();
    await page.goto(`http://${host}:${port}/genui.html`);
    await page.waitForFunction(() => typeof window.__canopyGenUiFeasibilityTest?.commitCandidate === 'function');
  } catch (error) {
    await browser?.close();
    stopProcessGroup(child);
    throw new Error(`Browser candidate evaluator failed to start: ${error instanceof Error ? error.message : String(error)}\n${logs.join('').slice(-4000)}`);
  }
  return Object.freeze({
    async evaluate({ candidateJson, input }) {
      return page.evaluate(async ({ rawCandidate, candidateInput }) => {
        const api = window.__canopyGenUiFeasibilityTest;
        if (!api) throw new Error('GenUI feasibility browser test API is unavailable.');
        await api.resetSlotSession();
        return api.commitCandidate({
          candidateJson: rawCandidate,
          ...candidateInput,
        });
      }, { rawCandidate: candidateJson, candidateInput: input });
    },
    async close() {
      await browser.close();
      stopProcessGroup(child);
      await waitForExit(child);
    },
  });
}

async function runProductionPreflight({ manifest, frozenCodexIdentity, repositoryRoot, codexBinary, bwrapBinary, authSource, canaries, overrides }) {
  const verifyRepository = overrides.verifyRepository ?? verifyCleanRepository;
  const frozenCommit = await verifyRepository(repositoryRoot);
  if (frozenCommit !== manifest.sourceCommit) throw new Error('Preflight repository commit differs from the manifest.');
  const stateHome = process.env.XDG_STATE_HOME;
  if (!stateHome) throw new Error('XDG_STATE_HOME is required for the production preflight.');
  const namespace = join(stateHome, 'canopy', 'genui-provider-benchmark');
  await access(authSource);
  const preflightRoot = await mkdtemp(join(namespace, '.preflight-'));
  await chmod(preflightRoot, 0o700);
  const hostCanary = join(preflightRoot, '.host-path-canary');
  await writeFile(hostCanary, `${canaries.secretValues[0]}\n`, { flag: 'wx', mode: 0o600 });
  canaries.hostPaths.push(hostCanary);
  let sandbox;
  try {
    sandbox = await (overrides.prepareSandbox ?? prepareCodexSandbox)({
      runRoot: preflightRoot,
      codexBinary,
      bwrapBinary,
      authSource,
      canaries,
    });
    const discover = overrides.discoverCodexIdentity ?? discoverCodexAppServerIdentity;
    const discoveredCodexIdentity = await discover({
      cliVersion: sandbox.contract.codexVersion,
      slug: frozenCodexIdentity.slug,
      effort: frozenCodexIdentity.effort,
      spawnProcess: sandbox.spawnProcess,
    });
    if (canonicalJson(discoveredCodexIdentity) !== canonicalJson(frozenCodexIdentity)) {
      throw new Error('Codex identity differs from the frozen manifest.');
    }
    if (manifest.branch === 'paired') {
      const ollamaIdentity = await (overrides.readOllamaIdentity ?? readOllamaIdentity)(manifest.providerIdentities.ollama.lookupTag);
      if (canonicalJson(ollamaIdentity) !== canonicalJson(manifest.providerIdentities.ollama)) {
        throw new Error('Ollama identity differs from the frozen manifest.');
      }
    }
  } finally {
    await sandbox?.cleanup();
    canaries.hostPaths.splice(canaries.hostPaths.indexOf(hostCanary), 1);
    await rm(preflightRoot, { recursive: true, force: true });
  }
  return Object.freeze({ isolation: true, identity: true, credentials: true, budget: true });
}

async function verifyCleanRepository(repositoryRoot) {
  const [{ stdout: commit }, { stdout: status }] = await Promise.all([
    execFile('git', ['rev-parse', 'HEAD'], { cwd: repositoryRoot, encoding: 'utf8' }),
    execFile('git', ['status', '--porcelain'], { cwd: repositoryRoot, encoding: 'utf8' }),
  ]);
  if (status.length !== 0) throw new Error('Repository must be clean before provider execution.');
  return commit.trim();
}

async function auditStage1Artifacts({ manifest, slots, runRoot }) {
  const stage1 = manifest.schedule.filter((slot) => slot.stage === 1);
  const terminalIds = new Set(slots.map((slot) => slot.slotId));
  const manifestMatches = canonicalJson(JSON.parse(await readFile(join(runRoot, 'manifest.json'), 'utf8'))) === canonicalJson(manifest);
  const scheduleMatches = stage1.length === slots.length && stage1.every((slot) => terminalIds.has(slot.slotId));
  let evidenceComplete = true;
  for (const slot of stage1.filter((candidate) => candidate.active)) {
    try {
      for (const directory of ['raw', 'normalized']) {
        const info = await stat(join(runRoot, directory, `${slot.slotId}.json`));
        evidenceComplete &&= info.isFile() && (info.mode & 0o777) === 0o600;
      }
    } catch {
      evidenceComplete = false;
    }
  }
  const rootInfo = await stat(runRoot);
  const retention = rootInfo.isDirectory() && (rootInfo.mode & 0o777) === 0o700;
  return Object.freeze({
    manifest: manifestMatches,
    schedule: scheduleMatches,
    evidence: evidenceComplete,
    retention,
  });
}

async function waitForUrl(url, child, logs) {
  for (let attempt = 0; attempt < 600; attempt += 1) {
    if (child.exitCode !== null) throw new Error(`Vite exited with code ${child.exitCode}. ${logs.join('').slice(-1000)}`);
    try {
      const response = await fetch(url);
      if (response.ok) return;
    } catch {
      // The local server is not accepting connections yet.
    }
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 100));
  }
  throw new Error('Timed out waiting for the local GenUI server.');
}

function stopProcessGroup(child) {
  try {
    process.kill(-child.pid, 'SIGTERM');
  } catch {
    child.kill('SIGTERM');
  }
}

async function waitForExit(child) {
  if (child.exitCode !== null) return;
  await Promise.race([
    new Promise((resolvePromise) => child.once('exit', resolvePromise)),
    new Promise((resolvePromise) => setTimeout(resolvePromise, 5_000)),
  ]);
  if (child.exitCode === null) {
    try {
      process.kill(-child.pid, 'SIGKILL');
    } catch {
      child.kill('SIGKILL');
    }
  }
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}
