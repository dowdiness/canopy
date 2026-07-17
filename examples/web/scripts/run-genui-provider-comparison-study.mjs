#!/usr/bin/env node
import { createHash } from 'node:crypto';
import {
  chmod,
  lstat,
  mkdir,
  open,
  readFile,
  realpath,
  writeFile,
} from 'node:fs/promises';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  evaluateStage1Eligibility,
  finalizeComparisonEvidence,
  normalizeProviderTranscript,
  qualifyProvider,
  validateComparisonJournal,
} from './genui-provider-comparison.mjs';

const RUN_NAMESPACE = join('canopy', 'genui-provider-benchmark');
const GLOBAL_STOP = 'global_stop';
const STAGE1_INELIGIBLE = 'stage1_ineligible';
const REQUIRED_PREFLIGHT = Object.freeze(['isolation', 'identity', 'credentials', 'budget']);
const REQUIRED_STAGE1_AUDIT = Object.freeze(['manifest', 'schedule', 'evidence', 'retention']);

export async function validateComparisonRunRoot({
  runRoot,
  xdgStateHome,
  repositoryRoot,
  createIfMissing = false,
}) {
  requireAbsolutePath(runRoot, 'runRoot');
  requireAbsolutePath(xdgStateHome, 'XDG_STATE_HOME');
  requireAbsolutePath(repositoryRoot, 'repositoryRoot');
  const absoluteRunRoot = resolve(runRoot);
  const absoluteStateHome = resolve(xdgStateHome);
  const absoluteRepositoryRoot = resolve(repositoryRoot);
  const namespaceRoot = resolve(absoluteStateHome, RUN_NAMESPACE);
  if (!isDescendant(namespaceRoot, absoluteRunRoot)) {
    throw new Error(`runRoot must be an absolute descendant of ${namespaceRoot}.`);
  }
  if (pathsOverlap(absoluteRepositoryRoot, absoluteRunRoot)) {
    throw new Error('runRoot must not resolve inside the repository.');
  }
  await assertNoSymbolicLink(resolve(absoluteStateHome));
  await assertNoSymbolicLink(resolve(namespaceRoot));
  await assertNoSymbolicLink(absoluteRunRoot);
  if (!await pathExists(absoluteRunRoot)) {
    if (!createIfMissing) throw new Error('runRoot must already exist.');
    await mkdir(absoluteRunRoot, { recursive: true, mode: 0o700 });
    await chmod(absoluteRunRoot, 0o700);
  }
  const info = await lstat(absoluteRunRoot);
  if (!info.isDirectory() || (info.mode & 0o777) !== 0o700) {
    throw new Error('runRoot must be a private directory with mode 0700.');
  }
  const resolvedRunRoot = await realpath(absoluteRunRoot);
  const resolvedNamespace = await realpath(namespaceRoot);
  if (!isDescendant(resolvedNamespace, resolvedRunRoot)) {
    throw new Error('runRoot escaped the XDG benchmark namespace through a symbolic link.');
  }
  return resolvedRunRoot;
}
export async function prepareComparisonRunRoot(input) {
  const resolvedRunRoot = await validateComparisonRunRoot({ ...input, createIfMissing: true });
  const journalPath = join(resolvedRunRoot, 'journal.jsonl');
  await writeExclusive(journalPath, '');
  return Object.freeze({ runRoot: resolvedRunRoot, journalPath });
}

