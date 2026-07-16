import { randomBytes } from 'node:crypto';
import { closeSync, existsSync, fsyncSync, mkdirSync, openSync, readFileSync, writeSync } from 'node:fs';
import { dirname, relative, resolve, sep } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { canonicalJson, readOllamaIdentity, sha256Hex } from '../src/genui-feasibility-provider.js';
import { finalizeFromFiles } from './finalize-genui-feasibility-study.mjs';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(SCRIPT_DIR, '../../..');
const WEB_ROOT = resolve(REPOSITORY_ROOT, 'examples/web');
const HEX_64 = /^[0-9a-f]{64}$/;

export function assertUnusedOutputs({ journalExists, evidenceExists }) {
  if (journalExists) throw new Error('Study journal already exists; refusing execute mode');
  if (evidenceExists) throw new Error('Study evidence already exists; refusing execute mode');
}

export function createRunCapability(randomBytesImpl = randomBytes) {
  const bytes = randomBytesImpl(32);
  if (!Buffer.isBuffer(bytes) && !(bytes instanceof Uint8Array)) {
    throw new Error('Run capability source must return bytes');
  }
  if (bytes.byteLength !== 32) throw new Error('Run capability source must return exactly 32 bytes');
  return Buffer.from(bytes).toString('hex');
}

export function appendJournalEvent(journalPath, event) {
  mkdirSync(dirname(journalPath), { recursive: true });
  const file = openSync(journalPath, 'a', 0o600);
  try {
    writeSync(file, `${canonicalJson(event)}\n`);
    fsyncSync(file);
  } finally {
    closeSync(file);
  }
}

function runGit(args, cwd = REPOSITORY_ROOT) {
  const result = spawnSync('git', args, { cwd, encoding: 'utf8' });
  if (result.status !== 0) {
    throw new Error(`git ${args.join(' ')} failed: ${(result.stderr || result.stdout).trim()}`);
  }
  return result.stdout;
}

function repositoryRelativePath(absolutePath) {
  const path = relative(REPOSITORY_ROOT, absolutePath);
  if (path === '' || path === '..' || path.startsWith(`..${sep}`)) {
    throw new Error('Study manifest must be inside the repository');
  }
  return path.split(sep).join('/');
}

export function verifyFrozenRepository(manifestPath) {
  const dirty = runGit(['status', '--porcelain']);
  if (dirty !== '') throw new Error('Study execution requires a clean working tree');
  const absoluteManifestPath = resolve(REPOSITORY_ROOT, manifestPath);
  const relativeManifestPath = repositoryRelativePath(absoluteManifestPath);
  runGit(['ls-files', '--error-unmatch', '--', relativeManifestPath]);
  const committed = Buffer.from(runGit(['show', `HEAD:${relativeManifestPath}`]));
  const working = readFileSync(absoluteManifestPath);
  if (!working.equals(committed)) {
    throw new Error('Working manifest bytes do not match the committed manifest');
  }
  return {
    absoluteManifestPath,
    relativeManifestPath,
    frozenCommit: runGit(['rev-parse', 'HEAD']).trim(),
    manifestBytes: working,
    manifestSha256: sha256Hex(working),
  };
}

function validateManifest(manifest) {
  if (manifest?.manifestVersion !== 1 || typeof manifest.studyId !== 'string') {
    throw new Error('Unsupported feasibility study manifest');
  }
  if (!Array.isArray(manifest.schedule) || manifest.schedule.length !== 9) {
    throw new Error('Study manifest must freeze exactly nine schedule slots');
  }
  if (!manifest.modelIdentity || typeof manifest.modelIdentity.lookupTag !== 'string') {
    throw new Error('Study manifest is missing frozen model identity');
  }
  for (const field of [
    'modelManifestSha256',
    'showDetailsSha256',
    'templateSha256',
    'parametersSha256',
  ]) {
    if (!HEX_64.test(manifest.modelIdentity[field] ?? '')) {
      throw new Error(`Study manifest model identity field ${field} is invalid`);
    }
  }
  if (!Array.isArray(manifest.validationCommands) || manifest.validationCommands.length === 0) {
    throw new Error('Study manifest is missing deterministic validation commands');
  }
  if (typeof manifest.journalPath !== 'string' || typeof manifest.evidencePath !== 'string') {
    throw new Error('Study manifest output paths are missing');
  }
}

function runCommand(check) {
  const cwd = check.cwd === '.' ? REPOSITORY_ROOT : resolve(REPOSITORY_ROOT, check.cwd);
  const result = spawnSync(check.command, check.args, {
    cwd,
    env: { ...process.env, ...check.env },
    stdio: 'inherit',
  });
  return {
    id: check.id,
    command: [check.command, ...check.args].join(' '),
    cwd: check.cwd,
    exitCode: result.status ?? 1,
    signal: result.signal ?? null,
  };
}

export function runDeterministicPreflight(validationCommands) {
  const checks = [];
  for (const command of validationCommands) {
    const result = runCommand(command);
    checks.push(result);
    if (result.exitCode !== 0) break;
  }
  return {
    passed: checks.length === validationCommands.length && checks.every((check) => check.exitCode === 0),
    checks,
  };
}

