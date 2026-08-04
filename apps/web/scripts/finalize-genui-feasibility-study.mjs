import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HEX_64 = /^[0-9a-f]{64}$/;
const NON_TERMINAL_CLASSIFICATIONS = new Set([
  'interrupted',
  'not_run_interrupted',
  'not_run_missing_journal',
  'not_run_preflight_failure',
  'not_run_harness_failure',
]);

function sha256Hex(value) {
  return createHash('sha256').update(value).digest('hex');
}

function slotKey(caseId, slotId) {
  return `${caseId}\u0000${slotId}`;
}

function sanitizeProvider(provider) {
  if (!provider || typeof provider !== 'object') return null;
  return {
    classification: typeof provider.classification === 'string' ? provider.classification : null,
    model: typeof provider.model === 'string' ? provider.model : null,
    ollamaVersion: typeof provider.ollamaVersion === 'string' ? provider.ollamaVersion : null,
    lookupTag: typeof provider.lookupTag === 'string' ? provider.lookupTag : null,
    modelManifestSha256: typeof provider.modelManifestSha256 === 'string' ? provider.modelManifestSha256 : null,
    showDetailsSha256: typeof provider.showDetailsSha256 === 'string' ? provider.showDetailsSha256 : null,
    templateSha256: typeof provider.templateSha256 === 'string' ? provider.templateSha256 : null,
    parametersSha256: typeof provider.parametersSha256 === 'string' ? provider.parametersSha256 : null,
    promptSha256: typeof provider.promptSha256 === 'string' ? provider.promptSha256 : null,
    schemaSha256: typeof provider.schemaSha256 === 'string' ? provider.schemaSha256 : null,
    elapsedMs: Number.isFinite(provider.elapsedMs) ? provider.elapsedMs : null,
    providerDurationMs: Number.isFinite(provider.providerDurationMs) ? provider.providerDurationMs : null,
    promptTokens: Number.isFinite(provider.promptTokens) ? provider.promptTokens : null,
    outputTokens: Number.isFinite(provider.outputTokens) ? provider.outputTokens : null,
  };
}

function sanitizeTerminalResult(scheduleSlot, result) {
  const rawCandidate = typeof result?.candidateJson === 'string' ? result.candidateJson : null;
  const candidateSha256 = rawCandidate === null
    ? (HEX_64.test(result?.candidateSha256 ?? '') ? result.candidateSha256 : null)
    : sha256Hex(rawCandidate);
  return {
    ...scheduleSlot,
    classification: typeof result?.classification === 'string'
      ? result.classification
      : 'harness_result_invalid',
    candidateSha256,
    replayEqual: typeof result?.replayEqual === 'boolean' ? result.replayEqual : null,
    safeOutputSha256: HEX_64.test(result?.safeOutputSha256 ?? '')
      ? result.safeOutputSha256
      : (HEX_64.test(result?.safe_output_sha256 ?? '') ? result.safe_output_sha256 : null),
    evidence: result?.evidence && typeof result.evidence === 'object' ? result.evidence : null,
    rubric: result?.rubric && typeof result.rubric === 'object' ? result.rubric : null,
    session: result?.session && typeof result.session === 'object'
      ? {
          success: result.session.success === true,
          revision: Number.isInteger(result.session.revision) ? result.session.revision : null,
          errorCode: typeof result.session.error?.code === 'string' ? result.session.error.code : null,
        }
      : null,
    provider: sanitizeProvider(result?.provider),
  };
}

function validateSchedule(schedule) {
  if (!Array.isArray(schedule) || schedule.length !== 9) {
    throw new Error('Study manifest schedule must contain exactly nine slots');
  }
  const keys = new Set();
  for (const slot of schedule) {
    if (!slot || typeof slot.caseId !== 'string' || !Number.isInteger(slot.slotId)) {
      throw new Error('Study manifest contains an invalid schedule slot');
    }
    const key = slotKey(slot.caseId, slot.slotId);
    if (keys.has(key)) throw new Error(`Study manifest repeats slot ${slot.caseId}/${slot.slotId}`);
    keys.add(key);
  }
}