export async function executeComparisonStudy({
  manifest,
  runRoot,
  xdgStateHome,
  repositoryRoot,
}, deps) {
  requireDependencies(deps, [
    'verifyRepository',
    'preflight',
    'loadFixture',
    'createSandbox',
    'requestGate',
    'evaluateCandidate',
    'auditStage1',
  ]);
  if (!deps.attempts || typeof deps.attempts.codex !== 'function' || typeof deps.attempts.ollama !== 'function') {
    throw new Error('Both injected provider attempt functions are required.');
  }
  const frozenCommit = await deps.verifyRepository();
  if (frozenCommit !== manifest?.sourceCommit) {
    throw new Error('The checked-out commit does not match the reviewed manifest.');
  }
  const preflight = await deps.preflight({ manifest, repositoryRoot });
  requireTrueFields(preflight, REQUIRED_PREFLIGHT, 'preflight');
  const prepared = await prepareComparisonRunRoot({ runRoot, xdgStateHome, repositoryRoot });
  const rawRoot = join(prepared.runRoot, 'raw');
  const normalizedRoot = join(prepared.runRoot, 'normalized');
  await makePrivateDirectory(rawRoot);
  await makePrivateDirectory(normalizedRoot);
  const manifestPath = join(prepared.runRoot, 'manifest.json');
  await writeExclusiveJson(manifestPath, manifest);
  await writeExclusiveJson(join(prepared.runRoot, 'preflight.json'), preflight);

  const journal = [];
  const terminals = [];
  const rawArtifacts = [];
  let globalStop = false;
  let stage1Eligible = true;

  for (const slot of manifest.schedule) {
    if (!slot.active) {
      await appendTerminal(prepared.journalPath, journal, terminals, terminalFor(slot, slot.classification));
      continue;
    }
    if (globalStop) {
      await appendTerminal(prepared.journalPath, journal, terminals, terminalFor(slot, GLOBAL_STOP));
      continue;
    }
    if (slot.stage === 2 && !stage1Eligible) {
      await appendTerminal(prepared.journalPath, journal, terminals, terminalFor(slot, STAGE1_INELIGIBLE));
      continue;
    }
    if (slot.stage === 2 && terminals.filter((record) => record.stage === 1).length > 0 && stage1Eligible === true) {
      // Stage 1 is evaluated exactly once below, before the first Stage 2 slot.
    }

    if (slot.stage === 2 && !terminals.some((record) => record.stage === 2)) {
      const audit = await deps.auditStage1({ manifest, slots: terminals.filter((record) => record.stage === 1), runRoot: prepared.runRoot });
      requireTrueFields(audit, REQUIRED_STAGE1_AUDIT, 'Stage 1 audit');
      const eligibility = evaluateStage1Eligibility({
        manifest,
        slots: terminals.filter((record) => record.stage === 1),
        audit,
      });
      stage1Eligible = eligibility.eligible;
      await writeExclusiveJson(join(prepared.runRoot, 'stage1-eligibility.json'), eligibility);
      if (!stage1Eligible) {
        await appendTerminal(prepared.journalPath, journal, terminals, terminalFor(slot, STAGE1_INELIGIBLE));
        continue;
      }
    }

    if (
      slot.providerId === 'ollama' &&
      (
        !Number.isInteger(slot.ollamaSeed) ||
        slot.ollamaSeed !== manifest.ollamaSeeds[slot.repeatIndex]
      )
    ) {
      throw new Error(`Ollama slot ${slot.slotId} does not use the reviewed manifest seed vector.`);
    }

    const input = await deps.loadFixture(slot, manifest);
    if (!input || input.digest !== slot.fixtureDigest || input.fixture?.caseId !== slot.fixtureId) {
      throw new Error(`Fixture identity drift for ${slot.slotId}.`);
    }
    const gate = await deps.requestGate({ manifest, slot, input, runRoot: prepared.runRoot });
    if (gate?.classification === GLOBAL_STOP) {
      globalStop = true;
      await appendTerminal(prepared.journalPath, journal, terminals, terminalFor(slot, GLOBAL_STOP));
      continue;
    }

    const start = Object.freeze({ type: 'start', slotId: slot.slotId });
    await appendJournal(prepared.journalPath, start);
    journal.push(start);
    let sandbox = null;
    let attempt;
    try {
      if (slot.providerId === 'codex') {
        sandbox = await deps.createSandbox({ manifest, slot, runRoot: prepared.runRoot });
      }
      attempt = await deps.attempts[slot.providerId]({
        manifest,
        slot,
        fixture: input.fixture,
        input,
        seed: slot.ollamaSeed,
        sandbox,
      });
    } catch (error) {
      attempt = {
        classification: typeof error?.classification === 'string' ? error.classification : 'process_crash',
        rawEvents: [],
        error: error instanceof Error ? { name: error.name, message: error.message } : { message: String(error) },
      };
    } finally {
      await sandbox?.cleanup();
    }
    if (attempt?.globalStop === true || attempt?.classification === GLOBAL_STOP) {
      globalStop = true;
    } else if (attempt?.classification === STAGE1_INELIGIBLE) {
      attempt = { ...attempt, classification: 'provider_protocol_error' };
    }

    const rawArtifactPath = join(rawRoot, `${slot.slotId}.json`);
    await makePrivateDirectory(dirname(rawArtifactPath));
    await writeExclusiveJson(rawArtifactPath, attempt);
    rawArtifacts.push(Object.freeze({
      id: slot.slotId,
      available: true,
      digest: await digestFile(rawArtifactPath),
    }));
    const transcript = normalizeProviderTranscript({
      providerId: slot.providerId,
      rawEvents: attempt?.rawEvents ?? [],
      canaries: deps.canaries,
    });
    const normalizedArtifactPath = join(normalizedRoot, `${slot.slotId}.json`);
    await makePrivateDirectory(dirname(normalizedArtifactPath));
    await writeExclusiveJson(normalizedArtifactPath, transcript);

    let terminal;
    if (attempt?.classification === 'candidate_pass' && typeof attempt.candidateJson === 'string') {
      const evaluated = await deps.evaluateCandidate({
        manifest,
        slot,
        candidateJson: attempt.candidateJson,
        input,
      });
      terminal = terminalFor(slot, evaluated.classification, evaluated);
    } else {
      terminal = terminalFor(slot, attempt?.classification ?? 'provider_protocol_error');
    }
    await appendTerminal(prepared.journalPath, journal, terminals, terminal);
  }

  if (!globalStop && !await pathExists(join(prepared.runRoot, 'stage1-eligibility.json'))) {
    const audit = await deps.auditStage1({ manifest, slots: terminals.filter((record) => record.stage === 1), runRoot: prepared.runRoot });
    requireTrueFields(audit, REQUIRED_STAGE1_AUDIT, 'Stage 1 audit');
    const eligibility = evaluateStage1Eligibility({
      manifest,
      slots: terminals.filter((record) => record.stage === 1),
      audit,
    });
    stage1Eligible = eligibility.eligible;
    await writeExclusiveJson(join(prepared.runRoot, 'stage1-eligibility.json'), eligibility);
  }

  const journalSummary = validateComparisonJournal({ manifest, journal });
  const manifestSha256 = await digestFile(manifestPath);
  const evidence = finalizeComparisonEvidence({
    manifest,
    manifestSha256,
    frozenCommit,
    preflight,
    journal,
    rawArtifacts,
  });
  const qualification = Object.freeze({
    ollama: qualifyProvider({ providerId: 'ollama', slots: terminals }),
    codex: qualifyProvider({ providerId: 'codex', slots: terminals }),
  });
  await writeExclusiveJson(join(prepared.runRoot, 'qualification.json'), qualification);
  await writeExclusiveJson(join(prepared.runRoot, 'evidence.json'), evidence);
  return Object.freeze({
    runRoot: prepared.runRoot,
    slots: Object.freeze(terminals),
    journal: journalSummary,
    qualification,
    evidence,
  });
}