function identityMatches(frozen, current) {
  return frozen.lookupTag === current.lookupTag &&
    frozen.ollamaVersion === current.ollamaVersion &&
    frozen.modelManifestSha256 === current.modelManifestSha256 &&
    frozen.showDetailsSha256 === current.showDetailsSha256 &&
    frozen.templateSha256 === current.templateSha256 &&
    frozen.parametersSha256 === current.parametersSha256;
}

function appendStudyMetadata(journalPath, metadata) {
  appendJournalEvent(journalPath, { kind: 'study', ...metadata });
}

function writePreflightFailureEvidence({
  manifest,
  frozen,
  preflight,
  journalPath,
}) {
  appendStudyMetadata(journalPath, {
    frozenCommit: frozen.frozenCommit,
    manifestSha256: frozen.manifestSha256,
    preflight,
  });
  return finalizeFromFiles({
    repositoryRoot: REPOSITORY_ROOT,
    manifestPath: frozen.relativeManifestPath,
    journalPath: repositoryRelativePath(journalPath),
    evidencePath: manifest.evidencePath,
  });
}

export async function executeStudy({
  manifestPath,
  live = process.env.GENUI_FEASIBILITY_LIVE === '1',
  fake = process.env.GENUI_FEASIBILITY_FAKE === '1',
  randomBytesImpl = randomBytes,
} = {}) {
  if (!live) throw new Error('Set GENUI_FEASIBILITY_LIVE=1 to execute the frozen study');
  if (!manifestPath) throw new Error('GENUI_FEASIBILITY_MANIFEST is required');

  const frozen = verifyFrozenRepository(manifestPath);
  const manifest = JSON.parse(frozen.manifestBytes.toString('utf8'));
  validateManifest(manifest);
  const journalPath = resolve(REPOSITORY_ROOT, manifest.journalPath);
  const evidencePath = resolve(REPOSITORY_ROOT, manifest.evidencePath);
  assertUnusedOutputs({
    journalExists: existsSync(journalPath),
    evidenceExists: existsSync(evidencePath),
  });

  const preflight = runDeterministicPreflight(manifest.validationCommands);
  if (!preflight.passed) {
    return writePreflightFailureEvidence({ manifest, frozen, preflight, journalPath });
  }

  if (!fake) {
    let currentIdentity;
    try {
      currentIdentity = await readOllamaIdentity(manifest.modelIdentity.lookupTag);
    } catch (error) {
      preflight.passed = false;
      preflight.checks.push({
        id: 'model-identity',
        command: 'provider-read-only model identity discovery',
        cwd: 'examples/web',
        exitCode: 1,
        signal: null,
        classification: 'model_identity_unavailable',
      });
      return writePreflightFailureEvidence({ manifest, frozen, preflight, journalPath });
    }
    if (!identityMatches(manifest.modelIdentity, currentIdentity)) {
      preflight.passed = false;
      preflight.checks.push({
        id: 'model-identity',
        command: 'provider-read-only model identity comparison',
        cwd: 'examples/web',
        exitCode: 1,
        signal: null,
        classification: 'model_identity_mismatch',
      });
      return writePreflightFailureEvidence({ manifest, frozen, preflight, journalPath });
    }
    preflight.checks.push({
      id: 'model-identity',
      command: 'provider-read-only model identity comparison',
      cwd: 'examples/web',
      exitCode: 0,
      signal: null,
      classification: 'matched',
    });
  }

  const runCapability = createRunCapability(randomBytesImpl);
  appendStudyMetadata(journalPath, {
    frozenCommit: frozen.frozenCommit,
    manifestSha256: frozen.manifestSha256,
    preflight,
  });
  const rawOutputPath = resolve(REPOSITORY_ROOT, manifest.rawOutputPath);
  const liveResult = spawnSync(
    'npx',
    ['playwright', 'test', '--config=playwright.feasibility.config.ts', '--project=chromium'],
    {
      cwd: WEB_ROOT,
      env: {
        ...process.env,
        GENUI_FEASIBILITY_LIVE: '1',
        GENUI_FEASIBILITY_FAKE: fake ? '1' : '0',
        GENUI_FEASIBILITY_MANIFEST: frozen.absoluteManifestPath,
        GENUI_FEASIBILITY_RUN_CAPABILITY: runCapability,
        GENUI_FEASIBILITY_JOURNAL: journalPath,
        GENUI_FEASIBILITY_RAW_OUTPUT: rawOutputPath,
      },
      stdio: 'inherit',
    },
  );
  appendJournalEvent(journalPath, {
    kind: 'harness',
    exitCode: liveResult.status ?? 1,
    signal: liveResult.signal ?? null,
  });

  const finalized = finalizeFromFiles({
    repositoryRoot: REPOSITORY_ROOT,
    manifestPath: frozen.relativeManifestPath,
    journalPath: repositoryRelativePath(journalPath),
    evidencePath: manifest.evidencePath,
  });
  return finalized;
}

function parseCliArguments(argv) {
  if (argv.length !== 0) throw new Error('This runner accepts configuration through environment variables only');
  return {
    manifestPath: process.env.GENUI_FEASIBILITY_MANIFEST,
  };
}

async function main() {
  const result = await executeStudy(parseCliArguments(process.argv.slice(2)));
  process.stdout.write(`${result.evidence.decision} ${result.evidencePath}\n`);
  if (result.evidence.decision !== 'TECHNICALLY_FEASIBLE') process.exitCode = 2;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  main().catch((error) => {
    process.stderr.write(`${error.stack ?? error}\n`);
    process.exitCode = 1;
  });
}
