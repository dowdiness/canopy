import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, readdir, realpath, stat, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, join } from 'node:path';
import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import test from 'node:test';

import {
  createPrivateRun,
  parseMinimalProviderArgs,
  runMinimalProviderE2E,
  runProviderAttempt,
  writeTerminalResult,
} from './run-genui-minimal-provider-e2e.mjs';
import { GENUI_PROVIDER_SETTINGS } from '../src/genui-feasibility-provider.js';
import { recordedFeasibilityCandidateJson } from '../src/genui-recorded-candidates.js';

const fixtureId = 'orders-pending-attention';

async function sandbox() {
  const root = await mkdtemp(join(tmpdir(), 'canopy-minimal-e2e-'));
  const repositoryRoot = await realpath(join(import.meta.dirname, '../../..'));
  return { root, repositoryRoot };
}

function argv(outputDir, extra = []) {
  return ['--fixture', fixtureId, '--model', 'test-model', '--output-dir', outputDir, ...extra];
}

function configurationError(fn) {
  assert.throws(fn, error => error.code === 'configuration_error' && error.message.length > 0);
}

for (const bad of [
  [], ['--fixture', fixtureId],
  ['--fixture', fixtureId, '--model', ''],
  ['--fixture', 'missing', '--model', 'm', '--output-dir', '/tmp/x'],
  ['--fixture', fixtureId, '--fixture', fixtureId, '--model', 'm', '--output-dir', '/tmp/x'],
  ['--fixture', fixtureId, '--model', 'm', '--output-dir', '/tmp/x', '--wat', 'x'],
  ['--fixture', fixtureId, '--model', 'm', '--output-dir', '/tmp/x', '--timeout-ms', '0'],
  ['--fixture', fixtureId, '--model', 'm', '--output-dir', '/tmp/x', '--timeout-ms', '1.5'],
]) {
  test(`CLI rejects ${JSON.stringify(bad)}`, () => configurationError(() => parseMinimalProviderArgs(bad, { repositoryRoot: '/repo' })));
}

test('CLI applies default timeout', () => {
  const parsed = parseMinimalProviderArgs(argv('/tmp/new-run'), { repositoryRoot: '/repo' });
  assert.equal(parsed.timeoutMs, GENUI_PROVIDER_SETTINGS.timeoutMs);
});

test('output path accepts one canonical external child and creates private artifacts', async () => {
  const { root, repositoryRoot } = await sandbox();
  const outputDir = join(root, 'run');
  const options = parseMinimalProviderArgs(argv(outputDir), { repositoryRoot });
  const run = await createPrivateRun(options, { repositoryRoot, now: () => '2026-07-17T00:00:00.000Z' });
  assert.equal((await stat(outputDir)).mode & 0o777, 0o700);
  for (const path of [run.paths.request, run.paths.providerEvents]) assert.equal((await stat(path)).mode & 0o777, 0o600);
  const request = JSON.parse(await readFile(run.paths.request, 'utf8'));
  assert.equal(request.fixtureId, fixtureId);
  assert.equal(request.model, 'test-model');
  assert.equal(request.expectedProviderInvocationCount, 1);
  assert.equal(typeof request.promptSha256, 'string');
  assert.equal(typeof request.schemaSha256, 'string');
  assert.equal(Object.hasOwn(request, 'candidateJson'), false);
  await writeTerminalResult(run, { classification: 'provider_failed', safeMessage: 'test' });
  assert.equal((await stat(run.paths.result)).mode & 0o777, 0o600);
  await assert.rejects(() => writeTerminalResult(run, { classification: 'provider_failed' }));
});

test('output path rejects aliases and unsafe parents before run creation', async () => {
  const { root, repositoryRoot } = await sandbox();
  const existing = join(root, 'existing');
  await mkdir(existing);
  const alias = join(root, 'repo-link');
  await symlink(repositoryRoot, alias);
  for (const outputDir of ['relative', existing, join(root, 'missing', 'run'), join(repositoryRoot, 'run'), `${root}/../${basename(root)}/alias`, join(alias, 'run')]) {
    const options = parseMinimalProviderArgs(argv(outputDir), { repositoryRoot });
    await assert.rejects(() => createPrivateRun(options, { repositoryRoot }), error => error.code === 'configuration_error');
  }
});

test('provider lifecycle performs exactly one fixed Codex invocation', async () => {
  const { root, repositoryRoot } = await sandbox();
  const options = parseMinimalProviderArgs(argv(join(root, 'run')), { repositoryRoot });
  const run = await createPrivateRun(options, { repositoryRoot });
  const calls = [];
  const child = new EventEmitter();
  child.pid = 12345;
  child.stdin = new PassThrough();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.kill = () => true;
  const resultPromise = runProviderAttempt(run, options, {
    spawnProcess(command, args, spawnOptions) {
      calls.push({ command, args, spawnOptions });
      queueMicrotask(() => {
        child.stdout.end();
        child.stderr.end();
        child.emit('exit', 0, null);
      });
      return child;
    },
    providerInvocation: { command: 'codex', prefixArgs: [] },
  });
  const result = await resultPromise;
  assert.equal(result.classification, 'success');
  assert.equal(result.invocationCount, 1);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].command, 'codex');
  assert.equal(calls[0].args.filter(value => value === 'exec').length, 1);
  for (const flag of ['--json', '--ephemeral', '--ignore-git-repo-check', '--skip-rules', '--sandbox', '--model', '--output-schema', '--output-last-message']) {
    assert.equal(calls[0].args.filter(value => value === flag).length, 1);
  }
  assert.equal(calls[0].args.at(-1), '-');
  assert.equal(calls[0].spawnOptions.cwd, run.paths.work);
});

test('fake provider traverses real browser and MoonBit commit path', { timeout: 360_000 }, async () => {
  const { root, repositoryRoot } = await sandbox();
  const fakeProvider = join(root, 'fake-provider.mjs');
  const candidateJson = recordedFeasibilityCandidateJson(fixtureId);
  await writeFile(fakeProvider, [
    "import { writeFile } from 'node:fs/promises';",
    "const outputFlag = process.argv.indexOf('--output-last-message');",
    "if (outputFlag < 0) process.exit(2);",
    `await writeFile(process.argv[outputFlag + 1], ${JSON.stringify(candidateJson)});`,
    "process.stdout.write(JSON.stringify({ type: 'turn.completed' }) + '\\n');",
  ].join('\n'));
  const outputDir = join(root, 'run');
  const options = parseMinimalProviderArgs(argv(outputDir, ['--timeout-ms', '300000']), { repositoryRoot });
  const observed = await runMinimalProviderE2E(options, {
    repositoryRoot,
    providerInvocation: { command: process.execPath, prefixArgs: [fakeProvider] },
  });
  assert.equal(observed.exitCode, 0);
  assert.equal(observed.result.classification, 'success');
  assert.equal(observed.result.rubric.passed, true);
  assert.equal(observed.result.session.success, true);
  assert.deepEqual((await readdir(outputDir)).sort(), ['candidate.json', 'provider-events.jsonl', 'request.json', 'result.json']);
});