function terminalFor(slot, classification, details = {}) {
  return Object.freeze({
    type: 'terminal',
    terminal: true,
    slotId: slot.slotId,
    pairId: slot.pairId,
    fixtureId: slot.fixtureId,
    providerId: slot.providerId,
    stage: slot.stage,
    active: slot.active,
    classification,
    preparationPassed: details.preparationPassed === true,
    passedRubric: details.validations?.rubric === true,
    safetyViolations: details.safetyViolations ?? 0,
    toolUseViolations: classification === 'tool_use' ? 1 : (details.toolUseViolations ?? 0),
    stateMutationViolations: classification === 'state_mutation'
      ? 1
      : (details.stateMutationViolations ?? details.mutationViolations ?? 0),
    credentialLeakageViolations: classification === 'credential_leakage'
      ? 1
      : (details.credentialLeakageViolations ?? 0),
    identityDrift: classification === 'identity_drift' || details.identityDrift === true,
    replayMismatch: details.replayMismatch === true,
    validations: details.validations ?? null,
  });
}

async function appendTerminal(journalPath, journal, terminals, terminal) {
  await appendJournal(journalPath, terminal);
  journal.push(terminal);
  terminals.push(terminal);
}

async function appendJournal(path, event) {
  const handle = await open(path, 'a', 0o600);
  try {
    await handle.writeFile(`${JSON.stringify(event)}\n`, 'utf8');
    await handle.sync();
  } finally {
    await handle.close();
  }
}