export function finalizeEvidence({
  manifest,
  manifestSha256,
  frozenCommit,
  preflight,
  journal,
}) {
  validateSchedule(manifest.schedule);
  if (!HEX_64.test(manifestSha256)) throw new Error('Manifest SHA-256 is invalid');
  if (typeof frozenCommit !== 'string' || frozenCommit.length === 0) {
    throw new Error('Frozen Git commit is required');
  }
  const events = Array.isArray(journal) ? journal : [];
  const scheduledKeys = new Set(
    manifest.schedule.map((slot) => slotKey(slot.caseId, slot.slotId)),
  );
  const started = new Map();
  const terminals = new Map();
  const harnessEvents = [];
  let duplicateEvents = 0;
  let nextSlotIndex = 0;
  let activeSlotKey = null;
  let journalProtocolValid = true;
  for (const event of events) {
    if (!event || typeof event !== 'object') {
      journalProtocolValid = false;
      continue;
    }
    if (event.kind === 'study') continue;
    if (event.kind === 'harness') {
      harnessEvents.push(event);
      if (
        harnessEvents.length !== 1 ||
        activeSlotKey !== null ||
        nextSlotIndex !== manifest.schedule.length
      ) {
        journalProtocolValid = false;
      }
      continue;
    }
    if (event.kind !== 'started' && event.kind !== 'terminal') {
      journalProtocolValid = false;
      continue;
    }
    if (harnessEvents.length !== 0) journalProtocolValid = false;
    const key = slotKey(event.caseId, event.slotId);
    if (!scheduledKeys.has(key)) journalProtocolValid = false;
    if (event.kind === 'started') {
      if (started.has(key)) duplicateEvents += 1;
      const expectedSlot = manifest.schedule[nextSlotIndex];
      const expectedKey = expectedSlot === undefined
        ? null
        : slotKey(expectedSlot.caseId, expectedSlot.slotId);
      if (activeSlotKey !== null || key !== expectedKey) {
        journalProtocolValid = false;
      } else {
        activeSlotKey = key;
      }
      started.set(key, event);
    } else {
      if (terminals.has(key)) duplicateEvents += 1;
      if (activeSlotKey !== key || !started.has(key)) {
        journalProtocolValid = false;
      } else {
        activeSlotKey = null;
        nextSlotIndex += 1;
      }
      terminals.set(key, event.result);
    }
  }
  journalProtocolValid = journalProtocolValid &&
    activeSlotKey === null &&
    nextSlotIndex === manifest.schedule.length;
  const harnessPassed = harnessEvents.length === 1 &&
    harnessEvents[0].exitCode === 0 &&
    harnessEvents[0].signal == null;

  const slots = [];
  let interruptionSeen = false;
  for (const scheduleSlot of manifest.schedule) {
    const key = slotKey(scheduleSlot.caseId, scheduleSlot.slotId);
    if (terminals.has(key)) {
      slots.push(sanitizeTerminalResult(scheduleSlot, terminals.get(key)));
      continue;
    }
    let classification;
    if (preflight?.passed !== true) {
      classification = 'not_run_preflight_failure';
    } else if (interruptionSeen) {
      classification = 'not_run_interrupted';
    } else if (started.has(key)) {
      classification = 'interrupted';
      interruptionSeen = true;
    } else if (events.length === 0) {
      classification = 'not_run_missing_journal';
    } else {
      classification = 'not_run_harness_failure';
    }
    slots.push({
      ...scheduleSlot,
      classification,
      candidateSha256: null,
      replayEqual: null,
      safeOutputSha256: null,
      evidence: null,
      rubric: null,
      session: null,
      provider: null,
    });
  }

  const fixtureIds = [...new Set(manifest.schedule.map((slot) => slot.caseId))];
  const everyCandidateReplayed = slots.every((slot) => {
    const requiresReplay = slot.classification === 'success' ||
      slot.provider?.classification === 'success' ||
      slot.candidateSha256 !== null;
    return !requiresReplay ||
      (HEX_64.test(slot.candidateSha256 ?? '') && slot.replayEqual === true);
  });
  const eachFixtureHasSuccess = fixtureIds.every(
    (caseId) => slots.some((slot) => slot.caseId === caseId && slot.classification === 'success'),
  );
  const everySlotTerminal = slots.every(
    (slot) => !NON_TERMINAL_CLASSIFICATIONS.has(slot.classification),
  );
  const decision = preflight?.passed === true && duplicateEvents === 0 &&
    journalProtocolValid && harnessPassed && everySlotTerminal &&
    everyCandidateReplayed && eachFixtureHasSuccess
    ? 'TECHNICALLY_FEASIBLE'
    : 'NOT_YET_FEASIBLE';

  return {
    evidenceVersion: 1,
    studyId: manifest.studyId,
    decision,
    claimScope: 'technical feasibility only; no usability, task-performance, adoption, or product-value claim',
    frozenCommit,
    manifestSha256,
    modelIdentity: manifest.modelIdentity ?? null,
    generationSettings: manifest.generationSettings ?? null,
    inputDigests: manifest.inputDigests ?? null,
    decisionRule: manifest.decisionRule,
    preflight: preflight ?? { passed: false, checks: [] },
    audit: {
      scheduledSlots: manifest.schedule.length,
      terminalSlots: slots.length,
      duplicateEvents,
      journalProtocolValid,
      harnessPassed,
      everyCandidateReplayed,
      eachFixtureHasSuccess,
      everySlotTerminal,
    },
    slots,
  };
}

