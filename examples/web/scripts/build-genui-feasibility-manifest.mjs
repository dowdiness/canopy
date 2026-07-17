import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';

import { GENUI_CANDIDATE_SCHEMA } from '../src/genui-candidate-schema.js';
import {
  GENUI_FEASIBILITY_FIXTURES,
  capabilitiesJsonForFixture,
} from '../src/genui-feasibility-fixtures.js';
import {
  GENUI_PROVIDER_SETTINGS,
  buildFeasibilityPrompt,
  canonicalJson,
  readOllamaIdentity,
  sha256Hex,
} from '../src/genui-feasibility-provider.js';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(SCRIPT_DIR, '../../..');

function git(args) {
  const result = spawnSync('git', args, { cwd: REPOSITORY_ROOT, encoding: 'utf8' });
  if (result.status !== 0) {
    throw new Error(`git ${args.join(' ')} failed: ${(result.stderr || result.stdout).trim()}`);
  }
  return result.stdout;
}

function verifyBuilderRepository() {
  if (git(['status', '--porcelain']) !== '') {
    throw new Error('Manifest discovery requires a clean committed implementation tree');
  }
  return git(['rev-parse', 'HEAD']).trim();
}

function digestFile(path) {
  return sha256Hex(readFileSync(resolve(REPOSITORY_ROOT, path)));
}

function parseArguments(argv) {
  const args = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith('--') || value === undefined) {
      throw new Error('Usage: build-genui-feasibility-manifest.mjs --model TAG --output PATH');
    }
    args.set(key.slice(2), value);
  }
  const model = args.get('model');
  const output = args.get('output');
  if (!model || !output || args.size !== 2) {
    throw new Error('Usage: build-genui-feasibility-manifest.mjs --model TAG --output PATH');
  }
  return { model, output };
}

export async function buildManifest({
  model,
  readIdentity = readOllamaIdentity,
  verifyRepository = verifyBuilderRepository,
}) {
  const sourceCommit = verifyRepository();
  const modelIdentity = await readIdentity(model);
  const schedule = GENUI_FEASIBILITY_FIXTURES.flatMap((fixture) =>
    GENUI_PROVIDER_SETTINGS.slotSeeds.map((seed, slotId) => ({ caseId: fixture.caseId, slotId, seed }))
  );
  const fixturesCanonical = canonicalJson(GENUI_FEASIBILITY_FIXTURES);
  const capabilitiesCanonical = canonicalJson(GENUI_FEASIBILITY_FIXTURES.map((fixture) => ({
    caseId: fixture.caseId,
    capabilities: JSON.parse(capabilitiesJsonForFixture(fixture)),
  })));
  const promptsCanonical = canonicalJson(GENUI_FEASIBILITY_FIXTURES.map((fixture) => ({
    caseId: fixture.caseId,
    prompt: buildFeasibilityPrompt(fixture),
  })));

  return {
    manifestVersion: 1,
    studyId: 'genui-local-llm-v2',
    claimScope: 'technical feasibility only; no usability, task-performance, adoption, or product-value claim',
    changedInputReason:
      'validation children remove inherited GENUI_FEASIBILITY_* before manifest env overlay',
    sourceCommit,
    modelIdentity,
    generationSettings: {
      stream: GENUI_PROVIDER_SETTINGS.stream,
      temperature: GENUI_PROVIDER_SETTINGS.temperature,
      numCtx: GENUI_PROVIDER_SETTINGS.numCtx,
      numPredict: GENUI_PROVIDER_SETTINGS.numPredict,
      keepAlive: GENUI_PROVIDER_SETTINGS.keepAlive,
      timeoutMs: GENUI_PROVIDER_SETTINGS.timeoutMs,
      slotSeeds: [...GENUI_PROVIDER_SETTINGS.slotSeeds],
      maxCandidateBytes: GENUI_PROVIDER_SETTINGS.maxCandidateBytes,
    },
    schedule,
    inputDigests: {
      candidateSchemaSha256: sha256Hex(canonicalJson(GENUI_CANDIDATE_SCHEMA)),
      fixturesSha256: sha256Hex(fixturesCanonical),
      normalizerSourceSha256: digestFile('examples/web/src/genui-feasibility-fixtures.js'),
      capabilitiesSha256: sha256Hex(capabilitiesCanonical),
      promptSha256: sha256Hex(promptsCanonical),
      rubricSourceSha256: digestFile('ffi/jsx/generative_ui_feasibility_rubric.mbt'),
      preparationCoreSourceSha256: digestFile('ffi/jsx/generative_ui_feasibility_adapter.mbt'),
    },
    decisionRule: {
      positive: 'all_checks_pass_and_each_fixture_has_success',
      negative: 'otherwise',
      requiredSlots: 9,
      noRetry: true,
      replayRequiredForEveryCandidate: true,
    },
    validationCommands: [
      { id: 'moonbit-tests', command: 'moon', args: ['test', 'ffi/jsx'], cwd: '.', env: { NEW_MOON_MOD: '0' } },
      {
        id: 'node-tests',
        command: 'node',
        args: [
          '--test',
          'src/genui-feasibility-fixtures.test.mjs',
          'src/genui-feasibility-provider.test.mjs',
          'src/genui-feasibility-demo.test.mjs',
          'src/genui-feasibility-flow.test.mjs',
          'scripts/run-genui-feasibility-study.test.mjs',
        ],
        cwd: 'examples/web',
        env: {},
      },
      { id: 'moonbit-js-build', command: 'moon', args: ['build', '--target', 'js'], cwd: '.', env: { NEW_MOON_MOD: '0' } },
      { id: 'typescript', command: 'npx', args: ['tsc', '--noEmit'], cwd: 'examples/web', env: {} },
      {
        id: 'development-e2e',
        command: 'npx',
        args: ['playwright', 'test', 'tests/genui.spec.ts', '--project=chromium', '--grep', 'feasibility'],
        cwd: 'examples/web',
        env: {},
      },
      { id: 'production-build', command: 'npm', args: ['run', 'build'], cwd: 'examples/web', env: { NEW_MOON_MOD: '0' } },
      {
        id: 'production-e2e',
        command: 'npx',
        args: [
          'playwright', 'test',
          '--config=playwright.preview.config.ts',
          '--project=chromium',
          '--grep', 'local study runner|local provider marker',
        ],
        cwd: 'examples/web',
        env: {},
      },
    ],
    journalPath: 'examples/web/test-results/genui-feasibility-live-v2/journal.jsonl',
    rawOutputPath: 'examples/web/test-results/genui-feasibility-live-v2/raw-slots.json',
    evidencePath: 'docs/evidence/2026-07-15-generative-ui-local-llm-feasibility-v2.json',
  };
}

async function main() {
  const { model, output } = parseArguments(process.argv.slice(2));
  const outputPath = resolve(REPOSITORY_ROOT, output);
  if (existsSync(outputPath)) throw new Error(`Refusing to overwrite manifest: ${outputPath}`);
  const manifest = await buildManifest({ model });
  mkdirSync(dirname(outputPath), { recursive: true });
  writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`, { flag: 'wx' });
  process.stdout.write(`${output}\n`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  main().catch((error) => {
    process.stderr.write(`${error.stack ?? error}\n`);
    process.exitCode = 1;
  });
}