async function writeExclusiveJson(path, value) {
  await writeExclusive(path, `${JSON.stringify(value, null, 2)}\n`);
}

async function writeExclusive(path, contents) {
  await writeFile(path, contents, { encoding: 'utf8', flag: 'wx', mode: 0o600 });
  await chmod(path, 0o600);
}

async function makePrivateDirectory(path) {
  await mkdir(path, { recursive: true, mode: 0o700 });
  await chmod(path, 0o700);
}

async function digestFile(path) {
  return createHash('sha256').update(await readFile(path)).digest('hex');
}

function requireAbsolutePath(path, name) {
  if (typeof path !== 'string' || path.length === 0 || !isAbsolute(path)) {
    throw new Error(`${name} must be set to an absolute path.`);
  }
}

function requireDependencies(deps, names) {
  if (!deps || typeof deps !== 'object') throw new Error('Runner dependencies are required.');
  for (const name of names) {
    if (typeof deps[name] !== 'function') throw new Error(`Runner dependency ${name} is required.`);
  }
}

function requireTrueFields(value, fields, label) {
  if (!value || fields.some((field) => value[field] !== true)) {
    throw new Error(`${label} failed closed.`);
  }
}

function isDescendant(parent, child) {
  const rel = relative(parent, child);
  return rel.length > 0 && rel !== '..' && !rel.startsWith(`..${sep}`) && !isAbsolute(rel);
}

function pathsOverlap(first, second) {
  return first === second || isDescendant(first, second) || isDescendant(second, first);
}

async function assertNoSymbolicLink(path) {
  const absolute = resolve(path);
  const root = absolute.slice(0, 1);
  let cursor = root;
  for (const segment of absolute.split(sep).filter(Boolean)) {
    cursor = join(cursor, segment);
    try {
      const info = await lstat(cursor);
      if (info.isSymbolicLink()) throw new Error(`Path contains a symbolic link: ${cursor}`);
    } catch (error) {
      if (error?.code === 'ENOENT') return;
      throw error;
    }
  }
}

async function pathExists(path) {
  try {
    await lstat(path);
    return true;
  } catch (error) {
    if (error?.code === 'ENOENT') return false;
    throw error;
  }
}

async function runCli(argv) {
  const manifestIndex = argv.indexOf('--manifest');
  const runRootIndex = argv.indexOf('--run-root');
  if (manifestIndex < 0 || runRootIndex < 0 || !argv[manifestIndex + 1] || !argv[runRootIndex + 1]) {
    throw new Error('Usage: run-genui-provider-comparison-study.mjs --manifest PATH --run-root PATH');
  }
  const manifest = JSON.parse(await readFile(resolve(argv[manifestIndex + 1]), 'utf8'));
  const dependencyModule = process.env.GENUI_PROVIDER_COMPARISON_DEPS;
  if (!dependencyModule) {
    throw new Error('GENUI_PROVIDER_COMPARISON_DEPS must name the reviewed production dependency module.');
  }
  const imported = await import(pathToFileURL(resolve(dependencyModule)).href);
  const deps = await imported.createComparisonDependencies({ manifest });
  const result = await executeComparisonStudy({
    manifest,
    runRoot: resolve(argv[runRootIndex + 1]),
    xdgStateHome: process.env.XDG_STATE_HOME,
    repositoryRoot: resolve(import.meta.dirname, '../../..'),
  }, deps);
  process.stdout.write(`${JSON.stringify({ runRoot: result.runRoot, evidence: result.evidence }, null, 2)}\n`);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  runCli(process.argv.slice(2)).catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.stack : String(error)}\n`);
    process.exitCode = 1;
  });
}