export function parseJournal(text) {
  if (text.trim() === '') return [];
  return text.trimEnd().split('\n').map((line, index) => {
    try {
      return JSON.parse(line);
    } catch (error) {
      throw new Error(`Journal line ${index + 1} is invalid JSON: ${error.message}`);
    }
  });
}

function resolveFromRoot(repositoryRoot, path) {
  return resolve(repositoryRoot, path);
}

export function finalizeFromFiles({ repositoryRoot, manifestPath, journalPath, evidencePath }) {
  const manifestBytes = readFileSync(resolveFromRoot(repositoryRoot, manifestPath));
  const manifest = JSON.parse(manifestBytes.toString('utf8'));
  const resolvedJournal = resolveFromRoot(repositoryRoot, journalPath ?? manifest.journalPath);
  const resolvedEvidence = resolveFromRoot(repositoryRoot, evidencePath ?? manifest.evidencePath);
  if (existsSync(resolvedEvidence)) throw new Error(`Study evidence already exists: ${resolvedEvidence}`);
  const journal = existsSync(resolvedJournal)
    ? parseJournal(readFileSync(resolvedJournal, 'utf8'))
    : [];
  const metadata = journal.find((event) => event?.kind === 'study');
  const evidence = finalizeEvidence({
    manifest,
    manifestSha256: metadata?.manifestSha256 ?? sha256Hex(manifestBytes),
    frozenCommit: metadata?.frozenCommit ?? manifest.sourceCommit,
    preflight: metadata?.preflight ?? { passed: false, checks: [] },
    journal,
  });
  mkdirSync(dirname(resolvedEvidence), { recursive: true });
  writeFileSync(resolvedEvidence, `${JSON.stringify(evidence, null, 2)}\n`, { flag: 'wx' });
  return { evidence, evidencePath: resolvedEvidence };
}

function parseCliArguments(argv) {
  const args = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith('--') || value === undefined) {
      throw new Error('Usage: finalize-genui-feasibility-study.mjs --manifest PATH [--journal PATH] [--evidence PATH]');
    }
    args.set(key.slice(2), value);
  }
  return args;
}

async function main() {
  const args = parseCliArguments(process.argv.slice(2));
  const manifestPath = args.get('manifest') ?? process.env.GENUI_FEASIBILITY_MANIFEST;
  if (!manifestPath) throw new Error('A manifest path is required');
  const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
  const result = finalizeFromFiles({
    repositoryRoot,
    manifestPath,
    journalPath: args.get('journal'),
    evidencePath: args.get('evidence'),
  });
  process.stdout.write(`${result.evidence.decision} ${result.evidencePath}\n`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  main().catch((error) => {
    process.stderr.write(`${error.stack ?? error}\n`);
    process.exitCode = 1;
  });
}
